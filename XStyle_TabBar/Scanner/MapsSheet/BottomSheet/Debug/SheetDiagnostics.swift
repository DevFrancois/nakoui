//
//  SheetDiagnostics.swift
//  MapsIOS26BottomSheet
//

import Foundation
import QuartzCore

/// Gesture tracing for the sheet. Enable with the launch argument `-SheetTrace YES` (DEBUG builds only).
enum SheetTrace {
    #if DEBUG
    static let isEnabled = UserDefaults.standard.bool(forKey: "SheetTrace")
    #else
    static let isEnabled = false
    #endif

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard isEnabled else { return }
        print("[Sheet] \(String(format: "%.4f", CACurrentMediaTime())) \(message())")
        #endif
    }
}
