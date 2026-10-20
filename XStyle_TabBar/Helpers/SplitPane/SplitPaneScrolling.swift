import SwiftUI

// Scrollable content in a `SplitPane`'s bottom pane, like SplitPaneKit's
// `dismissalHandlingScrollView`, but sheet-like: it scrolls once the pane is
// fully open, and hands downward drags back to the pane at its top.

extension EnvironmentValues {
    /// Whether scrollable content in a `SplitPane`'s bottom pane scrolls, or
    /// leaves drags to the pane: only at its tallest snap point while it isn't
    /// being dragged. Outside a split pane, content scrolls as usual.
    @Entry var splitPaneScrollsContent = true
}

/// Whether the bottom pane's scrollable content is at its top, so a downward
/// drag shrinks the pane instead of scrolling.
nonisolated struct SplitPaneContentAtTopKey: PreferenceKey {
    static let defaultValue = true

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value && nextValue()
    }
}

extension View {
    /// Marks a scroll view in a `SplitPane`'s bottom pane: it scrolls only
    /// once the pane is fully open, and tells the pane when it's at its top.
    func splitPaneScrollable() -> some View {
        modifier(SplitPaneScrollable())
    }
}

private struct SplitPaneScrollable: ViewModifier {
    @Environment(\.splitPaneScrollsContent) private var scrollsContent
    @State private var isAtTop = true

    func body(content: Content) -> some View {
        content
            .scrollDisabled(!scrollsContent)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                // Within a point of the top, as offsets settle fractionally.
                geometry.contentOffset.y <= -geometry.contentInsets.top + 1
            } action: { _, isAtTop in
                self.isAtTop = isAtTop
            }
            .preference(key: SplitPaneContentAtTopKey.self, value: isAtTop)
    }
}
