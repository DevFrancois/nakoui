import SwiftUI

/// The pet to call, on glass. Its value waits behind a question mark, then
/// counts up along a meter whose midpoint is the known pet's value. Once the
/// verdict lands, the card settles green or red and spells out the answer
/// beside a symbol, so the result never rests on color alone.
struct HigherLowerChallengerCard: View {
    let round: HigherLowerRound
    /// The value as it counts up; nil while it's still hidden.
    let shownValue: Double?
    let outcome: QuizOutcome?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HigherLowerContenderRow(contender: round.challenger, stat: round.stat, value: shownValue)

            HigherLowerMeter(
                fraction: round.meterFraction(of: shownValue ?? 0),
                tint: round.challenger.tint,
                markSymbol: round.known.symbol
            )

            HStack {
                if outcome == nil {
                    Text(round.stat.question)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Label(round.stat.title(for: round.answer), systemImage: round.answer.symbol)
                        .font(.headline)
                }

                Spacer(minLength: 0)

                if let outcome {
                    Image(systemName: outcome.symbol)
                        .font(.title2)
                        .foregroundStyle(outcome.tint)
                        .transition(.symbolEffect(.drawOn))
                        .accessibilityLabel(Text(outcome.title))
                }
            }
        }
        .padding()
        .glassEffect(glass, in: .rect(cornerRadius: QuizMetrics.cardCornerRadius))
        .accessibilityElement(children: .combine)
    }

    private var glass: Glass {
        if let outcome {
            .regular.tint(outcome.tint.opacity(0.3))
        } else {
            .regular
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        HigherLowerChallengerCard(round: HigherLowerRounds.all[0], shownValue: nil, outcome: nil)
        HigherLowerChallengerCard(round: HigherLowerRounds.all[0], shownValue: 30, outcome: .correct)
        HigherLowerChallengerCard(round: HigherLowerRounds.all[1], shownValue: 45, outcome: .wrong)
    }
    .padding()
    .background(.red.gradient)
}
