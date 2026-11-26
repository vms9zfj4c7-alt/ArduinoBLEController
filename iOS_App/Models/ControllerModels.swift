import Foundation
import SwiftUI

/// Emplacements disponibles sur la manette virtuelle.
enum GamepadSlot: String, CaseIterable, Codable, Identifiable, Hashable {
    // Croix directionnelle
    case dpadUp
    case dpadDown
    case dpadLeft
    case dpadRight

    // Boutons d'action principaux
    case buttonA
    case buttonB
    case buttonX
    case buttonY

    // Gâchettes et boutons auxiliaires
    case shoulderL1
    case shoulderR1
    case select
    case start

    // Curseurs analogiques (L2 / R2)
    case sliderLeft
    case sliderRight

    var id: String { rawValue }

    var isSlider: Bool {
        self == .sliderLeft || self == .sliderRight
    }

    var slotDisplayName: String {
        switch self {
        case .dpadUp: return "Croix Haut (↑)"
        case .dpadDown: return "Croix Bas (↓)"
        case .dpadLeft: return "Croix Gauche (←)"
        case .dpadRight: return "Croix Droite (→)"
        case .buttonA: return "Bouton A"
        case .buttonB: return "Bouton B"
        case .buttonX: return "Bouton X"
        case .buttonY: return "Bouton Y"
        case .shoulderL1: return "Gâchette L1"
        case .shoulderR1: return "Gâchette R1"
        case .select: return "Select"
        case .start: return "Start"
        case .sliderLeft: return "Curseur Gauche (L2)"
        case .sliderRight: return "Curseur Droit (R2)"
        }
    }

    var shortCode: String {
        switch self {
        case .dpadUp: return "↑"
        case .dpadDown: return "↓"
        case .dpadLeft: return "←"
        case .dpadRight: return "→"
        case .buttonA: return "A"
        case .buttonB: return "B"
        case .buttonX: return "X"
        case .buttonY: return "Y"
        case .shoulderL1: return "L1"
        case .shoulderR1: return "R1"
        case .select: return "SEL"
        case .start: return "STA"
        case .sliderLeft: return "L2"
        case .sliderRight: return "R2"
        }
    }

    var sectionTitle: String {
        switch self {
        case .dpadUp, .dpadDown, .dpadLeft, .dpadRight:
            return "Croix directionnelle"
        case .buttonA, .buttonB, .buttonX, .buttonY:
            return "Boutons d'action"
        case .shoulderL1, .shoulderR1, .select, .start:
            return "Gâchettes & Système"
        case .sliderLeft, .sliderRight:
            return "Curseurs analogiques (PWM / Servo)"
        }
    }

    var ps4Hint: String {
        switch self {
        case .dpadUp: return "PS4 : Haut / Stick G ↑"
        case .dpadDown: return "PS4 : Bas / Stick G ↓"
        case .dpadLeft: return "PS4 : Gauche / Stick G ←"
        case .dpadRight: return "PS4 : Droite / Stick G →"
        case .buttonA: return "PS4 : Croix"
        case .buttonB: return "PS4 : Rond"
        case .buttonX: return "PS4 : Carré"
        case .buttonY: return "PS4 : Triangle"
        case .shoulderL1: return "PS4 : L1"
        case .shoulderR1: return "PS4 : R1"
        case .select: return "PS4 : Share"
        case .start: return "PS4 : Options"
        case .sliderLeft: return "PS4 : L2 / Stick D (X)"
        case .sliderRight: return "PS4 : R2 / Stick D (Y)"
        }
    }
}

/// Type d'action exécutée par un bouton ou curseur sur l'Arduino.
enum ButtonActionType: String, CaseIterable, Codable, Identifiable {
    case pinDigital = "DIGITAL"
    case pinPWM = "PWM"
    case pinServo = "SERVO"
    case multiPin = "MULTI_PIN"
    case customCommand = "CUSTOM"
    case emergencyStop = "STOP"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pinDigital: return "Broche Digitale (ON/OFF)"
        case .pinPWM: return "Broche PWM (0–255)"
        case .pinServo: return "Servomoteur (0–180°)"
        case .multiPin: return "Multi-broches (ex: Moteurs)"
        case .customCommand: return "Commande texte libre"
        case .emergencyStop: return "Arrêt d'urgence (STOP)"
        }
    }
}

