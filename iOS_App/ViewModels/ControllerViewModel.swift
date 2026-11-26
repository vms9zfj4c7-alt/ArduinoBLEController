import Foundation
import Combine
import UIKit
import QuartzCore

/// ViewModel haute performance pilotant l'écran manette, le pont manette PS4 -> BLE et la console.
final class ControllerViewModel: ObservableObject {
    @Published private(set) var connectionState: BLEManager.ConnectionState = .disconnected
    @Published private(set) var boardCapability: ArduinoBoardCapability
    @Published private(set) var activeProfileDescription: String = "Aucun profil"
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

    var logStore: BLELogStore { bleManager.logStore }
    var telemetryStore: BLETelemetryStore { bleManager.telemetryStore }
    let externalSliderUpdates = PassthroughSubject<(slot: GamepadSlot, value: Double), Never>()

    private let bleManager: BLEManager
    private let storageService: ControllerStorageService
    private let ps4Manager: PS4ControllerManager
    private var cancellables: Set<AnyCancellable> = []

    // États internes non publiés pour zéro re-rendu SwiftUI lors des appuis maintenus et glissements
    private var momentaryPressedSlots: Set<GamepadSlot> = []
    private var sliderCache: [GamepadSlot: Double] = [:]
    private var lastSliderSendTime: [GamepadSlot: CFAbsoluteTime] = [:]
    private var lastSentSliderInt: [GamepadSlot: Int] = [:]
    private var lastDisplayedExternalInt: [GamepadSlot: Int] = [:]
    private var pendingSliderValues: [GamepadSlot: Int] = [:]
    private var pendingSliderFlushWorkItems: [GamepadSlot: DispatchWorkItem] = [:]
    private var cachedActivePackets: [GamepadSlot: [BLEPreparedCommand]] = [:]
    private var cachedReleasePackets: [GamepadSlot: [BLEPreparedCommand]] = [:]
    private var cachedSliderLookup: [GamepadSlot: [BLEPreparedCommand]] = [:]
    private let sliderThrottleInterval: CFTimeInterval = 0.030

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

