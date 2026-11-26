import Foundation
import Combine

/// ViewModel gérant la page d'assignation des boutons style manette, l'adaptation Arduino et la manette PS4.
final class MappingViewModel: ObservableObject {
    @Published private(set) var assignments: [GamepadSlot: ButtonAssignment] = [:]
    @Published private(set) var boardCapability: ArduinoBoardCapability
    @Published private(set) var selectedBoardPreference: ArduinoBoardType
    @Published private(set) var activePreset: BuiltInPresetKind
    @Published private(set) var isConnected: Bool = false

    @Published private(set) var isPS4Connected: Bool = false
    @Published private(set) var ps4ControllerName: String = "Aucune manette"
    @Published private(set) var ps4BatteryPercentage: Int?
    @Published private(set) var ps4LeftStickAsDPad: Bool
    @Published private(set) var ps4RightStickAsSliders: Bool

    @Published var selectedSlotForEditing: GamepadSlot?

    private let bleManager: BLEManager
    private let storageService: ControllerStorageService
    private let ps4Manager: PS4ControllerManager

    init(
        bleManager: BLEManager,
        storageService: ControllerStorageService,
        ps4Manager: PS4ControllerManager
    ) {
        self.bleManager = bleManager
        self.storageService = storageService
        self.ps4Manager = ps4Manager
        self.boardCapability = bleManager.detectedBoardCapability
        self.selectedBoardPreference = storageService.selectedBoardPreference
        self.activePreset = storageService.activePreset
        self.assignments = storageService.assignments
        self.ps4LeftStickAsDPad = storageService.ps4LeftStickAsDPad
        self.ps4RightStickAsSliders = storageService.ps4RightStickAsSliders

        // Applique au démarrage la préférence enregistrée au gestionnaire BLE
        bleManager.setManualBoardOverride(storageService.selectedBoardPreference)

        bleManager.$detectedBoardCapability
            .receive(on: DispatchQueue.main)
            .assign(to: &$boardCapability)

        bleManager.$connectionState
            .receive(on: DispatchQueue.main)
            .map { $0.isConnected }
            .assign(to: &$isConnected)

        storageService.$assignments
            .receive(on: DispatchQueue.main)
            .assign(to: &$assignments)

        storageService.$selectedBoardPreference
            .receive(on: DispatchQueue.main)
            .assign(to: &$selectedBoardPreference)

        storageService.$activePreset
            .receive(on: DispatchQueue.main)
            .assign(to: &$activePreset)

        storageService.$ps4LeftStickAsDPad
            .receive(on: DispatchQueue.main)
            .assign(to: &$ps4LeftStickAsDPad)

        storageService.$ps4RightStickAsSliders
            .receive(on: DispatchQueue.main)
            .assign(to: &$ps4RightStickAsSliders)

        ps4Manager.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPS4Connected)

        ps4Manager.$controllerName
            .receive(on: DispatchQueue.main)
            .assign(to: &$ps4ControllerName)

        ps4Manager.$batteryPercentage
            .receive(on: DispatchQueue.main)
            .assign(to: &$ps4BatteryPercentage)
    }

    func assignment(for slot: GamepadSlot) -> ButtonAssignment {
        assignments[slot] ?? storageService.assignment(for: slot)
    }

    func selectBoardPreference(_ type: ArduinoBoardType) {
        storageService.setBoardPreference(type)
        bleManager.setManualBoardOverride(type)
        storageService.adaptIfNotCustomized(to: bleManager.detectedBoardCapability)
    }

    func applyPreset(_ preset: BuiltInPresetKind) {
        storageService.applyPreset(preset, for: boardCapability)
    }

    func adaptPresetToCurrentBoard() {
        storageService.applyPreset(activePreset, for: boardCapability)
    }

    func updatePS4Options(leftStickAsDPad: Bool, rightStickAsSliders: Bool) {
        storageService.setPS4Options(
            leftStickAsDPad: leftStickAsDPad,
            rightStickAsSliders: rightStickAsSliders
        )
    }

    func refreshPS4Controllers() {
        ps4Manager.refreshConnectedControllers()
    }

    func saveAssignment(_ updated: ButtonAssignment) {
        storageService.updateAssignment(updated, markCustom: true)
    }

    func testAssignment(_ assignment: ButtonAssignment, isActive: Bool = true) {
        let cmds = assignment.generateCommands(isActive: isActive)
        for cmd in cmds {
            bleManager.send(command: cmd, preferWithoutResponse: false)
        }
    }
}
