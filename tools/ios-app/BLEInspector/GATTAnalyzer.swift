//
//  GATTAnalyzer.swift
//  BLEInspector
//
//  On-device, OFFLINE analysis of captured GATT snapshots. Pure functions —
//  no Bluetooth, no network, no writes. This is the iPhone-native port of
//  tools/scripts/analyze_gatt_log.py, so a full analysis can be produced in
//  the field with only the phone.
//
//  What it produces:
//   - a device-identity summary (manufacturer/model/firmware/serial from DIS),
//   - transport detection (Nordic UART Service),
//   - a list of write-capable characteristics (potential command channel,
//     level E in docs/10) — flagged, never exercised,
//   - findings with a plain-language severity note,
//   - a diff of two snapshots (e.g. before vs. during your own authorized rental).
//

import Foundation

// MARK: - Findings

enum FindingLevel: String, Codable {
    case info       // neutral observation
    case notable    // worth recording for the report
    case attention  // security-relevant surface (still not a proven vuln)
}

struct Finding: Identifiable, Codable {
    var id = UUID()
    let level: FindingLevel
    let title: String
    let detail: String
}

// MARK: - Device identity (from Device Information Service)

struct DeviceIdentity: Codable {
    var manufacturer: String?
    var model: String?
    var serial: String?
    var firmwareRevision: String?
    var hardwareRevision: String?
    var softwareRevision: String?

    var isEmpty: Bool {
        manufacturer == nil && model == nil && serial == nil &&
        firmwareRevision == nil && hardwareRevision == nil && softwareRevision == nil
    }
}

// MARK: - Analyzer

enum GATTAnalyzer {

    static func deviceIdentity(_ snap: GATTSnapshot) -> DeviceIdentity {
        var id = DeviceIdentity()
        for s in snap.services {
            for c in s.characteristics {
                let u = GATTCatalog.normalize(c.uuid)
                let value = c.decodedString
                switch u {
                case GATTCatalog.normalize("2A29"): id.manufacturer = value
                case GATTCatalog.normalize("2A24"): id.model = value
                case GATTCatalog.normalize("2A25"): id.serial = value
                case GATTCatalog.normalize("2A26"): id.firmwareRevision = value
                case GATTCatalog.normalize("2A27"): id.hardwareRevision = value
                case GATTCatalog.normalize("2A28"): id.softwareRevision = value
                default: break
                }
            }
        }
        return id
    }

    /// (serviceUUID, charUUID, properties) for every write-capable characteristic.
    static func writeCapable(_ snap: GATTSnapshot) -> [(service: String, char: String, props: [String])] {
        var out: [(String, String, [String])] = []
        for s in snap.services {
            for c in s.characteristics where !GATTCatalog.writeLikeProperties.isDisjoint(with: Set(c.properties)) {
                out.append((GATTCatalog.normalize(s.uuid), GATTCatalog.normalize(c.uuid), c.properties))
            }
        }
        return out
    }

    static func hasNinebotService(_ snap: GATTSnapshot) -> Bool {
        snap.services.contains { NinebotRef.isNinebotService($0.uuid) }
    }

    static func analyze(_ snap: GATTSnapshot) -> [Finding] {
        var findings: [Finding] = []

        let identity = deviceIdentity(snap)
        if !identity.isEmpty {
            var parts: [String] = []
            if let m = identity.manufacturer { parts.append("mfr=\(m)") }
            if let mo = identity.model { parts.append("model=\(mo)") }
            if let fw = identity.firmwareRevision { parts.append("fw=\(fw)") }
            if let hw = identity.hardwareRevision { parts.append("hw=\(hw)") }
            if let sw = identity.softwareRevision { parts.append("sw=\(sw)") }
            findings.append(Finding(level: .notable,
                title: "Device Information exposed",
                detail: parts.joined(separator: ", ") +
                        ". Maps this unit to a model + firmware version (docs/02, docs/16)."))
        }

        if hasNinebotService(snap) {
            findings.append(Finding(level: .notable,
                title: "Ninebot/Xiaomi transport service present",
                detail: "Matches a Ninebot transport (Nordic UART family A, or native Ninebot family B " +
                        "with UUID embedding \"ninebot\"). The …0002 write characteristic is the command " +
                        "channel — this tool records it but never writes to it."))
        }

        let writers = writeCapable(snap)
        if !writers.isEmpty {
            let nusRXwritable = writers.contains { NinebotRef.isCommandWriteChar($0.char) }
            let bullets = writers.map { w -> String in
                let known = GATTCatalog.name(for: w.char).map { " (\($0))" } ?? ""
                return "• \(w.char)\(known) [\(w.props.joined(separator: ", "))]"
            }.joined(separator: "\n")
            findings.append(Finding(
                level: nusRXwritable ? .attention : .info,
                title: "\(writers.count) write-capable characteristic(s)",
                detail: bullets + "\n\nPresence of a write channel is transport, not a vulnerability by " +
                        "itself. The security question (docs/08) is whether the device EXECUTES a privileged " +
                        "command here without a valid device-side rental session — do NOT test that on a " +
                        "production/rented unit."))
        }

        if findings.isEmpty {
            findings.append(Finding(level: .info, title: "No notable markers",
                detail: "No Device Information, no Nordic UART Service, no write-capable characteristics " +
                        "found in this snapshot. Either a non-Ninebot device or a restricted GATT surface."))
        }
        return findings
    }

