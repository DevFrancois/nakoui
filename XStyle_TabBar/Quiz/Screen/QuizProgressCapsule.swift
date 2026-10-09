import SwiftUI

/// "Question 3 of 8" over a thin bar, on a glass capsule.
struct QuizProgressCapsule: View {
    let kind: QuizKind
    let session: QuizSession

    var body: some View {
        VStack(spacing: 6) {
            Text("Question \(session.index + 1) of \(session.questionCount)")
                .font(.footnote)
                .bold()
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(session.index)))

            ProgressView(value: session.progress)
                .tint(kind.tint)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: 180)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .glassEffect(in: .capsule)
        .animation(.smooth, value: session.progress)
        .accessibilityElement(children: .combine)
    }
}
