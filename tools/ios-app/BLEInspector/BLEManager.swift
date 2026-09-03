//
//  BLEManager.swift
//  BLEInspector
//
//  All CoreBluetooth logic lives here. READ-ONLY BY DESIGN:
//  this file contains no call to peripheral.writeValue(_:for:type:)
//  anywhere. If you are reviewing this code before running it against
//  your own device (as you should), that absence is the safety
//  property to verify.
//
//  Usage boundaries (see ../../README.md for the full rules):
//   - Passive scanning (startScan/stopScan) is safe near any device,
//     including ones you do not own — it only listens to advertising.
//   - connectAndEnumerate() performs a real GATT connection and should
//     only be used against a device you own, or during your own,
//     currently active, paid rental session.
//

import Foundation
import CoreBluetooth

// MARK: - Data models (Codable for JSON export)

struct AdvertisementRecord: Codable {
    let peripheralID: String
    let name: String?
    let rssi: Int
    let timestamp: Date
    let serviceUUIDs: [String]
    let manufacturerDataHex: String?
    let isConnectable: Bool?
}

struct CharacteristicRecord: Codable {
    let uuid: String
    let properties: [String]
    let isReadable: Bool
    var valueHex: String?
    var readError: String?
}

struct ServiceRecord: Codable {
    let uuid: String
    var characteristics: [CharacteristicRecord]
}

struct GATTSnapshot: Codable {
    let peripheralID: String
    let name: String?
    let timestamp: Date
    var services: [ServiceRecord]
}

struct ExportPayload: Codable {
    let advertisements: [AdvertisementRecord]
    let gattSnapshots: [GATTSnapshot]
    let exportedAt: Date
    let toolNote: String = "Read-only research tool. No write operations were ever issued to any characteristic."
}

// MARK: - BLEManager

