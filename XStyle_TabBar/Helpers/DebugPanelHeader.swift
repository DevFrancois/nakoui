#if DEBUG
import SwiftUI

/// A debug panel's title row, with a Reset button and the debug tag.
struct DebugPanelHeader: View {
    let title: LocalizedStringKey
    let systemImage: String
    /// Whether the panel's values are already at their defaults.
    let isDefault: Bool
    let reset: () -> Void

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.callout.bold())
                .foregroundStyle(.secondary)

            Spacer()

            Button("Reset", action: reset)
                .font(.caption.bold())
                .disabled(isDefault)

            DebugBadge()
        }
        .padding(.top, 6)
    }
}
#endif
