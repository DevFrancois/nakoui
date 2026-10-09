import SwiftUI

/// One glass chip. Its selected look is an opaque platter inside the glass,
/// faded in by `weight`, so moving the selection crossfades between chips.
struct CategoryChip<Tab: TopMenuTab>: View {
    let tab: Tab
    /// 0 unselected … 1 selected.
    let weight: CGFloat
    let isSelected: Bool
    /// Resolved outside the glass, which can adapt the colors of its content.
    let isDark: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChipLabel(tab: tab, titleColor: .primary)
                .overlay {
                    ChipLabel(tab: tab, titleColor: isDark ? .white : .black)
                        .background(
                            isDark ? TopMenuMetrics.darkPlatter : TopMenuMetrics.lightPlatter,
                            in: .rect(cornerRadius: TopMenuMetrics.chipCornerRadius)
                        )
                        .opacity(weight)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect(cornerRadius: TopMenuMetrics.chipCornerRadius))
        }
        .buttonStyle(PassthroughButtonStyle())
        .glassEffect(
            .regular.tint(isDark ? nil : TopMenuMetrics.lightGlassTint).interactive(),
            in: .rect(cornerRadius: TopMenuMetrics.chipCornerRadius)
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // Chip text has a fixed size, like a tab bar's.
        .accessibilityShowsLargeContentViewer()
        .accessibilityIdentifier("history.tab.\(tab.title)")
    }
}
