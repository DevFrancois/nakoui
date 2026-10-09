import SwiftUI

/// The pet whose value is on show, on glass with a hint of its color.
struct HigherLowerKnownCard: View {
    let contender: HigherLowerContender
    let stat: HigherLowerStat

    var body: some View {
        HigherLowerContenderRow(contender: contender, stat: stat, value: contender.value)
            .padding()
            .glassEffect(
                .regular.tint(contender.tint.opacity(0.12)),
                in: .rect(cornerRadius: QuizMetrics.cardCornerRadius)
            )
            .accessibilityElement(children: .combine)
    }
}

#Preview {
    HigherLowerKnownCard(contender: .cat("Maine Coon", 7), stat: .weight)
        .padding()
        .background(.red.gradient)
}
