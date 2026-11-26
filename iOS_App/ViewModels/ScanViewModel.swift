import Foundation
import CoreBluetooth
import Combine

/// ViewModel gérant l'écran de scan et de connexion aux cartes Arduino BLE.
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

    @Published var filterMode: FilterMode = .all
    @Published var searchText: String = ""
    @Published var selectedDeviceID: UUID?

    @Published private(set) var filteredDevices: [BLEDevice] = []
    @Published private(set) var connectionState: BLEManager.ConnectionState = .disconnected
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var lastConnectedDeviceName: String?
    @Published var errorMessage: String?

    private let bleManager: BLEManager
    private var didAutoScanOnLaunch = false

    init(bleManager: BLEManager) {
        self.bleManager = bleManager

        Publishers.CombineLatest3(
            bleManager.$discoveredDevices,
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

        bleManager.$connectionState
            .removeDuplicates()
            .assign(to: &$connectionState)

        bleManager.$bluetoothState
            .removeDuplicates()
            .assign(to: &$bluetoothState)

        bleManager.$lastConnectedDeviceName
            .removeDuplicates()
            .assign(to: &$lastConnectedDeviceName)

        bleManager.$lastErrorMessage
            .removeDuplicates()
            .assign(to: &$errorMessage)
    }

    var isScanning: Bool {
        if case .scanning = connectionState { return true }
        return false
    }

    func toggleScan() {
        if isScanning {
            bleManager.stopScan()
        } else {
            bleManager.startScan()
        }
    }

    func startAutoScanIfNeeded() {
        guard !didAutoScanOnLaunch,
              bluetoothState == .poweredOn,
              case .disconnected = connectionState else { return }
        didAutoScanOnLaunch = true
        bleManager.startScan()
    }

    func stopScanIfActive() {
        if isScanning {
            bleManager.stopScan()
        }
    }

    func connect(to device: BLEDevice) {
        selectedDeviceID = device.id
        bleManager.connect(to: device)
    }

    func selectDevice(_ device: BLEDevice) {
        selectedDeviceID = device.id
    }

    func reconnectLastDevice() {
        bleManager.reconnectLastDevice()
    }

    func disconnect() {
        bleManager.disconnect()
    }

    func clearError() {
        errorMessage = nil
        bleManager.lastErrorMessage = nil
    }
}
