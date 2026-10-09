#if DEBUG
import SwiftUI

/// Brings the For you tasks back, from the bottom of the side menu. Compiled
/// into debug builds only, so it never ships.
struct ResetTasksDebugButton: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()

            Button(action: action) {
                HStack {
                    Label("Reset Tasks", systemImage: "arrow.counterclockwise")
                        .font(.callout.bold())

                    Spacer()

                    Text("Debug")
                        .font(.caption.bold())
                        .textCase(.uppercase)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.quaternary, in: .capsule)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: TopMenuMetrics.minimumTapSize, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 15)
            .accessibilityHint("Brings back every For you task. Debug builds only.")
        }
    }
}

#Preview {
    ResetTasksDebugButton {}
}
#endif
