import Foundation
import GameController
import Combine

/// Gestionnaire natif pour manette PS4 DualShock 4 (et manettes Bluetooth compatibles iOS via GameController).
/// Traduit les entrées physiques (croix, Croix/Rond/Carré/Triangle, L1/R1, L2/R2, Share/Options et sticks)
/// vers les emplacements configurables de l'application pour piloter l'Arduino en BLE.
final class PS4ControllerManager: ObservableObject {
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var controllerName: String = "Aucune manette"
    @Published private(set) var isDualShock4: Bool = false
    @Published private(set) var batteryPercentage: Int?
    @Published private(set) var isDiscovering: Bool = false

    var useLeftStickAsDPad: Bool = true {
        didSet {
            if !useLeftStickAsDPad {
                releaseAllStickDirections()
            }
        }
    }
    var useRightStickAsSliders: Bool = false {
        didSet {
            if !useRightStickAsSliders {
                lastRightStickX = 0
                lastRightStickY = 0
            }
        }
    }

    var onSlotDown: ((GamepadSlot) -> Void)?
    var onSlotUp: ((GamepadSlot) -> Void)?
    var onSliderNormalizedChanged: ((GamepadSlot, Double, Bool) -> Void)?
    var onStatusLog: ((String) -> Void)?

    private var activeController: GCController?
    private var activeDPadDirections: Set<GamepadSlot> = []
    private var activeStickDirections: Set<GamepadSlot> = []
    private var activeStandardButtons: Set<GamepadSlot> = []
    private var lastRightStickX: Float = 0
    private var lastRightStickY: Float = 0
    private var lastTriggerValues: [GamepadSlot: Float] = [:]
    private var batteryTimer: Timer?
    private var lastLightbarState: BLEManager.ConnectionState = .disconnected

