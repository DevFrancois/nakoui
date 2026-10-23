//
//  XStyle_TabBarApp.swift
//  XStyle_TabBar
//
//  Created by Francois Chaillou on 28/07/26.
//

import SwiftUI
import TipKit

@main
struct XStyle_TabBarApp: App {
    /// One entrance across windows, reset only when the app process launches.
    @State private var scannerEntranceSession = ScannerViewportEntranceSession()

    init() {
        // Before any tip shows. To see tips afresh, launch with
        // `-com.apple.TipKit.ResetDatastore 1`.
        try? Tips.configure([.displayFrequency(.immediate)])
    }

    var body: some Scene {
        WindowGroup {
            ContentView(scannerEntranceSession: scannerEntranceSession)
        }
    }
}
