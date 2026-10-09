import SwiftUI

/// The menu's upper row: buttons at the edges, the wordmark in the middle.
/// As the row collapses, every item flies toward the device pill in step
/// with the scroll.
struct TopMenuLogoRow<Leading: View, Trailing: View>: View {
    let title: String
    /// How far the row has collapsed, in points.
    let collapse: CGFloat
    let flight: LogoFlight
    @Binding var wordmarkSize: CGSize
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading
                .modifier(LogoFlightEffect(distance: collapse, flight: flight))

            Spacer(minLength: 0)

            trailing
                .modifier(LogoFlightEffect(distance: collapse, flight: flight))
        }
        .overlay {
            Wordmark(title: title)
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { newSize in
                    wordmarkSize = newSize
                }
                .modifier(LogoFlightEffect(distance: collapse, flight: flight))
                .allowsHitTesting(false)
                .accessibilityIdentifier("navigation.mainTitle")
        }
        .font(.title3)
        .foregroundStyle(.primary)
        .padding(.horizontal, TopMenuMetrics.logoRowHorizontalPadding)
        .frame(height: TopMenuMetrics.logoRowHeight)
        .allowsHitTesting(collapse < TopMenuMetrics.logoRowHeight / 2)
        .accessibilityHidden(collapse >= TopMenuMetrics.logoRowHeight / 2)
    }
}
