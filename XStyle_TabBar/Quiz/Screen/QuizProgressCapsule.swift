import SwiftUI

/// "Question 3 of 8" over a thin bar, on a glass capsule.
struct QuizProgressCapsule: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let kind: QuizKind
    let session: QuizSession

    @ScaledMetric(relativeTo: .footnote) private var maximumWidth = 180.0

    var body: some View {
        VStack(spacing: 6) {
            Text("Question \(session.index + 1) of \(session.questionCount)")
                .font(.footnote)
                .bold()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(session.index)))

            ProgressView(value: session.progress)
                .tint(kind.tint)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: maximumWidth)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .glassEffect(in: .capsule)
        .animation(reduceMotion ? nil : .smooth, value: session.progress)
        .accessibilityElement(children: .combine)
    }
}
