import SwiftUI

/// A full-width capsule of interactive glass under the board, with an
/// optional cost beside its title, such as the hint's "−1".
struct WordWagActionButton: View {
    let title: LocalizedStringResource
    let systemImage: String
    var cost: LocalizedStringResource?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage)

                if let cost {
                    Text(cost)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .font(.headline)
            .foregroundStyle(isEnabled ? .primary : .tertiary)
            .padding(.horizontal, WordWagMetrics.controlPadding)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: TopMenuMetrics.minimumTapSize)
            .contentShape(.capsule)
        }
        .buttonStyle(PassthroughButtonStyle())
        .glassEffect(.regular.interactive(isEnabled), in: .capsule)
    }
}

#Preview {
    HStack {
        WordWagActionButton(title: "Hint", systemImage: "lightbulb.fill", cost: "−1") {}
        WordWagActionButton(title: "Shuffle", systemImage: "shuffle") {}
    }
    .padding()
    .background(.mint.gradient)
}
