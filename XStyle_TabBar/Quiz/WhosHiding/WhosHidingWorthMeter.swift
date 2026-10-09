import SwiftUI

/// What naming the animal is worth right now, as paw prints on glass: one
/// goes hollow each time the glass costs a point, and the one at stake
/// pulses. Once answered, it shows what the answer earned, in words as well
/// as color.
struct WhosHidingWorthMeter: View {
    let points: Int
    let outcome: QuizOutcome?
    /// True while the clock runs and the next stage will cost a point.
    let isPointAtStake: Bool
    /// The paws bounce whenever this changes. Pass the session's score: it
    /// only changes when an answer earns points, so the paws don't bounce a
    /// second time when the next round refills them.
    let bounceTrigger: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let maxPoints = WhosHidingStage.frosted.points

    /// Paws beside the words, or above them at accessibility text sizes,
    /// where side by side would leave the words a few letters per line.
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 6))
            : AnyLayout(HStackLayout(spacing: 10))
    }

    /// A capsule, or a rounded rectangle once the meter stacks and grows tall.
    private var shape: AnyShape {
        dynamicTypeSize.isAccessibilitySize
            ? AnyShape(.rect(cornerRadius: QuizMetrics.answerCornerRadius))
            : AnyShape(.capsule)
    }

    var body: some View {
        layout {
            HStack(spacing: 4) {
                ForEach(0..<maxPoints, id: \.self) { index in
                    Image(systemName: index < points ? "pawprint.fill" : "pawprint")
                        .foregroundStyle(index < points ? pawTint : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.pulse, isActive: isPointAtStake && index == points - 1)
                        .symbolEffect(.bounce, value: bounceTrigger)
                }
            }

            Text(title)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .contentTransition(.numericText(value: Double(points)))
        }
        .font(.headline)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(glassTint), in: shape)
        .animation(.snappy, value: points)
        .animation(.smooth, value: outcome)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityTitle))
    }

    private var pawTint: Color {
        outcome == .correct ? .green : QuizKind.whosHiding.tint
    }

    private var glassTint: Color {
        outcome?.tint.opacity(0.25) ?? QuizKind.whosHiding.tint.opacity(0.15)
    }

    private var title: LocalizedStringResource {
        switch outcome {
        case nil: "Worth ^[\(points) point](inflect: true)"
        case .correct: "+^[\(points) point](inflect: true)"
        case .wrong, .timedOut: "No points"
        }
    }

    private var accessibilityTitle: LocalizedStringResource {
        switch outcome {
        case nil: "Worth ^[\(points) point](inflect: true)"
        case .correct: "Earned ^[\(points) point](inflect: true)"
        case .wrong, .timedOut: "No points this time"
        }
    }
}

#Preview {
    VStack {
        WhosHidingWorthMeter(points: 2, outcome: nil, isPointAtStake: true, bounceTrigger: 0)
        WhosHidingWorthMeter(points: 3, outcome: .correct, isPointAtStake: false, bounceTrigger: 3)
        WhosHidingWorthMeter(points: 0, outcome: .wrong, isPointAtStake: false, bounceTrigger: 0)
    }
    .padding()
    .background(.purple.gradient)
}
