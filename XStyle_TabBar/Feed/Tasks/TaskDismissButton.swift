import SwiftUI

/// The small gray close button in a task card's header.
struct TaskDismissButton: View {
    let taskTitle: LocalizedStringResource
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(
                    "Dismiss \(Text(taskTitle))",
                    comment: "VoiceOver label for a task card's close button. The placeholder is the task's title."
                )
            } icon: {
                Image(systemName: "xmark")
            }
            .labelStyle(.iconOnly)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .frame(width: TaskMetrics.dismissCircleSize, height: TaskMetrics.dismissCircleSize)
            .background(.fill.tertiary, in: .circle)
            .frame(width: TopMenuMetrics.minimumTapSize, height: TopMenuMetrics.minimumTapSize)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TaskDismissButton(taskTitle: "Finish Your Profile") {}
}
