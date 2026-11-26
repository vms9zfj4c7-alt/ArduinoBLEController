import Foundation
import Network
import Combine

/// Décodeur ligne-par-ligne partagé entre BLE et Wi-Fi pour INFO:, DATA: et ERR:.
final class ArduinoLineStreamProcessor {
    private let logStore: BLELogStore
    private let telemetryStore: BLETelemetryStore
    private var rxDataBuffer: Data

    var onCapabilityDetected: ((ArduinoBoardCapability) -> Void)?
    var onErrorMessage: ((String) -> Void)?

    init(logStore: BLELogStore, telemetryStore: BLETelemetryStore) {
        self.logStore = logStore
        self.telemetryStore = telemetryStore
        var buffer = Data()
        buffer.reserveCapacity(128)
        self.rxDataBuffer = buffer
    }

    func reset() {
        rxDataBuffer.removeAll(keepingCapacity: true)
    }

    func ingest(_ data: Data) {
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
            logStore.append(.rx, line)
            if let capability = ArduinoBoardCapability.parse(infoLine: line) {
                onCapabilityDetected?(capability)
                logStore.append(.info, "Carte identifiée : \(capability.boardType.displayName) (\(capability.availablePins.count) broches)")
            }
            return
        }

        if line.hasPrefix("DATA:") {
            parseTelemetryLine(line)
            logStore.append(.rx, line)
            return
        }

        if line.hasPrefix("ERR:") {
            logStore.append(.error, line)
            onErrorMessage?("Arduino : \(line)")
            return
        }

        logStore.append(.rx, line)
    }

    private func parseTelemetryLine(_ line: String) {
        var cursor = line.index(line.startIndex, offsetBy: 5)
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

/// Carte Arduino découverte sur le réseau Wi-Fi local via Bonjour (_arduinowifi._tcp).
struct WiFiDiscoveredDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let type: String
    let domain: String
    let endpoint: NWEndpoint
    let inferredBoardType: ArduinoBoardType
}

/// Gestionnaire Wi-Fi TCP local (Network.framework) : découverte Bonjour mDNS et connexion IP:Port directe.
final class WiFiManager: ObservableObject {
    @Published private(set) var connectionState: BLEManager.ConnectionState = .disconnected
    @Published private(set) var discoveredDevices: [WiFiDiscoveredDevice] = []
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var activeProfileDescription: String = "Aucun profil"
    @Published private(set) var detectedBoardCapability: ArduinoBoardCapability
    @Published private(set) var manualBoardOverride: ArduinoBoardType = .auto
    @Published private(set) var lastConnectedDeviceName: String?
    @Published private(set) var lastSavedHost: String?
    @Published private(set) var lastSavedPort: UInt16
    @Published var lastErrorMessage: String?

    let logStore: BLELogStore
    let telemetryStore: BLETelemetryStore

    private let lastHostKey = "arduino_wifi_last_host_v1"
    private let lastPortKey = "arduino_wifi_last_port_v1"
    private let lastNameKey = "arduino_wifi_last_name_v1"
    private let lastBonjourNameKey = "arduino_wifi_last_bonjour_name_v1"
    private let lastBonjourTypeKey = "arduino_wifi_last_bonjour_type_v1"
    private let lastBonjourDomainKey = "arduino_wifi_last_bonjour_domain_v1"

    private let networkQueue = DispatchQueue(label: "com.arduino.blecontroller.wifi", qos: .userInitiated)
    private let rxProcessor: ArduinoLineStreamProcessor

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var connectionToken: UInt64 = 0
    private var connectionTimeoutTimer: Timer?
    private var pendingQueue: [BLEPreparedCommand] = []
    private var isSendingPacket: Bool = false
    private var activeEndpoint: NWEndpoint?
    private var lastAutoDetectedCapability: ArduinoBoardCapability?

