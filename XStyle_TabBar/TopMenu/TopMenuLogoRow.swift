import SwiftUI

/// The menu's upper row: buttons at the edges, the wordmark in the middle.
/// When the row collapses, every item flies into the device pill.
struct TopMenuLogoRow<Leading: View, Trailing: View>: View {
    let title: String
    let isVisible: Bool
    let flight: LogoFlight
    @Binding var wordmarkSize: CGSize
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading
                .modifier(LogoFlightEffect(isVisible: isVisible, flight: flight))

            Spacer(minLength: 0)

            trailing
                .modifier(LogoFlightEffect(isVisible: isVisible, flight: flight))
        }
        .overlay {
            Wordmark(title: title)
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { newSize in
                    wordmarkSize = newSize
                }
                .modifier(LogoFlightEffect(isVisible: isVisible, flight: flight))
                .allowsHitTesting(false)
                .accessibilityIdentifier("navigation.mainTitle")
        }
        .font(.title3)
        .foregroundStyle(.primary)
        .padding(.horizontal, TopMenuMetrics.logoRowHorizontalPadding)
        .frame(height: TopMenuMetrics.logoRowHeight)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
    }
}