/// Mode d'activation d'un bouton de manette.
enum ButtonBehavior: String, CaseIterable, Codable, Identifiable {
    case momentary = "MOMENTARY"
    case toggle = "TOGGLE"
    case push = "PUSH"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .momentary: return "Maintenu (Appui = actif, Relâché = repos)"
        case .toggle: return "Interrupteur (ON / OFF)"
        case .push: return "Impulsion (Envoi au clic)"
        }
    }

    var shortName: String {
        switch self {
        case .momentary: return "Maintenu"
        case .toggle: return "Interrupteur"
        case .push: return "Impulsion"
        }
    }
}

/// Type de signal utilisé pour chaque cible d'une action multi-broches.
enum PinSignalKind: String, CaseIterable, Codable, Identifiable {
    case digital = "D"
    case pwm = "P"
    case servo = "V"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .digital: return "Digital (0/1)"
        case .pwm: return "PWM (0–255)"
        case .servo: return "Servo (0–180°)"
        }
    }
}

/// Cible d'une broche dans une action multi-broches.
struct PinTarget: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var pin: Int
    var signalKind: PinSignalKind
    var activeValue: Int
    var releaseValue: Int

    init(
        id: UUID = UUID(),
        pin: Int,
        signalKind: PinSignalKind = .digital,
        activeValue: Int = 1,
        releaseValue: Int = 0
    ) {
        self.id = id
        self.pin = pin
        self.signalKind = signalKind
        self.activeValue = activeValue
        self.releaseValue = releaseValue
    }

    func command(isActive: Bool) -> String {
        let value = isActive ? activeValue : releaseValue
        switch signalKind {
        case .digital:
            return BLEProtocolConstants.digitalCommand(pin: pin, isOn: value > 0)
        case .pwm:
            return BLEProtocolConstants.pwmCommand(pin: pin, value: value)
        case .servo:
            return BLEProtocolConstants.servoCommand(pin: pin, angle: value)
        }
    }

    func compactBatchToken(isActive: Bool) -> String {
        let raw = isActive ? activeValue : releaseValue
        let normalized: Int
        switch signalKind {
        case .digital:
            normalized = raw > 0 ? 1 : 0
        case .pwm:
            normalized = min(max(raw, 0), 255)
        case .servo:
            normalized = min(max(raw, 0), 180)
        }
        return "\(pin)\(signalKind.rawValue)\(normalized)"
    }
}

/// Palette de couleurs sérialisable pour personnaliser les boutons.
enum ControllerColorToken: String, CaseIterable, Codable, Identifiable {
    case blue
    case green
    case red
    case orange
    case yellow
    case purple
    case teal
    case pink
    case gray

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blue: return "Bleu"
        case .green: return "Vert"
        case .red: return "Rouge"
        case .orange: return "Orange"
        case .yellow: return "Jaune"
        case .purple: return "Violet"
        case .teal: return "Turquoise"
        case .pink: return "Rose"
        case .gray: return "Gris"
        }
    }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .purple: return .purple
        case .teal: return .teal
        case .pink: return .pink
        case .gray: return .gray
        }
    }
}

/// Configuration complète d'un bouton ou curseur de la manette.
struct ButtonAssignment: Identifiable, Codable, Equatable {
    let id: GamepadSlot
    var label: String
    var symbolName: String
    var colorToken: ControllerColorToken
    var actionType: ButtonActionType
    var behavior: ButtonBehavior

    // Action simple sur broche
    var primaryPin: Int
    var activeValue: Int
    var releaseValue: Int

    // Action multi-broches (robot, pont en H, etc.)
    var extraPinTargets: [PinTarget]

