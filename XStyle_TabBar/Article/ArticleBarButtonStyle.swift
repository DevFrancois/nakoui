import SwiftUI

/// A circular Liquid Glass button, sized like a navigation bar button.
struct ArticleBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .imageScale(.large)
            .frame(width: ArticleMetrics.barButtonSize, height: ArticleMetrics.barButtonSize)
            .contentShape(.circle)
            .glassEffect(.regular.interactive(), in: .circle)
    }
}
