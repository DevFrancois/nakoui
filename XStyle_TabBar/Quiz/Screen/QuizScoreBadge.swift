import SwiftUI

/// The running score in a glass circle, ticking up as answers land.
struct QuizScoreBadge: View {
    let score: Int

    var body: some View {
        Text(score, format: .number)
            .font(.headline)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(score)))
            .frame(minWidth: TopMenuMetrics.minimumTapSize, minHeight: TopMenuMetrics.minimumTapSize)
            .glassEffect(in: .circle)
            .animation(.snappy, value: score)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Score: \(score)"))
    }
}
