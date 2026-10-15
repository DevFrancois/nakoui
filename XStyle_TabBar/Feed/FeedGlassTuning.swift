import SwiftUI

/// Debug dials for the glass on the For you page's What's New card and
/// tiles, stored so they survive relaunches. At their defaults the glass is
/// unchanged.
enum FeedGlassTuning {
    static let materialKey = "feedGlass.material"
    static let strengthKey = "feedGlass.strength"
    static let whiteFillKey = "feedGlass.whiteFill"

    static let defaultMaterial = Material.regular
    /// How opaque the glass layer is, from gone to full.
    static let defaultStrength = 1.0
    /// Whether the cards are white instead of tinted.
    static let defaultWhiteFill = false

    enum Material: Int, CaseIterable, Identifiable {
        case regular
        case clear
        case off

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .regular: "Regular"
            case .clear: "Clear"
            case .off: "Off"
            }
        }

        /// None when off, so the card has no glass layer at all.
        var glass: Glass? {
            switch self {
            case .regular: .regular
            case .clear: .clear
            case .off: nil
            }
        }
    }
}
