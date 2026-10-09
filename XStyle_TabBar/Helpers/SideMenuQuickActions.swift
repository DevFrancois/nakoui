import SwiftUI

/// Bookmarks and Likes, side by side under the side menu's profile, as two
/// faintly tinted glass tiles with a big symbol, a title and a count, like
/// Control Center modules. A tap shows a short loading state in that tile,
/// then opens it.
struct SideMenuQuickActions: View {
    let onOpen: (SideMenuQuickAction) -> Void

    @State private var loading: SideMenuQuickAction?

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(SideMenuQuickAction.allCases) { action in
                    tile(action)
                }
            }
        }
        .sensoryFeedback(trigger: loading) { _, newValue in
            newValue == nil ? nil : .impact(flexibility: .soft)
        }
    }

    private func tile(_ action: SideMenuQuickAction) -> some View {
        Button {
            open(action)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                SideMenuQuickIcon(action: action, isLoading: loading == action)
                    .font(.title2)
                    .foregroundStyle(action.tint)
                    .frame(height: 28)

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

    private func open(_ action: SideMenuQuickAction) {
        guard loading == nil else { return }
        withAnimation(.bouncy) {
            loading = action
        }
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            withAnimation(.bouncy) {
                loading = nil
            }
            onOpen(action)
        }
    }
}

#Preview {
    SideMenuQuickActions { _ in }
        .padding()
        .background(.black)
}
