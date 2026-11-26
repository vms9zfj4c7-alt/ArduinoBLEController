import Foundation
import Combine

/// Service de persistance et source de vérité partagée pour l'assignation des boutons de la manette.
final class ControllerStorageService: ObservableObject {
    @Published var assignments: [GamepadSlot: ButtonAssignment]
    @Published var selectedBoardPreference: ArduinoBoardType
    @Published var activePreset: BuiltInPresetKind
    @Published var hasCustomEdits: Bool
    @Published var ps4LeftStickAsDPad: Bool
    @Published var ps4RightStickAsSliders: Bool

    private let assignmentsKey = "arduino_ble_controller_assignments_v1"
    private let boardPreferenceKey = "arduino_ble_board_preference_v1"
    private let activePresetKey = "arduino_ble_active_preset_v1"
    private let customEditsKey = "arduino_ble_has_custom_edits_v1"
    private let ps4LeftStickKey = "arduino_ble_ps4_left_stick_dpad_v1"
    private let ps4RightStickKey = "arduino_ble_ps4_right_stick_sliders_v1"

    private let defaults: UserDefaults
    private static let jsonEncoder = JSONEncoder()
    private static let jsonDecoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let savedBoardRaw = defaults.string(forKey: boardPreferenceKey)
        let savedBoard = savedBoardRaw.flatMap { ArduinoBoardType(rawValue: $0) } ?? .auto
        self.selectedBoardPreference = savedBoard

        let savedPresetRaw = defaults.string(forKey: activePresetKey)
        let savedPreset = savedPresetRaw.flatMap { BuiltInPresetKind(rawValue: $0) } ?? .standardKit
        self.activePreset = savedPreset

        self.hasCustomEdits = defaults.bool(forKey: customEditsKey)
        self.ps4LeftStickAsDPad = (defaults.object(forKey: ps4LeftStickKey) == nil)
            ? true
            : defaults.bool(forKey: ps4LeftStickKey)
        self.ps4RightStickAsSliders = defaults.bool(forKey: ps4RightStickKey)

        let defaultCap = ArduinoBoardCapability.defaultCapability(
            for: savedBoard == .auto ? .unoR4WiFi : savedBoard,
            isAutoDetected: savedBoard == .auto
        )

        if let data = defaults.data(forKey: assignmentsKey),
           let decoded = try? Self.jsonDecoder.decode([String: ButtonAssignment].self, from: data) {
            var mapped: [GamepadSlot: ButtonAssignment] = [:]
            for (rawKey, value) in decoded {
                if let slot = GamepadSlot(rawValue: rawKey) {
                    mapped[slot] = value
                }
            }
            // Compléter tout emplacement manquant avec le préréglage par défaut
            let fallback = savedPreset.buildAssignments(for: defaultCap)
            for slot in GamepadSlot.allCases where mapped[slot] == nil {
                mapped[slot] = fallback[slot]
            }
            self.assignments = mapped
        } else {
            self.assignments = savedPreset.buildAssignments(for: defaultCap)
        }
    }

    func assignment(for slot: GamepadSlot) -> ButtonAssignment {
        if let existing = assignments[slot] {
            return existing
        }
        let fallbackCap = ArduinoBoardCapability.defaultCapability(for: .unoR4WiFi)
        return BuiltInPresetKind.standardKit.buildAssignments(for: fallbackCap)[slot]!
    }

    func updateAssignment(_ assignment: ButtonAssignment, markCustom: Bool = true) {
        assignments[assignment.id] = assignment
        if markCustom {
            hasCustomEdits = true
        }
        persistAll()
    }

    func applyPreset(_ preset: BuiltInPresetKind, for board: ArduinoBoardCapability) {
        activePreset = preset
        hasCustomEdits = false
        assignments = preset.buildAssignments(for: board)
        persistAll()
    }

    func adaptIfNotCustomized(to board: ArduinoBoardCapability) {
        guard !hasCustomEdits else { return }
        let adapted = activePreset.buildAssignments(for: board)
        guard assignments != adapted else { return }
        assignments = adapted
        persistAssignmentsOnly()
    }

    func setBoardPreference(_ boardType: ArduinoBoardType) {
        selectedBoardPreference = boardType
        persistAll()
    }

    func setPS4Options(leftStickAsDPad: Bool, rightStickAsSliders: Bool) {
        ps4LeftStickAsDPad = leftStickAsDPad
        ps4RightStickAsSliders = rightStickAsSliders
        defaults.set(leftStickAsDPad, forKey: ps4LeftStickKey)
        defaults.set(rightStickAsSliders, forKey: ps4RightStickKey)
    }

    private func persistAll() {
        defaults.set(selectedBoardPreference.rawValue, forKey: boardPreferenceKey)
        defaults.set(activePreset.rawValue, forKey: activePresetKey)
        defaults.set(hasCustomEdits, forKey: customEditsKey)
        persistAssignmentsOnly()
    }

    private func persistAssignmentsOnly() {
        let stringKeyed = Dictionary(uniqueKeysWithValues: assignments.map { ($0.key.rawValue, $0.value) })
        if let data = try? Self.jsonEncoder.encode(stringKeyed) {
            defaults.set(data, forKey: assignmentsKey)
        }
    }
}
