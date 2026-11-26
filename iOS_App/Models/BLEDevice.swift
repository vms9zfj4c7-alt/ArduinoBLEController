import Foundation
import CoreBluetooth

/// Représente un périphérique BLE découvert lors du scan, avec distance estimée et décodage fabricant/service.
struct BLEDevice: Identifiable, Equatable {
    let id: UUID
    let rawName: String?
    let rssi: Int
    let advertisedServiceUUIDs: [CBUUID]
    let manufacturerID: UInt16?
    let manufacturerName: String?
    let appleContinuityType: UInt8?
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
        "ARDUINO", "ESP32", "HM-10", "HM10", "HMSOFT", "BT05", "BT04", "MLT-BT05",
        "AT-09", "HC-08", "HC-06", "HC-05", "HC05", "HC06", "JDY", "DX-BT",
        "FSC-", "FEASYCOM", "DSD", "SH-HC", "CC254", "SERIAL", "UART", "SPP",
        "V3.0", "NANO", "UNO", "MEGA", "ROBOT"
    ]

    init(
        id: UUID,
        rawName: String?,
        rssi: Int,
        advertisedServiceUUIDs: [CBUUID],
        manufacturerData: Data? = nil,
        manufacturerID: UInt16? = nil,
        appleContinuityType: UInt8? = nil,
        txPowerLevel: Int? = nil,
        isConnectable: Bool = true,
        lastSeen: TimeInterval = CFAbsoluteTimeGetCurrent()
    ) {
        let trimmedName = rawName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = (trimmedName?.isEmpty == false) ? trimmedName : nil

        let resolvedMfrID = Self.parseManufacturerID(from: manufacturerData) ?? manufacturerID
        let parsedAppleSubtype: UInt8?
        if resolvedMfrID == 0x004C, let mfrData = manufacturerData, mfrData.count >= 3 {
            parsedAppleSubtype = mfrData[mfrData.startIndex + 2]
        } else {
            parsedAppleSubtype = appleContinuityType
        }

        let mfrName = resolvedMfrID.flatMap { Self.manufacturerDisplayName(for: $0) }

        self.id = id
        self.rawName = cleanName
        self.rssi = rssi
        self.advertisedServiceUUIDs = advertisedServiceUUIDs
        self.manufacturerID = resolvedMfrID
        self.manufacturerName = mfrName
        self.appleContinuityType = parsedAppleSubtype
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

        let appleFriendly = parsedAppleSubtype.flatMap { Self.appleContinuityDisplayName(for: $0) }
        let standardServiceFriendly = Self.standardServiceName(from: advertisedServiceUUIDs)

        if let cleanName {
            self.displayName = cleanName
        } else if hasKnownUUID {
            self.displayName = "Module Arduino / BLE"
        } else if let appleFriendly {
            self.displayName = appleFriendly
        } else if let mfrName {
            self.displayName = "Appareil \(mfrName)"
        } else if let standardServiceFriendly {
            self.displayName = standardServiceFriendly
        } else {
            self.displayName = "Appareil BLE (\(id.uuidString.prefix(4)))"
        }

        self.detectedModuleHint = Self.buildHint(
            upperName: upper,
            serviceUUIDs: advertisedServiceUUIDs,
            manufacturerName: mfrName,
            appleSubtypeName: appleFriendly,
            standardServiceName: standardServiceFriendly,
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
            && lhs.appleContinuityType == rhs.appleContinuityType
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
        appleSubtypeName: String?,
        standardServiceName: String?,
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
        if serviceUUIDs.contains(BLEProtocolConstants.genericSerialServiceUUID)
            || serviceUUIDs.contains(BLEProtocolConstants.isscSerialServiceUUID) {
            return "Module BLE Série (UART)"
        }
        if upperName.contains("ESP32") { return "ESP32" }
        if upperName.contains("R4") { return "Arduino Uno R4 WiFi" }
        if upperName.contains("NANO") { return "Arduino Nano" }
        if upperName.contains("HM") || upperName.contains("BT05") || upperName.contains("JDY") {
            return "Module série BLE"
        }
        if let standardServiceName {
            return isConnectable ? "\(standardServiceName) • Connectable" : standardServiceName
        }
        if let appleSubtypeName {
            return isConnectable ? "Apple • \(appleSubtypeName)" : "Apple • \(appleSubtypeName) (balise)"
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

    private static func appleContinuityDisplayName(for typeByte: UInt8) -> String? {
        switch typeByte {
        case 0x02: return "Balise iBeacon"
        case 0x07: return "Audio / AirPods"
        case 0x09: return "Appareil AirPlay"
        case 0x10: return "iPhone / Mac / iPad"
        case 0x12: return "AirTag / Localiser"
        case 0x05, 0x06, 0x0B, 0x0F: return "Accessoire Apple"
        default: return nil
        }
    }

    private static let standardServiceNames: [CBUUID: String] = [
        CBUUID(string: "180D"): "Capteur cardiaque",
        CBUUID(string: "1812"): "Périphérique HID / Manette",
        CBUUID(string: "1816"): "Capteur vélo",
        CBUUID(string: "1818"): "Capteur puissance",
        CBUUID(string: "181A"): "Capteur environnement",
        CBUUID(string: "180F"): "Service Batterie BLE",
        CBUUID(string: "FE9F"): "Google Fast Pair",
        CBUUID(string: "FEAA"): "Balise Eddystone",
        CBUUID(string: "FEED"): "Traceur Tile"
    ]

    private static func standardServiceName(from serviceUUIDs: [CBUUID]) -> String? {
        for uuid in serviceUUIDs {
            if let label = standardServiceNames[uuid] {
                return label
            }
        }
        return nil
    }

    private static func manufacturerDisplayName(for companyID: UInt16) -> String? {
        switch companyID {
        case 0x004C: return "Apple"
        case 0x0006: return "Microsoft"
        case 0x0075: return "Samsung"
        case 0x00E0: return "Google"
        case 0x02E5: return "Espressif (ESP32)"
        case 0x0059: return "Nordic Semiconductor"
        case 0x000D: return "Texas Instruments / HM-10"
        case 0x012D: return "Sony"
        case 0x0057: return "Harman / JBL"
        case 0x038F: return "Xiaomi"
        case 0x0087: return "Garmin"
        case 0x009E: return "Bose"
        case 0x00A9: return "Beats"
        case 0x0157: return "Huawei"
        case 0x010F: return "Honor / HiSilicon"
        case 0x01DA: return "Logitech"
        case 0x026B: return "Fitbit"
        case 0x0553: return "Nintendo"
        case 0x0822: return "Adafruit"
        case 0x02FF: return "Silicon Labs"
        case 0x0047: return "Raspberry Pi / Cypress"
        case 0x000A: return "Qualcomm"
        case 0x005D: return "Realtek"
        case 0x00D2: return "Dialog"
        case 0x000F: return "Broadcom"
        case 0x0002: return "Intel"
        default: return nil
        }
    }
}
