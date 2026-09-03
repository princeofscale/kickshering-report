//
//  SnapshotStore.swift
//  BLEInspector
//
//  Persists captured GATT snapshots on the phone so a "before rental" and a
//  "during rental" capture can be compared later, entirely offline. Stored as
//  JSON files in the app's Documents directory. No network, no writes to any
//  BLE device.
//

import Foundation

struct SavedSnapshot: Identifiable, Codable {
    var id = UUID()
    var label: String            // e.g. "Whoosh #A12 pre-rental"
    var operatorTag: String?     // "Whoosh" / "Urent" / "own device"
    var state: String?           // "pre-rental" / "during-rental" / "control-A" / "control-B"
    var note: String?            // confounders: phone/OS/app version/battery/location/time
    var capturedAt: Date
    var snapshot: GATTSnapshot
    var advertising: AdvertisementRecord?   // ADV captured alongside GATT (state often lives here)
    var sighting: SightingStats?            // presence stats at capture time
}

final class SnapshotStore: ObservableObject {
    @Published private(set) var items: [SavedSnapshot] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("ble_snapshots.json")
    }()

    init() { load() }

    func save(_ snap: GATTSnapshot, label: String, operatorTag: String?,
              state: String? = nil, note: String? = nil,
              advertising: AdvertisementRecord? = nil, sighting: SightingStats? = nil) {
        let item = SavedSnapshot(label: label, operatorTag: operatorTag, state: state, note: note,
                                 capturedAt: Date(), snapshot: snap,
                                 advertising: advertising, sighting: sighting)
        items.insert(item, at: 0)
        persist()
    }

    func delete(_ item: SavedSnapshot) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func deleteAll() {
        items.removeAll()
        persist()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([SavedSnapshot].self, from: data) {
            items = decoded
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Combined JSON export of every saved snapshot, for AirDrop/Files off the phone.
    func exportAllJSON() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items), let s = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return s
    }
}