    deinit {
        cancelAllPendingSliderFlushes()
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
            sendSlotPackets(
                cachedActivePackets[slot],
                fallbackCommands: { config.generateCommands(isActive: true) },
                preferWithoutResponse: true
            )

        case .toggle:
            let nextState = !(toggledStates[slot] ?? false)
            toggledStates[slot] = nextState
            mediumHaptic.impactOccurred()
            mediumHaptic.prepare()
            if nextState {
                sendSlotPackets(
                    cachedActivePackets[slot],
                    fallbackCommands: { config.generateCommands(isActive: true) },
                    preferWithoutResponse: false
                )
            } else {
                sendSlotPackets(
                    cachedReleasePackets[slot],
                    fallbackCommands: { config.generateCommands(isActive: false) },
                    preferWithoutResponse: false
                )
            }

        case .push:
            lightHaptic.impactOccurred()
            lightHaptic.prepare()
            sendSlotPackets(
                cachedActivePackets[slot],
                fallbackCommands: { config.generateCommands(isActive: true) },
                preferWithoutResponse: true
            )
        }
    }

    func handleButtonUp(slot: GamepadSlot) {
        let config = assignment(for: slot)
        guard config.actionType != .emergencyStop else { return }

        if config.behavior == .momentary && momentaryPressedSlots.remove(slot) != nil {
            sendSlotPackets(
                cachedReleasePackets[slot],
                fallbackCommands: { config.generateCommands(isActive: false) },
                preferWithoutResponse: false
            )
        }
    }

    func handleSliderChanged(slot: GamepadSlot, value: Double, isFinal: Bool) {
        sliderCache[slot] = value
        let intVal = Int(value.rounded())
        let now = CACurrentMediaTime()

        if !isFinal {
            if lastSentSliderInt[slot] == intVal {
                cancelPendingSliderFlush(for: slot)
                return
            }
            if let lastTime = lastSliderSendTime[slot] {
                let elapsed = now - lastTime
                if elapsed < sliderThrottleInterval {
                    // Trailing-edge flush pour garantir la prise en compte si l'utilisateur s'arrête juste après une trame bridée
                    pendingSliderValues[slot] = intVal
                    if pendingSliderFlushWorkItems[slot] == nil {
                        let workItem = DispatchWorkItem { [weak self] in
                            self?.flushPendingSliderValue(for: slot)
                        }
                        pendingSliderFlushWorkItems[slot] = workItem
                        DispatchQueue.main.asyncAfter(deadline: .now() + (sliderThrottleInterval - elapsed), execute: workItem)
                    }
                    return
                }
            }
        } else {
            cancelPendingSliderFlush(for: slot)
            if lastSentSliderInt[slot] == intVal {
                lightHaptic.impactOccurred()
                lightHaptic.prepare()
                return
            }
        }

        cancelPendingSliderFlush(for: slot)
        sendSliderInt(slot: slot, intVal: intVal, timestamp: now, preferWithoutResponse: !isFinal)
        if isFinal {
            lightHaptic.impactOccurred()
            lightHaptic.prepare()
        }
    }

    func triggerEmergencyStop() {
        notificationHaptic.notificationOccurred(.warning)
        cancelAllPendingSliderFlushes()
        toggledStates.removeAll()
        momentaryPressedSlots.removeAll()
        lastSentSliderInt.removeAll()
        bleManager.sendPrepared(BLEProtocolConstants.emergencyStopPacket, preferWithoutResponse: false)
    }

    func sendRawCommand(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        bleManager.send(command: trimmed, preferWithoutResponse: false)
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
            cancelAllPendingSliderFlushes()
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
            .removeDuplicates()
            .sink { [weak self] newState in
                guard let self else { return }
                self.connectionState = newState
                self.ps4Manager.updateLightbar(for: newState)
                if !newState.isConnected {
                    self.cancelAllPendingSliderFlushes()
                    self.toggledStates.removeAll()
                    self.momentaryPressedSlots.removeAll()
                    self.lastSentSliderInt.removeAll()
                }
            }
            .store(in: &cancellables)

        bleManager.$detectedBoardCapability
            .removeDuplicates()
            .sink { [weak self] capability in
                guard let self else { return }
                self.boardCapability = capability
                self.storageService.adaptIfNotCustomized(to: capability)
            }
            .store(in: &cancellables)

        bleManager.$activeProfileDescription
            .removeDuplicates()
            .assign(to: &$activeProfileDescription)

        bleManager.$lastConnectedDeviceName
            .removeDuplicates()
            .assign(to: &$lastConnectedDeviceName)

        bleManager.$lastErrorMessage
            .removeDuplicates()
            .assign(to: &$errorMessage)
    }

    private func bindStorageService() {
        storageService.$assignments
            .removeDuplicates()
            .sink { [weak self] updated in
                self?.assignments = updated
                self?.lastSentSliderInt.removeAll()
                self?.lastDisplayedExternalInt.removeAll()
                self?.cancelAllPendingSliderFlushes()
                self?.rebuildCommandCache(with: updated)
                self?.syncSliderRanges(with: updated)
            }
            .store(in: &cancellables)

        storageService.$ps4LeftStickAsDPad
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.ps4Manager.useLeftStickAsDPad = enabled
            }
            .store(in: &cancellables)

        storageService.$ps4RightStickAsSliders
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.ps4Manager.useRightStickAsSliders = enabled
            }
            .store(in: &cancellables)
    }

    private func bindPS4Controller() {
        ps4Manager.useLeftStickAsDPad = storageService.ps4LeftStickAsDPad
        ps4Manager.useRightStickAsSliders = storageService.ps4RightStickAsSliders

        ps4Manager.$isConnected
            .removeDuplicates()
            .assign(to: &$isPS4Connected)

        ps4Manager.$controllerName
            .removeDuplicates()
            .assign(to: &$ps4ControllerName)

        ps4Manager.$batteryPercentage
            .removeDuplicates()
            .assign(to: &$ps4BatteryPercentage)

        ps4Manager.$isDiscovering
            .removeDuplicates()
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

    private func sendSlotPackets(
        _ cached: [BLEPreparedCommand]?,
        fallbackCommands: () -> [String],
        preferWithoutResponse: Bool
    ) {
        if let packets = cached {
            for packet in packets {
                bleManager.sendPrepared(packet, preferWithoutResponse: preferWithoutResponse)
            }
        } else {
            for command in fallbackCommands() {
                bleManager.send(command: command, preferWithoutResponse: preferWithoutResponse)
            }
        }
    }

    private func sendSliderInt(
        slot: GamepadSlot,
        intVal: Int,
        timestamp: CFAbsoluteTime,
        preferWithoutResponse: Bool
    ) {
        lastSliderSendTime[slot] = timestamp
        lastSentSliderInt[slot] = intVal
        if let lookup = cachedSliderLookup[slot], intVal >= 0 && intVal < lookup.count {
            bleManager.sendPrepared(lookup[intVal], preferWithoutResponse: preferWithoutResponse)
        } else {
            let config = assignment(for: slot)
            let commands = config.generateCommands(isActive: true, sliderValue: intVal)
            for command in commands {
                bleManager.send(command: command, preferWithoutResponse: preferWithoutResponse)
            }
        }
    }

    private func flushPendingSliderValue(for slot: GamepadSlot) {
        pendingSliderFlushWorkItems.removeValue(forKey: slot)
        guard let pendingInt = pendingSliderValues.removeValue(forKey: slot),
              lastSentSliderInt[slot] != pendingInt else { return }
        sendSliderInt(slot: slot, intVal: pendingInt, timestamp: CACurrentMediaTime(), preferWithoutResponse: true)
    }

    private func cancelPendingSliderFlush(for slot: GamepadSlot) {
        pendingSliderFlushWorkItems.removeValue(forKey: slot)?.cancel()
        pendingSliderValues.removeValue(forKey: slot)
    }

    private func cancelAllPendingSliderFlushes() {
        for workItem in pendingSliderFlushWorkItems.values {
            workItem.cancel()
        }
        pendingSliderFlushWorkItems.removeAll()
        pendingSliderValues.removeAll()
    }

    private func rebuildCommandCache(with updated: [GamepadSlot: ButtonAssignment]) {
        var activeMap: [GamepadSlot: [BLEPreparedCommand]] = [:]
        var releaseMap: [GamepadSlot: [BLEPreparedCommand]] = [:]
        var sliderMap: [GamepadSlot: [BLEPreparedCommand]] = [:]

        for (slot, config) in updated {
            let coalesceKey = Self.coalesceKey(for: config, slot: slot)
            activeMap[slot] = config.generateCommands(isActive: true).map {
                BLEPreparedCommand.make($0, coalesceKey: coalesceKey)
            }
            releaseMap[slot] = config.generateCommands(isActive: false).map {
                BLEPreparedCommand.make($0, coalesceKey: coalesceKey)
            }

            if slot.isSlider {
                if config.actionType == .pinServo {
                    let key = "V:\(config.primaryPin):"
                    sliderMap[slot] = (0...180).map {
                        BLEPreparedCommand.make(
                            BLEProtocolConstants.servoCommand(pin: config.primaryPin, angle: $0),
                            coalesceKey: key
                        )
                    }
                } else if config.actionType == .pinPWM {
                    let key = "P:\(config.primaryPin):"
                    sliderMap[slot] = (0...255).map {
                        BLEPreparedCommand.make(
                            BLEProtocolConstants.pwmCommand(pin: config.primaryPin, value: $0),
                            coalesceKey: key
                        )
                    }
                }
            }
        }

        cachedActivePackets = activeMap
        cachedReleasePackets = releaseMap
        cachedSliderLookup = sliderMap
    }

    private static func coalesceKey(for config: ButtonAssignment, slot: GamepadSlot) -> String? {
        switch config.actionType {
        case .pinPWM:
            return "P:\(config.primaryPin):"
        case .pinServo:
            return "V:\(config.primaryPin):"
        case .pinDigital:
            return "D:\(config.primaryPin):"
        case .multiPin:
            return "M:\(slot.rawValue)"
        case .customCommand, .emergencyStop:
            return nil
        }
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
