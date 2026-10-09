import SwiftUI

/// An open slot: a dashed outline, drawn in the quiz's color with a tap
/// hint when it's the next one to fill.
struct LineUpEmptySlot: View {
    /// Counting from 1.
    let position: Int
    let isNext: Bool
    let tint: Color

    @ScaledMetric(relativeTo: .headline) private var minHeight = LineUpMetrics.chipHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if isNext {
                Label("Tap a pet", systemImage: "hand.tap.fill")
                    .font(.subheadline)
                    .foregroundStyle(tint)
                    .symbolEffect(.breathe)
                    .symbolEffectsRemoved(reduceMotion)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .background {
            RoundedRectangle(cornerRadius: QuizMetrics.answerCornerRadius)
                .strokeBorder(isNext ? tint : .secondary, style: LineUpMetrics.dashedOutline)
                .opacity(isNext ? 1 : 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Position \(position)"))
        .accessibilityValue(Text("Empty"))
    }
}
