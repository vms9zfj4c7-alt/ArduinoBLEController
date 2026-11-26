import Foundation
import Combine
import UIKit

/// ViewModel haute performance pilotant l'écran manette, le pont manette PS4 -> BLE et la console.
final class ControllerViewModel: ObservableObject {
    @Published private(set) var connectionState: BLEManager.ConnectionState = .disconnected
    @Published private(set) var boardCapability: ArduinoBoardCapability
    @Published private(set) var activeProfileDescription: String = "Aucun profil"
    @Published private(set) var latestTemperature: Double?
    @Published private(set) var isTemperatureSimulated: Bool = false
    @Published private(set) var connectedRSSI: Int?
    @Published private(set) var lastConnectedDeviceName: String?
    @Published var errorMessage: String?

    // État de la manette PS4 Bluetooth
    @Published private(set) var isPS4Connected: Bool = false
    @Published private(set) var ps4ControllerName: String = "Aucune manette"
    @Published private(set) var ps4BatteryPercentage: Int?
    @Published private(set) var isPS4Discovering: Bool = false

    @Published private(set) var assignments: [GamepadSlot: ButtonAssignment] = [:]
    // Publié uniquement pour les boutons interrupteurs (toggle) afin d'éviter des re-rendus inutiles
    @Published private(set) var toggledStates: [GamepadSlot: Bool] = [:]
    @Published var rawCommandText: String = ""

    var logStore: BLELogStore { bleManager.logStore }
    let externalSliderUpdates = PassthroughSubject<(slot: GamepadSlot, value: Double), Never>()

    private let bleManager: BLEManager
    private let storageService: ControllerStorageService
    private let ps4Manager: PS4ControllerManager
    private var cancellables: Set<AnyCancellable> = []

    // États internes non publiés pour zéro re-rendu SwiftUI lors des appuis maintenus et glissements
    private var momentaryPressedSlots: Set<GamepadSlot> = []
    private var sliderCache: [GamepadSlot: Double] = [:]
    private var lastSliderSendTime: [GamepadSlot: Date] = [:]
    private var lastSentSliderInt: [GamepadSlot: Int] = [:]
    private var lastDisplayedExternalInt: [GamepadSlot: Int] = [:]
    private var cachedActiveCommands: [GamepadSlot: [String]] = [:]
    private var cachedReleaseCommands: [GamepadSlot: [String]] = [:]
    private var cachedSliderLookup: [GamepadSlot: [String]] = [:]
    private let sliderThrottleInterval: TimeInterval = 0.045

    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let notificationHaptic = UINotificationFeedbackGenerator()

    init(
        bleManager: BLEManager,
        storageService: ControllerStorageService,
        ps4Manager: PS4ControllerManager
    ) {
        self.bleManager = bleManager
        self.storageService = storageService
        self.ps4Manager = ps4Manager
        self.boardCapability = bleManager.detectedBoardCapability
        self.assignments = storageService.assignments

        rebuildCommandCache(with: storageService.assignments)
        syncSliderRanges(with: storageService.assignments)
        lightHaptic.prepare()
        mediumHaptic.prepare()

        bindBLEManager()
        bindStorageService()
        bindPS4Controller()
    }

    func assignment(for slot: GamepadSlot) -> ButtonAssignment {
        assignments[slot] ?? storageService.assignment(for: slot)
    }

    func isSlotActive(_ slot: GamepadSlot) -> Bool {
        toggledStates[slot] ?? false
    }

    func initialSliderValue(for slot: GamepadSlot) -> Double {
        let config = assignment(for: slot)
        let minVal = Double(min(config.minSliderValue, config.maxSliderValue))
        let maxVal = Double(max(config.minSliderValue + 1, config.maxSliderValue))
        let raw = sliderCache[slot] ?? Double(config.activeValue)
        return min(max(raw, minVal), maxVal)
    }

    // MARK: - Interactions Manette (écran tactile + manette PS4)

    func handleButtonDown(slot: GamepadSlot) {
        let config = assignment(for: slot)

        if config.actionType == .emergencyStop {
            triggerEmergencyStop()
            return
        }

        switch config.behavior {
        case .momentary:
            momentaryPressedSlots.insert(slot)
            lightHaptic.impactOccurred()
            lightHaptic.prepare()
            let cmds = cachedActiveCommands[slot] ?? config.generateCommands(isActive: true)
            sendCommands(cmds, preferWithoutResponse: true)

        case .toggle:
            let nextState = !(toggledStates[slot] ?? false)
            toggledStates[slot] = nextState
            mediumHaptic.impactOccurred()
            mediumHaptic.prepare()
            let cmds = nextState
                ? (cachedActiveCommands[slot] ?? config.generateCommands(isActive: true))
                : (cachedReleaseCommands[slot] ?? config.generateCommands(isActive: false))
            sendCommands(cmds, preferWithoutResponse: false)

        case .push:
            lightHaptic.impactOccurred()
            lightHaptic.prepare()
            let cmds = cachedActiveCommands[slot] ?? config.generateCommands(isActive: true)
            sendCommands(cmds, preferWithoutResponse: true)
        }
    }

