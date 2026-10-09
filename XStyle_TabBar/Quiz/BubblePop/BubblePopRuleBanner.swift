import SwiftUI

/// The round's rule on a lightly tinted glass banner, beside its symbol.
/// At accessibility text sizes the symbol sits above the rule, so the rule
/// gets the full width and long words don't break.
struct BubblePopRuleBanner: View {
    let round: BubblePopRound
    let tint: Color

    @ScaledMetric(relativeTo: .title2) private var iconSize = QuizMetrics.iconSize
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var layout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        } else {
            AnyLayout(HStackLayout(spacing: 14))
        }
    }

    var body: some View {
        layout {
            Image(systemName: round.symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: iconSize, height: iconSize)
                .background(tint.quaternary, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(round.rule)
                    .font(.title3)
                    .bold()

                Text("Find all \(round.matchCount). One wrong pop is forgiven.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .glassEffect(.regular.tint(tint.opacity(0.12)), in: .rect(cornerRadius: QuizMetrics.cardCornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    BubblePopRuleBanner(round: BubblePopRounds.all[0], tint: .cyan)
        .padding()
        .background(.cyan.gradient)
}
