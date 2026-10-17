import SwiftUI

/// The current guess, large, over the slider that sets it, on one glass panel.
struct EstimateGuessPanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let question: EstimateQuestion
    @Binding var guess: Double
    let isLocked: Bool
    let tint: Color

    var body: some View {
        VStack(spacing: 12) {
            Text("\(Text(guess, format: .number.precision(.fractionLength(0)))) \(Text(question.unit))")
                .font(.largeTitle)
                .bold()
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText(value: guess))
                .animation(reduceMotion ? nil : .snappy, value: guess)

            Slider(value: $guess, in: question.range, step: question.step) {
                Text("Your guess")
            }
            .tint(tint)
            .disabled(isLocked)
            .accessibilityValue(Text("\(Text(guess, format: .number.precision(.fractionLength(0)))) \(Text(question.unit))"))

            HStack {
                Text(question.range.lowerBound, format: .number)
                Spacer()
                Text(question.range.upperBound, format: .number)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: QuizMetrics.cardCornerRadius))
    }
}
