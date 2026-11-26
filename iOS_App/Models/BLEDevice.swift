import Foundation
import CoreBluetooth

/// Représente un périphérique BLE découvert lors du scan, en fusionnant les paquets ADV_IND et SCAN_RSP.
struct BLEDevice: Identifiable, Equatable {
    let id: UUID
    let rawName: String?
    let rssi: Int
    let advertisedServiceUUIDs: [CBUUID]
    let manufacturerID: UInt16?
    let manufacturerName: String?
    let txPowerLevel: Int?
    let estimatedDistanceMeters: Double
    let baseRadarAngle: Double
    let isConnectable: Bool
    let lastSeen: TimeInterval

    let hasResolvedName: Bool
    let displayName: String
    let isLikelyArduino: Bool
    let detectedModuleHint: String

    private static let arduinoKeywords = [
        "ARDUINO", "ESP32", "HM-10", "HM10", "HMSOFT", "BT05", "MLT-BT05",
        "AT-09", "HC-08", "JDY", "DSD", "SH-HC", "CC254", "NANO", "UNO", "MEGA", "ROBOT"
    ]

    init(
        id: UUID,
        rawName: String?,
        rssi: Int,
        advertisedServiceUUIDs: [CBUUID],
        manufacturerData: Data? = nil,
        manufacturerID: UInt16? = nil,
        txPowerLevel: Int? = nil,
        isConnectable: Bool = true,
        lastSeen: TimeInterval = CFAbsoluteTimeGetCurrent()
    ) {
        let trimmedName = rawName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = (trimmedName?.isEmpty == false) ? trimmedName : nil

        let resolvedMfrID = Self.parseManufacturerID(from: manufacturerData) ?? manufacturerID

        let mfrName = resolvedMfrID.flatMap { Self.manufacturerDisplayName(for: $0) }

        self.id = id
        self.rawName = cleanName
        self.rssi = rssi
        self.advertisedServiceUUIDs = advertisedServiceUUIDs
        self.manufacturerID = resolvedMfrID
        self.manufacturerName = mfrName
        self.txPowerLevel = txPowerLevel
        self.estimatedDistanceMeters = Self.estimateDistanceMeters(rssi: rssi, txPowerLevel: txPowerLevel)
        self.baseRadarAngle = Self.deterministicAngle(for: id)
        self.isConnectable = isConnectable
        self.lastSeen = lastSeen
        self.hasResolvedName = (cleanName != nil)

        let upper = cleanName?.uppercased() ?? ""
        let hasKnownUUID = advertisedServiceUUIDs.contains { uuid in
            BLEProtocolConstants.knownArduinoServiceUUIDs.contains(uuid)
        }
        let hasKeyword = !upper.isEmpty && Self.arduinoKeywords.contains { upper.contains($0) }
        let hasArduinoSilicon = isConnectable && (resolvedMfrID == 0x02E5 || resolvedMfrID == 0x000D)

        self.isLikelyArduino = hasKnownUUID || hasKeyword || hasArduinoSilicon

        if let cleanName {
            self.displayName = cleanName
        } else if hasKnownUUID {
            self.displayName = "Module Arduino / BLE"
        } else if let mfrName {
            self.displayName = "Appareil \(mfrName)"
        } else {
            self.displayName = "Appareil BLE (\(id.uuidString.prefix(4)))"
        }

        self.detectedModuleHint = Self.buildHint(
            upperName: upper,
            serviceUUIDs: advertisedServiceUUIDs,
            manufacturerName: mfrName,
            isConnectable: isConnectable
        )
    }

    static func parseManufacturerID(from manufacturerData: Data?) -> UInt16? {
        guard let mfrData = manufacturerData, mfrData.count >= 2 else { return nil }
        return UInt16(mfrData[mfrData.startIndex]) | (UInt16(mfrData[mfrData.startIndex + 1]) << 8)
    }