    init(
        initialBoardType: ArduinoBoardType = .auto,
        logStore: BLELogStore = BLELogStore(maxEntries: 200),
        telemetryStore: BLETelemetryStore = BLETelemetryStore()
    ) {
        self.logStore = logStore
        self.telemetryStore = telemetryStore
        self.manualBoardOverride = initialBoardType
        self.detectedBoardCapability = ArduinoBoardCapability.defaultCapability(
            for: initialBoardType == .auto ? .unoR4WiFi : initialBoardType,
            isAutoDetected: initialBoardType == .auto
        )
        let savedPortInt = UserDefaults.standard.integer(forKey: lastPortKey)
        self.lastSavedPort = (savedPortInt > 0 && savedPortInt <= 65535)
            ? UInt16(savedPortInt)
            : BLEProtocolConstants.defaultWiFiPort
        self.lastSavedHost = UserDefaults.standard.string(forKey: lastHostKey)
        self.lastConnectedDeviceName = UserDefaults.standard.string(forKey: lastNameKey)
        self.rxProcessor = ArduinoLineStreamProcessor(logStore: logStore, telemetryStore: telemetryStore)

        self.rxProcessor.onCapabilityDetected = { [weak self] capability in
            guard let self else { return }
            self.lastAutoDetectedCapability = capability
            if self.manualBoardOverride == .auto && self.detectedBoardCapability != capability {
                self.detectedBoardCapability = capability
            }
        }
        self.rxProcessor.onErrorMessage = { [weak self] message in
            self?.lastErrorMessage = message
        }
    }

    deinit {
        connectionTimeoutTimer?.invalidate()
        browser?.cancel()
        connection?.cancel()
    }

    // MARK: - Découverte Bonjour (_arduinowifi._tcp)