    private let stickDPadDeadzone: Float = 0.35
    private let triggerDeadzone: Float = 0.04
    private let rightStickCenterDeadzone: Float = 0.08
    private let rightStickDeltaThreshold: Float = 0.02

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleControllerDidConnect(_:)),
            name: .GCControllerDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleControllerDidDisconnect(_:)),
            name: .GCControllerDidDisconnect,
            object: nil
        )
        refreshConnectedControllers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        batteryTimer?.invalidate()
        GCController.stopWirelessControllerDiscovery()
    }

    func refreshConnectedControllers() {
        if let firstExtended = GCController.controllers().first(where: { $0.extendedGamepad != nil }) {
            attach(controller: firstExtended)
        } else {
            detachCurrentController(notifyLog: false)
        }
    }

    func startWirelessDiscovery() {
        guard !isDiscovering else { return }
        isDiscovering = true
        GCController.startWirelessControllerDiscovery { [weak self] in
            DispatchQueue.main.async {
                self?.isDiscovering = false
                self?.refreshConnectedControllers()
            }
        }
    }

    func stopWirelessDiscovery() {
        GCController.stopWirelessControllerDiscovery()
        isDiscovering = false
    }

    /// Synchronise la barre lumineuse LED de la DualShock 4 avec l'état BLE de l'Arduino.
    func updateLightbar(for bleState: BLEManager.ConnectionState) {
        lastLightbarState = bleState
        guard let light = activeController?.lightbar else { return }

        switch bleState {
        case .connected:
            light.color = GCColor(red: 0.10, green: 0.85, blue: 0.30)
        case .connecting, .discoveringServices, .scanning:
            light.color = GCColor(red: 0.95, green: 0.55, blue: 0.05)
        case .disconnected:
            light.color = GCColor(red: 0.85, green: 0.15, blue: 0.15)
        }
    }

    // MARK: - Notifications système GameController

    @objc private func handleControllerDidConnect(_ notification: Notification) {
        guard let controller = notification.object as? GCController,
              controller.extendedGamepad != nil else { return }
        attach(controller: controller)
    }

    @objc private func handleControllerDidDisconnect(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        if activeController === controller {
            detachCurrentController(notifyLog: true)
            refreshConnectedControllers()
        }
    }

    // MARK: - Liaison des entrées DualShock 4 / ExtendedGamepad

    private func attach(controller: GCController) {
        if activeController === controller { return }
        detachCurrentController(notifyLog: false)

        controller.handlerQueue = .main
        activeController = controller

        let rawName = controller.vendorName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (rawName?.isEmpty == false) ? rawName! : controller.productCategory
        controllerName = resolvedName
        isDualShock4 = (controller.extendedGamepad is GCDualShockGamepad)
            || resolvedName.uppercased().contains("DUALSHOCK")
            || resolvedName.uppercased().contains("PS4")
        isConnected = true
        updateBatteryLevel()
        updateLightbar(for: lastLightbarState)

        batteryTimer?.invalidate()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.updateBatteryLevel()
        }

        if let gamepad = controller.extendedGamepad {
            bindInputs(for: gamepad)
        }

        onStatusLog?("Manette connectée : \(resolvedName)")
    }

    private func detachCurrentController(notifyLog: Bool) {
        releaseAllActiveInputs()
        batteryTimer?.invalidate()
        batteryTimer = nil
        let oldName = controllerName
        activeController = nil
        isConnected = false
        isDualShock4 = false
        batteryPercentage = nil
        controllerName = "Aucune manette"
        if notifyLog {
            onStatusLog?("Manette déconnectée : \(oldName)")
        }
    }

    private func updateBatteryLevel() {
        guard let battery = activeController?.battery else {
            batteryPercentage = nil
            return
        }
        let level = battery.batteryLevel
        if level >= 0 {
            batteryPercentage = min(max(Int((level * 100.0).rounded()), 0), 100)
        }
    }

    private func bindInputs(for gamepad: GCExtendedGamepad) {
        // Croix directionnelle physique PS4
        bindDPadButton(gamepad.dpad.up, slot: .dpadUp)
        bindDPadButton(gamepad.dpad.down, slot: .dpadDown)
        bindDPadButton(gamepad.dpad.left, slot: .dpadLeft)
        bindDPadButton(gamepad.dpad.right, slot: .dpadRight)

        // Boutons PlayStation : Croix (A), Rond (B), Carré (X), Triangle (Y)
        bindStandardButton(gamepad.buttonA, slot: .buttonA)
        bindStandardButton(gamepad.buttonB, slot: .buttonB)
        bindStandardButton(gamepad.buttonX, slot: .buttonX)
        bindStandardButton(gamepad.buttonY, slot: .buttonY)

        // Gâchettes hautes L1 / R1 et boutons Share / Options
        bindStandardButton(gamepad.leftShoulder, slot: .shoulderL1)
        bindStandardButton(gamepad.rightShoulder, slot: .shoulderR1)
        if let optionsButton = gamepad.buttonOptions {
            bindStandardButton(optionsButton, slot: .select)
        }
        bindStandardButton(gamepad.buttonMenu, slot: .start)

        // Gâchettes analogiques L2 / R2 -> curseurs .sliderLeft / .sliderRight
        bindAnalogTrigger(gamepad.leftTrigger, slot: .sliderLeft)
        bindAnalogTrigger(gamepad.rightTrigger, slot: .sliderRight)

        // Stick gauche -> émulation croix directionnelle (avec zone morte)
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            guard let self, self.useLeftStickAsDPad else { return }
            self.updateStickDirection(.dpadUp, active: yValue > self.stickDPadDeadzone)
            self.updateStickDirection(.dpadDown, active: yValue < -self.stickDPadDeadzone)
            self.updateStickDirection(.dpadRight, active: xValue > self.stickDPadDeadzone)
            self.updateStickDirection(.dpadLeft, active: xValue < -self.stickDPadDeadzone)
        }

        // Stick droit optionnel -> pilotage proportionnel des curseurs L2 / R2 (ex: tourelle 2 servos)
        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            guard let self, self.useRightStickAsSliders else { return }
            self.processRightStickAxis(xValue, previous: &self.lastRightStickX, slot: .sliderLeft)
            self.processRightStickAxis(yValue, previous: &self.lastRightStickY, slot: .sliderRight)
        }
    }

    private func processRightStickAxis(_ raw: Float, previous: inout Float, slot: GamepadSlot) {
        let filtered: Float = (abs(raw) < rightStickCenterDeadzone) ? 0.0 : raw
        let returningToCenter = (filtered == 0.0 && previous != 0.0)
        guard returningToCenter || abs(filtered - previous) >= rightStickDeltaThreshold else {
            return
        }
        previous = filtered
        let norm = Double((filtered + 1.0) * 0.5)
        onSliderNormalizedChanged?(slot, min(max(norm, 0.0), 1.0), returningToCenter)
    }

    private func bindStandardButton(_ button: GCControllerButtonInput, slot: GamepadSlot) {
        button.pressedChangedHandler = { [weak self] _, _, pressed in
            guard let self else { return }
            if pressed {
                if self.activeStandardButtons.insert(slot).inserted {
                    self.onSlotDown?(slot)
                }
            } else if self.activeStandardButtons.remove(slot) != nil {
                self.onSlotUp?(slot)
            }
        }
    }

    private func bindDPadButton(_ button: GCControllerButtonInput, slot: GamepadSlot) {
        button.pressedChangedHandler = { [weak self] _, _, pressed in
            guard let self else { return }
            if pressed {
                let wasHeld = self.activeDPadDirections.contains(slot) || self.activeStickDirections.contains(slot)
                self.activeDPadDirections.insert(slot)
                if !wasHeld {
                    self.onSlotDown?(slot)
                }
            } else {
                self.activeDPadDirections.remove(slot)
                if !self.activeStickDirections.contains(slot) {
                    self.onSlotUp?(slot)
                }
            }
        }
    }

    private func bindAnalogTrigger(_ trigger: GCControllerButtonInput, slot: GamepadSlot) {
        trigger.valueChangedHandler = { [weak self] _, value, pressed in
            guard let self else { return }
            let filtered: Float = (value < self.triggerDeadzone) ? 0.0 : value
            let previous = self.lastTriggerValues[slot] ?? -1.0
            if abs(previous - filtered) < 0.015 && filtered != 0.0 && filtered != 1.0 {
                return
            }
            self.lastTriggerValues[slot] = filtered
            let isFinal = (!pressed && filtered == 0.0) || (filtered >= 0.99)
            self.onSliderNormalizedChanged?(slot, Double(filtered), isFinal)
        }
    }

    private func updateStickDirection(_ slot: GamepadSlot, active: Bool) {
        if active {
            if !activeStickDirections.contains(slot) {
                let alreadyHeldByDPad = activeDPadDirections.contains(slot)
                activeStickDirections.insert(slot)
                if !alreadyHeldByDPad {
                    onSlotDown?(slot)
                }
            }
        } else if activeStickDirections.remove(slot) != nil {
            if !activeDPadDirections.contains(slot) {
                onSlotUp?(slot)
            }
        }
    }

    private func releaseAllStickDirections() {
        let toRelease = activeStickDirections
        activeStickDirections.removeAll()
        for slot in toRelease where !activeDPadDirections.contains(slot) {
            onSlotUp?(slot)
        }
    }

    private func releaseAllActiveInputs() {
        let allHeld = activeDPadDirections
            .union(activeStickDirections)
            .union(activeStandardButtons)
        activeDPadDirections.removeAll()
        activeStickDirections.removeAll()
        activeStandardButtons.removeAll()

        let activeTriggers = lastTriggerValues.filter { $0.value > 0.0 }
        lastTriggerValues.removeAll()
        lastRightStickX = 0
        lastRightStickY = 0

        for slot in allHeld {
            onSlotUp?(slot)
        }
        for (slot, _) in activeTriggers {
            onSliderNormalizedChanged?(slot, 0.0, true)
        }
    }
}
