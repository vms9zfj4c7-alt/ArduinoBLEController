import Foundation
import Combine

/// Transport actif entre l'iPhone et la carte Arduino.
enum ConnectionTransport: String, CaseIterable, Identifiable {
    case ble = "BLE"
    case wifi = "Wi-Fi"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ble: return "Bluetooth (BLE)"
        case .wifi: return "Wi-Fi (TCP)"
        }
    }

    var shortBadge: String { rawValue }
}

/// Hub central unifiant BLEManager et WiFiManager derrière une interface unique pour les ViewModels.
final class ArduinoConnectionHub: ObservableObject {
    @Published var preferredTransport: ConnectionTransport {
        didSet {
            UserDefaults.standard.set(preferredTransport.rawValue, forKey: preferredTransportKey)
            if !connectionState.isConnected && !connectionState.isBusy {
                activeTransport = preferredTransport
                syncFromActiveTransport()
            }
        }
    }

    @Published private(set) var activeTransport: ConnectionTransport
    @Published private(set) var connectionState: BLEManager.ConnectionState = .disconnected
    @Published private(set) var detectedBoardCapability: ArduinoBoardCapability
    @Published private(set) var activeProfileDescription: String = "Aucun profil"
    @Published private(set) var lastConnectedDeviceName: String?
    @Published var lastErrorMessage: String?

    let logStore = BLELogStore(maxEntries: 200)
    let telemetryStore = BLETelemetryStore()
    let bleManager: BLEManager
    let wifiManager: WiFiManager

    private let preferredTransportKey = "arduino_preferred_transport_v1"
    private var cancellables: Set<AnyCancellable> = []

    init(initialBoardType: ArduinoBoardType = .auto) {
        let savedRaw = UserDefaults.standard.string(forKey: "arduino_preferred_transport_v1")
        let initialTransport = ConnectionTransport(rawValue: savedRaw ?? "") ?? .ble
        self.preferredTransport = initialTransport
        self.activeTransport = initialTransport
        self.detectedBoardCapability = ArduinoBoardCapability.defaultCapability(
            for: initialBoardType == .auto ? .unoR4WiFi : initialBoardType,
            isAutoDetected: initialBoardType == .auto
        )
        self.bleManager = BLEManager(
            initialBoardType: initialBoardType,
            logStore: logStore,
            telemetryStore: telemetryStore
        )
        self.wifiManager = WiFiManager(
            initialBoardType: initialBoardType,
            logStore: logStore,
            telemetryStore: telemetryStore
        )

        bindTransports()
        syncFromActiveTransport()
    }

    // MARK: - Envoi unifié des commandes

    func send(command: String, preferWithoutResponse: Bool = true) {
        if wifiManager.connectionState.isConnected {
            wifiManager.send(command: command, preferWithoutResponse: preferWithoutResponse)
        } else if bleManager.connectionState.isConnected {
            bleManager.send(command: command, preferWithoutResponse: preferWithoutResponse)
        } else if activeTransport == .wifi {
            wifiManager.send(command: command, preferWithoutResponse: preferWithoutResponse)
        } else {
            bleManager.send(command: command, preferWithoutResponse: preferWithoutResponse)
        }
    }

    func sendPrepared(_ packet: BLEPreparedCommand, preferWithoutResponse: Bool = true) {
        if wifiManager.connectionState.isConnected {
            wifiManager.sendPrepared(packet, preferWithoutResponse: preferWithoutResponse)
        } else if bleManager.connectionState.isConnected {
            bleManager.sendPrepared(packet, preferWithoutResponse: preferWithoutResponse)
        } else if activeTransport == .wifi {
            wifiManager.sendPrepared(packet, preferWithoutResponse: preferWithoutResponse)
        } else {
            bleManager.sendPrepared(packet, preferWithoutResponse: preferWithoutResponse)
        }
    }

    func requestBoardInfo() {
        if wifiManager.connectionState.isConnected {
            wifiManager.requestBoardInfo()
        } else if bleManager.connectionState.isConnected {
            bleManager.requestBoardInfo()
        }
    }

    func requestTelemetry() {
        if wifiManager.connectionState.isConnected {
            wifiManager.requestTelemetry()
        } else if bleManager.connectionState.isConnected {
            bleManager.requestTelemetry()
        }
    }

    func disconnect() {
        if wifiManager.connectionState != .disconnected {
            wifiManager.disconnect()
        }
        if bleManager.connectionState != .disconnected {
            bleManager.disconnect()
        }
    }

