import Foundation
import CoreBluetooth

/// Représente un périphérique BLE découvert lors du scan (métadonnées précalculées pour tri/affichage rapide).
struct BLEDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let advertisedServiceUUIDs: [CBUUID]
    let lastSeen: Date
    let isLikelyArduino: Bool
    let detectedModuleHint: String

    private static let arduinoKeywords = [
        "ARDUINO", "ESP32", "HM-10", "HMSOFT", "BT05", "MLT-BT05", "NANO", "UNO", "JDY", "BLE"
    ]

    init(
        id: UUID,
        name: String,
        rssi: Int,
        advertisedServiceUUIDs: [CBUUID],
        lastSeen: Date
    ) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.advertisedServiceUUIDs = advertisedServiceUUIDs
        self.lastSeen = lastSeen

        let upper = name.uppercased()
        let hasKnownUUID = advertisedServiceUUIDs.contains { uuid in
            BLEProtocolConstants.knownArduinoServiceUUIDs.contains(uuid)
        }
        self.isLikelyArduino = hasKnownUUID || Self.arduinoKeywords.contains { upper.contains($0) }

        if advertisedServiceUUIDs.contains(BLEProtocolConstants.customServiceUUID) {
            self.detectedModuleHint = "Arduino / ESP32 (BLE)"
        } else if advertisedServiceUUIDs.contains(BLEProtocolConstants.hm10ServiceUUID) {
            self.detectedModuleHint = "Module HM-10 / Série"
        } else if advertisedServiceUUIDs.contains(BLEProtocolConstants.nordicServiceUUID) {
            self.detectedModuleHint = "Nordic UART"
        } else if upper.contains("ESP32") {
            self.detectedModuleHint = "ESP32"
        } else if upper.contains("R4") {
            self.detectedModuleHint = "Uno R4 WiFi"
        } else if upper.contains("NANO") {
            self.detectedModuleHint = "Arduino Nano"
        } else if upper.contains("HM") || upper.contains("BT05") {
            self.detectedModuleHint = "Module série BLE"
        } else {
            self.detectedModuleHint = "Périphérique BLE"
        }
    }

    var signalBars: Int {
        switch rssi {
        case -55...0: return 4
        case -70 ..< -55: return 3
        case -85 ..< -70: return 2
        default: return 1
        }
    }

    var signalDescription: String {
        switch signalBars {
        case 4: return "Excellent"
        case 3: return "Bon"
        case 2: return "Moyen"
        default: return "Faible"
        }
    }
}
