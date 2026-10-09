import SwiftUI

/// ZoomInUIKit's top menu: a logo row over a row of glass chips, laid over
/// scrolling content. When the logo row collapses, the chips slide up into
/// its place and its items fly into the device pill.
struct TopMenuBar<Tab: TopMenuTab, Leading: View, Trailing: View>: View {
    let title: String
    /// Fractional index of the highlighted chip.
    let selection: CGFloat
    /// The tab VoiceOver reports as selected.
    let selectedTab: Tab
    /// True while a tapped tab is being reached.
    let isSelectionLocked: Bool
    let isLogoVisible: Bool
    let onSelect: (Tab) -> Void
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    @State private var safeAreaTop: CGFloat = 0
    @State private var width: CGFloat = 0
    @State private var wordmarkSize = CGSize.zero

    var body: some View {
        ZStack(alignment: .top) {
            CategoryChipStrip(
                selection: selection,
                selectedTab: selectedTab,
                isSelectionLocked: isSelectionLocked,
                onSelect: onSelect
            )
            .padding(.top, isLogoVisible ? TopMenuMetrics.logoRowHeight : 0)
            .animation(TopMenuMetrics.collapseAnimation, value: isLogoVisible)

            TopMenuLogoRow(
                title: title,
                isVisible: isLogoVisible,
                flight: flight,
                wordmarkSize: $wordmarkSize
            ) {
                leading
            } trailing: {
                trailing
            }
            // Flies above the chips, as ZoomInUIKit's unclipped copies do.
            .zIndex(1)
        }
        // As a safe-area bar, this height sets how far the soft edge reaches,
        // so it shrinks with the logo row, as ZoomInUIKit's menu does.
        .frame(
            height: isLogoVisible ? TopMenuMetrics.expandedHeight : TopMenuMetrics.chipRowHeight,
            alignment: .top
        )
        // Separate values, so the side menu's horizontal slide writes no state.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).minY
        } action: { minY in
            safeAreaTop = minY
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
    }

    private var flight: LogoFlight {
        DevicePillGeometry(safeAreaTop: safeAreaTop, containerWidth: width)
            .flight(wordmarkSize: wordmarkSize)
    }
}

#Preview {
    @Previewable @State var selection: CGFloat = 0
    @Previewable @State var isLogoVisible = true

    VStack {
        TopMenuBar(
            title: "Nako",
            selection: selection,
            selectedTab: AppTab.allCases[Int(selection.rounded())],
            isSelectionLocked: false,
            isLogoVisible: isLogoVisible,
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
        Toggle("Logo row", isOn: $isLogoVisible)
    }
    .padding(.bottom)
    .background {
        AmbientGradientBackground(palettes: AppTab.allCases.map(\.palette), progress: selection)
    }
}