    // Commande texte libre
    var pressCommand: String
    var releaseCommand: String

    // Bornes pour les curseurs analogiques
    var minSliderValue: Int
    var maxSliderValue: Int

    var summaryDescription: String {
        switch actionType {
        case .pinDigital:
            return "Pin \(primaryPin) • Digital (\(behavior.shortName))"
        case .pinPWM:
            if id.isSlider {
                return "Pin \(primaryPin) • PWM (\(minSliderValue)–\(maxSliderValue))"
            }
            return "Pin \(primaryPin) • PWM (\(activeValue))"
        case .pinServo:
            if id.isSlider {
                return "Pin \(primaryPin) • Servo (\(minSliderValue)°–\(maxSliderValue)°)"
            }
            return "Pin \(primaryPin) • Servo (\(activeValue)°)"
        case .multiPin:
            let pinList = extraPinTargets.map { "\($0.pin)" }.joined(separator: ",")
            return "Pins [\(pinList)] • Multi"
        case .customCommand:
            let trimmed = pressCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Commande vide" : "Cmd: \(trimmed)"
        case .emergencyStop:
            return "Arrêt d'urgence (STOP)"
        }
    }

    /// Génère les commandes BLE à envoyer selon l'état ou la valeur du curseur.
    func generateCommands(isActive: Bool, sliderValue: Int? = nil) -> [String] {
        switch actionType {
        case .pinDigital:
            let val = isActive ? activeValue : releaseValue
            return [BLEProtocolConstants.digitalCommand(pin: primaryPin, isOn: val > 0)]

        case .pinPWM:
            let val = sliderValue ?? (isActive ? activeValue : releaseValue)
            return [BLEProtocolConstants.pwmCommand(pin: primaryPin, value: val)]

        case .pinServo:
            let angle = sliderValue ?? (isActive ? activeValue : releaseValue)
            return [BLEProtocolConstants.servoCommand(pin: primaryPin, angle: angle)]

        case .multiPin:
            guard !extraPinTargets.isEmpty else { return [] }
            if extraPinTargets.count == 1, let single = extraPinTargets.first {
                return [single.command(isActive: isActive)]
            }
            // Regroupe les cibles en paquets batch M:... <= 20 octets (compatible BLE 4.0 / HM-10)
            var commands: [String] = []
            var currentLine = "M:"
            for target in extraPinTargets {
                let token = target.compactBatchToken(isActive: isActive)
                let separator = (currentLine.count > 2) ? "," : ""
                if currentLine.count + separator.count + token.count + 1 <= 20 {
                    currentLine += separator + token
                } else {
                    if currentLine.count > 2 {
                        commands.append(currentLine + "\n")
                    }
                    currentLine = "M:" + token
                }
            }
            if currentLine.count > 2 {
                commands.append(currentLine + "\n")
            }
            return commands

        case .customCommand:
            let raw = isActive ? pressCommand : releaseCommand
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            return [trimmed + "\n"]

        case .emergencyStop:
            return [BLEProtocolConstants.emergencyStopCommand]
        }
    }
}

