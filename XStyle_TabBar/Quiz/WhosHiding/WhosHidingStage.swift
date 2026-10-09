import SwiftUI

/// How far the frosted glass has cleared in a round of Who's Hiding?. Each
/// stage shows one more clue and is worth a point less, down to one.
enum WhosHidingStage: Int, CaseIterable, Comparable {
    case frosted
    case misty
    case hazy
    case clear

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The stage after this one, or nil once the glass is fully clear.
    var next: WhosHidingStage? {
        WhosHidingStage(rawValue: rawValue + 1)
    }

    /// Points for naming the animal during this stage.
    var points: Int {
        switch self {
        case .frosted: 3
        case .misty: 2
        case .hazy, .clear: 1
        }
    }

    /// Whether clearing to the next stage costs a point.
    var isPointAtStake: Bool {
        (next?.points ?? points) < points
    }

    /// Clues showing: one at first, then one more per stage, up to three.
    var clueCount: Int {
        min(rawValue + 1, 3)
    }

    /// How long the glass holds before clearing further: longest at first,
    /// to read the opening clue, about 7.5 seconds in all.
    var duration: Duration {
        switch self {
        case .frosted: .seconds(3)
        case .misty: .seconds(2.5)
        case .hazy: .seconds(2)
        case .clear: .zero
        }
    }

    /// Blur on the animal, as a fraction of its size.
    var blurFraction: Double {
        switch self {
        case .frosted: 0.3
        case .misty: 0.15
        case .hazy: 0.06
        case .clear: 0
        }
    }

    /// The animal starts askew and small, settling as the glass clears.
    var tilt: Double {
        switch self {
        case .frosted: -16
        case .misty: -9
        case .hazy: -3
        case .clear: 0
        }
    }

    var scale: Double {
        switch self {
        case .frosted: 0.78
        case .misty: 0.88
        case .hazy: 0.96
        case .clear: 1
        }
    }

    /// The window glass: milky at first, then barely there.
    var glass: Glass {
        switch self {
        case .frosted: .regular.tint(.white.opacity(0.5))
        case .misty: .regular.tint(.white.opacity(0.25))
        case .hazy, .clear: .clear
        }
    }

    /// Read by VoiceOver as the hidden animal's value.
    var accessibilityValue: LocalizedStringResource {
        switch self {
        case .frosted: "Heavily frosted"
        case .misty: "Starting to clear"
        case .hazy: "Almost clear"
        case .clear: "Fully clear"
        }
    }
}