    func startDiscovery() {
        stopDiscovery(silent: true)
        lastErrorMessage = nil

        let descriptor = NWBrowser.Descriptor.bonjour(
            type: BLEProtocolConstants.wifiBonjourServiceType,
            domain: "local."
        )
        let params = NWParameters()
        params.includePeerToPeer = true

        let newBrowser = NWBrowser(for: descriptor, using: params)
        newBrowser.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.handleBrowserState(state)
            }
        }
        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                self?.handleBrowseResults(results)
            }
        }

        browser = newBrowser
        discoveredDevices = []
        isScanning = true
        logStore.append(.info, "Recherche Wi-Fi locale (\(BLEProtocolConstants.wifiBonjourServiceType))...")
        newBrowser.start(queue: networkQueue)
    }

    func stopDiscovery(silent: Bool = false) {
        guard browser != nil || isScanning else { return }
        browser?.cancel()
        browser = nil
        isScanning = false
        if !silent {
            logStore.append(.info, "Recherche Wi-Fi arrêtée.")
        }
    }

    // MARK: - Connexion TCP

    func connect(host: String, port: UInt16) {
        let cleanedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedHost.isEmpty, port > 0 else {
            let msg = "Adresse IP ou port Wi-Fi invalide."
            lastErrorMessage = msg
            logStore.append(.error, msg)
            return
        }

        let nwHost = NWEndpoint.Host(cleanedHost)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            let msg = "Port TCP Wi-Fi invalide (\(port))."
            lastErrorMessage = msg
            logStore.append(.error, msg)
            return
        }

        let displayName = "\(cleanedHost):\(port)"
        let endpoint = NWEndpoint.hostPort(host: nwHost, port: nwPort)
        startConnection(
            to: endpoint,
            displayName: displayName,
            hostForPersistence: cleanedHost,
            portForPersistence: port,
            bonjourService: nil
        )
    }

    func connect(to device: WiFiDiscoveredDevice) {
        startConnection(
            to: device.endpoint,
            displayName: device.name,
            hostForPersistence: nil,
            portForPersistence: nil,
            bonjourService: (device.name, device.type, device.domain)
        )
    }

    func reconnectLastDevice() {
        if let endpoint = activeEndpoint, let name = lastConnectedDeviceName {
            startConnection(
                to: endpoint,
                displayName: name,
                hostForPersistence: lastSavedHost,
                portForPersistence: lastSavedPort,
                bonjourService: nil
            )
            return
        }

        if let host = UserDefaults.standard.string(forKey: lastHostKey), !host.isEmpty {
            let savedPort = UserDefaults.standard.integer(forKey: lastPortKey)
            let port = (savedPort > 0 && savedPort <= 65535) ? UInt16(savedPort) : BLEProtocolConstants.defaultWiFiPort
            connect(host: host, port: port)
            return
        }

        if let bName = UserDefaults.standard.string(forKey: lastBonjourNameKey),
           let bType = UserDefaults.standard.string(forKey: lastBonjourTypeKey),
           let bDomain = UserDefaults.standard.string(forKey: lastBonjourDomainKey) {
            let endpoint = NWEndpoint.service(name: bName, type: bType, domain: bDomain, interface: nil)
            startConnection(
                to: endpoint,
                displayName: bName,
                hostForPersistence: nil,
                portForPersistence: nil,
                bonjourService: (bName, bType, bDomain)
            )
            return
        }

        let msg = "Aucune carte Wi-Fi enregistrée pour reconnexion rapide."
        lastErrorMessage = msg
        logStore.append(.error, msg)
    }

    func disconnect(silent: Bool = false) {
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil
        connectionToken &+= 1

        let activeConn = connection
        connection = nil
        activeConn?.stateUpdateHandler = nil
        activeConn?.cancel()

        resetSessionState()
        if connectionState != .disconnected {
            connectionState = .disconnected
        }
        if !silent {
            logStore.append(.info, "Déconnecté du module Wi-Fi.")
        }
    }

    // MARK: - Envoi des commandes TCP

    func send(command: String, preferWithoutResponse: Bool = true) {
        let packet = BLEPreparedCommand.make(command)
        sendPrepared(packet, preferWithoutResponse: preferWithoutResponse)
    }

    func sendPrepared(_ packet: BLEPreparedCommand, preferWithoutResponse _: Bool = true) {
        guard case .connected = connectionState, let activeConn = connection else {
            logStore.append(.error, "Envoi Wi-Fi impossible : aucune carte connectée.")
            return
        }

        if packet.payload == BLEProtocolConstants.emergencyStopPacket.payload {
            pendingQueue.removeAll(keepingCapacity: true)
        }

        if isSendingPacket {
            enqueuePendingPacket(packet)
            return
        }

        writePacket(packet, on: activeConn, token: connectionToken)
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
            } else if let name = lastConnectedDeviceName {
                let inferred = ArduinoBoardCapability.inferFromDeviceMetadata(name: name, serviceUUIDStrings: [])
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

    func setAppActive(_ isActive: Bool) {
        if !isActive {
            stopDiscovery(silent: true)
        }
    }

    // MARK: - Logique interne NWConnection / NWBrowser

    private func startConnection(
        to endpoint: NWEndpoint,
        displayName: String,
        hostForPersistence: String?,
        portForPersistence: UInt16?,
        bonjourService: (name: String, type: String, domain: String)?
    ) {
        disconnect(silent: true)
        lastErrorMessage = nil

        connectionToken &+= 1
        let currentToken = connectionToken
        activeEndpoint = endpoint
        connectionState = .connecting(displayName)
        logStore.append(.info, "Connexion Wi-Fi TCP vers \(displayName)...")

        let newConn = NWConnection(to: endpoint, using: makeTCPParameters())
        connection = newConn

        newConn.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self, self.connectionToken == currentToken else { return }
                self.handleConnectionState(
                    state,
                    connection: newConn,
                    token: currentToken,
                    displayName: displayName,
                    hostForPersistence: hostForPersistence,
                    portForPersistence: portForPersistence,
                    bonjourService: bonjourService
                )
            }
        }

        startConnectionTimeout(for: displayName, token: currentToken)
        newConn.start(queue: networkQueue)
    }

    private func makeTCPParameters() -> NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 10
        tcpOptions.connectionTimeout = 8
        return NWParameters(tls: nil, tcp: tcpOptions)
    }

    private func handleConnectionState(
        _ state: NWConnection.State,
        connection activeConn: NWConnection,
        token: UInt64,
        displayName: String,
        hostForPersistence: String?,
        portForPersistence: UInt16?,
        bonjourService: (name: String, type: String, domain: String)?
    ) {
        switch state {
        case .ready:
            connectionTimeoutTimer?.invalidate()
            connectionTimeoutTimer = nil

            lastConnectedDeviceName = displayName
            UserDefaults.standard.set(displayName, forKey: lastNameKey)

            if let host = hostForPersistence, let port = portForPersistence {
                lastSavedHost = host
                lastSavedPort = port
                UserDefaults.standard.set(host, forKey: lastHostKey)
                UserDefaults.standard.set(Int(port), forKey: lastPortKey)
                UserDefaults.standard.removeObject(forKey: lastBonjourNameKey)
            } else if let bService = bonjourService {
                UserDefaults.standard.set(bService.name, forKey: lastBonjourNameKey)
                UserDefaults.standard.set(bService.type, forKey: lastBonjourTypeKey)
                UserDefaults.standard.set(bService.domain, forKey: lastBonjourDomainKey)
                UserDefaults.standard.removeObject(forKey: lastHostKey)
            }

            if manualBoardOverride == .auto {
                let inferred = ArduinoBoardCapability.inferFromDeviceMetadata(name: displayName, serviceUUIDStrings: [])
                let cap = ArduinoBoardCapability.defaultCapability(for: inferred, isAutoDetected: true)
                if detectedBoardCapability != cap {
                    detectedBoardCapability = cap
                }
            }

            activeProfileDescription = "Wi-Fi TCP (\(displayName))"
            connectionState = .connected(displayName)
            logStore.append(.info, "Connecté en Wi-Fi à \(displayName).")

            receiveLoop(for: activeConn, token: token)
            requestBoardInfo()

        case .waiting(let error):
            let desc = error.localizedDescription
            logStore.append(.info, "Wi-Fi en attente (\(desc))...")

        case .failed(let error):
            let msg = "Connexion Wi-Fi échouée : \(error.localizedDescription)"
            lastErrorMessage = msg
            logStore.append(.error, msg)
            disconnect(silent: true)

        case .cancelled:
            if connectionState != .disconnected {
                disconnect(silent: true)
            }

        default:
            break
        }
    }

    private func receiveLoop(for activeConn: NWConnection, token: UInt64) {
        activeConn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            DispatchQueue.main.async {
                guard let self, self.connectionToken == token else { return }

                if let data, !data.isEmpty {
                    self.rxProcessor.ingest(data)
                }

                if let error {
                    if case .connected = self.connectionState {
                        let msg = "Flux Wi-Fi interrompu : \(error.localizedDescription)"
                        self.lastErrorMessage = msg
                        self.logStore.append(.error, msg)
                    }
                    self.disconnect(silent: true)
                    return
                }

                if isComplete {
                    self.logStore.append(.info, "Connexion Wi-Fi fermée par l'Arduino.")
                    self.disconnect(silent: true)
                    return
                }

                self.receiveLoop(for: activeConn, token: token)
            }
        }
    }

    private func writePacket(_ packet: BLEPreparedCommand, on activeConn: NWConnection, token: UInt64) {
        let data = packet.payload
        guard !data.isEmpty else { return }
        isSendingPacket = true

        activeConn.send(content: data, completion: .contentProcessed { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.connectionToken == token else { return }
                self.isSendingPacket = false

                if let error {
                    self.pendingQueue.removeAll(keepingCapacity: true)
                    let msg = "Erreur d'envoi Wi-Fi : \(error.localizedDescription)"
                    self.lastErrorMessage = msg
                    self.logStore.append(.error, msg)
                    return
                }

                self.logStore.append(.tx, packet.logText)

                if !self.pendingQueue.isEmpty, case .connected = self.connectionState, let conn = self.connection {
                    let next = self.pendingQueue.removeFirst()
                    self.writePacket(next, on: conn, token: token)
                }
            }
        })
    }

    private func enqueuePendingPacket(_ packet: BLEPreparedCommand) {
        if let key = packet.coalesceKey,
           let existingIdx = pendingQueue.firstIndex(where: { $0.coalesceKey == key }) {
            pendingQueue[existingIdx] = packet
            return
        }
        if pendingQueue.count >= 8 {
            pendingQueue.removeFirst()
        }
        pendingQueue.append(packet)
    }

    private func startConnectionTimeout(for displayName: String, token: UInt64) {
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            guard let self, self.connectionToken == token else { return }
            guard !self.connectionState.isConnected else { return }
            let msg = "Délai dépassé pour \(displayName). Vérifiez le réseau Wi-Fi et le port TCP."
            self.lastErrorMessage = msg
            self.logStore.append(.error, msg)
            self.disconnect(silent: true)
        }
    }

    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .failed(let error):
            let msg = "Erreur recherche Wi-Fi : \(error.localizedDescription)"
            lastErrorMessage = msg
            logStore.append(.error, msg)
            isScanning = false
        case .waiting(let error):
            let msg = "Réseau local bloqué ou indisponible (\(error.localizedDescription))."
            logStore.append(.info, msg)
        case .cancelled:
            isScanning = false
        default:
            break
        }
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        var devices: [WiFiDiscoveredDevice] = []
        devices.reserveCapacity(results.count)

        for result in results {
            guard case let .service(name, type, domain, _) = result.endpoint else { continue }
            let id = "\(name)|\(type)|\(domain)"
            let inferred = ArduinoBoardCapability.inferFromDeviceMetadata(name: name, serviceUUIDStrings: [])
            devices.append(
                WiFiDiscoveredDevice(
                    id: id,
                    name: name,
                    type: type,
                    domain: domain,
                    endpoint: result.endpoint,
                    inferredBoardType: inferred
                )
            )
        }

        devices.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if discoveredDevices != devices {
            discoveredDevices = devices
        }
    }

    private func resetSessionState() {
        pendingQueue.removeAll(keepingCapacity: true)
        isSendingPacket = false
        rxProcessor.reset()
        telemetryStore.reset()
        activeProfileDescription = "Aucun profil"
        lastAutoDetectedCapability = nil
    }
}