    func handleButtonUp(slot: GamepadSlot) {
        let config = assignment(for: slot)
        guard config.actionType != .emergencyStop else { return }

        if config.behavior == .momentary && momentaryPressedSlots.remove(slot) != nil {
            let cmds = cachedReleaseCommands[slot] ?? config.generateCommands(isActive: false)
            sendCommands(cmds, preferWithoutResponse: false)
        }
    }

    func handleSliderChanged(slot: GamepadSlot, value: Double, isFinal: Bool) {
        sliderCache[slot] = value
        let intVal = Int(value.rounded())
        let config = assignment(for: slot)
        let now = Date()

        if !isFinal {
            if lastSentSliderInt[slot] == intVal {
                return
            }
            if let lastTime = lastSliderSendTime[slot],
               now.timeIntervalSince(lastTime) < sliderThrottleInterval {
                return
            }
        } else if lastSentSliderInt[slot] == intVal {
            lightHaptic.impactOccurred()
            lightHaptic.prepare()
            return
        }

        lastSliderSendTime[slot] = now
        lastSentSliderInt[slot] = intVal
        if let lookup = cachedSliderLookup[slot], intVal >= 0 && intVal < lookup.count {
            bleManager.send(command: lookup[intVal], preferWithoutResponse: !isFinal)
        } else {
            sendCommands(
                config.generateCommands(isActive: true, sliderValue: intVal),
                preferWithoutResponse: !isFinal
            )
        }
        if isFinal {
            lightHaptic.impactOccurred()
            lightHaptic.prepare()
        }
    }

    func triggerEmergencyStop() {
        notificationHaptic.notificationOccurred(.warning)
        toggledStates.removeAll()
        momentaryPressedSlots.removeAll()
        bleManager.send(command: BLEProtocolConstants.emergencyStopCommand, preferWithoutResponse: false)
    }

    func sendRawCommand() {
        let trimmed = rawCommandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        bleManager.send(command: trimmed, preferWithoutResponse: false)
        rawCommandText = ""
    }

    func reconnectLastDevice() {
        bleManager.reconnectLastDevice()
    }

    func requestTelemetry() {
        bleManager.requestTelemetry()
    }

    func clearLogs() {
        bleManager.clearLogs()
    }

    func disconnect() {
        bleManager.disconnect()
    }

    func startPS4Discovery() {
        ps4Manager.startWirelessDiscovery()
    }

    func stopPS4Discovery() {
        ps4Manager.stopWirelessDiscovery()
    }

    func refreshPS4Controllers() {
        ps4Manager.refreshConnectedControllers()
    }

    /// Sécurise les sorties momentanées et met le BLE en veille lors du passage en arrière-plan.
    func handleAppLifecycle(isActive: Bool) {
        if isActive {
            bleManager.setAppActive(true)
            ps4Manager.refreshConnectedControllers()
        } else {
            let held = momentaryPressedSlots
            for slot in held {
                handleButtonUp(slot: slot)
            }
            bleManager.setAppActive(false)
        }
    }

    // MARK: - Liaisons internes

    private func bindBLEManager() {
        bleManager.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self else { return }
                self.connectionState = newState
                self.ps4Manager.updateLightbar(for: newState)
                if !newState.isConnected {
                    self.toggledStates.removeAll()
                    self.momentaryPressedSlots.removeAll()
                    self.lastSentSliderInt.removeAll()
                }
            }
            .store(in: &cancellables)

        bleManager.$detectedBoardCapability
            .receive(on: DispatchQueue.main)
            .sink { [weak self] capability in
                guard let self else { return }
                self.boardCapability = capability
                self.storageService.adaptIfNotCustomized(to: capability)
            }
            .store(in: &cancellables)

        bleManager.$activeProfileDescription
            .receive(on: DispatchQueue.main)
            .assign(to: &$activeProfileDescription)

        bleManager.$latestTemperature
            .receive(on: DispatchQueue.main)
            .assign(to: &$latestTemperature)

        bleManager.$isTemperatureSimulated
            .receive(on: DispatchQueue.main)
            .assign(to: &$isTemperatureSimulated)

