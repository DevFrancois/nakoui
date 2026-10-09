import SwiftUI

/// A card-sized button drawn behind a task card's content, so tapping
/// anywhere on the card opens it while the dismiss button keeps its own taps.
/// It carries the card's VoiceOver label, since the content it sits behind is
/// only for show.
struct TaskCardOpenButton: View {
    let task: ForYouTask
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.clear
                .contentShape(.rect)
        }
        .buttonStyle(TaskCardButtonStyle())
        .accessibilityLabel(Text(task.title))
        .accessibilityValue(Text(task.message))
        .accessibilityHint("Shows all tasks")
    }
}
