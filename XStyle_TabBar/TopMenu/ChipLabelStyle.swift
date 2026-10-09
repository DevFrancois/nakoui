import SwiftUI

/// Icon and title side by side, with the chip's tight spacing.
struct ChipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: TopMenuMetrics.chipIconTitleSpacing) {
            configuration.icon
            configuration.title
        }
    }
}