final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    @Published var isScanning = false
    @Published var discovered: [String: AdvertisementRecord] = [:]   // keyed by peripheral identifier string
    @Published var log: [String] = []
    @Published var snapshots: [String: GATTSnapshot] = [:]           // keyed by peripheral identifier string
    @Published var bluetoothState: String = "unknown"

    private var central: CBCentralManager!
    private var peripherals: [String: CBPeripheral] = [:]
    private var servicesSeenCount: [String: Int] = [:]   // per-peripheral count of services fully processed
    private var expectedServiceCount: [String: Int] = [:]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: Scanning (passive, safe anywhere)

    func startScan() {
        guard central.state == .poweredOn else {
            appendLog("Bluetooth not powered on (state: \(stateDescription(central.state)))")
            return
        }
        isScanning = true
        appendLog("Passive scan started. No connections, no writes — advertising observation only.")
        central.scanForPeripherals(withServices: nil,
                                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
        appendLog("Scan stopped.")
    }

    // MARK: Connect + enumerate (READ-ONLY; only use on your own / your active rental)

    func connectAndEnumerate(peripheralID: String) {
        guard let p = peripherals[peripheralID] else {
            appendLog("Unknown peripheral \(peripheralID)")
            return
        }
        appendLog("Connecting to \(p.name ?? peripheralID) for READ-ONLY service discovery. " +
                   "Only proceed if this is your own device or your own active rental.")
        p.delegate = self
        central.connect(p, options: nil)
    }

    func disconnect(peripheralID: String) {
        guard let p = peripherals[peripheralID] else { return }
        central.cancelPeripheralConnection(p)
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = stateDescription(central.state)
        appendLog("Bluetooth state: \(bluetoothState)")
    }

    func centralManager(_ central: CBCentralManager,
                         didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any],
                         rssi RSSI: NSNumber) {
        let id = peripheral.identifier.uuidString
        peripherals[id] = peripheral

        let svcUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
            .map { $0.uuidString } ?? []
        let mfgHex = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?
            .map { String(format: "%02x", $0) }.joined()
        let connectable = advertisementData[CBAdvertisementDataIsConnectable] as? Bool
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String

        let record = AdvertisementRecord(
            peripheralID: id,
            name: peripheral.name ?? localName,
            rssi: RSSI.intValue,
            timestamp: Date(),
            serviceUUIDs: svcUUIDs,
            manufacturerDataHex: mfgHex,
            isConnectable: connectable
        )
        DispatchQueue.main.async {
            self.discovered[id] = record
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        appendLog("Connected to \(peripheral.name ?? peripheral.identifier.uuidString). Discovering services (read-only)...")
        let id = peripheral.identifier.uuidString
        snapshots[id] = GATTSnapshot(peripheralID: id, name: peripheral.name, timestamp: Date(), services: [])
        servicesSeenCount[id] = 0
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        appendLog("Failed to connect to \(peripheral.name ?? peripheral.identifier.uuidString): " +
                   "\(error?.localizedDescription ?? "unknown error")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        appendLog("Disconnected from \(peripheral.name ?? peripheral.identifier.uuidString).")
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            appendLog("Service discovery error: \(error.localizedDescription)")
            return
        }
        let services = peripheral.services ?? []
        expectedServiceCount[peripheral.identifier.uuidString] = services.count
        appendLog("Discovered \(services.count) service(s) on \(peripheral.name ?? "device").")
        if services.isEmpty {
            finalizeSnapshotIfComplete(peripheral: peripheral)
        }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let id = peripheral.identifier.uuidString
        if let error = error {
            appendLog("Characteristic discovery error for service \(service.uuid): \(error.localizedDescription)")
            servicesSeenCount[id, default: 0] += 1
            finalizeSnapshotIfComplete(peripheral: peripheral)
            return
        }

        var chars: [CharacteristicRecord] = []
        var readableCount = 0
        for c in service.characteristics ?? [] {
            let props = propertyNames(c.properties)
            let isReadable = c.properties.contains(.read)
            chars.append(CharacteristicRecord(uuid: c.uuid.uuidString, properties: props,
                                                isReadable: isReadable, valueHex: nil, readError: nil))
            if isReadable {
                readableCount += 1
                // SAFE: only characteristics that advertise .read are ever touched, and
                // only via readValue — there is no writeValue call anywhere in this file.
                peripheral.readValue(for: c)
            }
        }

        appendLog("Service \(service.uuid): \(chars.count) characteristic(s), \(readableCount) readable. " +
                   "Properties logged for all; only readable ones will be read.")

        upsertServiceRecord(peripheralID: id, serviceUUID: service.uuid.uuidString, characteristics: chars)

        if readableCount == 0 {
            servicesSeenCount[id, default: 0] += 1
            finalizeSnapshotIfComplete(peripheral: peripheral)
        }
        // If there ARE readable characteristics, finalization happens after the last
        // didUpdateValueFor callback for this service (see below), to make sure reads
        // land in the snapshot before we consider it complete.
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let id = peripheral.identifier.uuidString
        guard let serviceUUID = characteristic.service?.uuid.uuidString else { return }

        if let error = error {
            appendLog("Read error \(characteristic.uuid): \(error.localizedDescription)")
            updateCharacteristic(peripheralID: id, serviceUUID: serviceUUID, charUUID: characteristic.uuid.uuidString) { rec in
                rec.readError = error.localizedDescription
            }
        } else if let data = characteristic.value {
            let hex = data.map { String(format: "%02x", $0) }.joined()
            appendLog("Read \(characteristic.uuid): 0x\(hex) (\(data.count) bytes)")
            updateCharacteristic(peripheralID: id, serviceUUID: serviceUUID, charUUID: characteristic.uuid.uuidString) { rec in
                rec.valueHex = hex
            }
        }

        maybeFinalizeAfterRead(peripheral: peripheral, serviceUUID: serviceUUID)
    }

    // MARK: Snapshot bookkeeping helpers

    private func upsertServiceRecord(peripheralID: String, serviceUUID: String, characteristics: [CharacteristicRecord]) {
        DispatchQueue.main.async {
            guard var snap = self.snapshots[peripheralID] else { return }
            if let idx = snap.services.firstIndex(where: { $0.uuid == serviceUUID }) {
                snap.services[idx].characteristics = characteristics
            } else {
                snap.services.append(ServiceRecord(uuid: serviceUUID, characteristics: characteristics))
            }
            self.snapshots[peripheralID] = snap
        }
    }

    private func updateCharacteristic(peripheralID: String, serviceUUID: String, charUUID: String,
                                       mutate: (inout CharacteristicRecord) -> Void) {
        DispatchQueue.main.async {
            guard var snap = self.snapshots[peripheralID],
                  let sIdx = snap.services.firstIndex(where: { $0.uuid == serviceUUID }),
                  let cIdx = snap.services[sIdx].characteristics.firstIndex(where: { $0.uuid == charUUID }) else { return }
            mutate(&snap.services[sIdx].characteristics[cIdx])
            self.snapshots[peripheralID] = snap
        }
    }

    private var pendingReadsPerService: [String: Int] = [:]  // "peripheralID|serviceUUID" -> remaining reads

    private func maybeFinalizeAfterRead(peripheral: CBPeripheral, serviceUUID: String) {
        // Best-effort completion tracking: once every service has reported in
        // (didDiscoverCharacteristicsFor, with or without reads), we mark the
        // peripheral's snapshot complete. This is a research tool, not a
        // hard real-time guarantee — always eyeball the exported JSON.
        let id = peripheral.identifier.uuidString
        servicesSeenCount[id, default: 0] += 1
        finalizeSnapshotIfComplete(peripheral: peripheral)
    }

    private func finalizeSnapshotIfComplete(peripheral: CBPeripheral) {
        let id = peripheral.identifier.uuidString
        guard let expected = expectedServiceCount[id] else { return }
        if servicesSeenCount[id, default: 0] >= expected {
            appendLog("GATT enumeration complete for \(peripheral.name ?? id).")
        }
    }

    // MARK: Export

    func exportJSON() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = ExportPayload(
            advertisements: Array(discovered.values),
            gattSnapshots: Array(snapshots.values),
            exportedAt: Date()
        )
        guard let data = try? encoder.encode(payload), let str = String(data: data, encoding: .utf8) else {
            return "{\"error\": \"encoding failed\"}"
        }
        return str
    }

    // MARK: Helpers

    private func propertyNames(_ props: CBCharacteristicProperties) -> [String] {
        var names: [String] = []
        if props.contains(.read) { names.append("read") }
        if props.contains(.write) { names.append("write") }
        if props.contains(.writeWithoutResponse) { names.append("writeWithoutResponse") }
        if props.contains(.notify) { names.append("notify") }
        if props.contains(.indicate) { names.append("indicate") }
        if props.contains(.broadcast) { names.append("broadcast") }
        if props.contains(.authenticatedSignedWrites) { names.append("authenticatedSignedWrites") }
        return names
    }

    private func stateDescription(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: return "poweredOn"
        case .poweredOff: return "poweredOff"
        case .resetting: return "resetting"
        case .unauthorized: return "unauthorized"
        case .unsupported: return "unsupported"
        case .unknown: return "unknown"
        @unknown default: return "unknown"
        }
    }

    private func appendLog(_ s: String) {
        DispatchQueue.main.async {
            self.log.append("[\(ISO8601DateFormatter().string(from: Date()))] \(s)")
        }
    }
}