/// Préréglages de manette qui adaptent automatiquement leurs broches selon la carte Arduino.
enum BuiltInPresetKind: String, CaseIterable, Identifiable {
    case standardKit = "STANDARD_KIT"
    case robotCar = "ROBOT_CAR"
    case servoArm = "SERVO_ARM"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standardKit: return "Découverte (LEDs + Servo)"
        case .robotCar: return "Robot 4 Directions (Moteurs)"
        case .servoArm: return "Bras / Multi-Servos"
        }
    }

    var subtitle: String {
        switch self {
        case .standardKit: return "2 LEDs en interrupteur, PWM, servo et commandes de test"
        case .robotCar: return "Croix directionnelle multi-broches pour pont en H + vitesse"
        case .servoArm: return "Curseurs et boutons dédiés au pilotage multi-servomoteurs"
        }
    }

    func buildAssignments(for board: ArduinoBoardCapability) -> [GamepadSlot: ButtonAssignment] {
        let led1 = board.boardType.defaultLedPin
        let led2 = board.boardType.defaultSecondaryLedPin
        let servo1 = board.boardType.defaultServoPin
        let pwmPins = board.pwmAvailablePins.map { $0.number }
        let pwm1 = pwmPins.first(where: { $0 != led1 && $0 != servo1 }) ?? servo1
        let pwm2 = pwmPins.last(where: { $0 != led1 && $0 != pwm1 }) ?? pwm1
        let allPins = board.availablePins.map { $0.number }
        let auxPin = allPins.first(where: { $0 != led1 && $0 != led2 && $0 != servo1 }) ?? led2
        let motors = board.boardType.defaultMotorPins
        let m1 = motors[0]
        let m2 = motors[1]
        let m3 = motors[2]
        let m4 = motors[3]

        switch self {
        case .standardKit:
            return [
                .dpadUp: ButtonAssignment(
                    id: .dpadUp, label: "Avant", symbolName: "arrow.up",
                    colorToken: .blue, actionType: .pinDigital, behavior: .momentary,
                    primaryPin: auxPin, activeValue: 1, releaseValue: 0,
                    extraPinTargets: [], pressCommand: "FWD", releaseCommand: "STOP",
                    minSliderValue: 0, maxSliderValue: 1
                ),
                .dpadDown: ButtonAssignment(
                    id: .dpadDown, label: "Arrière", symbolName: "arrow.down",
                    colorToken: .blue, actionType: .pinDigital, behavior: .momentary,
                    primaryPin: led2, activeValue: 1, releaseValue: 0,
                    extraPinTargets: [], pressCommand: "BWD", releaseCommand: "STOP",
                    minSliderValue: 0, maxSliderValue: 1
                ),
                .dpadLeft: ButtonAssignment(
                    id: .dpadLeft, label: "Gauche", symbolName: "arrow.left",
                    colorToken: .blue, actionType: .pinServo, behavior: .push,
                    primaryPin: servo1, activeValue: 30, releaseValue: 90,
                    extraPinTargets: [], pressCommand: "LEFT", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 180
                ),
                .dpadRight: ButtonAssignment(
                    id: .dpadRight, label: "Droite", symbolName: "arrow.right",
                    colorToken: .blue, actionType: .pinServo, behavior: .push,
                    primaryPin: servo1, activeValue: 150, releaseValue: 90,
                    extraPinTargets: [], pressCommand: "RIGHT", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 180
                ),
                .buttonA: ButtonAssignment(
                    id: .buttonA, label: "LED 1", symbolName: "lightbulb.fill",
                    colorToken: .green, actionType: .pinDigital, behavior: .toggle,
                    primaryPin: led1, activeValue: 1, releaseValue: 0,
                    extraPinTargets: [], pressCommand: "", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 1
                ),
                .buttonB: ButtonAssignment(
                    id: .buttonB, label: "LED 2", symbolName: "lightbulb.circle.fill",
                    colorToken: .red, actionType: .pinDigital, behavior: .toggle,
                    primaryPin: led2, activeValue: 1, releaseValue: 0,
                    extraPinTargets: [], pressCommand: "", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 1
                ),
                .buttonX: ButtonAssignment(
                    id: .buttonX, label: "Pulse", symbolName: "bolt.fill",
                    colorToken: .blue, actionType: .pinPWM, behavior: .momentary,
                    primaryPin: pwm1, activeValue: 200, releaseValue: 0,
                    extraPinTargets: [], pressCommand: "", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 255
                ),
                .buttonY: ButtonAssignment(
                    id: .buttonY, label: "Centre", symbolName: "scope",
                    colorToken: .orange, actionType: .pinServo, behavior: .push,
                    primaryPin: servo1, activeValue: 90, releaseValue: 90,
                    extraPinTargets: [], pressCommand: "", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 180
                ),
                .shoulderL1: ButtonAssignment(
                    id: .shoulderL1, label: "Min", symbolName: "minus.circle.fill",
                    colorToken: .teal, actionType: .pinPWM, behavior: .push,
                    primaryPin: pwm1, activeValue: 64, releaseValue: 0,
                    extraPinTargets: [], pressCommand: "", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 255
                ),
                .shoulderR1: ButtonAssignment(
                    id: .shoulderR1, label: "Max", symbolName: "plus.circle.fill",
                    colorToken: .purple, actionType: .pinPWM, behavior: .push,
                    primaryPin: pwm1, activeValue: 255, releaseValue: 0,
                    extraPinTargets: [], pressCommand: "", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 255
                ),
                .select: ButtonAssignment(
                    id: .select, label: "Ping", symbolName: "wave.3.right",
                    colorToken: .gray, actionType: .customCommand, behavior: .push,
                    primaryPin: led1, activeValue: 1, releaseValue: 0,
                    extraPinTargets: [], pressCommand: "PING", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 1
                ),
                .start: ButtonAssignment(
                    id: .start, label: "STOP", symbolName: "stop.circle.fill",
                    colorToken: .red, actionType: .emergencyStop, behavior: .push,
                    primaryPin: led1, activeValue: 0, releaseValue: 0,
                    extraPinTargets: [], pressCommand: "X", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 1
                ),
                .sliderLeft: ButtonAssignment(
                    id: .sliderLeft, label: "Servo", symbolName: "angle",
                    colorToken: .orange, actionType: .pinServo, behavior: .push,
                    primaryPin: servo1, activeValue: 90, releaseValue: 90,
                    extraPinTargets: [], pressCommand: "", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 180
                ),
                .sliderRight: ButtonAssignment(
                    id: .sliderRight, label: "Variateur PWM", symbolName: "slider.horizontal.3",
                    colorToken: .teal, actionType: .pinPWM, behavior: .push,
                    primaryPin: pwm1, activeValue: 128, releaseValue: 0,
                    extraPinTargets: [], pressCommand: "", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 255
                )
            ]

        case .robotCar:
            return [
                .dpadUp: ButtonAssignment(
                    id: .dpadUp, label: "Avancer", symbolName: "arrow.up",
                    colorToken: .green, actionType: .multiPin, behavior: .momentary,
                    primaryPin: m1, activeValue: 1, releaseValue: 0,
                    extraPinTargets: [
                        PinTarget(pin: m1, signalKind: .digital, activeValue: 1, releaseValue: 0),
                        PinTarget(pin: m2, signalKind: .digital, activeValue: 0, releaseValue: 0),
                        PinTarget(pin: m3, signalKind: .digital, activeValue: 1, releaseValue: 0),
                        PinTarget(pin: m4, signalKind: .digital, activeValue: 0, releaseValue: 0)
                    ],
                    pressCommand: "", releaseCommand: "", minSliderValue: 0, maxSliderValue: 1
                ),
                .dpadDown: ButtonAssignment(
                    id: .dpadDown, label: "Reculer", symbolName: "arrow.down",
                    colorToken: .orange, actionType: .multiPin, behavior: .momentary,
                    primaryPin: m1, activeValue: 1, releaseValue: 0,
                    extraPinTargets: [
                        PinTarget(pin: m1, signalKind: .digital, activeValue: 0, releaseValue: 0),
                        PinTarget(pin: m2, signalKind: .digital, activeValue: 1, releaseValue: 0),
                        PinTarget(pin: m3, signalKind: .digital, activeValue: 0, releaseValue: 0),
                        PinTarget(pin: m4, signalKind: .digital, activeValue: 1, releaseValue: 0)
                    ],
                    pressCommand: "", releaseCommand: "", minSliderValue: 0, maxSliderValue: 1
                ),
                .dpadLeft: ButtonAssignment(
                    id: .dpadLeft, label: "Gauche", symbolName: "arrow.left",
                    colorToken: .blue, actionType: .multiPin, behavior: .momentary,
                    primaryPin: m1, activeValue: 1, releaseValue: 0,
                    extraPinTargets: [
                        PinTarget(pin: m1, signalKind: .digital, activeValue: 0, releaseValue: 0),
                        PinTarget(pin: m2, signalKind: .digital, activeValue: 1, releaseValue: 0),
                        PinTarget(pin: m3, signalKind: .digital, activeValue: 1, releaseValue: 0),
                        PinTarget(pin: m4, signalKind: .digital, activeValue: 0, releaseValue: 0)
                    ],
                    pressCommand: "", releaseCommand: "", minSliderValue: 0, maxSliderValue: 1
                ),
                .dpadRight: ButtonAssignment(
                    id: .dpadRight, label: "Droite", symbolName: "arrow.right",
                    colorToken: .blue, actionType: .multiPin, behavior: .momentary,
                    primaryPin: m1, activeValue: 1, releaseValue: 0,
                    extraPinTargets: [
                        PinTarget(pin: m1, signalKind: .digital, activeValue: 1, releaseValue: 0),
                        PinTarget(pin: m2, signalKind: .digital, activeValue: 0, releaseValue: 0),
                        PinTarget(pin: m3, signalKind: .digital, activeValue: 0, releaseValue: 0),
                        PinTarget(pin: m4, signalKind: .digital, activeValue: 1, releaseValue: 0)
                    ],
                    pressCommand: "", releaseCommand: "", minSliderValue: 0, maxSliderValue: 1
                ),
                .buttonA: ButtonAssignment(
                    id: .buttonA, label: "Phares", symbolName: "flashlight.on.fill",
                    colorToken: .yellow, actionType: .pinDigital, behavior: .toggle,
                    primaryPin: led1, activeValue: 1, releaseValue: 0,
                    extraPinTargets: [], pressCommand: "", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 1
                ),
                .buttonB: ButtonAssignment(
                    id: .buttonB, label: "Frein", symbolName: "octagon.fill",
                    colorToken: .red, actionType: .emergencyStop, behavior: .push,
                    primaryPin: led1, activeValue: 0, releaseValue: 0,
                    extraPinTargets: [], pressCommand: "", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 1
                ),
                .buttonX: ButtonAssignment(
                    id: .buttonX, label: "Klaxon", symbolName: "speaker.wave.3.fill",
                    colorToken: .teal, actionType: .pinDigital, behavior: .momentary,
                    primaryPin: led2, activeValue: 1, releaseValue: 0,
                    extraPinTargets: [], pressCommand: "", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 1
                ),
                .buttonY: ButtonAssignment(
                    id: .buttonY, label: "Tourelle", symbolName: "rotate.right.fill",
                    colorToken: .purple, actionType: .pinServo, behavior: .momentary,
                    primaryPin: servo1, activeValue: 160, releaseValue: 90,
                    extraPinTargets: [], pressCommand: "", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 180
                ),
                .shoulderL1: ButtonAssignment(
                    id: .shoulderL1, label: "Lent", symbolName: "tortoise.fill",
                    colorToken: .teal, actionType: .pinPWM, behavior: .push,
                    primaryPin: pwm2, activeValue: 110, releaseValue: 0,
                    extraPinTargets: [], pressCommand: "", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 255
                ),
                .shoulderR1: ButtonAssignment(
                    id: .shoulderR1, label: "Turbo", symbolName: "hare.fill",
                    colorToken: .orange, actionType: .pinPWM, behavior: .push,
                    primaryPin: pwm2, activeValue: 255, releaseValue: 0,
                    extraPinTargets: [], pressCommand: "", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 255
                ),
                .select: ButtonAssignment(
                    id: .select, label: "Capteur", symbolName: "thermometer",
                    colorToken: .gray, actionType: .customCommand, behavior: .push,
                    primaryPin: led1, activeValue: 1, releaseValue: 0,
                    extraPinTargets: [], pressCommand: "T?", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 1
                ),
                .start: ButtonAssignment(
                    id: .start, label: "STOP", symbolName: "stop.circle.fill",
                    colorToken: .red, actionType: .emergencyStop, behavior: .push,
                    primaryPin: led1, activeValue: 0, releaseValue: 0,
                    extraPinTargets: [], pressCommand: "X", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 1
                ),
                .sliderLeft: ButtonAssignment(
                    id: .sliderLeft, label: "Vitesse PWM", symbolName: "speedometer",
                    colorToken: .green, actionType: .pinPWM, behavior: .push,
                    primaryPin: pwm2, activeValue: 180, releaseValue: 0,
                    extraPinTargets: [], pressCommand: "", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 255
                ),
                .sliderRight: ButtonAssignment(
                    id: .sliderRight, label: "Direction Servo", symbolName: "arrow.triangle.turn.up.right.circle.fill",
                    colorToken: .blue, actionType: .pinServo, behavior: .push,
                    primaryPin: servo1, activeValue: 90, releaseValue: 90,
                    extraPinTargets: [], pressCommand: "", releaseCommand: "",
                    minSliderValue: 0, maxSliderValue: 180
                )
            ]

        case .servoArm:
            var base = BuiltInPresetKind.standardKit.buildAssignments(for: board)
            base[.dpadUp] = ButtonAssignment(
                id: .dpadUp, label: "Bras Haut", symbolName: "arrow.up",
                colorToken: .orange, actionType: .pinServo, behavior: .push,
                primaryPin: m1, activeValue: 150, releaseValue: 90,
                extraPinTargets: [], pressCommand: "", releaseCommand: "",
                minSliderValue: 0, maxSliderValue: 180
            )
            base[.dpadDown] = ButtonAssignment(
                id: .dpadDown, label: "Bras Bas", symbolName: "arrow.down",
                colorToken: .orange, actionType: .pinServo, behavior: .push,
                primaryPin: m1, activeValue: 30, releaseValue: 90,
                extraPinTargets: [], pressCommand: "", releaseCommand: "",
                minSliderValue: 0, maxSliderValue: 180
            )
            base[.dpadLeft] = ButtonAssignment(
                id: .dpadLeft, label: "Base -", symbolName: "arrow.left",
                colorToken: .purple, actionType: .pinServo, behavior: .push,
                primaryPin: servo1, activeValue: 20, releaseValue: 90,
                extraPinTargets: [], pressCommand: "", releaseCommand: "",
                minSliderValue: 0, maxSliderValue: 180
            )
            base[.dpadRight] = ButtonAssignment(
                id: .dpadRight, label: "Base +", symbolName: "arrow.right",
                colorToken: .purple, actionType: .pinServo, behavior: .push,
                primaryPin: servo1, activeValue: 160, releaseValue: 90,
                extraPinTargets: [], pressCommand: "", releaseCommand: "",
                minSliderValue: 0, maxSliderValue: 180
            )
            base[.buttonA] = ButtonAssignment(
                id: .buttonA, label: "Fermer Pince", symbolName: "hand.raised.fill",
                colorToken: .green, actionType: .pinServo, behavior: .toggle,
                primaryPin: m2, activeValue: 140, releaseValue: 40,
                extraPinTargets: [], pressCommand: "", releaseCommand: "",
                minSliderValue: 0, maxSliderValue: 180
            )
            base[.sliderLeft] = ButtonAssignment(
                id: .sliderLeft, label: "Rotation Base", symbolName: "rotate.3d",
                colorToken: .purple, actionType: .pinServo, behavior: .push,
                primaryPin: servo1, activeValue: 90, releaseValue: 90,
                extraPinTargets: [], pressCommand: "", releaseCommand: "",
                minSliderValue: 0, maxSliderValue: 180
            )
            base[.sliderRight] = ButtonAssignment(
                id: .sliderRight, label: "Élévation Bras", symbolName: "slider.vertical.3",
                colorToken: .orange, actionType: .pinServo, behavior: .push,
                primaryPin: m1, activeValue: 90, releaseValue: 90,
                extraPinTargets: [], pressCommand: "", releaseCommand: "",
                minSliderValue: 0, maxSliderValue: 180
            )
            return base
        }
    }
}
