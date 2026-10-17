import SwiftUI

/// The horizontally scrolling row of glass chips. The highlight follows the
/// supplied selection, and the row scrolls to keep it in view.
struct CategoryChipStrip<Tab: TopMenuTab>: View {
    /// Fractional index of the highlighted chip.
    let selection: CGFloat
    let selectedTab: Tab
    /// Committed selections reveal their chip with an animation.
    let isSelectionLocked: Bool
    let onSelect: (Tab) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position = ScrollPosition()
    @State private var chipFrames: [Int: CGRect] = [:]
    @State private var geometry = ChipStripGeometry()

    private let tabs = Array(Tab.allCases)
    private static var contentSpace: String { "chips" }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: TopMenuMetrics.chipSpacing) {
                ForEach(tabs.enumerated(), id: \.element) { index, tab in
                    CategoryChip(
                        tab: tab,
                        weight: weight(at: index),
                        isSelected: tab == selectedTab,
                        isDark: colorScheme == .dark
                    ) {
                        onSelect(tab)
                    }
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(Self.contentSpace))
                    } action: { frame in
                        chipFrames[index] = frame
                        revealSelection(animated: false)
                    }
                }
            }
            .padding(.horizontal, TopMenuMetrics.chipRowSideInset)
            .padding(.vertical, TopMenuMetrics.chipVerticalInset)
            .coordinateSpace(.named(Self.contentSpace))
        }
        .scrollIndicators(.hidden)
        // Interactive glass grows a pressed chip past the row's insets; the
        // row spans the screen, so nothing else shows outside it.
        .scrollClipDisabled()
        .scrollEdgeEffectHidden(true)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .scrollPosition($position)
        .onScrollGeometryChange(for: ChipStripGeometry.self) { scrollGeometry in
            ChipStripGeometry(scrollGeometry)
        } action: { oldGeometry, newGeometry in
            geometry = newGeometry
            if oldGeometry.viewportWidth != newGeometry.viewportWidth
                || oldGeometry.contentWidth != newGeometry.contentWidth {
                revealSelection(animated: false)
            }
        }
        // Clamped, so a pager bouncing past its last page doesn't scroll the
        // row to the same place every frame.
        .onChange(of: clampedSelection) {
            revealSelection(animated: isSelectionLocked)
        }
        .frame(height: TopMenuMetrics.chipRowHeight)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }

    private var clampedSelection: CGFloat {
        min(max(selection, 0), CGFloat(tabs.count - 1))
    }

    /// A linear crossfade: halfway between two chips, both are half selected.
    private func weight(at index: Int) -> CGFloat {
        max(0, 1 - abs(clampedSelection - CGFloat(index)))
    }

    private func revealSelection(animated: Bool) {
        let frames = tabs.indices.compactMap { chipFrames[$0] }
        guard frames.count == tabs.count,
              let target = ChipReveal.targetOffset(
                  selection: clampedSelection,
                  chipFrames: frames,
                  geometry: geometry
              ) else { return }

        if animated && !reduceMotion {
            withAnimation(TopMenuMetrics.revealAnimation) {
                position.scrollTo(x: target)
            }
        } else {
            // Geometry changes track the new viewport immediately.
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                position.scrollTo(x: target)
            }
        }
    }
}
