import SwiftUI

/// The For you feed's task stack: the next task's card, with the one after it
/// peeking out underneath. Tapping the front card opens every task. When the
/// front task goes, its card fades out while the one behind grows into place.
struct TaskStack: View {
    let tasks: [ForYouTask]
    let onOpen: () -> Void
    let onDismiss: (ForYouTask) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let visibleCount = 2
    private static let peek: CGFloat = 12
    private static let backScale: CGFloat = 0.94

    var body: some View {
        TaskStackLayout(peek: Self.peek) {
            ForEach(tasks.prefix(Self.visibleCount).enumerated(), id: \.element.id) { index, task in
                let isFront = index == 0

                TaskCard(task: task, isContentHidden: !isFront) {
                    onDismiss(task)
                } content: {
                    Button(action: onOpen) {
                        TaskSummary(task: task)
                            .padding()
                            .contentShape(.rect)
                    }
                    .buttonStyle(PassthroughButtonStyle())
                    .accessibilityHint("Shows all tasks")
                }
                // Scaled from the bottom, so the card's lower edge stays put.
                .scaleEffect(isFront || reduceMotion ? 1 : Self.backScale, anchor: .bottom)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .allowsHitTesting(isFront)
                .accessibilityHidden(!isFront)
                // Counted from the back, so a card fading out on removal keeps
                // drawing over the one growing in behind it.
                .zIndex(Double(tasks.count - index))
                .transition(.opacity)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

#Preview {
    TaskStack(tasks: ForYouTask.samples, onOpen: {}, onDismiss: { _ in })
        .background(Color(.taskSheetBackground))
}
