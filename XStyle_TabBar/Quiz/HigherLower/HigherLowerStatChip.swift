import SwiftUI

/// The stat this round compares, on glass. Its symbol swaps with a replace
/// effect as the rounds change.
struct HigherLowerStatChip: View {
    let stat: HigherLowerStat

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// A capsule while the title sits on one line. At accessibility sizes it
    /// wraps, and a capsule's round ends would cut into the text.
    private var shape: AnyShape {
        dynamicTypeSize.isAccessibilitySize
            ? AnyShape(.rect(cornerRadius: QuizMetrics.answerCornerRadius))
            : AnyShape(.capsule)
    }

    var body: some View {
        Label {
            Text(stat.title)
        } icon: {
            Image(systemName: stat.symbol)
                .foregroundStyle(QuizKind.higherLower.tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .font(.headline)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(QuizKind.higherLower.tint.opacity(0.15)), in: shape)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    VStack {
        HigherLowerStatChip(stat: .weight)
        HigherLowerStatChip(stat: .heartRate)
        HigherLowerStatChip(stat: .height)
            .dynamicTypeSize(.accessibility3)
    }
    .padding()
    .background(.red.gradient)
}
