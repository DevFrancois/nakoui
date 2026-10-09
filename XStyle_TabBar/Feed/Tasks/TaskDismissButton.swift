import SwiftUI

/// The small gray close button in a task card's header.
struct TaskDismissButton: View {
    let taskTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Dismiss \(taskTitle)", systemImage: "xmark")
                .labelStyle(.iconOnly)
                .font(.footnote.bold())
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
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
