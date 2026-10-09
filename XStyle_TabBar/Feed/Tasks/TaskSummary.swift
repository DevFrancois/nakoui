import SwiftUI

/// A task's symbol beside its title and message, with an optional footer,
/// such as the sheet's action button, under the text.
struct TaskSummary<Footer: View>: View {
    let task: ForYouTask
    @ViewBuilder let footer: Footer

    var body: some View {
        HStack(alignment: .top, spacing: TaskMetrics.summarySpacing) {
            Image(systemName: task.symbol)
                .font(.largeTitle)
                .foregroundStyle(task.tint)
                .frame(width: TaskMetrics.iconWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: TaskMetrics.textSpacing) {
                Text(task.title)
                    .font(.headline)

                Text(task.message)
                    .foregroundStyle(.secondary)

                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension TaskSummary where Footer == EmptyView {
    init(task: ForYouTask) {
        self.init(task: task) {}
    }
}

#Preview {
    TaskSummary(task: ForYouTask.samples[0])
        .padding()
}