    func reconnectLastDevice() {
        if preferredTransport == .wifi {
            if bleManager.connectionState != .disconnected {
                bleManager.disconnect(silent: true)
            }
            activeTransport = .wifi
            wifiManager.reconnectLastDevice()
        } else {
            if wifiManager.connectionState != .disconnected {
                wifiManager.disconnect(silent: true)
            }
            activeTransport = .ble
            bleManager.reconnectLastDevice()
        }
    }

    func setManualBoardOverride(_ boardType: ArduinoBoardType) {
        bleManager.setManualBoardOverride(boardType)
        wifiManager.setManualBoardOverride(boardType)
        syncFromActiveTransport()
    }

    func clearLogs() {
        logStore.clear()
    }

    func clearError() {
        lastErrorMessage = nil
        bleManager.lastErrorMessage = nil
        wifiManager.lastErrorMessage = nil
    }

    func setAppActive(_ isActive: Bool) {
        bleManager.setAppActive(isActive)
        wifiManager.setAppActive(isActive)
    }

    // MARK: - Synchronisation des transports

    private func bindTransports() {
        bleManager.$connectionState
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                if state != .disconnected {
                    if self.wifiManager.connectionState != .disconnected {
                        self.wifiManager.disconnect(silent: true)
                    }
                    self.activeTransport = .ble
                } else if self.wifiManager.connectionState == .disconnected {
                    self.activeTransport = self.preferredTransport
                }
                self.syncFromActiveTransport()
            }
            .store(in: &cancellables)

        wifiManager.$connectionState
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                if state != .disconnected {
                    if self.bleManager.connectionState != .disconnected {
                        self.bleManager.disconnect(silent: true)
                    }
                    self.activeTransport = .wifi
                } else if self.bleManager.connectionState == .disconnected {
                    self.activeTransport = self.preferredTransport
                }
                self.syncFromActiveTransport()
            }
            .store(in: &cancellables)

        bleManager.$detectedBoardCapability
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.syncFromActiveTransport()
            }
            .store(in: &cancellables)

        wifiManager.$detectedBoardCapability
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.syncFromActiveTransport()
            }
            .store(in: &cancellables)

        bleManager.$activeProfileDescription
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.syncFromActiveTransport()
            }
            .store(in: &cancellables)

        wifiManager.$activeProfileDescription
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.syncFromActiveTransport()
            }
            .store(in: &cancellables)

        bleManager.$lastConnectedDeviceName
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.syncFromActiveTransport()
            }
            .store(in: &cancellables)

        wifiManager.$lastConnectedDeviceName
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.syncFromActiveTransport()
            }
            .store(in: &cancellables)

        bleManager.$lastErrorMessage
            .removeDuplicates()
            .sink { [weak self] msg in
                if let msg {
                    self?.lastErrorMessage = msg
                }
            }
            .store(in: &cancellables)

        wifiManager.$lastErrorMessage
            .removeDuplicates()
            .sink { [weak self] msg in
                if let msg {
                    self?.lastErrorMessage = msg
                }
            }
            .store(in: &cancellables)
    }

    private func syncFromActiveTransport() {
        let resolvedTransport: ConnectionTransport
        if wifiManager.connectionState != .disconnected {
            resolvedTransport = .wifi
        } else if bleManager.connectionState != .disconnected {
            resolvedTransport = .ble
        } else {
            resolvedTransport = preferredTransport
        }

        if activeTransport != resolvedTransport {
            activeTransport = resolvedTransport
        }

        let targetState: BLEManager.ConnectionState
        let targetCapability: ArduinoBoardCapability
        let targetProfile: String
        let targetLastName: String?

        switch resolvedTransport {
        case .wifi:
            targetState = wifiManager.connectionState
            targetCapability = wifiManager.detectedBoardCapability
            targetProfile = wifiManager.activeProfileDescription
            targetLastName = wifiManager.lastConnectedDeviceName
        case .ble:
            targetState = bleManager.connectionState
            targetCapability = bleManager.detectedBoardCapability
            targetProfile = bleManager.activeProfileDescription
            targetLastName = bleManager.lastConnectedDeviceName
        }

        if connectionState != targetState {
            connectionState = targetState
        }
        if detectedBoardCapability != targetCapability {
            detectedBoardCapability = targetCapability
        }
        if activeProfileDescription != targetProfile {
            activeProfileDescription = targetProfile
        }
        if lastConnectedDeviceName != targetLastName {
            lastConnectedDeviceName = targetLastName
        }
    }
}
