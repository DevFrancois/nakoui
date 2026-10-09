import SwiftUI

/// The board's theme, what to match, and its par, up front on a glass card.
/// VoiceOver reads it as one heading, so a new board can start there.
struct PawPairsBoardHeader: View {
    let board: PawPairsBoard

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the symbol sits above the words, leaving
        // them the card's full width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: QuizMetrics.sectionSpacing))

        layout {
            Image(systemName: board.symbol)
                .font(.title2)
                // Decorative, so it stops growing before it outgrows its circle.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(QuizKind.pawPairs.tint)
                .frame(width: QuizMetrics.iconSize, height: QuizMetrics.iconSize)
                .background(QuizKind.pawPairs.tint.quaternary, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(board.title)
                    .font(.title3)
                    .bold()

                Text(board.prompt)
                    .font(.subheadline)

                Text("Clear it in \(board.par) moves or fewer to score.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(in: .rect(cornerRadius: QuizMetrics.cardCornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    PawPairsBoardHeader(board: PawPairsRounds.all[0])
        .padding()
        .background(.indigo.gradient)
}
