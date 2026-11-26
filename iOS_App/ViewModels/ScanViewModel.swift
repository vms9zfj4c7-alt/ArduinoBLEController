import Foundation
import CoreBluetooth
import Combine

/// ViewModel gérant l'écran de scan et de connexion aux cartes Arduino BLE.
final class ScanViewModel: ObservableObject {
    @Published var showOnlyArduinoDevices: Bool = false
    @Published var searchText: String = ""

    @Published private(set) var filteredDevices: [BLEDevice] = []
    @Published private(set) var connectionState: BLEManager.ConnectionState = .disconnected
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var lastConnectedDeviceName: String?
    @Published var errorMessage: String?

    private let bleManager: BLEManager

    init(bleManager: BLEManager) {
        self.bleManager = bleManager

        Publishers.CombineLatest3(
            bleManager.$discoveredDevices,
            $showOnlyArduinoDevices,
            $searchText
        )
        .map { devices, onlyArduino, rawQuery in
            let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !onlyArduino && query.isEmpty {
                return devices
            }
            return devices.filter { device in
                if onlyArduino && !device.isLikelyArduino {
                    return false
                }
                if query.isEmpty { return true }
                return device.name.localizedCaseInsensitiveContains(query)
                    || device.detectedModuleHint.localizedCaseInsensitiveContains(query)
            }
        }
        .receive(on: DispatchQueue.main)
        .assign(to: &$filteredDevices)

        bleManager.$connectionState
            .receive(on: DispatchQueue.main)
            .assign(to: &$connectionState)

        bleManager.$bluetoothState
            .receive(on: DispatchQueue.main)
            .assign(to: &$bluetoothState)

        bleManager.$lastConnectedDeviceName
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastConnectedDeviceName)

        bleManager.$lastErrorMessage
            .receive(on: DispatchQueue.main)
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
