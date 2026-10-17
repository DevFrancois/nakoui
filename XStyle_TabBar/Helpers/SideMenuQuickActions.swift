import SwiftUI

/// Bookmarks and Likes, side by side under the side menu's profile, as two
/// faintly tinted glass tiles with a big symbol, a title and a count, like
/// Control Center modules. Each action opens its destination directly.
struct SideMenuQuickActions: View {
    let onOpen: (SideMenuQuickAction) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(SideMenuQuickAction.allCases) { action in
                    SideMenuQuickActionTile(action: action) {
                        onOpen(action)
                    }
                }
            }
        }
    }
}

private struct SideMenuQuickActionTile: View {
    let action: SideMenuQuickAction
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: action.symbol)
                    .font(.title2)
                    .foregroundStyle(action.tint)
                    .accessibilityHidden(true)

                Text(action.title)
                    .font(.subheadline.bold())

                Text(action.count, format: .number.notation(.compactName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .padding(14)
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(action.tint.opacity(0.12)).interactive(), in: .rect(cornerRadius: 22))
    }
}

#Preview {
    SideMenuQuickActions { _ in }
        .padding()
        .background(.black)
}
