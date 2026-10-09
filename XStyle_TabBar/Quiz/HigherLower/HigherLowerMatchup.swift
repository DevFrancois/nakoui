import SwiftUI

/// The known pet over the challenger, with a versus badge reaching into both
/// cards. All three share one glass container, so where they overlap the
/// glass melts into a single liquid shape, and the badge flows wider as it
/// turns into the ratio.
struct HigherLowerMatchup: View {
    let round: HigherLowerRound
    /// The challenger's value as it counts up; nil while it's still hidden.
    let shownValue: Double?
    let outcome: QuizOutcome?

    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: HigherLowerMetrics.versusOverlap) {
            VStack(spacing: -HigherLowerMetrics.versusOverlap) {
                HigherLowerKnownCard(contender: round.known, stat: round.stat)
                    .glassEffectID("known", in: glassNamespace)

                HigherLowerVersusBadge(
                    ratio: outcome == nil ? nil : round.ratio,
                    tint: outcome?.tint ?? QuizKind.higherLower.tint
                )
                    .glassEffectID("versus", in: glassNamespace)
                    .zIndex(1)

                HigherLowerChallengerCard(round: round, shownValue: shownValue, outcome: outcome)
                    .glassEffectID("challenger", in: glassNamespace)
            }
        }
    }
}

#Preview {
    HigherLowerMatchup(round: HigherLowerRounds.all[3], shownValue: 14, outcome: .correct)
        .padding()
        .background(.red.gradient)
}
