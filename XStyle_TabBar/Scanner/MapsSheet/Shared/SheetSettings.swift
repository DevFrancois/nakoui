//
//  SheetSettings.swift
//  MapsIOS26BottomSheet
//

import Foundation
import Observation

/// Debug settings shown inside the sheet, persisted across launches.
@Observable
final class SheetSettings {
    // MARK: Motion, to compare what makes the pane move

    /// How the pane makes way for the rising sheet.
    var viewportMode: ViewportMode {
        didSet {
            defaults.set(viewportMode.rawValue, forKey: Key.viewportMode)
        }
    }

    /// The pane stretches with the sheet's speed; off, it only follows the sheet's position.
    var paneStretch: Bool {
        didSet {
            defaults.set(paneStretch, forKey: Key.paneStretch)
        }
    }

    /// Critically damped stretch that follows a filtered speed and ignores touch moves without movement.
    var smoothStretch: Bool {
        didSet {
            defaults.set(smoothStretch, forKey: Key.smoothStretch)
        }
    }

    /// The stretch narrows the pane by up to `PaneTuning.maxSquash`.
    var paneSquash: Bool {
        didSet {
            defaults.set(paneSquash, forKey: Key.paneSquash)
        }
    }

    /// The sheet settles with the bouncy spring; off, with a critically damped one.
    var sheetBounce: Bool {
        didSet {
            defaults.set(sheetBounce, forKey: Key.sheetBounce)
        }
    }

    /// The pane follows the sheet past the detent while it bounces; off, it waits at the detent.
    var paneFollowsBounce: Bool {
        didSet {
            defaults.set(paneFollowsBounce, forKey: Key.paneFollowsBounce)
        }
    }

    // MARK: Scanning

    /// The camera keeps scanning while a result shows, another code replacing it; off, it scans again once the
    /// result is dismissed.
    var scansWithResultOpen: Bool {
        didSet {
            defaults.set(scansWithResultOpen, forKey: Key.scansWithResultOpen)
        }
    }

    /// How a found code is shown in the camera.
    var revealStyle: ScanRevealStyle {
        didSet {
            defaults.set(revealStyle.rawValue, forKey: Key.revealStyle)
        }
    }

    /// The full reveal blurs the frozen camera frame behind the found code; off, the frame stays sharp.
    var revealBlur: Bool {
        didSet {
            defaults.set(revealBlur, forKey: Key.revealBlur)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        viewportMode = defaults.string(forKey: Key.viewportMode).flatMap(ViewportMode.init(rawValue:)) ?? .fixed
        paneStretch = Self.bool(Key.paneStretch, in: defaults) ?? false
        smoothStretch = Self.bool(Key.smoothStretch, in: defaults) ?? true
        paneSquash = Self.bool(Key.paneSquash, in: defaults) ?? false
        sheetBounce = Self.bool(Key.sheetBounce, in: defaults) ?? true
        paneFollowsBounce = Self.bool(Key.paneFollowsBounce, in: defaults) ?? true
        scansWithResultOpen = Self.bool(Key.scansWithResultOpen, in: defaults) ?? true
        revealStyle = defaults.string(forKey: Key.revealStyle).flatMap(ScanRevealStyle.init(rawValue:)) ?? .standard
        revealBlur = Self.bool(Key.revealBlur, in: defaults) ?? true
        /// Settings that are now fixed: forget what earlier builds stored.
        for key in Self.retiredKeys {
            defaults.removeObject(forKey: key)
        }
    }

    /// `bool(forKey:)` also reads `-key YES` launch arguments, which arrive as strings.
    private static func bool(_ key: String, in defaults: UserDefaults) -> Bool? {
        defaults.object(forKey: key) == nil ? nil : defaults.bool(forKey: key)
    }

    private enum Key {
        static let viewportMode = "sheet.viewportMode"
        static let paneStretch = "sheet.paneStretch"
        static let smoothStretch = "sheet.smoothStretch"
        static let paneSquash = "sheet.paneSquash"
        static let sheetBounce = "sheet.sheetBounce"
        static let paneFollowsBounce = "sheet.paneFollowsBounce"
        static let scansWithResultOpen = "sheet.scansWithResultOpen"
        static let revealStyle = "sheet.revealStyle"
        static let revealBlur = "sheet.revealBlur"
    }

    private static let retiredKeys = [
        "sheet.feel",
        "sheet.snapRule",
        "sheet.haptics",
        "sheet.rubberBand",
        "sheet.tapPaneToCollapse",
        "sheet.paneEffect",
        "sheet.paneDeformation",
        "sheet.fixedViewport",
    ]
}
