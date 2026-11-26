import Foundation
import CoreBluetooth
import Combine

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
    @Published private(set) var latestTemperature: Double?
    @Published private(set) var isTemperatureSimulated: Bool = false
    @Published private(set) var connectedRSSI: Int?
    @Published private(set) var lastConnectedDeviceName: String?
    @Published var lastErrorMessage: String?

    /// Journal isolé pour éviter les re-rendus de la manette à chaque paquet TX/RX
    let logStore = BLELogStore(maxEntries: 200)

    private let lastDeviceIDKey = "arduino_ble_last_device_id_v1"
    private let lastDeviceNameKey = "arduino_ble_last_device_name_v1"

    // MARK: - État CoreBluetooth interne
    private var centralManager: CBCentralManager!
    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var devicesByID: [UUID: BLEDevice] = [:]
    private var scanDevicesDirty: Bool = false
    private var connectedPeripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?
    private var supportsWriteWithoutResponse: Bool = false
    private var supportsWriteWithResponse: Bool = false
    private var maxWriteNoRespLen: Int = 20
    private var maxWriteWithRespLen: Int = 20
    private var pendingWithoutResponseQueue: [String] = []
    private var pendingCharacteristicServicesCount: Int = 0
    private var discoveredServiceUUIDStrings: [String] = []
    private var rxLineBuffer: String = ""

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
        scanDevicesDirty = false
        discoveredDevices = []
        connectionState = .scanning
        appendLog(.info, "Démarrage du scan BLE...")

        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )

        scanRefreshTimer?.invalidate()
        scanRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.flushScanUpdatesIfNeeded()
        }

        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            if case .scanning = self.connectionState {
                self.stopScan()
                self.appendLog(.info, "Scan terminé automatiquement (20 s).")
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

        connect(toPeripheral: peripheral, displayName: device.name)
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
        guard let peripheral = connectedPeripheral,
              peripheral.state == .connected,
              let rxChar = rxCharacteristic else {
            let msg = "Envoi impossible : aucun Arduino connecté."
            appendLog(.error, msg)
            return
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

        // Protection anti-saturation L2CAP CoreBluetooth (utile en streaming rapide manette PS4)
        if writeType == .withoutResponse && (!peripheral.canSendWriteWithoutResponse || !pendingWithoutResponseQueue.isEmpty) {
            enqueuePendingWithoutResponse(command)
            return
        }

        writeNormalizedCommand(command, to: peripheral, rxChar: rxChar, writeType: writeType, maxChunk: maxChunk)
    }

    private func writeNormalizedCommand(
        _ command: String,
        to peripheral: CBPeripheral,
        rxChar: CBCharacteristic,
        writeType: CBCharacteristicWriteType,
        maxChunk: Int
    ) {
        let normalized = command.hasSuffix("\n") ? command : (command + "\n")
        guard let data = normalized.data(using: .utf8), !data.isEmpty else {
            return
        }

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

        let displayCmd = command.hasSuffix("\n") ? String(command.dropLast()) : command
        appendLog(.tx, displayCmd.trimmingCharacters(in: .newlines))
    }

    private func enqueuePendingWithoutResponse(_ command: String) {
        // Pour les commandes continues P:<pin>: ou V:<pin>:, ne conserver que la dernière valeur par broche
        if command.hasPrefix("P:") || command.hasPrefix("V:") {
            let parts = command.split(separator: ":", maxSplits: 2)
            if parts.count >= 2 {
                let pinPrefix = "\(parts[0]):\(parts[1]):"
                if let existingIdx = pendingWithoutResponseQueue.firstIndex(where: { $0.hasPrefix(pinPrefix) }) {
                    pendingWithoutResponseQueue[existingIdx] = command
                    return
                }
            }
        }
        if pendingWithoutResponseQueue.count >= 8 {
            pendingWithoutResponseQueue.removeFirst()
        }
        pendingWithoutResponseQueue.append(command)
    }

    func requestBoardInfo() {
        send(command: BLEProtocolConstants.infoQueryCommand, preferWithoutResponse: false)
    }

    func requestTelemetry() {
        send(command: BLEProtocolConstants.telemetryQueryCommand, preferWithoutResponse: true)
    }

    func setManualBoardOverride(_ boardType: ArduinoBoardType) {
        manualBoardOverride = boardType
        if boardType == .auto {
            if let autoCap = lastAutoDetectedCapability {
                detectedBoardCapability = autoCap
            } else if let peripheral = connectedPeripheral {
                let inferred = ArduinoBoardCapability.inferFromDeviceMetadata(
                    name: peripheral.name ?? "",
                    serviceUUIDStrings: discoveredServiceUUIDStrings
                )
                detectedBoardCapability = ArduinoBoardCapability.defaultCapability(for: inferred, isAutoDetected: true)
            } else {
                detectedBoardCapability = ArduinoBoardCapability.defaultCapability(for: .unoR4WiFi, isAutoDetected: true)
            }
        } else {
            detectedBoardCapability = ArduinoBoardCapability.defaultCapability(for: boardType, isAutoDetected: false)
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
        rxLineBuffer = ""
        connectedRSSI = nil
        latestTemperature = nil
        isTemperatureSimulated = false
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
        let now = Date()
        let beforeCount = devicesByID.count
        devicesByID = devicesByID.filter { now.timeIntervalSince($0.value.lastSeen) <= 12.0 }
        let removedStale = (devicesByID.count != beforeCount)

        guard scanDevicesDirty || removedStale else { return }
        scanDevicesDirty = false
        discoveredDevices = devicesByID.values.sorted { lhs, rhs in
            if lhs.isLikelyArduino != rhs.isLikelyArduino {
                return lhs.isLikelyArduino && !rhs.isLikelyArduino
            }
            return lhs.rssi > rhs.rssi
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
            let inferred = ArduinoBoardCapability.inferFromDeviceMetadata(
                name: peripheral.name ?? "",
                serviceUUIDStrings: discoveredServiceUUIDStrings
            )
            let cap = ArduinoBoardCapability.defaultCapability(for: inferred, isAutoDetected: true)
            lastAutoDetectedCapability = cap
            detectedBoardCapability = cap
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
        let displayName = peripheral.name ?? "Arduino BLE"
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
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        if text.contains("\r") {
            rxLineBuffer.append(text.replacingOccurrences(of: "\r", with: ""))
        } else {
            rxLineBuffer.append(text)
        }

        if rxLineBuffer.count > 512 && !rxLineBuffer.contains("\n") {
            rxLineBuffer.removeAll(keepingCapacity: true)
            return
        }

        while let newlineIndex = rxLineBuffer.firstIndex(of: "\n") {
            let line = String(rxLineBuffer[..<newlineIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            rxLineBuffer.removeSubrange(...newlineIndex)
            if !line.isEmpty {
                processReceivedLine(line)
            }
        }
    }

    private func processReceivedLine(_ line: String) {
        if line.hasPrefix("INFO:") {
            appendLog(.rx, line)
            if let capability = ArduinoBoardCapability.parse(infoLine: line) {
                lastAutoDetectedCapability = capability
                if manualBoardOverride == .auto {
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
        let body = String(line.dropFirst("DATA:".count))
        let parts = body.split(separator: ";")
        for part in parts {
            let kv = part.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let key = kv[0].trimmingCharacters(in: .whitespaces).uppercased()
            let val = kv[1].trimmingCharacters(in: .whitespaces)

            if (key == "TEMP" || key == "T"), let temp = Double(val) {
                if latestTemperature != temp {
                    latestTemperature = temp
                }
            } else if key == "SIM" || key == "S" {
                let sim = (val == "1" || val.lowercased() == "true")
                if isTemperatureSimulated != sim {
                    isTemperatureSimulated = sim
                }
            }
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
        let advertisedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
            ?? "Appareil BLE sans nom"
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []

        peripheralsByID[peripheral.identifier] = peripheral
        let existing = devicesByID[peripheral.identifier]
        let smoothedRSSI: Int
        if let prev = existing?.rssi {
            smoothedRSSI = Int((Double(prev) * 0.6 + Double(normalizedRSSI) * 0.4).rounded())
        } else {
            smoothedRSSI = normalizedRSSI
        }

        let updatedDevice = BLEDevice(
            id: peripheral.identifier,
            name: advertisedName,
            rssi: smoothedRSSI,
            advertisedServiceUUIDs: serviceUUIDs,
            lastSeen: Date()
        )
        devicesByID[peripheral.identifier] = updatedDevice

        if existing == nil {
            scanDevicesDirty = true
            flushScanUpdatesIfNeeded()
        } else if abs((existing?.rssi ?? smoothedRSSI) - smoothedRSSI) >= 2 || existing?.name != advertisedName {
            scanDevicesDirty = true
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name ?? "Arduino BLE"
        connectionState = .discoveringServices(name)
        appendLog(.info, "Connecté à \(name). Découverte des services...")
        peripheral.delegate = self
        peripheral.discoverServices(nil)
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
        guard !services.isEmpty else {
            let msg = "Aucun service BLE exposé par cet appareil."
            lastErrorMessage = msg
            appendLog(.error, msg)
            disconnect()
            return
        }

        pendingCharacteristicServicesCount = services.count
        for service in services {
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
        if val != 127 && connectedRSSI != val {
            connectedRSSI = val
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard peripheral === connectedPeripheral,
              peripheral.state == .connected,
              let rxChar = rxCharacteristic else { return }
        while !pendingWithoutResponseQueue.isEmpty && peripheral.canSendWriteWithoutResponse {
            let nextCmd = pendingWithoutResponseQueue.removeFirst()
            writeNormalizedCommand(
                nextCmd,
                to: peripheral,
                rxChar: rxChar,
                writeType: .withoutResponse,
                maxChunk: maxWriteNoRespLen
            )
        }
    }
}
