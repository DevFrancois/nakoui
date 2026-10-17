#if DEBUG
import SwiftUI

/// A debug panel's title row, with a Reset button and the debug tag.
struct DebugPanelHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: LocalizedStringKey
    let systemImage: String
    /// Whether the panel's values are already at their defaults.
    let isDefault: Bool
    let reset: () -> Void

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    var body: some View {
        layout {
            Label(title, systemImage: systemImage)
                .font(.callout.bold())
                .foregroundStyle(.secondary)

            HStack {
                Button("Reset", action: reset)
                    .font(.caption.bold())
                    .disabled(isDefault)

                DebugBadge()
            }
            .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
        }
        .padding(.top, 6)
    }
}
#endif
