import SwiftUI

/// The order to make, over what's being compared, beside the round's symbol
/// on a glass card. Kept to a short row, so the slots, the pool and the
/// verdict fit below it on a phone; at accessibility sizes the symbol sits
/// above, so the title keeps the card's full width.
struct LineUpPromptCard: View {
    let round: LineUpRound
    let tint: Color

    @ScaledMetric(relativeTo: .largeTitle) private var iconWidth = 48.0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isStacked: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var layout: AnyLayout {
        isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 16))
    }

    var body: some View {
        layout {
            Image(systemName: round.symbol)
                .font(.largeTitle)
                .foregroundStyle(tint)
                .frame(width: iconWidth, alignment: isStacked ? .leading : .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(round.title)
                    .font(.title2)
                    .bold()

                Text(round.measure)
                    .font(.subheadline)
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
    LineUpPromptCard(round: LineUpRounds.all[0], tint: .blue)
        .padding()
        .background(.blue.gradient)
}
