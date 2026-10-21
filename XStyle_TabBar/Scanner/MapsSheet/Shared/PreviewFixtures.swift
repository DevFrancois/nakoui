//
//  PreviewFixtures.swift
//  MapsIOS26BottomSheet
//

#if DEBUG
import CoreGraphics
import Foundation

/// Fresh state for each canvas so preview controls never write to the app's saved preferences.
enum PreviewFixtures {
    static let canvas = PaneCanvas(
        size: CGSize(width: 393, height: 852),
        safeAreaTop: 59,
        safeAreaBottom: 34
    )

    static func makeSettings() -> SheetSettings {
        guard let defaults = UserDefaults(suiteName: "MapsIOS26BottomSheet.preview.\(UUID().uuidString)") else {
            preconditionFailure("Unable to create preview preferences")
        }
        return SheetSettings(defaults: defaults)
    }

    /// A history of its own, empty or with a few products scanned over the
    /// last days.
    static func makeHistory(seeded: Bool = false) -> ScanHistory {
        guard let defaults = UserDefaults(suiteName: "ScanHistory.preview.\(UUID().uuidString)") else {
            preconditionFailure("Unable to create preview preferences")
        }
        let history = ScanHistory(defaults: defaults)
        if seeded {
            let codes = [
                ScannedCode(value: "4006381333931", symbology: .ean13),
                ScannedCode(value: "036000291452", symbology: .upcA),
                ScannedCode(value: "96385074", symbology: .ean8),
                ScannedCode(value: "4006381333931", symbology: .ean13),
            ]
            for (index, code) in codes.enumerated() {
                history.record(code, at: .now.addingTimeInterval(Double(index - codes.count) * 86_400))
            }
            history.revealButton()
        }
        return history
    }

    static func makeSheet(detent: SheetDetent) -> SheetController {
        let sheet = SheetController(initialDetent: detent)
        sheet.updateCanvas(canvas)
        return sheet
    }
}
#endif
