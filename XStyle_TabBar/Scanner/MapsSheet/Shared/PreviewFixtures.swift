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

    static func makeSheet(detent: SheetDetent) -> SheetController {
        let sheet = SheetController(initialDetent: detent)
        sheet.updateCanvas(canvas)
        return sheet
    }
}
#endif
