import SwiftUI

/// A share as a capsule bar that grows to length as it appears, or simply
/// appears at length with Reduce Motion on.
struct PetMatchMixBar: View {
    /// The bar's length, from 0 to 1.
    let fraction: Double
    let tint: Color

    @ScaledMetric(relativeTo: .subheadline) private var height = 10.0
    @State private var trackWidth = 0.0
    @State private var shownFraction = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .frame(height: height)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(height, trackWidth * shownFraction))
            }
            .onGeometryChange(for: Double.self) { proxy in
                proxy.size.width
            } action: { width in
                trackWidth = width
            }
            .onAppear(perform: grow)
            .accessibilityHidden(true)
    }

    private func grow() {
        if reduceMotion {
            shownFraction = fraction
        } else {
            withAnimation(.smooth(duration: 0.8).delay(0.3)) {
                shownFraction = fraction
            }
        }
    }
}
