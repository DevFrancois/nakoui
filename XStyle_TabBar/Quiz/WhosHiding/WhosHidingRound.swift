import SwiftUI

/// One animal hiding behind the glass, with three clues that get more
/// telling, four names to choose from and a fact for the reveal.
struct WhosHidingRound: Identifiable {
    let id = UUID()
    /// The SF Symbol drawn behind the glass.
    let symbol: String
    let tint: Color
    /// Shown on the pane once the animal is revealed.
    let reveal: LocalizedStringResource
    /// From vague to nearly a giveaway; one more shows at each stage.
    let clues: [LocalizedStringResource]
    let choices: [LocalizedStringResource]
    let answerIndex: Int
    let fact: LocalizedStringResource
}
