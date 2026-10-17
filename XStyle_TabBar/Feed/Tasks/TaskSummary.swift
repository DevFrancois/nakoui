import SwiftUI

/// A task's symbol beside its title and message, with an optional footer,
/// such as the sheet's action button, under the text.
struct TaskSummary<Footer: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var iconWidth = TaskMetrics.iconWidth
    let task: ForYouTask
    @ViewBuilder let footer: Footer

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: TaskMetrics.summarySpacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: TaskMetrics.summarySpacing))
    }

    var body: some View {
        layout {
            Image(systemName: task.symbol)
                .font(.largeTitle)
                .foregroundStyle(task.tint)
                .frame(width: iconWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: TaskMetrics.textSpacing) {
                Text(task.title)
                    .font(.headline)

                Text(task.message)
                    .foregroundStyle(.secondary)

                footer
            }
            .fixedSize(horizontal: false, vertical: true)
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
