import SwiftUI

/// Slides each new question in from the trailing edge, or fades it with
/// Reduce Motion on. Apply with an `id` that changes per question.
struct QuizQuestionTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .transition(reduceMotion ? AnyTransition.opacity : .push(from: .trailing))
    }
}

extension View {
    func quizQuestionTransition() -> some View {
        modifier(QuizQuestionTransition())
    }
}
