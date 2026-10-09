import SwiftUI

/// A chip's tinted icon and title, padded to the chip's size.
struct ChipLabel<Tab: TopMenuTab>: View {
    let tab: Tab
    let titleColor: Color

    var body: some View {
        Label {
            Text(tab.title)
                .font(TopMenuMetrics.chipTitleFont)
                .foregroundStyle(titleColor)
                .lineLimit(1)
        } icon: {
            Image(systemName: tab.symbol)
                .symbolVariant(.fill)
                .font(TopMenuMetrics.chipIconFont)
                .imageScale(.large)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tab.tint)
        }
        .labelStyle(ChipLabelStyle())
        .padding(.leading, TopMenuMetrics.chipLeadingPadding)
        .padding(.trailing, TopMenuMetrics.chipTrailingPadding)
        .frame(height: TopMenuMetrics.chipHeight)
    }
}
