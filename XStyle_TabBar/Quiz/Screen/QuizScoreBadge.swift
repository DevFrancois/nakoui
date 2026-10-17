import SwiftUI

/// The running score in a glass circle, ticking up as answers land.
struct QuizScoreBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let score: Int

    var body: some View {
        Text(score, format: .number)
            .font(.headline)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(score)))
            .padding(8)
            .frame(minWidth: TopMenuMetrics.minimumTapSize, minHeight: TopMenuMetrics.minimumTapSize)
            .glassEffect(in: .circle)
            .animation(reduceMotion ? nil : .snappy, value: score)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Score: \(score)"))
    }
}
