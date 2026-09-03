//
//  ContentView.swift
//  BLEInspector
//
//  UI only. BLE logic is in BLEManager.swift (read-only by design); the
//  offline analyzers are in GATTAnalyzer.swift; on-device persistence is in
//  SnapshotStore.swift. Nothing here writes to a BLE characteristic.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @StateObject private var ble = BLEManager()
    @StateObject private var store = SnapshotStore()

    var body: some View {
        TabView {
            ScanView(ble: ble, store: store)
                .tabItem { Label("Scan", systemImage: "dot.radiowaves.left.and.right") }
            SavedView(store: store)
                .tabItem { Label("Saved", systemImage: "tray.full") }
            DiffView(store: store)
                .tabItem { Label("Diff", systemImage: "arrow.left.arrow.right") }
        }
    }
}

// MARK: - Scan

struct ScanView: View {
    @ObservedObject var ble: BLEManager
    @ObservedObject var store: SnapshotStore
    @State private var selected: AdvertisementRecord?
    @State private var showShare = false
    @State private var exportText = ""

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Read-only tool. Passive scan is safe anywhere. Connect ONLY to your own device or your own active paid rental.")
                    .font(.caption).foregroundColor(.secondary).padding(.horizontal)
                Text("Bluetooth: \(ble.bluetoothState)").font(.caption2).foregroundColor(.secondary).padding(.horizontal)

                HStack {
                    Button(ble.isScanning ? "Stop Scan" : "Start Scan") {
                        ble.isScanning ? ble.stopScan() : ble.startScan()
                    }.buttonStyle(.borderedProminent)
                    Spacer()
                    Button("Export raw") {
                        exportText = ble.exportJSON(); showShare = true
                    }.buttonStyle(.bordered)
                }.padding(.horizontal)

                List {
                    Section("Devices (\(ble.discovered.count)) — tap to inspect") {
                        ForEach(sortedDevices, id: \.peripheralID) { rec in
                            Button { selected = rec } label: { deviceRow(rec) }
                        }
                    }
                }.listStyle(.plain)
            }
            .navigationTitle("BLE Inspector")
            .sheet(item: $selected) { rec in
                DeviceDetailView(ble: ble, store: store, record: rec)
            }
            .sheet(isPresented: $showShare) {
                #if canImport(UIKit)
                ActivityView(text: exportText, filename: "ble-raw-\(Int(Date().timeIntervalSince1970)).json")
                #endif
            }
        }
    }

    private var sortedDevices: [AdvertisementRecord] {
        ble.discovered.values.sorted {
            let la = ($0.likelyNinebotFamily != nil || $0.advertisesNinebotService) ? 1 : 0
            let lb = ($1.likelyNinebotFamily != nil || $1.advertisesNinebotService) ? 1 : 0
            if la != lb { return la > lb }         // likely-Ninebot first
            return $0.rssi > $1.rssi                // then strongest signal
        }
    }

    @ViewBuilder private func deviceRow(_ rec: AdvertisementRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(rec.name ?? "Unnamed device").bold()
                if rec.likelyNinebotFamily != nil || rec.advertisesNinebotService {
                    Text("Ninebot/Xiaomi?").font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.orange.opacity(0.25)).cornerRadius(4)
                }
            }
            if let fam = rec.likelyNinebotFamily { Text(fam).font(.caption2).foregroundColor(.orange) }
            Text("RSSI \(rec.rssi)   ID \(String(rec.peripheralID.prefix(8)))…").font(.caption2)
            if rec.advertisesNinebotService { Text("Advertises Ninebot service").font(.caption2).foregroundColor(.secondary) }
        }
    }
}

// MARK: - Device detail + on-device analysis

struct DeviceDetailView: View {
    @ObservedObject var ble: BLEManager
    @ObservedObject var store: SnapshotStore
    let record: AdvertisementRecord

    @Environment(\.dismiss) private var dismiss
    @State private var confirmConnect = false
    @State private var label = ""
    @State private var operatorTag = "Whoosh"
    @State private var savedConfirmation = false

    private var snapshot: GATTSnapshot? { ble.snapshot(for: record.peripheralID) }

