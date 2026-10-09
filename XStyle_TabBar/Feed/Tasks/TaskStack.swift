import SwiftUI

/// The For you feed's task stack: the next task's card, with up to two more
/// peeking out underneath, each a little narrower and dimmer than the one in
/// front. Tapping anywhere on the front card, apart from its close button,
/// opens every task. When the front task goes, its card lifts toward you,
/// blurring and fading, while the ones behind grow forward.
struct TaskStack: View {
    let tasks: [ForYouTask]
    let onOpen: () -> Void
    let onDismiss: (ForYouTask) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TaskStackLayout(peek: TaskMetrics.stackPeek) {
            ForEach(tasks.prefix(TaskMetrics.visibleStackCount).enumerated(), id: \.element.id) { index, task in
                let isFront = index == 0

                TaskCard(task: task, depth: index, onOpen: onOpen, onDismiss: { onDismiss(task) }) {
                    TaskSummary(task: task)
                        .padding()
                }
                // Scaled from the bottom, so the card's lower edge stays put.
                .scaleEffect(reduceMotion ? 1 : 1 - TaskMetrics.stackScaleStep * CGFloat(index), anchor: .bottom)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .allowsHitTesting(isFront)
                .accessibilityHidden(!isFront)
                // Counted from the back, so a card fading out on removal keeps
                // drawing over the ones growing forward behind it.
                .zIndex(Double(tasks.count - index))
                .layoutValue(key: TaskStackDepth.self, value: index)
                .transition(.asymmetric(insertion: .opacity, removal: removal))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tasks")
        .padding(.horizontal)
        // Empty once the last card has gone, so nothing is left behind.
        .padding(.vertical, tasks.isEmpty ? 0 : 8)
    }

    /// With Reduce Motion, the card just fades.
    private var removal: AnyTransition {
        reduceMotion ? .opacity : AnyTransition(TaskLiftTransition())
    }
}

#Preview {
    TaskStack(tasks: ForYouTask.samples, onOpen: {}, onDismiss: { _ in })
        .background(Color(.taskSheetBackground))
}
