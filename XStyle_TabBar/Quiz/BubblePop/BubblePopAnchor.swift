import Foundation

/// The parts of a Bubble Pop round that the screen scrolls to, or that
/// VoiceOver moves to: the rule as each round starts, and the verdict and
/// Next once it ends. Nonisolated so it can identify views anywhere.
nonisolated enum BubblePopAnchor: Hashable {
    case rule
    case verdict
    case next
}
