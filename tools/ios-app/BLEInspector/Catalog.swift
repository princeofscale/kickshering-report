//
//  Catalog.swift
//  BLEInspector
//
//  Offline reference data used by the on-device analyzers. No secrets,
//  keys, or exploit payloads — only public, interoperability-oriented
//  identifiers (standard Bluetooth SIG UUIDs + the verified Ninebot/Xiaomi
//  markers documented in ../../../docs/16-ble-protocol-reference.md).
//

import Foundation

// MARK: - Verified Ninebot/Xiaomi constants (docs/16)

enum NinebotRef {
    // Family A -- Legacy / M365 (Nordic UART Service). Source: etransport/py9b.
    static let nusServiceUUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    static let nusRXCharUUID  = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"  // phone -> scooter (write)
    static let nusTXCharUUID  = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"  // scooter -> phone (notify)

    // Family B -- Native Ninebot service. Source: djensenius Segway BLE Reference.
    // Suffix = ASCII "ninebot". NOTE: notify is ...0004, NOT ...0003.
    static let nbServiceUUID   = "6E400001-0000-0000-006E-696E65626F74"
    static let nbWriteCharUUID = "6E400002-0000-0000-006E-696E65626F74"  // phone -> scooter (write)
    static let nbNotifyCharUUID = "6E400004-0000-0000-006E-696E65626F74" // scooter -> phone (notify)

    // ASCII "ninebot" marker; any service UUID whose hex contains it is a native Ninebot service.
    static let asciiMarker = "696E65626F74"

    static let namePrefixes: [String: String] = [
        "MISc": "Mi Scooter (Xiaomi M365 family)",
        "NBSc": "Ninebot Scooter (Max/ES family)",
    ]

    /// Human label if the advertised name matches a known prefix, else nil.
    static func familyForName(_ name: String?) -> String? {
        guard let name = name else { return nil }
        for (prefix, label) in namePrefixes where name.hasPrefix(prefix) { return label }
        return nil
    }

    /// True if UUID is a known Ninebot transport service (either family) or embeds the ASCII marker.
    static func isNinebotService(_ uuid: String) -> Bool {
        let u = GATTCatalog.normalize(uuid)
        if u == nusServiceUUID || u == nbServiceUUID { return true }
        return u.replacingOccurrences(of: "-", with: "").contains(asciiMarker)
    }

    /// True for the write ('command') characteristic of either service family.
    static func isCommandWriteChar(_ uuid: String) -> Bool {
        let u = GATTCatalog.normalize(uuid)
        return u == nusRXCharUUID || u == nbWriteCharUUID
    }
}

// MARK: - Standard + known UUID catalog

enum GATTCatalog {

    /// Uppercase, and expand a 16-bit shorthand ("180A") to the full 128-bit base UUID.
    static func normalize(_ uuid: String) -> String {
        let u = uuid.trimmingCharacters(in: .whitespaces).uppercased()
        if u.count == 4 {
            return "0000\(u)-0000-1000-8000-00805F9B34FB"
        }
        return u
    }

    /// Human-readable names for well-known services/characteristics (normalized keys).
    static let names: [String: String] = {
        var m: [String: String] = [:]
        func put(_ short: String, _ name: String) { m[normalize(short)] = name }
        // Services
        put("1800", "Generic Access")
        put("1801", "Generic Attribute")
        put("180A", "Device Information")
        put("180F", "Battery Service")
        put("1802", "Immediate Alert")
        put("1803", "Link Loss")
        put("1804", "Tx Power")
        put("FE95", "Xiaomi (Mi) Service")
        // Device Information characteristics
        put("2A29", "Manufacturer Name String")
        put("2A24", "Model Number String")
        put("2A25", "Serial Number String")
        put("2A26", "Firmware Revision String")
        put("2A27", "Hardware Revision String")
        put("2A28", "Software Revision String")
        put("2A23", "System ID")
        put("2A50", "PnP ID")
        // Generic Access characteristics
        put("2A00", "Device Name")
        put("2A01", "Appearance")
        // Battery
        put("2A19", "Battery Level")
        // Family A -- Nordic UART Service
        m[NinebotRef.nusServiceUUID] = "Nordic UART Service (Ninebot/Xiaomi transport, family A)"
        m[NinebotRef.nusRXCharUUID]  = "NUS RX — command channel (phone → scooter, write)"
        m[NinebotRef.nusTXCharUUID]  = "NUS TX — telemetry (scooter → phone, notify)"
        // Family B -- Native Ninebot service (UUID embeds ASCII "ninebot")
        m[NinebotRef.nbServiceUUID]    = "Native Ninebot Service (transport, family B)"
        m[NinebotRef.nbWriteCharUUID]  = "Ninebot write — command channel (phone → scooter, write)"
        m[NinebotRef.nbNotifyCharUUID] = "Ninebot notify — telemetry (scooter → phone, notify, ...0004)"
        return m
    }()

    static func name(for uuid: String) -> String? {
        names[normalize(uuid)]
    }

    /// Device Information Service characteristics whose value is a UTF-8/ASCII string.
    static let stringDecodableChars: Set<String> = [
        normalize("2A29"), normalize("2A24"), normalize("2A25"),
        normalize("2A26"), normalize("2A27"), normalize("2A28"),
        normalize("2A00"),
    ]

    /// Properties that make a characteristic a potential command channel (level E, docs/10).
    static let writeLikeProperties: Set<String> = [
        "write", "writeWithoutResponse", "authenticatedSignedWrites",
    ]

    static func isNUSService(_ uuid: String) -> Bool { normalize(uuid) == NinebotRef.nusServiceUUID }
    static func isNUSRX(_ uuid: String) -> Bool { normalize(uuid) == NinebotRef.nusRXCharUUID }
    static func isNUSTX(_ uuid: String) -> Bool { normalize(uuid) == NinebotRef.nusTXCharUUID }

    // Bluetooth SIG company identifiers (little-endian, first 2 bytes of manufacturer data).
    // Only labels we can attest; everything else is reported as an unknown ID (no guessing).
    static let companyIDs: [Int: String] = [
        0x038F: "Xiaomi Inc.",
        0x0157: "Anhui Huami (Xiaomi ecosystem)",
    ]

    /// Parse manufacturer-specific data hex: returns (companyID, label, payloadHex).
    /// Format of the payload itself is NOT decoded (community reference is incomplete/UNCONFIRMED),
    /// so only the company ID is interpreted; the rest is kept as raw hex for the record.
    static func parseManufacturerData(_ hex: String?) -> (companyID: Int, label: String, payloadHex: String)? {
        guard let hex = hex, hex.count >= 4 else { return nil }
        let bytes = stride(from: hex.startIndex, to: hex.endIndex, by: 2).compactMap { i -> UInt8? in
            let j = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            return UInt8(hex[i..<j], radix: 16)
        }
        guard bytes.count >= 2 else { return nil }
        let companyID = Int(bytes[0]) | (Int(bytes[1]) << 8)   // little-endian
        let label = companyIDs[companyID] ?? "unknown company ID"
        let payloadHex = bytes.dropFirst(2).map { String(format: "%02x", $0) }.joined()
        return (companyID, label, payloadHex)
    }
}
