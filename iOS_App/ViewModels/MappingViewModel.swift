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
    @Published private(set) var isSimplifiedMode: Bool

    @Published var selectedSlotForEditing: GamepadSlot?

    private let connectionHub: ArduinoConnectionHub
    private let storageService: ControllerStorageService
    private let ps4Manager: PS4ControllerManager

    init(
        connectionHub: ArduinoConnectionHub,
        storageService: ControllerStorageService,
        ps4Manager: PS4ControllerManager
    ) {
        self.connectionHub = connectionHub
        self.storageService = storageService
        self.ps4Manager = ps4Manager
        self.boardCapability = connectionHub.detectedBoardCapability
        self.selectedBoardPreference = storageService.selectedBoardPreference
        self.activePreset = storageService.activePreset
        self.assignments = storageService.assignments
        self.ps4LeftStickAsDPad = storageService.ps4LeftStickAsDPad
        self.ps4RightStickAsSliders = storageService.ps4RightStickAsSliders
        self.isSimplifiedMode = storageService.isSimplifiedMode

        // Applique au démarrage la préférence enregistrée au gestionnaire de connexion
        connectionHub.setManualBoardOverride(storageService.selectedBoardPreference)

        connectionHub.$detectedBoardCapability
            .removeDuplicates()
            .assign(to: &$boardCapability)

        connectionHub.$connectionState
            .map { $0.isConnected }
            .removeDuplicates()
            .assign(to: &$isConnected)

        storageService.$assignments
            .removeDuplicates()
            .assign(to: &$assignments)

        storageService.$selectedBoardPreference
            .removeDuplicates()
            .assign(to: &$selectedBoardPreference)

        storageService.$activePreset
            .removeDuplicates()
            .assign(to: &$activePreset)

        storageService.$ps4LeftStickAsDPad
            .removeDuplicates()
            .assign(to: &$ps4LeftStickAsDPad)

        storageService.$ps4RightStickAsSliders
            .removeDuplicates()
            .assign(to: &$ps4RightStickAsSliders)

        storageService.$isSimplifiedMode
            .removeDuplicates()
            .assign(to: &$isSimplifiedMode)

        ps4Manager.$isConnected
            .removeDuplicates()
            .assign(to: &$isPS4Connected)

        ps4Manager.$controllerName
            .removeDuplicates()
            .assign(to: &$ps4ControllerName)

        ps4Manager.$batteryPercentage
            .removeDuplicates()
            .assign(to: &$ps4BatteryPercentage)
    }

    func assignment(for slot: GamepadSlot) -> ButtonAssignment {
        assignments[slot] ?? storageService.assignment(for: slot)
    }

    func selectBoardPreference(_ type: ArduinoBoardType) {
        storageService.setBoardPreference(type)
        connectionHub.setManualBoardOverride(type)
        storageService.adaptIfNotCustomized(to: connectionHub.detectedBoardCapability)
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

    func setSimplifiedMode(_ enabled: Bool) {
        storageService.setSimplifiedMode(enabled)
    }

    func saveAssignment(_ updated: ButtonAssignment) {
        storageService.updateAssignment(updated, markCustom: true)
    }

    func testAssignment(_ assignment: ButtonAssignment, isActive: Bool = true) {
        let cmds = assignment.generateCommands(isActive: isActive)
        for cmd in cmds {
            connectionHub.send(command: cmd, preferWithoutResponse: false)
        }
    }
}
