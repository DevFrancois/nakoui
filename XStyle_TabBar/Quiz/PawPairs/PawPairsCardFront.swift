import SwiftUI

/// The face-up side: the card's symbol over its word, with a check or a cross
/// once it's settled. When a cleared board lines up in pairs, the symbol
/// moves beside the word to fit a row, except at accessibility sizes, where
/// the word needs the full width.
struct PawPairsCardFront: View {
    let card: PawPairsCard
    let state: PawPairsCardState
    let isReviewing: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let isSideBySide = isReviewing && !dynamicTypeSize.isAccessibilitySize
        let layout = isSideBySide ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 6))

        layout {
            Image(systemName: card.face.symbol)
                .font(.title3)
                .foregroundStyle(QuizKind.pawPairs.tint)
                .accessibilityHidden(true)

            Text(card.face.text)
                .font(.subheadline)
                .bold()
                .multilineTextAlignment(.center)
                // Long single words, such as "Pandemonium", shrink rather
                // than break; at accessibility sizes, two columns leave them
                // less room, but even halved they stay above the default size.
                // One line per word stops text layout hyphenating them instead.
                .lineLimit(max(1, String(localized: card.face.text).split(separator: " ").count))
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.5 : 0.7)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Inside the glass, so it draws crisply rather than blending in.
        .overlay(alignment: .topTrailing) {
            if let symbol = state.badgeSymbol, !isReviewing {
                Image(systemName: symbol)
                    .font(.subheadline)
                    .foregroundStyle(state.badgeTint)
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
        }
    }
}

#Preview {
    let card = PawPairsCard(
        pairID: 0,
        face: PawPairsFace("Pembroke Welsh Corgi", symbol: "dog.fill"),
        number: 1,
        boardIndex: 0
    )

    PawPairsCardFront(card: card, state: .matched, isReviewing: false)
        .frame(width: 110, height: 96)
        .glassEffect(PawPairsCardState.matched.frontGlass, in: .rect(cornerRadius: QuizMetrics.answerCornerRadius))
        .padding()
        .background(.indigo.gradient)
}