    static func == (lhs: BLEDevice, rhs: BLEDevice) -> Bool {
        lhs.id == rhs.id
            && lhs.rssi == rhs.rssi
            && lhs.txPowerLevel == rhs.txPowerLevel
            && lhs.rawName == rhs.rawName
            && lhs.manufacturerID == rhs.manufacturerID
            && lhs.isConnectable == rhs.isConnectable
            && lhs.advertisedServiceUUIDs == rhs.advertisedServiceUUIDs
            && lhs.displayName == rhs.displayName
            && lhs.isLikelyArduino == rhs.isLikelyArduino
            && lhs.detectedModuleHint == rhs.detectedModuleHint
    }

    var formattedDistance: String {
        if estimatedDistanceMeters >= 10.0 {
            return "\(Int(estimatedDistanceMeters.rounded())) m"
        }
        return String(format: "%.1f m", estimatedDistanceMeters)
    }

    var proximityZoneText: String {
        switch estimatedDistanceMeters {
        case ..<1.0: return "Très proche"
        case ..<3.5: return "Proche"
        case ..<9.0: return "Moyen"
        default: return "Éloigné"
        }
    }

    static func estimateDistanceMeters(rssi: Int, txPowerLevel: Int?) -> Double {
        let ref1m: Double
        if let tx = txPowerLevel {
            ref1m = min(max(Double(tx) - 59.0, -76.0), -46.0)
        } else {
            ref1m = -59.0
        }
        let exponent = (ref1m - Double(rssi)) / 24.0
        return min(max(pow(10.0, exponent), 0.2), 25.0)
    }

    private static func deterministicAngle(for uuid: UUID) -> Double {
        let b = uuid.uuid
        let hash = UInt64(b.0) &+ (UInt64(b.5) << 8) &+ (UInt64(b.10) << 16) &+ (UInt64(b.15) << 24)
        let mixed = (hash &* 2654435761) & 0xFFFF
        return (Double(mixed) / 65536.0) * (2.0 * Double.pi)
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

    private static func buildHint(
        upperName: String,
        serviceUUIDs: [CBUUID],
        manufacturerName: String?,
        isConnectable: Bool
    ) -> String {
        if serviceUUIDs.contains(BLEProtocolConstants.customServiceUUID) {
            return "Arduino / ESP32 (BLE)"
        }
        if serviceUUIDs.contains(BLEProtocolConstants.hm10ServiceUUID) {
            return "Module HM-10 / Série (FFE0)"
        }
        if serviceUUIDs.contains(BLEProtocolConstants.nordicServiceUUID) {
            return "Nordic UART (NUS)"
        }
        if upperName.contains("ESP32") { return "ESP32" }
        if upperName.contains("R4") { return "Arduino Uno R4 WiFi" }
        if upperName.contains("NANO") { return "Arduino Nano" }
        if upperName.contains("HM") || upperName.contains("BT05") || upperName.contains("JDY") {
            return "Module série BLE"
        }
        if let mfr = manufacturerName {
            return isConnectable ? "\(mfr) • Connectable" : "\(mfr) • Balise"
        }
        if !serviceUUIDs.isEmpty {
            let shortList = serviceUUIDs.prefix(2).map { $0.uuidString }.joined(separator: ", ")
            return "Services : \(shortList)"
        }
        return isConnectable ? "Bluetooth Low Energy" : "Balise non connectable"
    }

    private static func manufacturerDisplayName(for companyID: UInt16) -> String? {
        switch companyID {
        case 0x004C: return "Apple"
        case 0x0006: return "Microsoft"
        case 0x0075: return "Samsung"
        case 0x00E0: return "Google"
        case 0x02E5: return "Espressif (ESP32)"
        case 0x0059: return "Nordic"
        case 0x000D: return "Texas Instruments / HM-10"
        case 0x012D: return "Sony"
        case 0x038F: return "Xiaomi"
        case 0x0087: return "Garmin"
        case 0x009E: return "Bose"
        case 0x0157: return "Huawei"
        case 0x000A: return "Qualcomm"
        case 0x005D: return "Realtek"
        case 0x00D2: return "Dialog"
        default: return nil
        }
    }
}