    var body: some View {
        NavigationView {
            List {
                Section("Advertising") {
                    row("Name", record.name ?? "—")
                    row("RSSI", "\(record.rssi)")
                    row("Family", record.likelyNinebotFamily ?? "not matched")
                    row("Ninebot service advertised", record.advertisesNinebotService ? "yes" : "no")
                    if let mfg = record.manufacturerDataHex { row("Mfg data", "0x\(mfg)") }
                }

                Section("Read-only GATT analysis") {
                    if snapshot == nil {
                        Text("Not connected yet.").foregroundColor(.secondary)
                        Button("Connect & analyze (read-only)") { confirmConnect = true }
                            .buttonStyle(.borderedProminent)
                    } else {
                        analysisContent(snapshot!)
                    }
                }

                if let snap = snapshot {
                    Section("Save this capture (for before/after diff)") {
                        TextField("Label (e.g. 'Whoosh A12 pre-rental')", text: $label)
                        Picker("Operator", selection: $operatorTag) {
                            Text("Whoosh").tag("Whoosh")
                            Text("Urent").tag("Urent")
                            Text("Own device").tag("own device")
                            Text("Other").tag("other")
                        }
                        Button("Save snapshot") {
                            store.save(snap, label: label.isEmpty ? (record.name ?? "capture") : label,
                                       operatorTag: operatorTag)
                            savedConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(record.name ?? "Device")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .alert("Confirm you're authorized", isPresented: $confirmConnect) {
                Button("I own this / it's my active rental", role: .none) {
                    ble.connectAndEnumerate(peripheralID: record.peripheralID)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Connecting performs a real GATT connection. Only proceed for a device you own, or one you are renting right now under your own paid account. Never for a parked scooter you have not rented.")
            }
            .alert("Saved", isPresented: $savedConfirmation) {
                Button("OK", role: .cancel) {}
            } message: { Text("Snapshot saved on this phone. See the Saved tab; diff two captures in the Diff tab.") }
        }
    }

    @ViewBuilder private func analysisContent(_ snap: GATTSnapshot) -> some View {
        let identity = GATTAnalyzer.deviceIdentity(snap)
        if !identity.isEmpty {
            if let v = identity.manufacturer { row("Manufacturer", v) }
            if let v = identity.model { row("Model", v) }
            if let v = identity.firmwareRevision { row("Firmware", v) }
            if let v = identity.hardwareRevision { row("Hardware", v) }
            if let v = identity.softwareRevision { row("Software", v) }
            if let v = identity.serial { row("Serial", v) }
        }
        ForEach(GATTAnalyzer.analyze(snap)) { f in
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(f.level.rawValue.uppercased()).font(.caption2).bold()
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(color(for: f.level).opacity(0.25)).cornerRadius(4)
                    Text(f.title).font(.subheadline).bold()
                }
                Text(f.detail).font(.caption).foregroundColor(.secondary)
            }.padding(.vertical, 2)
        }
        NavigationLink("Full GATT map & report") { ReportView(markdown: GATTAnalyzer.markdownReport(for: snap, label: record.name ?? "device")) }
    }

    private func color(for level: FindingLevel) -> Color {
        switch level {
        case .info: return .secondary
        case .notable: return .blue
        case .attention: return .orange
        }
    }

    @ViewBuilder private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundColor(.secondary); Spacer(); Text(v).multilineTextAlignment(.trailing) }
            .font(.callout)
    }
}

// MARK: - Saved snapshots

struct SavedView: View {
    @ObservedObject var store: SnapshotStore
    @State private var showShare = false
    @State private var exportText = ""

    var body: some View {
        NavigationView {
            List {
                if store.items.isEmpty {
                    Text("No saved captures yet. Capture from the Scan tab.").foregroundColor(.secondary)
                }
                ForEach(store.items) { item in
                    NavigationLink {
                        ReportView(markdown: GATTAnalyzer.markdownReport(for: item.snapshot, label: item.label))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label).bold()
                            Text("\(item.operatorTag ?? "—") · \(item.snapshot.services.count) services · \(DateFormatter.short.string(from: item.capturedAt))")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { idx in idx.map { store.items[$0] }.forEach(store.delete) }
            }
            .navigationTitle("Saved (\(store.items.count))")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Export all") { exportText = store.exportAllJSON(); showShare = true }
                        .disabled(store.items.isEmpty)
                }
            }
            .sheet(isPresented: $showShare) {
                #if canImport(UIKit)
                ActivityView(text: exportText, filename: "ble-snapshots-\(Int(Date().timeIntervalSince1970)).json")
                #endif
            }
        }
    }
}

// MARK: - Diff two saved snapshots

struct DiffView: View {
    @ObservedObject var store: SnapshotStore
    @State private var aID: UUID?
    @State private var bID: UUID?

    private var a: SavedSnapshot? { store.items.first { $0.id == aID } }
    private var b: SavedSnapshot? { store.items.first { $0.id == bID } }

    var body: some View {
        NavigationView {
            Form {
                Section("Pick two captures (e.g. pre-rental vs during-rental)") {
                    picker("A (before)", selection: $aID)
                    picker("B (after)", selection: $bID)
                }
                if let a = a, let b = b {
                    Section {
                        NavigationLink("Show diff report") {
                            ReportView(markdown: GATTAnalyzer.markdownDiffReport(a, b))
                        }
                    }
                } else {
                    Text("Select two different captures to compare.").foregroundColor(.secondary)
                }
            }
            .navigationTitle("Diff")
        }
    }

    @ViewBuilder private func picker(_ title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            Text("—").tag(UUID?.none)
            ForEach(store.items) { item in
                Text(item.label).tag(UUID?.some(item.id))
            }
        }
    }
}

// MARK: - Report viewer

struct ReportView: View {
    let markdown: String
    @State private var showShare = false

    var body: some View {
        ScrollView {
            Text(markdown).font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .navigationTitle("Report")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("Share") { showShare = true } } }
        .sheet(isPresented: $showShare) {
            #if canImport(UIKit)
            ActivityView(text: markdown, filename: "ble-report-\(Int(Date().timeIntervalSince1970)).md")
            #endif
        }
    }
}

// MARK: - Share sheet

#if canImport(UIKit)
struct ActivityView: UIViewControllerRepresentable {
    let text: String
    var filename: String = "ble-export.txt"
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif

private extension DateFormatter {
    static let short: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f
    }()
}
