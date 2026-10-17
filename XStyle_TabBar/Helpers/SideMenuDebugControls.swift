#if DEBUG
import SwiftUI

/// The dormant menu's footer owns its local expansion independently of navigation.
struct SideMenuDebugControls: View {
    let onResetTasks: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                FeedGlassDebugControls()
                GradientDebugControls()
            }

            Divider()

            Button(action: toggleExpanded) {
                Label(isExpanded ? "Hide Tuning" : "Show Tuning", systemImage: "slider.horizontal.3")
                    .font(.callout.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: TopMenuMetrics.minimumTapSize, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 15)

            ResetTasksDebugButton(action: onResetTasks)
        }
    }

    private func toggleExpanded() {
        withAnimation { isExpanded.toggle() }
    }
}
#endif
