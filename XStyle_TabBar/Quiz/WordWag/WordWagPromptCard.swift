import SwiftUI

/// Which kind of breed is hiding, how long it is and what it's worth, on a
/// glass card. The animal wiggles with joy at each solve.
struct WordWagPromptCard: View {
    let puzzle: WordWagPuzzle
    let points: Int
    /// Changes on each solve.
    let solves: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The length and the stakes side by side, or stacked at accessibility
    /// text sizes, where both won't fit across a phone.
    private var detailsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 6))
            : AnyLayout(HStackLayout(spacing: 16))
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: puzzle.species.symbol)
                .font(.largeTitle)
                .foregroundStyle(puzzle.species.tint)
                .symbolEffect(.wiggle, value: reduceMotion ? 0 : solves)
                .accessibilityHidden(true)

            Text(puzzle.prompt)
                .font(.title3)
                .bold()
                .multilineTextAlignment(.center)

            detailsLayout {
                Label("^[\(puzzle.word.count) letter](inflect: true)", systemImage: "textformat.abc")

                WordWagStakes(points: points)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .glassEffect(in: .rect(cornerRadius: QuizMetrics.cardCornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    WordWagPromptCard(puzzle: WordWagRounds.all[0], points: 2, solves: 0)
        .padding()
        .background(.mint.gradient)
}
