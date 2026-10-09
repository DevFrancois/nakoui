import SwiftUI

/// A circular Liquid Glass button, sized like a navigation bar button and
/// Apple's minimum tap size. Shared by the article and quiz screens.
struct GlassCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .imageScale(.large)
            .frame(width: TopMenuMetrics.minimumTapSize, height: TopMenuMetrics.minimumTapSize)
            .contentShape(.circle)
            .glassEffect(.regular.interactive(), in: .circle)
    }
}
