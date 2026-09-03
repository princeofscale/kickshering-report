//
//  BLEInspectorApp.swift
//  BLEInspector — passive, read-only BLE research tool.
//
//  Part of the kickshering-report security research repository.
//  This app NEVER writes to a BLE characteristic. It only listens to
//  advertising packets and reads characteristics that advertise the
//  "read" property. See ../../README.md and ../../../docs/00-scope-and-methodology.md
//  for the safety rules that govern how this tool may be used.
//

import SwiftUI

@main
struct BLEInspectorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