    // MARK: Diff

    struct DiffEntry: Identifiable, Codable {
        var id = UUID()
        let service: String
        let onlyInA: [String]
        let onlyInB: [String]
    }

    /// Build "charUUID [props]" set per service for a snapshot.
    private static func surface(_ snap: GATTSnapshot) -> [String: Set<String>] {
        var m: [String: Set<String>] = [:]
        for s in snap.services {
            let key = GATTCatalog.normalize(s.uuid)
            var bucket = m[key] ?? []
            for c in s.characteristics {
                bucket.insert("\(GATTCatalog.normalize(c.uuid)) [\(c.properties.joined(separator: ","))]")
            }
            m[key] = bucket
        }
        return m
    }

    static func diff(_ a: GATTSnapshot, _ b: GATTSnapshot) -> [DiffEntry] {
        let sa = surface(a), sb = surface(b)
        let allServices = Set(sa.keys).union(sb.keys).sorted()
        var out: [DiffEntry] = []
        for svc in allServices {
            let aOnly = (sa[svc] ?? []).subtracting(sb[svc] ?? []).sorted()
            let bOnly = (sb[svc] ?? []).subtracting(sa[svc] ?? []).sorted()
            if !aOnly.isEmpty || !bOnly.isEmpty {
                out.append(DiffEntry(service: svc, onlyInA: aOnly, onlyInB: bOnly))
            }
        }
        return out
    }

    // MARK: Markdown report (for sharing / pasting into docs or a bug-bounty draft)

    static func markdownReport(for snap: GATTSnapshot, label: String) -> String {
        var out = "# GATT analysis — \(label)\n\n"
        out += "_Generated on-device, offline. No characteristic was ever written._\n\n"
        out += "- Device: \(snap.name ?? "(unknown)")\n"
        out += "- Captured: \(ISO8601DateFormatter().string(from: snap.timestamp))\n"
        out += "- Services: \(snap.services.count)\n\n"

        let identity = deviceIdentity(snap)
        if !identity.isEmpty {
            out += "## Device identity\n"
            if let v = identity.manufacturer { out += "- Manufacturer: \(v)\n" }
            if let v = identity.model { out += "- Model: \(v)\n" }
            if let v = identity.firmwareRevision { out += "- Firmware: \(v)\n" }
            if let v = identity.hardwareRevision { out += "- Hardware: \(v)\n" }
            if let v = identity.softwareRevision { out += "- Software: \(v)\n" }
            if let v = identity.serial { out += "- Serial: \(v)\n" }
            out += "\n"
        }

        out += "## Findings\n"
        for f in analyze(snap) {
            out += "- **[\(f.level.rawValue)] \(f.title)** — \(f.detail.replacingOccurrences(of: "\n", with: " "))\n"
        }
        out += "\n## Full GATT map\n"
        for s in snap.services {
            let sname = GATTCatalog.name(for: s.uuid).map { " (\($0))" } ?? ""
            out += "### Service \(GATTCatalog.normalize(s.uuid))\(sname)\n"
            for c in s.characteristics {
                let cname = GATTCatalog.name(for: c.uuid).map { " \($0)" } ?? ""
                let val = c.decodedString.map { " = \"\($0)\"" } ?? (c.valueHex.map { " = 0x\($0)" } ?? "")
                out += "- \(GATTCatalog.normalize(c.uuid))\(cname) [\(c.properties.joined(separator: ", "))]\(val)\n"
            }
            out += "\n"
        }
        return out
    }

    /// Richer report for a SAVED capture — includes state/note/advertising/presence context.
    static func markdownReport(for saved: SavedSnapshot) -> String {
        var out = markdownReport(for: saved.snapshot, label: saved.label)
        out += "## Capture context\n"
        out += "- Operator: \(saved.operatorTag ?? "—")\n"
        out += "- State: \(saved.state ?? "—")\n"
        if let n = saved.note { out += "- Note (confounders): \(n)\n" }
        if let st = saved.sighting {
            out += "- Presence: \(st.count) sightings, RSSI \(st.minRSSI)…\(st.maxRSSI)\n"
        }
        if let adv = saved.advertising {
            out += "- Advertised services: \(adv.serviceUUIDs.joined(separator: ", ").ifEmpty("—"))\n"
            if let p = GATTCatalog.parseManufacturerData(adv.manufacturerDataHex) {
                out += "- Mfg data: company 0x\(String(format: "%04x", p.companyID)) (\(p.label)), " +
                       "payload 0x\(p.payloadHex) (payload format UNCONFIRMED)\n"
            }
        }
        return out
    }

