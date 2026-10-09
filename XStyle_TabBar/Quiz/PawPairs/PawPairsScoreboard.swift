import SwiftUI

/// Moves against par and pairs found, as glass capsules that reshape as
/// their numbers change. Going over par turns the moves orange, with a
/// crossed-out flag; finding every pair turns the pairs green, with a seal.
struct PawPairsScoreboard: View {
    let moves: Int
    let par: Int
    let found: Int
    let total: Int

    @Namespace private var glassNamespace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isOverPar: Bool {
        moves > par
    }

    private var isComplete: Bool {
        total > 0 && found == total
    }

    var body: some View {
        // Side by side, each on one line that shrinks a little on a narrow
        // phone, such as "15 moves, over par" at 375 points. Stacked, and
        // free to wrap, at accessibility sizes. The choice never changes
        // mid-board, so the cards below don't jump.
        let isStacked = dynamicTypeSize.isAccessibilitySize
        let layout = isStacked
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))

        GlassEffectContainer(spacing: 8) {
            layout {
                PawPairsStatChip(
                    title: isOverPar ? "\(moves) moves, over par" : "\(moves) of \(par) moves",
                    systemImage: isOverPar ? "flag.slash.fill" : "flag.fill",
                    tint: isOverPar ? .orange : nil
                )
                .glassEffectID("moves", in: glassNamespace)

                PawPairsStatChip(
                    title: "\(found) of \(total) pairs",
                    systemImage: isComplete ? "checkmark.seal.fill" : "pawprint.fill",
                    tint: isComplete ? .green : nil
                )
                .glassEffectID("pairs", in: glassNamespace)
            }
            .lineLimit(isStacked ? nil : 1)
        }
        .animation(.snappy, value: moves)
        .animation(.snappy, value: found)
    }
}

#Preview {
    PawPairsScoreboard(moves: 15, par: 14, found: 4, total: 6)
        .padding()
        .background(.indigo.gradient)
}
