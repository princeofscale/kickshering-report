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
    static let nusServiceUUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    static let nusRXCharUUID  = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"  // phone -> scooter (write)
    static let nusTXCharUUID  = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"  // scooter -> phone (notify)

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
        // Nordic UART Service
        m[NinebotRef.nusServiceUUID] = "Nordic UART Service (classic Ninebot/Xiaomi transport)"
        m[NinebotRef.nusRXCharUUID]  = "NUS RX — command channel (phone → scooter, write)"
        m[NinebotRef.nusTXCharUUID]  = "NUS TX — telemetry (scooter → phone, notify)"
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
}