    static func markdownDiffReport(_ a: SavedSnapshot, _ b: SavedSnapshot) -> String {
        var out = "# GATT diff — \(a.label) (A) vs \(b.label) (B)\n\n"
        out += "_Offline comparison. Null hypothesis: rental state is NOT reflected in readable GATT " +
               "(docs/20.4). An identical surface is the EXPECTED result, not a failure._\n\n"

        // Capture context (confounders) — required for a valid diff (docs/15.5).
        out += "## Capture context\n"
        out += "- A: state=\(a.state ?? "?"), op=\(a.operatorTag ?? "?"), at=\(ISO8601DateFormatter().string(from: a.capturedAt))"
        out += (a.note.map { ", note=\($0)" } ?? "") + "\n"
        out += "- B: state=\(b.state ?? "?"), op=\(b.operatorTag ?? "?"), at=\(ISO8601DateFormatter().string(from: b.capturedAt))"
        out += (b.note.map { ", note=\($0)" } ?? "") + "\n\n"

        // GATT diff (structural).
        let entries = diff(a.snapshot, b.snapshot)
        let sharedServices = Set(surface(a.snapshot).keys).intersection(surface(b.snapshot).keys).count
        out += "## GATT surface\n"
        if entries.isEmpty {
            out += "**No change observed** across \(sharedServices) shared service(s): identical " +
                   "service/characteristic/property surface. (Expected under the null hypothesis.)\n\n"
        } else {
            out += "| Service | Only in A (\(a.label)) | Only in B (\(b.label)) |\n|---|---|---|\n"
            for e in entries {
                out += "| \(e.service) | \(e.onlyInA.joined(separator: "<br>").ifEmpty("—")) " +
                       "| \(e.onlyInB.joined(separator: "<br>").ifEmpty("—")) |\n"
            }
            out += "\nIf characteristics became reachable only AFTER an authorized rental started, that points " +
                   "to backend involvement in BLE availability, which would weaken the local-unlock hypothesis.\n\n"
        }

        // Advertising diff (state often lives here, not in GATT — docs/20.4).
        out += "## Advertising\n"
        out += advertisingDiff(a.advertising, b.advertising)

        // Presence (decisive Tuul test).
        out += "\n## Presence (BLE exposure)\n"
        out += "- A sightings: \(a.sighting.map { "\($0.count) (RSSI \($0.minRSSI)…\($0.maxRSSI))" } ?? "—")\n"
        out += "- B sightings: \(b.sighting.map { "\($0.count) (RSSI \($0.minRSSI)…\($0.maxRSSI))" } ?? "—")\n"
        return out
    }

    private static func advertisingDiff(_ a: AdvertisementRecord?, _ b: AdvertisementRecord?) -> String {
        guard let a = a, let b = b else { return "One or both captures lack advertising data.\n" }
        var out = ""
        let aServices = Set(a.serviceUUIDs.map { GATTCatalog.normalize($0) })
        let bServices = Set(b.serviceUUIDs.map { GATTCatalog.normalize($0) })
        let svcAOnly = aServices.subtracting(bServices).sorted()
        let svcBOnly = bServices.subtracting(aServices).sorted()
        if svcAOnly.isEmpty && svcBOnly.isEmpty {
            out += "- Advertised services: no change observed.\n"
        } else {
            out += "- Advertised services only in A: \(svcAOnly.joined(separator: ", ").ifEmpty("—"))\n"
            out += "- Advertised services only in B: \(svcBOnly.joined(separator: ", ").ifEmpty("—"))\n"
        }
        let am = GATTCatalog.parseManufacturerData(a.manufacturerDataHex)
        let bm = GATTCatalog.parseManufacturerData(b.manufacturerDataHex)
        func mfg(_ m: (companyID: Int, label: String, payloadHex: String)?) -> String {
            guard let m = m else { return "—" }
            return "company 0x\(String(format: "%04x", m.companyID)) (\(m.label)), payload 0x\(m.payloadHex)"
        }
        out += "- Mfg data A: \(mfg(am))\n- Mfg data B: \(mfg(bm))\n"
        if a.manufacturerDataHex == b.manufacturerDataHex {
            out += "- Manufacturer data: no change observed.\n"
        } else {
            out += "- **Manufacturer data CHANGED** between states — inspect payload above (format UNCONFIRMED).\n"
        }
        if a.name != b.name { out += "- Name changed: '\(a.name ?? "—")' → '\(b.name ?? "—")'\n" }
        return out
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
