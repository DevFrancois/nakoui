import SwiftUI

/// The cards, sharing one glass container so they morph as they're dealt
/// one by one and as they move. Once the board is cleared, they glide into
/// rows, each card beside its match, and every pair's glass joins into one
/// piece.
struct PawPairsTable: View {
    let game: PawPairsGame
    /// Cards dealt so far; the rest keep their places, empty.
    let dealtCount: Int
    /// True once the board is cleared and settled: the cards line up in pairs.
    let isReviewing: Bool
    let flip: (PawPairsCard) -> Void

    @ScaledMetric(relativeTo: .subheadline) private var cardHeight = 96.0
    @ScaledMetric(relativeTo: .subheadline) private var pairHeight = 52.0
    @Namespace private var glassNamespace
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer(spacing: PawPairsMetrics.cardSpacing) {
            PawPairsTableLayout(
                columns: columns,
                rowHeight: rowHeight,
                columnSpacing: isReviewing ? PawPairsMetrics.pairSeam : PawPairsMetrics.cardSpacing,
                rowSpacing: isReviewing ? PawPairsMetrics.pairRowSpacing : PawPairsMetrics.cardSpacing
            ) {
                ForEach(isReviewing ? game.cardsInPairs : game.cards) { card in
                    Group {
                        if card.number <= dealtCount {
                            PawPairsCardButton(
                                card: card,
                                state: game.state(of: card),
                                isReviewing: isReviewing,
                                misses: game.missCount(of: card)
                            ) {
                                flip(card)
                            }
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
                        } else {
                            Color.clear
                                .accessibilityHidden(true)
                        }
                    }
                    .glassEffectID(card.id, in: glassNamespace)
                    .glassEffectUnion(id: isReviewing ? card.pairID : nil, namespace: glassNamespace)
                }
            }
        }
        // With Reduce Motion, the board crossfades into its pairs rather
        // than gliding there.
        .id(reduceMotion && isReviewing)
        .transition(.opacity)
    }

    /// Pairs line up in short rows, with the symbol beside the word. At
    /// accessibility sizes they keep the card's height, symbol over word,
    /// so long words have room.
    private var rowHeight: Double {
        isReviewing && !dynamicTypeSize.isAccessibilitySize ? pairHeight : cardHeight
    }

    /// Three across on iPhone and four with more room, so a board fits on
    /// screen; two once cleared, one pair per row, or at accessibility sizes.
    private var columns: Int {
        if isReviewing || dynamicTypeSize.isAccessibilitySize {
            2
        } else if horizontalSizeClass == .regular {
            4
        } else {
            3
        }
    }
}
