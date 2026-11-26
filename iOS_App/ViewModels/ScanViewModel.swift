import Foundation
import CoreBluetooth
import Combine

/// ViewModel gérant le scan BLE et la connexion Wi-Fi TCP aux cartes Arduino.
final class ScanViewModel: ObservableObject {
    enum FilterMode: Int, CaseIterable, Identifiable {
        case all
        case namedOnly
        case arduinoOnly

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .all: return "Tous"
            case .namedOnly: return "Nommés"
            case .arduinoOnly: return "Arduino"
            }
        }
    }

    @Published var transportTab: ConnectionTransport {
        didSet {
            guard oldValue != transportTab else { return }
            connectionHub.preferredTransport = transportTab
            handleTransportTabChanged(transportTab)
        }
    }

    @Published var filterMode: FilterMode = .all
    @Published var searchText: String = ""
    @Published var selectedDeviceID: UUID?

    @Published var wifiHost: String
    @Published var wifiPortText: String

    @Published private(set) var filteredDevices: [BLEDevice] = []
    @Published private(set) var wifiDevices: [WiFiDiscoveredDevice] = []
    @Published private(set) var isWiFiScanning: Bool = false
    @Published private(set) var connectionState: BLEManager.ConnectionState = .disconnected
    @Published private(set) var activeTransport: ConnectionTransport = .ble
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var lastConnectedDeviceName: String?
    @Published private(set) var lastBLEDeviceName: String?
    @Published private(set) var lastWiFiDeviceName: String?
    @Published var errorMessage: String?

    private let connectionHub: ArduinoConnectionHub
    private var didAutoScanOnLaunch = false

    init(connectionHub: ArduinoConnectionHub) {
        self.connectionHub = connectionHub
        self.transportTab = connectionHub.preferredTransport
        self.wifiHost = connectionHub.wifiManager.lastSavedHost ?? BLEProtocolConstants.defaultWiFiAPHost
        self.wifiPortText = String(connectionHub.wifiManager.lastSavedPort)

        let ble = connectionHub.bleManager
        let wifi = connectionHub.wifiManager

        Publishers.CombineLatest3(
            ble.$discoveredDevices,
            $filterMode,
            $searchText
        )
        .map { devices, mode, rawQuery in
            let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            return devices.filter { device in
                switch mode {
                case .namedOnly:
                    if !device.hasResolvedName && !device.isLikelyArduino {
                        return false
                    }
                case .arduinoOnly:
                    if !device.isLikelyArduino {
                        return false
                    }
                case .all:
                    break
                }
                if query.isEmpty { return true }
                return device.displayName.localizedCaseInsensitiveContains(query)
                    || device.detectedModuleHint.localizedCaseInsensitiveContains(query)
                    || (device.manufacturerName?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        .removeDuplicates()
        .assign(to: &$filteredDevices)

        wifi.$discoveredDevices
            .removeDuplicates()
            .assign(to: &$wifiDevices)

        wifi.$isScanning
            .removeDuplicates()
            .assign(to: &$isWiFiScanning)

        connectionHub.$connectionState
            .removeDuplicates()
            .assign(to: &$connectionState)

        connectionHub.$activeTransport
            .removeDuplicates()
            .assign(to: &$activeTransport)

        ble.$bluetoothState
            .removeDuplicates()
            .assign(to: &$bluetoothState)

        connectionHub.$lastConnectedDeviceName
            .removeDuplicates()
            .assign(to: &$lastConnectedDeviceName)

        ble.$lastConnectedDeviceName
            .removeDuplicates()
            .assign(to: &$lastBLEDeviceName)

        wifi.$lastConnectedDeviceName
            .removeDuplicates()
            .assign(to: &$lastWiFiDeviceName)

        connectionHub.$lastErrorMessage
            .removeDuplicates()
            .assign(to: &$errorMessage)
    }

    var isScanning: Bool {
        if case .scanning = connectionState { return true }
        return false
    }

    // MARK: - Actions BLE

    func toggleScan() {
        connectionHub.preferredTransport = .ble
        if isScanning {
            connectionHub.bleManager.stopScan()
        } else {
            connectionHub.bleManager.startScan()
        }
    }

    func startAutoScanIfNeeded() {
        if transportTab == .wifi {
            startWiFiDiscovery()
            return
        }
        guard !didAutoScanOnLaunch,
              bluetoothState == .poweredOn,
              case .disconnected = connectionState else { return }
        didAutoScanOnLaunch = true
        connectionHub.bleManager.startScan()
    }

    func stopScanIfActive() {
        if isScanning {
            connectionHub.bleManager.stopScan()
        }
        if isWiFiScanning {
            connectionHub.wifiManager.stopDiscovery(silent: true)
        }
    }

    func connect(to device: BLEDevice) {
        selectedDeviceID = device.id
        connectionHub.preferredTransport = .ble
        connectionHub.bleManager.connect(to: device)
    }

    func selectDevice(_ device: BLEDevice) {
        selectedDeviceID = device.id
    }

    func reconnectLastDevice() {
        connectionHub.preferredTransport = .ble
        connectionHub.bleManager.reconnectLastDevice()
    }

    // MARK: - Actions Wi-Fi

    func startWiFiDiscovery() {
        connectionHub.wifiManager.startDiscovery()
    }

    func stopWiFiDiscovery() {
        connectionHub.wifiManager.stopDiscovery(silent: true)
    }

    func toggleWiFiDiscovery() {
        if isWiFiScanning {
            connectionHub.wifiManager.stopDiscovery(silent: false)
        } else {
            connectionHub.wifiManager.startDiscovery()
        }
    }

    func applyWiFiAPPreset() {
        wifiHost = BLEProtocolConstants.defaultWiFiAPHost
        wifiPortText = String(BLEProtocolConstants.defaultWiFiPort)
    }

    func connectWiFiManual() {
        let portString = wifiPortText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let portInt = Int(portString), portInt >= 1, portInt <= 65535 else {
            let msg = "Port TCP Wi-Fi invalide (1 à 65535)."
            errorMessage = msg
            connectionHub.wifiManager.lastErrorMessage = msg
            return
        }
        connectionHub.preferredTransport = .wifi
        connectionHub.wifiManager.connect(host: wifiHost, port: UInt16(portInt))
    }

    func connectWiFiAP() {
        applyWiFiAPPreset()
        connectWiFiManual()
    }

    func connectWiFi(device: WiFiDiscoveredDevice) {
        connectionHub.preferredTransport = .wifi
        connectionHub.wifiManager.connect(to: device)
    }

    func reconnectLastWiFi() {
        connectionHub.preferredTransport = .wifi
        connectionHub.wifiManager.reconnectLastDevice()
    }

    // MARK: - Commun

    func disconnect() {
        connectionHub.disconnect()
    }

    func clearError() {
        errorMessage = nil
        connectionHub.clearError()
    }

    private func handleTransportTabChanged(_ tab: ConnectionTransport) {
        switch tab {
        case .wifi:
            if isScanning {
                connectionHub.bleManager.stopScan()
            }
            connectionHub.wifiManager.startDiscovery()
        case .ble:
            connectionHub.wifiManager.stopDiscovery(silent: true)
            startAutoScanIfNeeded()
        }
    }
}
