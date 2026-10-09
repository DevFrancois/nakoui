import SwiftUI

/// Bubble Pop, an arcade game: each round has a rule, and glass bubbles of
/// words float up through a tank. Pop every bubble that fits the rule before
/// time runs out, and leave the decoys alone. Each round is a view of its
/// own, so its board starts fresh and slides in after the last.
struct BubblePopQuizView: View {
    let namespace: Namespace.ID

    @State private var session = QuizSession(kind: .bubblePop)

    var body: some View {
        QuizScreen(kind: .bubblePop, session: session, namespace: namespace) {
            // Overlaps the outgoing and incoming rounds as one slides in.
            ZStack(alignment: .top) {
                BubblePopRoundView(
                    round: BubblePopRounds.all[session.index],
                    number: session.index,
                    session: session
                )
                .id(session.index)
                .quizQuestionTransition()
            }
            .animation(.smooth, value: session.index)
        }
    }
}

#Preview {
    @Previewable @Namespace var namespace

    NavigationStack {
        BubblePopQuizView(namespace: namespace)
    }
}
