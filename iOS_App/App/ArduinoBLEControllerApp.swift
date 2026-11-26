import SwiftUI

/// Point d'entrée principal de l'application iOS Arduino BLE Controller.
@main
struct ArduinoBLEControllerApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var scanViewModel: ScanViewModel
    @StateObject private var controllerViewModel: ControllerViewModel
    @StateObject private var mappingViewModel: MappingViewModel

    init() {
        let storage = ControllerStorageService()
        let ble = BLEManager(initialBoardType: storage.selectedBoardPreference)
        let ps4 = PS4ControllerManager()

        _scanViewModel = StateObject(wrappedValue: ScanViewModel(bleManager: ble))
        _controllerViewModel = StateObject(
            wrappedValue: ControllerViewModel(
                bleManager: ble,
                storageService: storage,
                ps4Manager: ps4
            )
        )
        _mappingViewModel = StateObject(
            wrappedValue: MappingViewModel(
                bleManager: ble,
                storageService: storage,
                ps4Manager: ps4
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            MainTabView(
                scanViewModel: scanViewModel,
                controllerViewModel: controllerViewModel,
                mappingViewModel: mappingViewModel
            )
            .onChange(of: scenePhase) { newPhase in
                switch newPhase {
                case .active:
                    controllerViewModel.handleAppLifecycle(isActive: true)
                case .background:
                    controllerViewModel.handleAppLifecycle(isActive: false)
                default:
                    break
                }
            }
        }
    }
}
