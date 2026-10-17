import SwiftUI

/// ZoomInUIKit's top menu: a logo row over a row of glass chips, laid over
/// scrolling content. As the logo row collapses, in step with the scroll,
/// the chips slide up into its place and the logo shrinks and fades.
struct TopMenuBar<Tab: TopMenuTab, Leading: View, Trailing: View>: View {
    let title: String
    /// Fractional index of the highlighted chip.
    let selection: CGFloat
    /// The tab VoiceOver reports as selected.
    let selectedTab: Tab
    /// True when selection changes discretely, so its chip is revealed smoothly.
    let isSelectionLocked: Bool
    let logoCollapse: LogoCollapse
    let onSelect: (Tab) -> Void
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    @State private var wordmarkSize = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                CategoryChipStrip(
                    selection: selection,
                    selectedTab: selectedTab,
                    isSelectionLocked: isSelectionLocked,
                    onSelect: onSelect
                )
                .padding(.top, TopMenuMetrics.logoRowHeight)
                .offset(y: -logoCollapse.distance)

                TopMenuLogoRow(
                    title: title,
                    collapse: logoCollapse.distance,
                    flight: LogoCollapseGeometry(containerWidth: geometry.size.width).flight(wordmarkSize: wordmarkSize),
                    wordmarkSize: $wordmarkSize
                ) {
                    leading
                } trailing: {
                    trailing
                }
                // Flies above the chips, as ZoomInUIKit's unclipped copies do.
                .zIndex(1)
            }
        }
        // A fixed height: the collapse moves what's inside, never the menu's
        // footprint, so the pages under it never move with it.
        .frame(height: TopMenuMetrics.expandedHeight, alignment: .top)
    }
}

#Preview {
    @Previewable @State var selection: CGFloat = 0
    @Previewable @State var logoCollapse = LogoCollapse()

    VStack {
        TopMenuBar(
            title: "Nako",
            selection: selection,
            selectedTab: AppTab.allCases[Int(selection.rounded())],
            isSelectionLocked: false,
            logoCollapse: logoCollapse,
            onSelect: { selection = CGFloat($0.index) }
        ) {
            Button("Open menu", systemImage: "line.3.horizontal") {}
                .labelStyle(.iconOnly)
        } trailing: {
            Button("Search", systemImage: "magnifyingglass") {}
                .labelStyle(.iconOnly)
        }

        Spacer()

        Slider(value: $selection, in: 0...CGFloat(AppTab.allCases.count - 1))
        Button("Toggle logo row") {
            logoCollapse.isShown ? logoCollapse.hide() : logoCollapse.reveal()
        }
    }
    .padding(.bottom)
    .background {
        AmbientGradientBackground(palettes: AppTab.allCases.map(\.palette), progress: selection)
    }
}
