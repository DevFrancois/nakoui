import SwiftUI

/// A task's card: its category and a dismiss button over a divider, then the
/// content below. Content keeps its natural height, so a card given less
/// height, as a card behind the stack's front one is, clips it instead of
/// squeezing it.
struct TaskCard<Content: View>: View {
    let task: ForYouTask
    /// Hides the content while keeping the card's surface, for cards behind
    /// the stack's front one.
    var isContentHidden = false
    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    static var cornerRadius: CGFloat { 26 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(task.category)
                    .font(.subheadline.weight(.medium))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                Spacer()

                TaskDismissButton(taskTitle: task.title, action: onDismiss)
            }
            .padding(.leading)
            .padding(.trailing, 8)
            .padding(.vertical, 4)

            Divider()

            content
        }
        .fixedSize(horizontal: false, vertical: true)
        .opacity(isContentHidden ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.taskCardBackground), in: .rect(cornerRadius: Self.cornerRadius))
        .clipShape(.rect(cornerRadius: Self.cornerRadius))
    }
}

#Preview {
    TaskCard(task: ForYouTask.samples[0]) {} content: {
        TaskSummary(task: ForYouTask.samples[0])
            .padding()
    }
    .padding()
    .background(Color(.taskSheetBackground))
}
