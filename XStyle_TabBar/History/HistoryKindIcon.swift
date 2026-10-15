import SwiftUI

/// A history entry's kind as a white symbol on a tinted rounded square.
struct HistoryKindIcon: View {
    let kind: HistoryKind
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(kind.tint.gradient, in: .rect(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}