        bleManager.$connectedRSSI
            .receive(on: DispatchQueue.main)
            .assign(to: &$connectedRSSI)

        bleManager.$lastConnectedDeviceName
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastConnectedDeviceName)

        bleManager.$lastErrorMessage
            .receive(on: DispatchQueue.main)
            .assign(to: &$errorMessage)
    }

    private func bindStorageService() {
        storageService.$assignments
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updated in
                self?.assignments = updated
                self?.lastSentSliderInt.removeAll()
                self?.lastDisplayedExternalInt.removeAll()
                self?.rebuildCommandCache(with: updated)
                self?.syncSliderRanges(with: updated)
            }
            .store(in: &cancellables)

        storageService.$ps4LeftStickAsDPad
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.ps4Manager.useLeftStickAsDPad = enabled
            }
            .store(in: &cancellables)

        storageService.$ps4RightStickAsSliders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.ps4Manager.useRightStickAsSliders = enabled
            }
            .store(in: &cancellables)
    }

    private func bindPS4Controller() {
        ps4Manager.useLeftStickAsDPad = storageService.ps4LeftStickAsDPad
        ps4Manager.useRightStickAsSliders = storageService.ps4RightStickAsSliders

        ps4Manager.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPS4Connected)

        ps4Manager.$controllerName
            .receive(on: DispatchQueue.main)
            .assign(to: &$ps4ControllerName)

        ps4Manager.$batteryPercentage
            .receive(on: DispatchQueue.main)
            .assign(to: &$ps4BatteryPercentage)

        ps4Manager.$isDiscovering
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPS4Discovering)

        ps4Manager.onSlotDown = { [weak self] slot in
            self?.handleButtonDown(slot: slot)
        }
        ps4Manager.onSlotUp = { [weak self] slot in
            self?.handleButtonUp(slot: slot)
        }
        ps4Manager.onSliderNormalizedChanged = { [weak self] slot, normalized01, isFinal in
            guard let self else { return }
            let config = self.assignment(for: slot)
            let minVal = Double(min(config.minSliderValue, config.maxSliderValue))
            let maxVal = Double(max(config.minSliderValue + 1, config.maxSliderValue))
            let mapped = minVal + (maxVal - minVal) * min(max(normalized01, 0.0), 1.0)
            let roundedInt = Int(mapped.rounded())
            if isFinal || self.lastDisplayedExternalInt[slot] != roundedInt {
                self.lastDisplayedExternalInt[slot] = roundedInt
                self.externalSliderUpdates.send((slot: slot, value: Double(roundedInt)))
            }
            self.handleSliderChanged(slot: slot, value: mapped, isFinal: isFinal)
        }
        ps4Manager.onStatusLog = { [weak self] message in
            self?.bleManager.logStore.append(.info, message)
        }
    }

    private func sendCommands(_ commands: [String], preferWithoutResponse: Bool) {
        for command in commands {
            bleManager.send(command: command, preferWithoutResponse: preferWithoutResponse)
        }
    }

    private func rebuildCommandCache(with updated: [GamepadSlot: ButtonAssignment]) {
        var activeMap: [GamepadSlot: [String]] = [:]
        var releaseMap: [GamepadSlot: [String]] = [:]
        var sliderMap: [GamepadSlot: [String]] = [:]

        for (slot, config) in updated {
            activeMap[slot] = config.generateCommands(isActive: true)
            releaseMap[slot] = config.generateCommands(isActive: false)

            if slot.isSlider {
                if config.actionType == .pinServo {
                    sliderMap[slot] = (0...180).map { BLEProtocolConstants.servoCommand(pin: config.primaryPin, angle: $0) }
                } else if config.actionType == .pinPWM {
                    sliderMap[slot] = (0...255).map { BLEProtocolConstants.pwmCommand(pin: config.primaryPin, value: $0) }
                }
            }
        }

        cachedActiveCommands = activeMap
        cachedReleaseCommands = releaseMap
        cachedSliderLookup = sliderMap
    }

    private func syncSliderRanges(with updated: [GamepadSlot: ButtonAssignment]) {
        for slot in [GamepadSlot.sliderLeft, GamepadSlot.sliderRight] {
            guard let config = updated[slot] else { continue }
            let minVal = Double(min(config.minSliderValue, config.maxSliderValue))
            let maxVal = Double(max(config.minSliderValue + 1, config.maxSliderValue))
            let current = sliderCache[slot] ?? Double(config.activeValue)
            sliderCache[slot] = min(max(current, minVal), maxVal)
        }
    }
}
