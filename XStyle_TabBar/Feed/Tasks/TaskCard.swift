import SwiftUI

/// A task's card: its category and a dismiss button over a divider, then the
/// content below. Content keeps its natural height, so a card given less
/// height, as the cards behind the stack's front one are, clips it instead of
/// squeezing it.
struct TaskCard<Content: View>: View {
    let task: ForYouTask
    /// How far back in the stack the card sits; 0 is the front. Cards behind
    /// hide their content and dim their surface the deeper they are, and both
    /// ease back as a card moves forward.
    var depth = 0
    /// Makes the whole card a button, apart from its dismiss button. The
    /// heading and content then let taps through to it, so they shouldn't
    /// hold controls of their own.
    var onOpen: (() -> Void)?
    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    private var isOpenable: Bool {
        onOpen != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(task.category)
                    .font(.subheadline)
                    // A step up from regular, short of bold, to match the
                    // reference design.
                    .fontWeight(.medium)
                    .allowsHitTesting(!isOpenable)
                    .accessibilityHidden(isOpenable)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                Spacer()

                TaskDismissButton(taskTitle: task.title, action: onDismiss)
            }
            .padding(.leading)
            .padding(.trailing, 8)
            .padding(.vertical, 4)

            Divider()
                .allowsHitTesting(!isOpenable)

            content
                .allowsHitTesting(!isOpenable)
                .accessibilityHidden(isOpenable)
        }
        .fixedSize(horizontal: false, vertical: true)
        .opacity(depth == 0 ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            if let onOpen {
                TaskCardOpenButton(task: task, action: onOpen)
            }
        }
        .background {
            Rectangle()
                .fill(.fill.secondary)
                .opacity(min(Double(depth) * TaskMetrics.stackDimStep, 1))
        }
        .background(Color(.taskCardBackground))
        .clipShape(.rect(cornerRadius: TaskMetrics.cornerRadius))
    }
}

#Preview {
    TaskCard(task: ForYouTask.samples[0], onDismiss: {}) {
        TaskSummary(task: ForYouTask.samples[0])
            .padding()
    }
    .padding()
    .background(Color(.taskSheetBackground))
}
