//
//  ContentView.swift
//  BLEInspector
//
//  UI only. All BLE logic lives in BLEManager.swift (read-only by design).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @StateObject private var ble = BLEManager()
    @State private var showShareSheet = false
    @State private var exportText = ""

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Read-only BLE research tool. Never sends unlock/control/write commands.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                Text("Bluetooth: \(ble.bluetoothState)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                HStack {
                    Button(ble.isScanning ? "Stop Scan" : "Start Scan") {
                        if ble.isScanning { ble.stopScan() } else { ble.startScan() }
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Button("Export Log") {
                        exportText = ble.exportJSON()
                        showShareSheet = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)

                List {
                    Section("Discovered devices (\(ble.discovered.count)) — tap to connect & enumerate (read-only)") {
                        ForEach(Array(ble.discovered.values.sorted(by: { $0.rssi > $1.rssi })), id: \.peripheralID) { record in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(record.name ?? "Unnamed device").bold()
                                    if record.likelyNinebotFamily != nil || record.advertisesNordicUART {
                                        Text("Ninebot/Xiaomi?")
                                            .font(.caption2)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color.orange.opacity(0.25))
                                            .cornerRadius(4)
                                    }
                                }
                                if let fam = record.likelyNinebotFamily {
                                    Text(fam).font(.caption2).foregroundColor(.orange)
                                }
                                Text("RSSI: \(record.rssi)   ID: \(String(record.peripheralID.prefix(8)))…")
                                    .font(.caption2)
                                if !record.serviceUUIDs.isEmpty {
                                    Text("Advertised services: \(record.serviceUUIDs.joined(separator: ", "))")
                                        .font(.caption2)
                                }
                                if let mfg = record.manufacturerDataHex {
                                    Text("Manufacturer data: 0x\(mfg)")
                                        .font(.caption2)
                                }
                                if let snap = ble.snapshots[record.peripheralID] {
                                    Text("GATT: \(snap.services.count) service(s) enumerated")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                ble.connectAndEnumerate(peripheralID: record.peripheralID)
                            }
                        }
                    }

                    Section("Log") {
                        ForEach(Array(ble.log.suffix(80).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("BLE Inspector")
        }
        .sheet(isPresented: $showShareSheet) {
            #if canImport(UIKit)
            ActivityView(text: exportText)
            #endif
        }
    }
}

#if canImport(UIKit)
struct ActivityView: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Export as a temp file so the share sheet offers "Save to Files" with a .json name.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ble-inspector-log-\(Int(Date().timeIntervalSince1970)).json")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
