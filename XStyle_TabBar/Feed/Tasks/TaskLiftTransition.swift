import SwiftUI

/// Lifts a card toward the viewer while it blurs and fades.
struct TaskLiftTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .scaleEffect(phase.isIdentity ? 1 : 1.06)
            .offset(y: phase.isIdentity ? 0 : -24)
            .blur(radius: phase.isIdentity ? 0 : 12)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}
