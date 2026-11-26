import Foundation
import CoreBluetooth

/// Constantes partagées entre l'application iOS et le sketch Arduino (.ino).
enum BLEProtocolConstants {
    // MARK: - Profil GATT personnalisé (ESP32 / ArduinoBLE : Uno R4 WiFi, Nano 33 BLE, etc.)
    static let customServiceUUID = CBUUID(string: "4FAFCA01-1FB5-459E-8FCC-C5C9C331914B")
    static let customRXCharacteristicUUID = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A8") // iOS -> Arduino (Write)
    static let customTXCharacteristicUUID = CBUUID(string: "BEB5483F-36E1-4688-B7F5-EA07361B26A8") // Arduino -> iOS (Notify)

    // MARK: - Profil HM-10 / AT-09 / BT05 (UART Série sur BLE)
    static let hm10ServiceUUID = CBUUID(string: "FFE0")
    static let hm10CharacteristicUUID = CBUUID(string: "FFE1")

    // MARK: - Profil Nordic UART Service (NUS)
    static let nordicServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let nordicRXCharacteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    static let nordicTXCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    static let knownArduinoServiceUUIDs: [CBUUID] = [
        customServiceUUID,
        hm10ServiceUUID,
        nordicServiceUUID
    ]

    // MARK: - Formatage des commandes compactes (<= 20 octets)
    static let infoQueryCommand = "I?\n"
    static let telemetryQueryCommand = "T?\n"
    static let emergencyStopCommand = "X\n"

    static func digitalCommand(pin: Int, isOn: Bool) -> String {
        "D:\(pin):\(isOn ? 1 : 0)\n"
    }

    static func pwmCommand(pin: Int, value: Int) -> String {
        let clamped = min(max(value, 0), 255)
        return "P:\(pin):\(clamped)\n"
    }

    static func servoCommand(pin: Int, angle: Int) -> String {
        let clamped = min(max(angle, 0), 180)
        return "V:\(pin):\(clamped)\n"
    }

    static func readPinCommand(pin: Int) -> String {
        "R:\(pin)\n"
    }
}
