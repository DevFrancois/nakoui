//
//  SheetSettings.swift
//  MapsIOS26BottomSheet
//

import Foundation
import Observation

/// Debug settings shown inside the sheet, persisted across launches.
@Observable
final class SheetSettings {
    var paneEffect: PaneEffect {
        didSet {
            defaults.set(paneEffect.rawValue, forKey: Self.paneEffectKey)
        }
    }

    // MARK: Motion, to compare what makes the pane move

    /// The pane deforms with the sheet's speed; off, it only follows the sheet's position.
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

    /// The stretch bends the collapse: width, corner timing and funnel pinch in `PaneDisappearModifier`.
    var paneDeformation: Bool {
        didSet {
            defaults.set(paneDeformation, forKey: Key.paneDeformation)
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

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        paneEffect = defaults.string(forKey: Self.paneEffectKey).flatMap(PaneEffect.init(rawValue:)) ?? .standard
        paneStretch = Self.bool(Key.paneStretch, in: defaults) ?? false
        smoothStretch = Self.bool(Key.smoothStretch, in: defaults) ?? true
        paneSquash = Self.bool(Key.paneSquash, in: defaults) ?? false
        paneDeformation = Self.bool(Key.paneDeformation, in: defaults) ?? false
        sheetBounce = Self.bool(Key.sheetBounce, in: defaults) ?? true
        paneFollowsBounce = Self.bool(Key.paneFollowsBounce, in: defaults) ?? true
        /// Settings that are now fixed: forget what earlier builds stored.
        for key in Self.retiredKeys {
            defaults.removeObject(forKey: key)
        }
    }

    /// `bool(forKey:)` also reads `-key YES` launch arguments, which arrive as strings.
    private static func bool(_ key: String, in defaults: UserDefaults) -> Bool? {
        defaults.object(forKey: key) == nil ? nil : defaults.bool(forKey: key)
    }

    private static let paneEffectKey = "sheet.paneEffect"

    private enum Key {
        static let paneStretch = "sheet.paneStretch"
        static let smoothStretch = "sheet.smoothStretch"
        static let paneSquash = "sheet.paneSquash"
        static let paneDeformation = "sheet.paneDeformation"
        static let sheetBounce = "sheet.sheetBounce"
        static let paneFollowsBounce = "sheet.paneFollowsBounce"
    }

    private static let retiredKeys = [
        "sheet.feel",
        "sheet.snapRule",
        "sheet.haptics",
        "sheet.rubberBand",
        "sheet.tapPaneToCollapse",
    ]
}
