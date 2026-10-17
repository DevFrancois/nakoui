import SwiftUI

/// Readable scanner guidance belongs to the safe-area chrome, separate
/// from the camera and aiming artwork that extend behind system bars.
struct ScannerHint: View {
    let isRevealing: Bool

    var body: some View {
        Label("Point at a product barcode", systemImage: "barcode.viewfinder")
            .font(.subheadline)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .glassEffect(in: .capsule)
            .padding(.horizontal)
            .padding(.bottom)
            .opacity(isRevealing ? 0 : 1)
            .accessibilityHidden(isRevealing)
            .animation(.easeOut(duration: 0.15), value: isRevealing)
    }
}
