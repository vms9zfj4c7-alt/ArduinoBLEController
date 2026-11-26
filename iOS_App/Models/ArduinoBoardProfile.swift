import Foundation

/// Types de cartes Arduino / BLE reconnues par l'application.
enum ArduinoBoardType: String, CaseIterable, Codable, Identifiable {
    case auto = "AUTO"
    case unoR4WiFi = "UNO_R4_WIFI"
    case nano33BLE = "NANO_33_BLE"
    case esp32 = "ESP32"
    case unoHM10 = "UNO_HM10"
    case megaHM10 = "MEGA_HM10"
    case generic = "GENERIC"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto-détection"
        case .unoR4WiFi: return "Arduino Uno R4 WiFi"
        case .nano33BLE: return "Arduino Nano 33 BLE / IoT"
        case .esp32: return "ESP32 / Nano ESP32"
        case .unoHM10: return "Arduino Uno / Nano + HM-10"
        case .megaHM10: return "Arduino Mega + HM-10"
        case .generic: return "Autre carte BLE"
        }
    }

    var shortBadge: String {
        switch self {
        case .auto: return "Auto"
        case .unoR4WiFi: return "Uno R4"
        case .nano33BLE: return "Nano 33"
        case .esp32: return "ESP32"
        case .unoHM10: return "Uno + HM-10"
        case .megaHM10: return "Mega + HM-10"
        case .generic: return "BLE"
        }
    }

    var defaultLedPin: Int {
        switch self {
        case .esp32: return 2
        default: return 13
        }
    }

    var defaultSecondaryLedPin: Int {
        switch self {
        case .esp32: return 4
        case .unoHM10: return 12
        default: return 12
        }
    }

    var defaultServoPin: Int {
        switch self {
        case .esp32: return 18
        default: return 9
        }
    }

    var defaultMotorPins: [Int] {
        switch self {
        case .esp32: return [12, 13, 14, 27]
        case .unoHM10: return [5, 6, 10, 11]
        default: return [5, 6, 9, 10]
        }
    }
}

/// Représente une broche disponible sur la carte Arduino connectée.
struct ArduinoPinOption: Identifiable, Hashable, Codable {
    var id: Int { number }
    let number: Int
    let supportsPWM: Bool
    let isBuiltInLED: Bool

    var displayLabel: String {
        var tags: [String] = []
        if supportsPWM { tags.append("PWM") }
        if isBuiltInLED { tags.append("LED") }
        if tags.isEmpty {
            return "Broche \(number)"
        }
        return "Broche \(number) (\(tags.joined(separator: ", ")))"
    }

    var shortLabel: String {
        "Pin \(number)"
    }
}

/// Capacités matérielles actives de la carte Arduino (détectées automatiquement ou sélectionnées).
struct ArduinoBoardCapability: Equatable, Codable {
    let boardType: ArduinoBoardType
    let boardIdentifier: String
    let availablePins: [ArduinoPinOption]
    let pwmPins: Set<Int>
    let hasTemperatureTelemetry: Bool
    let isAutoDetected: Bool

    var pwmAvailablePins: [ArduinoPinOption] {
        availablePins.filter { $0.supportsPWM }
    }

    func pinOption(for number: Int) -> ArduinoPinOption? {
        availablePins.first { $0.number == number }
    }

    static func defaultCapability(for type: ArduinoBoardType, isAutoDetected: Bool = false) -> ArduinoBoardCapability {
        let resolvedType: ArduinoBoardType = (type == .auto) ? .unoR4WiFi : type
        let pins: [Int]
        let pwm: Set<Int>
        let ledPin = resolvedType.defaultLedPin

        switch resolvedType {
        case .esp32:
            pins = [2, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33]
            pwm = Set([2, 4, 5, 12, 13, 14, 15, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33])
        case .unoR4WiFi:
            pins = Array(2...13)
            pwm = Set([3, 5, 6, 9, 10, 11])
        case .nano33BLE:
            pins = Array(2...13)
            pwm = Set(2...13)
        case .unoHM10:
            // Broches 2 et 3 réservées à SoftwareSerial (HM-10)
            pins = Array(4...13)
            pwm = Set([5, 6, 9, 10, 11])
        case .megaHM10:
            pins = Array(2...13) + Array(22...33) + [44, 45, 46]
            pwm = Set(Array(2...13) + [44, 45, 46])
        case .generic, .auto:
            pins = Array(2...13)
            pwm = Set([3, 5, 6, 9, 10, 11])
        }

        let options = pins.map { pin in
            ArduinoPinOption(
                number: pin,
                supportsPWM: pwm.contains(pin),
                isBuiltInLED: pin == ledPin
            )
        }

        return ArduinoBoardCapability(
            boardType: resolvedType,
            boardIdentifier: resolvedType.rawValue,
            availablePins: options,
            pwmPins: pwm,
            hasTemperatureTelemetry: true,
            isAutoDetected: isAutoDetected
        )
    }

    /// Analyse la réponse `INFO:BOARD=...;PINS=...;PWM=...;TEMP=...` émise par l'Arduino.
    static func parse(infoLine: String) -> ArduinoBoardCapability? {
        guard infoLine.hasPrefix("INFO:") else { return nil }
        let body = String(infoLine.dropFirst("INFO:".count))
        let segments = body.split(separator: ";")

        var boardID = "GENERIC"
        var parsedPins: [Int] = []
        var parsedPWM: Set<Int> = []
        var hasTemp = true

        for segment in segments {
            let parts = segment.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).uppercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "BOARD":
                boardID = value.uppercased()
            case "PINS":
                parsedPins = value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            case "PWM":
                parsedPWM = Set(value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
            case "TEMP":
                hasTemp = (value == "1" || value.lowercased() == "true")
            default:
                break
            }
        }

        let boardType = ArduinoBoardType(rawValue: boardID) ?? inferFromBoardIdentifier(boardID)
        if parsedPins.isEmpty {
            return defaultCapability(for: boardType, isAutoDetected: true)
        }

        let ledPin = boardType.defaultLedPin
        let options = parsedPins.map { pin in
            ArduinoPinOption(
                number: pin,
                supportsPWM: parsedPWM.contains(pin),
                isBuiltInLED: pin == ledPin
            )
        }

        return ArduinoBoardCapability(
            boardType: boardType,
            boardIdentifier: boardID,
            availablePins: options,
            pwmPins: parsedPWM,
            hasTemperatureTelemetry: hasTemp,
            isAutoDetected: true
        )
    }

    static func inferFromBoardIdentifier(_ identifier: String) -> ArduinoBoardType {
        let upper = identifier.uppercased()
        if upper.contains("ESP32") { return .esp32 }
        if upper.contains("R4") { return .unoR4WiFi }
        if upper.contains("NANO") { return .nano33BLE }
        if upper.contains("MEGA") { return .megaHM10 }
        if upper.contains("HM10") || upper.contains("UNO") { return .unoHM10 }
        return .generic
    }

    static func inferFromDeviceMetadata(name: String, serviceUUIDStrings: [String]) -> ArduinoBoardType {
        let upperName = name.uppercased()
        if serviceUUIDStrings.contains(where: { $0.uppercased() == "FFE0" }) {
            if upperName.contains("MEGA") { return .megaHM10 }
            return .unoHM10
        }
        if upperName.contains("ESP32") { return .esp32 }
        if upperName.contains("R4") { return .unoR4WiFi }
        if upperName.contains("NANO") { return .nano33BLE }
        if upperName.contains("UNO") { return .unoHM10 }
        return .unoR4WiFi
    }
}
