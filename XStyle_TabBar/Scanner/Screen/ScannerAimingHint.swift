import SwiftUI

/// What to do, under the camera and above the tab bar, while aiming, until the
/// first scan. It keeps its place while hidden, so the camera above it doesn't
/// move as it comes and goes. Once the history button shows, the button takes
/// its place for good.
struct ScannerAimingHint: View {
    let isShown: Bool

    var body: some View {
        Text("Point at a product barcode")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            .padding(.vertical, 8)
            // Only the fade: its place is the pane's footer slot, which doesn't animate.
            .animation(.easeOut(duration: 0.15)) { content in
                content.opacity(isShown ? 1 : 0)
            }
            .accessibilityHidden(!isShown)
    }
}

#Preview {
    ScannerAimingHint(isShown: true)
}
