import Foundation
import CoreBluetooth
import Combine

/// ViewModel gérant l'écran de scan et de connexion aux cartes Arduino BLE.
final class ScanViewModel: ObservableObject {
    @Published var showOnlyArduinoDevices: Bool = false
    @Published var hideUnnamedBeacons: Bool = true
    @Published var searchText: String = ""

    @Published private(set) var filteredDevices: [BLEDevice] = []
    @Published private(set) var connectionState: BLEManager.ConnectionState = .disconnected
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var lastConnectedDeviceName: String?
    @Published var errorMessage: String?

    private let bleManager: BLEManager

    init(bleManager: BLEManager) {
        self.bleManager = bleManager

        Publishers.CombineLatest4(
            bleManager.$discoveredDevices,
            $showOnlyArduinoDevices,
            $hideUnnamedBeacons,
            $searchText
        )
        .map { devices, onlyArduino, hideUnnamed, rawQuery in
            let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            return devices.filter { device in
                if onlyArduino && !device.isLikelyArduino {
                    return false
                }
                if hideUnnamed && !device.hasResolvedName && !device.isLikelyArduino {
                    // Masquer les balises anonymes (Apple Continuity, AirTag, etc.) sans nom
                    return false
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

    func connect(to device: BLEDevice) {
        bleManager.connect(to: device)
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
