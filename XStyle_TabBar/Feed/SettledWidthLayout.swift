import SwiftUI

extension EnvironmentValues {
    /// True while a page's width follows horizontal paging rather than the
    /// viewport, so its content keeps the width it had at rest.
    @Entry var holdsSettledWidth = false
}

/// Keeps a component's text and vertical geometry at the width it last had
/// at rest. Its surface still receives the current width as the page moves
/// past the rail.
struct SettledWidth<Content: View>: View {
    @Environment(\.holdsSettledWidth) private var holdsWidth
    @ViewBuilder let content: Content

    var body: some View {
        SettledWidthLayout(holdsWidth: holdsWidth) {
            content
        }
    }
}

/// Lays out a single subview; wrap several in a stack.
struct SettledWidthLayout: Layout {
    let holdsWidth: Bool

    struct Cache {
        var restingWidth: CGFloat?
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    /// The resting width outlives the update that starts holding it.
    func updateCache(_ cache: inout Cache, subviews: Subviews) {}

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        assert(subviews.count <= 1, "SettledWidthLayout places only one subview; wrap several in a stack.")
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(ProposedViewSize(width: contentWidth(proposal.width, cache: cache), height: nil))
        let availableWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        return CGSize(width: availableWidth ?? size.width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        // Only a placement records the width; sizing passes also probe
        // widths the component never takes.
        if !holdsWidth {
            cache.restingWidth = bounds.width
        }
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: contentWidth(bounds.width, cache: cache), height: nil)
        )
    }

    private func contentWidth(_ proposed: CGFloat?, cache: Cache) -> CGFloat? {
        let width = holdsWidth ? cache.restingWidth ?? proposed : proposed
        return width.flatMap { $0.isFinite ? max(0, $0) : nil }
    }
}
