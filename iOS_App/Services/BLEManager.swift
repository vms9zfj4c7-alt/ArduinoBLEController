import Foundation
import CoreBluetooth
import Combine

/// Magasin isolé pour la télémétrie et le RSSI : évite de redessiner toute la manette à chaque trame.
final class BLETelemetryStore: ObservableObject {
    @Published var latestTemperature: Double?
    @Published var isTemperatureSimulated: Bool = false
    @Published var connectedRSSI: Int?

    func reset() {
        if latestTemperature != nil { latestTemperature = nil }
        if isTemperatureSimulated { isTemperatureSimulated = false }
        if connectedRSSI != nil { connectedRSSI = nil }
    }
}

/// Gestionnaire Bluetooth Low Energy basé sur CoreBluetooth.
/// Découvre automatiquement les services/caractéristiques et s'adapte à la carte Arduino connectée.
final class BLEManager: NSObject, ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case scanning
        case connecting(String)
        case discoveringServices(String)
        case connected(String)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }

        var isBusy: Bool {
            switch self {
            case .scanning, .connecting, .discoveringServices:
                return true
            case .disconnected, .connected:
                return false
            }
        }

        var statusText: String {
            switch self {
            case .disconnected:
                return "Déconnecté"
            case .scanning:
                return "Scan en cours..."
            case .connecting(let name):
                return "Connexion à \(name)..."
            case .discoveringServices(let name):
                return "Découverte BLE (\(name))..."
            case .connected(let name):
                return "Connecté : \(name)"
            }
        }
    }

    // MARK: - Propriétés publiées
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var discoveredDevices: [BLEDevice] = []
    @Published private(set) var activeProfileDescription: String = "Aucun profil"
    @Published private(set) var detectedBoardCapability: ArduinoBoardCapability
    @Published private(set) var manualBoardOverride: ArduinoBoardType = .auto
    @Published private(set) var lastConnectedDeviceName: String?
    @Published var lastErrorMessage: String?

    /// Journal et télémétrie isolés pour éviter les re-rendus de la manette à chaque paquet TX/RX
    let logStore = BLELogStore(maxEntries: 200)
    let telemetryStore = BLETelemetryStore()

    private let lastDeviceIDKey = "arduino_ble_last_device_id_v1"
    private let lastDeviceNameKey = "arduino_ble_last_device_name_v1"

    // MARK: - État CoreBluetooth interne
    private var centralManager: CBCentralManager!
    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var devicesByID: [UUID: BLEDevice] = [:]
    private var lastSeenTimestamps: [UUID: TimeInterval] = [:]
    private var scanDevicesDirty: Bool = false
    private var connectedPeripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?
    private var supportsWriteWithoutResponse: Bool = false
    private var supportsWriteWithResponse: Bool = false
    private var maxWriteNoRespLen: Int = 20
    private var maxWriteWithRespLen: Int = 20
    private var pendingWithoutResponseQueue: [BLEPreparedCommand] = []
    private var pendingCharacteristicServicesCount: Int = 0
    private var discoveredServiceUUIDStrings: [String] = []
    private var usedTargetedDiscovery: Bool = false
    private var didAttemptFullFallbackDiscovery: Bool = false
    private var didDiscoverFullCharScan: Bool = false
    private var rxDataBuffer: Data = {
        var data = Data()
        data.reserveCapacity(128)
        return data
    }()

    private var scanTimeoutTimer: Timer?
    private var scanRefreshTimer: Timer?
    private var connectionTimeoutTimer: Timer?
    private var rssiTimer: Timer?
    private var lastAutoDetectedCapability: ArduinoBoardCapability?

    init(initialBoardType: ArduinoBoardType = .auto) {
        self.manualBoardOverride = initialBoardType
        self.detectedBoardCapability = ArduinoBoardCapability.defaultCapability(
            for: initialBoardType == .auto ? .unoR4WiFi : initialBoardType,
            isAutoDetected: initialBoardType == .auto
        )
        self.lastConnectedDeviceName = UserDefaults.standard.string(forKey: lastDeviceNameKey)
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    deinit {
        invalidateTimers()
    }

    // MARK: - Actions publiques

    func startScan() {
        lastErrorMessage = nil

        guard centralManager.state == .poweredOn else {
            lastErrorMessage = bluetoothUnavailableMessage(for: centralManager.state)
            appendLog(.error, lastErrorMessage ?? "Bluetooth indisponible.")
            return
        }

        if case .connected = connectionState {
            disconnect()
        }

        devicesByID.removeAll()
        lastSeenTimestamps.removeAll()
        scanDevicesDirty = false
        discoveredDevices = []
        connectionState = .scanning
        appendLog(.info, "Démarrage du scan BLE...")

        // Inclure aussi les cartes et accessoires BLE déjà connectés au niveau iOS
        let connectedLookupServices = BLEProtocolConstants.knownArduinoServiceUUIDs + [
            CBUUID(string: "1800"),
            CBUUID(string: "180A"),
            CBUUID(string: "180F"),
            CBUUID(string: "1812"),
            CBUUID(string: "180D")
        ]
        let alreadyConnected = centralManager.retrieveConnectedPeripherals(
            withServices: connectedLookupServices
        )
        let now = CFAbsoluteTimeGetCurrent()
        for peripheral in alreadyConnected {
            peripheralsByID[peripheral.identifier] = peripheral
            lastSeenTimestamps[peripheral.identifier] = now
            let knownServices = peripheral.services?.map(\.uuid) ?? []
            let device = BLEDevice(
                id: peripheral.identifier,
                rawName: peripheral.name,
                rssi: -48,
                advertisedServiceUUIDs: knownServices.isEmpty ? [CBUUID(string: "180A")] : knownServices,
                isConnectable: true,
                lastSeen: now
            )
            devicesByID[peripheral.identifier] = device
            scanDevicesDirty = true
        }
        if scanDevicesDirty {
            flushScanUpdatesIfNeeded()
        }

        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )

        scanRefreshTimer?.invalidate()
        scanRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.flushScanUpdatesIfNeeded()
        }

        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 45.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            if case .scanning = self.connectionState {
                self.stopScan()
                self.appendLog(.info, "Scan terminé automatiquement (45 s).")
            }
        }
    }

    func stopScan() {
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = nil
        scanRefreshTimer?.invalidate()
        scanRefreshTimer = nil
        if centralManager.isScanning {
            centralManager.stopScan()
        }
        flushScanUpdatesIfNeeded()
        if case .scanning = connectionState {
            connectionState = .disconnected
        }
    }

    func connect(to device: BLEDevice) {
        lastErrorMessage = nil
        stopScan()

        guard let peripheral = peripheralsByID[device.id] else {
            let msg = "Périphérique introuvable. Relancez le scan."
            lastErrorMessage = msg
            appendLog(.error, msg)
            return
        }

        connect(toPeripheral: peripheral, displayName: device.displayName)
    }

    /// Reconnexion rapide sans repasser par l'écran de scan via l'UUID mémorisé.
    func reconnectLastDevice() {
        lastErrorMessage = nil
        guard centralManager.state == .poweredOn else {
            lastErrorMessage = bluetoothUnavailableMessage(for: centralManager.state)
            appendLog(.error, lastErrorMessage ?? "Bluetooth indisponible.")
            return
        }
        guard let uuidStr = UserDefaults.standard.string(forKey: lastDeviceIDKey),
              let uuid = UUID(uuidString: uuidStr) else {
            startScan()
            return
        }

        let retrieved = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        guard let peripheral = retrieved.first else {
            startScan()
            return
        }

        peripheralsByID[peripheral.identifier] = peripheral
        let displayName = peripheral.name ?? lastConnectedDeviceName ?? "Arduino BLE"
        connect(toPeripheral: peripheral, displayName: displayName)
    }

    private func connect(toPeripheral peripheral: CBPeripheral, displayName: String) {
        stopScan()

        if let current = connectedPeripheral, current.identifier != peripheral.identifier {
            centralManager.cancelPeripheralConnection(current)
        }

        resetSessionState()
        connectedPeripheral = peripheral
        connectionState = .connecting(displayName)
        appendLog(.info, "Connexion en cours vers \(displayName)...")

        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 12.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            if !self.connectionState.isConnected {
                self.appendLog(.error, "Délai de connexion dépassé (12 s).")
                self.lastErrorMessage = "La connexion a expiré. Vérifiez que la carte est allumée."
                self.disconnect()
            }
        }

        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        invalidateTimers()
        let peripheralToDisconnect = connectedPeripheral
        connectedPeripheral = nil
        resetSessionState()
        connectionState = .disconnected
        if let peripheral = peripheralToDisconnect {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        appendLog(.info, "Déconnecté du périphérique.")
    }

    func send(command: String, preferWithoutResponse: Bool = true) {
        let packet = BLEPreparedCommand.make(command, coalesceKey: Self.inferCoalesceKey(for: command))
        sendPrepared(packet, preferWithoutResponse: preferWithoutResponse)
    }

    func sendPrepared(_ packet: BLEPreparedCommand, preferWithoutResponse: Bool = true) {
        guard let peripheral = connectedPeripheral,
              peripheral.state == .connected,
              let rxChar = rxCharacteristic else {
            let msg = "Envoi impossible : aucun Arduino connecté."
            appendLog(.error, msg)
            return
        }

        // Un arrêt d'urgence ou une écriture critique purge toute trame périmée en attente sur la même broche
        if packet.payload == BLEProtocolConstants.emergencyStopPacket.payload {
            pendingWithoutResponseQueue.removeAll(keepingCapacity: true)
        }

        let writeType: CBCharacteristicWriteType
        let maxChunk: Int
        if preferWithoutResponse && supportsWriteWithoutResponse {
            writeType = .withoutResponse
            maxChunk = maxWriteNoRespLen
        } else if supportsWriteWithResponse {
            writeType = .withResponse
            maxChunk = maxWriteWithRespLen
        } else {
            writeType = .withoutResponse
            maxChunk = maxWriteNoRespLen
        }

        if writeType == .withResponse, let key = packet.coalesceKey, !pendingWithoutResponseQueue.isEmpty {
            pendingWithoutResponseQueue.removeAll { $0.coalesceKey == key }
        }

        // Protection anti-saturation L2CAP CoreBluetooth (utile en streaming rapide manette PS4)
        if writeType == .withoutResponse && (!peripheral.canSendWriteWithoutResponse || !pendingWithoutResponseQueue.isEmpty) {
            enqueuePendingWithoutResponse(packet)
            return
        }

        writePreparedPacket(packet, to: peripheral, rxChar: rxChar, writeType: writeType, maxChunk: maxChunk)
    }

    private func writePreparedPacket(
        _ packet: BLEPreparedCommand,
        to peripheral: CBPeripheral,
        rxChar: CBCharacteristic,
        writeType: CBCharacteristicWriteType,
        maxChunk: Int
    ) {
        let data = packet.payload
        guard !data.isEmpty else { return }

        if data.count <= maxChunk {
            peripheral.writeValue(data, for: rxChar, type: writeType)
        } else {
            var offset = 0
            while offset < data.count {
                let end = min(offset + maxChunk, data.count)
                peripheral.writeValue(data.subdata(in: offset ..< end), for: rxChar, type: writeType)
                offset = end
            }
        }

        appendLog(.tx, packet.logText)
    }

    private func enqueuePendingWithoutResponse(_ packet: BLEPreparedCommand) {
        if let key = packet.coalesceKey,
           let existingIdx = pendingWithoutResponseQueue.firstIndex(where: { $0.coalesceKey == key }) {
            pendingWithoutResponseQueue[existingIdx] = packet
            return
        }
        if pendingWithoutResponseQueue.count >= 8 {
            pendingWithoutResponseQueue.removeFirst()
        }
        pendingWithoutResponseQueue.append(packet)
    }

    private static func inferCoalesceKey(for command: String) -> String? {
        guard command.count >= 4 else { return nil }
        let idx1 = command.index(after: command.startIndex)
        guard command[idx1] == ":" else { return nil }
        let kind = command[command.startIndex]
        guard kind == "P" || kind == "V" || kind == "D" else { return nil }
        let rest = command[command.index(after: idx1)...]
        if let secondColon = rest.firstIndex(of: ":") {
            return String(command[command.startIndex ... secondColon])
        }
        return nil
    }

    func requestBoardInfo() {
        send(command: BLEProtocolConstants.infoQueryCommand, preferWithoutResponse: false)
    }

    func requestTelemetry() {
        send(command: BLEProtocolConstants.telemetryQueryCommand, preferWithoutResponse: true)
    }

    func setManualBoardOverride(_ boardType: ArduinoBoardType) {
        guard manualBoardOverride != boardType else { return }
        manualBoardOverride = boardType
        let resolvedCap: ArduinoBoardCapability
        if boardType == .auto {
            if let autoCap = lastAutoDetectedCapability {
                resolvedCap = autoCap
            } else if let peripheral = connectedPeripheral {
                let inferred = ArduinoBoardCapability.inferFromDeviceMetadata(
                    name: peripheral.name ?? "",
                    serviceUUIDStrings: discoveredServiceUUIDStrings
                )
                resolvedCap = ArduinoBoardCapability.defaultCapability(for: inferred, isAutoDetected: true)
            } else {
                resolvedCap = ArduinoBoardCapability.defaultCapability(for: .unoR4WiFi, isAutoDetected: true)
            }
        } else {
            resolvedCap = ArduinoBoardCapability.defaultCapability(for: boardType, isAutoDetected: false)
        }
        if detectedBoardCapability != resolvedCap {
            detectedBoardCapability = resolvedCap
        }
    }

    func clearLogs() {
        logStore.clear()
    }

    /// Met en pause les tâches radio non essentielles lorsque l'app passe en arrière-plan.
    func setAppActive(_ isActive: Bool) {
        if isActive {
            if connectionState.isConnected, rssiTimer == nil {
                startRSSITimer()
                connectedPeripheral?.readRSSI()
            }
        } else {
            if case .scanning = connectionState {
                stopScan()
            }
            rssiTimer?.invalidate()
            rssiTimer = nil
        }
    }

    // MARK: - Méthodes privées

    private func resetSessionState() {
        rxCharacteristic = nil
        txCharacteristic = nil
        supportsWriteWithoutResponse = false
        supportsWriteWithResponse = false
        maxWriteNoRespLen = 20
        maxWriteWithRespLen = 20
        pendingWithoutResponseQueue.removeAll()
        pendingCharacteristicServicesCount = 0
        discoveredServiceUUIDStrings = []
        usedTargetedDiscovery = false
        didAttemptFullFallbackDiscovery = false
        didDiscoverFullCharScan = false
        rxDataBuffer.removeAll(keepingCapacity: true)
        telemetryStore.reset()
        activeProfileDescription = "Aucun profil"
        lastAutoDetectedCapability = nil
    }

    private func invalidateTimers() {
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = nil
        scanRefreshTimer?.invalidate()
        scanRefreshTimer = nil
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil
        rssiTimer?.invalidate()
        rssiTimer = nil
    }

    private func startRSSITimer() {
        rssiTimer?.invalidate()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            guard let self, let peripheral = self.connectedPeripheral, peripheral.state == .connected else { return }
            peripheral.readRSSI()
        }
    }

    private func appendLog(_ direction: BLELogEntry.Direction, _ message: String) {
        logStore.append(direction, message)
    }

    private func flushScanUpdatesIfNeeded() {
        let now = CFAbsoluteTimeGetCurrent()
        var removedStale = false
        for (id, seenAt) in lastSeenTimestamps where (now - seenAt) > 20.0 {
            lastSeenTimestamps.removeValue(forKey: id)
            if devicesByID.removeValue(forKey: id) != nil {
                removedStale = true
            }
        }

        guard scanDevicesDirty || removedStale else { return }
        scanDevicesDirty = false
        let sorted = devicesByID.values.sorted { lhs, rhs in
            if lhs.isLikelyArduino != rhs.isLikelyArduino {
                return lhs.isLikelyArduino && !rhs.isLikelyArduino
            }
            if lhs.hasResolvedName != rhs.hasResolvedName {
                return lhs.hasResolvedName && !rhs.hasResolvedName
            }
            if lhs.isConnectable != rhs.isConnectable {
                return lhs.isConnectable && !rhs.isConnectable
            }
            return lhs.rssi > rhs.rssi
        }
        let capped: [BLEDevice]
        if sorted.count > 60 {
            for evicted in sorted.dropFirst(60) {
                devicesByID.removeValue(forKey: evicted.id)
                lastSeenTimestamps.removeValue(forKey: evicted.id)
            }
            capped = Array(sorted.prefix(60))
        } else {
            capped = sorted
        }
        if discoveredDevices != capped {
            discoveredDevices = capped
        }
    }

    private func bluetoothUnavailableMessage(for state: CBManagerState) -> String {
        switch state {
        case .poweredOff:
            return "Le Bluetooth de l'iPhone est désactivé. Activez-le dans Réglages."
        case .unauthorized:
            return "Permission Bluetooth refusée. Autorisez l'accès dans Réglages."
        case .unsupported:
            return "Cet appareil ne prend pas en charge le Bluetooth Low Energy (BLE)."
        case .resetting:
            return "Réinitialisation du Bluetooth en cours..."
        default:
            return "Bluetooth non prêt. Veuillez patienter un instant."
        }
    }

    private func finalizeCharacteristicDiscovery(for peripheral: CBPeripheral) {
        let services = peripheral.services ?? []
        let allChars = services.flatMap { $0.characteristics ?? [] }
        discoveredServiceUUIDStrings = services.map { $0.uuid.uuidString }

        var chosenRX: CBCharacteristic?
        var chosenTX: CBCharacteristic?
        var profileLabel = "Générique"

        // 1. Profil personnalisé (ESP32 / ArduinoBLE)
        if let customRX = allChars.first(where: { $0.uuid == BLEProtocolConstants.customRXCharacteristicUUID }),
           let customTX = allChars.first(where: { $0.uuid == BLEProtocolConstants.customTXCharacteristicUUID }) {
            chosenRX = customRX
            chosenTX = customTX
            profileLabel = "ArduinoBLE / ESP32"
        }
        // 2. Profil HM-10 (FFE0 / FFE1)
        else if let hm10Char = allChars.first(where: { $0.uuid == BLEProtocolConstants.hm10CharacteristicUUID }) {
            chosenRX = hm10Char
            chosenTX = hm10Char
            profileLabel = "HM-10 Série (FFE1)"
        }
        // 3. Profil Nordic UART
        else if let nusRX = allChars.first(where: { $0.uuid == BLEProtocolConstants.nordicRXCharacteristicUUID }),
                let nusTX = allChars.first(where: { $0.uuid == BLEProtocolConstants.nordicTXCharacteristicUUID }) {
            chosenRX = nusRX
            chosenTX = nusTX
            profileLabel = "Nordic UART"
        }
        // 4. Fallback universel sur tout module BLE série
        else {
            chosenRX = allChars.first(where: {
                $0.properties.contains(.writeWithoutResponse) || $0.properties.contains(.write)
            })
            chosenTX = allChars.first(where: {
                $0.properties.contains(.notify) || $0.properties.contains(.indicate)
            })
            profileLabel = "BLE Universel"
        }

        guard let rxChar = chosenRX else {
            if !didDiscoverFullCharScan {
                didDiscoverFullCharScan = true
                didAttemptFullFallbackDiscovery = true
                usedTargetedDiscovery = false
                peripheral.discoverServices(nil)
                return
            }
            let errMsg = "Aucune caractéristique d'écriture BLE compatible trouvée sur ce périphérique."
            lastErrorMessage = errMsg
            appendLog(.error, errMsg)
            disconnect()
            return
        }

        self.rxCharacteristic = rxChar
        self.txCharacteristic = chosenTX
        self.supportsWriteWithoutResponse = rxChar.properties.contains(.writeWithoutResponse)
        self.supportsWriteWithResponse = rxChar.properties.contains(.write)
        self.maxWriteNoRespLen = max(1, peripheral.maximumWriteValueLength(for: .withoutResponse))
        self.maxWriteWithRespLen = max(1, peripheral.maximumWriteValueLength(for: .withResponse))
        self.activeProfileDescription = profileLabel

        if manualBoardOverride == .auto {
            let bestName = peripheral.name ?? devicesByID[peripheral.identifier]?.displayName ?? ""
            let inferred = ArduinoBoardCapability.inferFromDeviceMetadata(
                name: bestName,
                serviceUUIDStrings: discoveredServiceUUIDStrings
            )
            let cap = ArduinoBoardCapability.defaultCapability(for: inferred, isAutoDetected: true)
            lastAutoDetectedCapability = cap
            if detectedBoardCapability != cap {
                detectedBoardCapability = cap
            }
        }

        if let txChar = chosenTX,
           txChar.properties.contains(.notify) || txChar.properties.contains(.indicate) {
            peripheral.setNotifyValue(true, for: txChar)
        } else {
            markAsConnected(peripheral: peripheral)
        }
    }

    private func markAsConnected(peripheral: CBPeripheral) {
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil
        let displayName = peripheral.name
            ?? devicesByID[peripheral.identifier]?.displayName
            ?? "Arduino BLE"
        connectionState = .connected(displayName)
        lastConnectedDeviceName = displayName
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: lastDeviceIDKey)
        UserDefaults.standard.set(displayName, forKey: lastDeviceNameKey)
        appendLog(.info, "Prêt (\(activeProfileDescription)) sur \(displayName).")
        startRSSITimer()
        peripheral.readRSSI()
        requestBoardInfo()
    }

    private func handleIncomingData(_ data: Data) {
        rxDataBuffer.append(data)

        if rxDataBuffer.count > 512 && !rxDataBuffer.contains(0x0A) {
            rxDataBuffer.removeAll(keepingCapacity: true)
            return
        }

        var searchStart = rxDataBuffer.startIndex
        while let newlineIdx = rxDataBuffer[searchStart...].firstIndex(of: 0x0A) {
            var lineEnd = newlineIdx
            if lineEnd > searchStart && rxDataBuffer[rxDataBuffer.index(before: lineEnd)] == 0x0D {
                lineEnd = rxDataBuffer.index(before: lineEnd)
            }
            if searchStart < lineEnd {
                let slice = rxDataBuffer[searchStart ..< lineEnd]
                let line = String(decoding: slice, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty {
                    processReceivedLine(line)
                }
            }
            searchStart = rxDataBuffer.index(after: newlineIdx)
        }

        if searchStart > rxDataBuffer.startIndex {
            rxDataBuffer.removeSubrange(..<searchStart)
        }
    }

    private func processReceivedLine(_ line: String) {
        if line.hasPrefix("INFO:") {
            appendLog(.rx, line)
            if let capability = ArduinoBoardCapability.parse(infoLine: line) {
                lastAutoDetectedCapability = capability
                if manualBoardOverride == .auto && detectedBoardCapability != capability {
                    detectedBoardCapability = capability
                }
                appendLog(.info, "Carte identifiée : \(capability.boardType.displayName) (\(capability.availablePins.count) broches)")
            }
            return
        }

        if line.hasPrefix("DATA:") {
            parseTelemetryLine(line)
            appendLog(.rx, line)
            return
        }

        if line.hasPrefix("ERR:") {
            appendLog(.error, line)
            lastErrorMessage = "Arduino : \(line)"
            return
        }

        appendLog(.rx, line)
    }

    private func parseTelemetryLine(_ line: String) {
        var cursor = line.index(line.startIndex, offsetBy: 5) // Après "DATA:"
        while cursor < line.endIndex {
            let nextSemi = line[cursor...].firstIndex(of: ";") ?? line.endIndex
            let part = line[cursor ..< nextSemi]
            if let eqIdx = part.firstIndex(of: "=") {
                let rawKey = part[..<eqIdx]
                let rawVal = part[part.index(after: eqIdx)...]
                let key = rawKey.trimmingCharacters(in: .whitespaces)
                let val = rawVal.trimmingCharacters(in: .whitespaces)

                if key == "T" || key.caseInsensitiveCompare("TEMP") == .orderedSame {
                    if let temp = Double(val), telemetryStore.latestTemperature != temp {
                        telemetryStore.latestTemperature = temp
                    }
                } else if key == "S" || key.caseInsensitiveCompare("SIM") == .orderedSame {
                    let sim = (val == "1" || val.caseInsensitiveCompare("true") == .orderedSame)
                    if telemetryStore.isTemperatureSimulated != sim {
                        telemetryStore.isTemperatureSimulated = sim
                    }
                }
            }
            cursor = (nextSemi < line.endIndex) ? line.index(after: nextSemi) : line.endIndex
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        if central.state != .poweredOn {
            if connectionState.isConnected || connectionState.isBusy {
                invalidateTimers()
                resetSessionState()
                connectedPeripheral = nil
                connectionState = .disconnected
            }
            if central.state != .unknown {
                let msg = bluetoothUnavailableMessage(for: central.state)
                lastErrorMessage = msg
                appendLog(.error, msg)
            }
        } else {
            lastErrorMessage = nil
            appendLog(.info, "Bluetooth prêt.")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let rssiValue = RSSI.intValue
        // Ignorer les lectures RSSI invalides (127 indique indisponible dans CoreBluetooth)
        let normalizedRSSI = (rssiValue == 127) ? -99 : rssiValue
        let now = CFAbsoluteTimeGetCurrent()

        peripheralsByID[peripheral.identifier] = peripheral
        lastSeenTimestamps[peripheral.identifier] = now
        let existing = devicesByID[peripheral.identifier]

        // Fusionner ADV_IND et SCAN_RSP sans allouer inutilement sur les paquets répétés
        let rawPacketName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let rawPeripheralName = peripheral.name
        let mergedName: String?
        if let rawPacketName, rawPacketName == existing?.rawName {
            mergedName = existing?.rawName
        } else {
            let trimmedPacket = rawPacketName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedPacket, !trimmedPacket.isEmpty {
                mergedName = trimmedPacket
            } else if let rawPeripheralName, rawPeripheralName == existing?.rawName {
                mergedName = existing?.rawName
            } else {
                let trimmedPeripheral = rawPeripheralName?.trimmingCharacters(in: .whitespacesAndNewlines)
                mergedName = (trimmedPeripheral?.isEmpty == false ? trimmedPeripheral : nil) ?? existing?.rawName
            }
        }

        let primaryUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
        let overflowUUIDs = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]
        let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]

        let existingUUIDs = existing?.advertisedServiceUUIDs ?? []
        var hasNewUUID = false
        if let primaryUUIDs {
            for uuid in primaryUUIDs where !existingUUIDs.contains(uuid) {
                hasNewUUID = true
                break
            }
        }
        if !hasNewUUID, let overflowUUIDs {
            for uuid in overflowUUIDs where !existingUUIDs.contains(uuid) {
                hasNewUUID = true
                break
            }
        }
        if !hasNewUUID, let serviceData {
            for uuid in serviceData.keys where !existingUUIDs.contains(uuid) {
                hasNewUUID = true
                break
            }
        }

        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let incomingMfrID = BLEDevice.parseManufacturerID(from: manufacturerData)
        let incomingTxPower = (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue
            ?? existing?.txPowerLevel

        let connectableFlag: Bool
        if let rawBool = advertisementData[CBAdvertisementDataIsConnectable] as? Bool {
            connectableFlag = rawBool
        } else if let rawNum = advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber {
            connectableFlag = rawNum.boolValue
        } else {
            connectableFlag = existing?.isConnectable ?? true
        }

        let smoothedRSSI: Int
        if let prev = existing?.rssi {
            smoothedRSSI = Int((Double(prev) * 0.6 + Double(normalizedRSSI) * 0.4).rounded())
        } else {
            smoothedRSSI = normalizedRSSI
        }

        // Chemin rapide zéro-allocation : si rien de visible n'a changé, ne pas reconstruire BLEDevice
        if let existing,
           mergedName == existing.rawName,
           !hasNewUUID,
           (incomingMfrID == nil || incomingMfrID == existing.manufacturerID),
           incomingTxPower == existing.txPowerLevel,
           connectableFlag == existing.isConnectable,
           abs(existing.rssi - smoothedRSSI) < 2 {
            return
        }

        let mergedUUIDs: [CBUUID]
        if hasNewUUID || existing == nil {
            var mergedUUIDSet = Set(existingUUIDs)
            if let primaryUUIDs { mergedUUIDSet.formUnion(primaryUUIDs) }
            if let overflowUUIDs { mergedUUIDSet.formUnion(overflowUUIDs) }
            if let serviceData { mergedUUIDSet.formUnion(serviceData.keys) }
            mergedUUIDs = mergedUUIDSet.isEmpty ? [] : Array(mergedUUIDSet).sorted { $0.uuidString < $1.uuidString }
        } else {
            mergedUUIDs = existingUUIDs
        }

        let updatedDevice = BLEDevice(
            id: peripheral.identifier,
            rawName: mergedName,
            rssi: smoothedRSSI,
            advertisedServiceUUIDs: mergedUUIDs,
            manufacturerData: manufacturerData,
            manufacturerID: existing?.manufacturerID,
            appleContinuityType: existing?.appleContinuityType,
            txPowerLevel: incomingTxPower,
            isConnectable: connectableFlag,
            lastSeen: now
        )
        devicesByID[peripheral.identifier] = updatedDevice

        let resolvedNewName = !(existing?.hasResolvedName ?? false) && updatedDevice.hasResolvedName
        let resolvedNewArduino = !(existing?.isLikelyArduino ?? false) && updatedDevice.isLikelyArduino

        if existing == nil || resolvedNewName || resolvedNewArduino {
            scanDevicesDirty = true
            flushScanUpdatesIfNeeded()
        } else {
            scanDevicesDirty = true
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name
            ?? devicesByID[peripheral.identifier]?.displayName
            ?? "Arduino BLE"
        connectionState = .discoveringServices(name)
        appendLog(.info, "Connecté à \(name). Découverte des services...")
        peripheral.delegate = self

        let hasKnownAdvService = devicesByID[peripheral.identifier]?.advertisedServiceUUIDs.contains(where: {
            BLEProtocolConstants.knownArduinoServiceUUIDs.contains($0)
        }) ?? false

        if hasKnownAdvService {
            usedTargetedDiscovery = true
            didAttemptFullFallbackDiscovery = false
            peripheral.discoverServices(BLEProtocolConstants.knownArduinoServiceUUIDs)
        } else {
            usedTargetedDiscovery = false
            didAttemptFullFallbackDiscovery = true
            peripheral.discoverServices(nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        invalidateTimers()
        resetSessionState()
        connectedPeripheral = nil
        connectionState = .disconnected
        let msg = "Échec de connexion : \(error?.localizedDescription ?? "erreur inconnue")"
        lastErrorMessage = msg
        appendLog(.error, msg)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard connectedPeripheral?.identifier == peripheral.identifier else { return }
        invalidateTimers()
        resetSessionState()
        connectedPeripheral = nil
        connectionState = .disconnected
        if let error {
            let msg = "Connexion perdue : \(error.localizedDescription)"
            lastErrorMessage = msg
            appendLog(.error, msg)
        } else {
            appendLog(.info, "Déconnecté proprement.")
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            let msg = "Erreur découverte services : \(error.localizedDescription)"
            lastErrorMessage = msg
            appendLog(.error, msg)
            disconnect()
            return
        }

        let services = peripheral.services ?? []
        if services.isEmpty && usedTargetedDiscovery && !didAttemptFullFallbackDiscovery {
            didAttemptFullFallbackDiscovery = true
            usedTargetedDiscovery = false
            peripheral.discoverServices(nil)
            return
        }

        guard !services.isEmpty else {
            let msg = "Aucun service BLE exposé par cet appareil."
            lastErrorMessage = msg
            appendLog(.error, msg)
            disconnect()
            return
        }

        if !didDiscoverFullCharScan {
            // Prioriser la découverte ciblée sur le service UART connu pour connecter 2 à 3x plus vite
            if let customService = services.first(where: { $0.uuid == BLEProtocolConstants.customServiceUUID }) {
                pendingCharacteristicServicesCount = 1
                peripheral.discoverCharacteristics(
                    [BLEProtocolConstants.customRXCharacteristicUUID, BLEProtocolConstants.customTXCharacteristicUUID],
                    for: customService
                )
                return
            }

            if let hm10Service = services.first(where: { $0.uuid == BLEProtocolConstants.hm10ServiceUUID }) {
                pendingCharacteristicServicesCount = 1
                peripheral.discoverCharacteristics([BLEProtocolConstants.hm10CharacteristicUUID], for: hm10Service)
                return
            }

            if let nordicService = services.first(where: { $0.uuid == BLEProtocolConstants.nordicServiceUUID }) {
                pendingCharacteristicServicesCount = 1
                peripheral.discoverCharacteristics(
                    [BLEProtocolConstants.nordicRXCharacteristicUUID, BLEProtocolConstants.nordicTXCharacteristicUUID],
                    for: nordicService
                )
                return
            }
        }

        let targetServices: [CBService]
        if didDiscoverFullCharScan {
            targetServices = services
        } else {
            let nonSystemServices = services.filter { !BLEProtocolConstants.systemMetadataServiceUUIDs.contains($0.uuid) }
            targetServices = nonSystemServices.isEmpty ? services : nonSystemServices
            if targetServices.count == services.count {
                didDiscoverFullCharScan = true
            }
        }

        pendingCharacteristicServicesCount = targetServices.count
        for service in targetServices {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            appendLog(.error, "Erreur caractéristiques (\(service.uuid.uuidString)) : \(error.localizedDescription)")
        }

        pendingCharacteristicServicesCount = max(0, pendingCharacteristicServicesCount - 1)
        if pendingCharacteristicServicesCount == 0 {
            finalizeCharacteristicDiscovery(for: peripheral)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appendLog(.error, "Erreur activation notifications : \(error.localizedDescription)")
        }
        if !connectionState.isConnected {
            markAsConnected(peripheral: peripheral)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appendLog(.error, "Erreur lecture BLE : \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value, !data.isEmpty else { return }
        handleIncomingData(data)
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        let val = RSSI.intValue
        if val != 127 && telemetryStore.connectedRSSI != val {
            telemetryStore.connectedRSSI = val
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard peripheral === connectedPeripheral,
              peripheral.state == .connected,
              let rxChar = rxCharacteristic else { return }
        while !pendingWithoutResponseQueue.isEmpty && peripheral.canSendWriteWithoutResponse {
            let nextPacket = pendingWithoutResponseQueue.removeFirst()
            writePreparedPacket(
                nextPacket,
                to: peripheral,
                rxChar: rxChar,
                writeType: .withoutResponse,
                maxChunk: maxWriteNoRespLen
            )
        }
    }
}
