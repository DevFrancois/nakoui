import SwiftUI

/// Keeps horizontal chrome inset and lets the navigation container place
/// vertical chrome in its shared bar region, outside the content safe area.
struct GlassTabBarInset: ViewModifier {
    @Binding var selection: RootTab

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.modifier(AdaptiveGlassTabBarInset(selection: $selection))
        } else {
            content.modifier(HorizontalGlassTabBarInset(selection: $selection, isPresented: true))
        }
    }
}

@available(iOS 27.1, *)
private struct AdaptiveGlassTabBarInset: ViewModifier {
    @Binding var selection: RootTab
    @Environment(\.toolbarVerticalEdge) private var verticalEdge

    func body(content: Content) -> some View {
        // A side safeAreaBar sits against the content safe area, inward of
        // Duo's system strip. A toolbar item participates in that strip's
        // layout instead, including its hardware avoidance and compression.
        content
            .modifier(HorizontalGlassTabBarInset(selection: $selection, isPresented: verticalEdge == nil))
            .toolbar {
                if verticalEdge != nil {
                    ToolbarItem(placement: .bottomBar) {
                        ToolbarGlassTabBar(selection: $selection)
                    }
                    .axisBehavior(.verticalPreferred)
                    .sharedBackgroundVisibility(.hidden)
                    .contentMarginsRemoved()
                    .visibilityPriority(.high)
                }
            }
            .toolbarVisibility(verticalEdge == nil ? .automatic : .visible, for: .bottomBar)
    }
}

@available(iOS 27.1, *)
private struct ToolbarGlassTabBar: View {
    @Binding var selection: RootTab
    @Environment(\.toolbarVerticalEdge) private var verticalEdge

    var body: some View {
        GlassTabBar(selection: $selection, axis: verticalEdge == nil ? .horizontal : .vertical)
    }
}

private struct HorizontalGlassTabBarInset: ViewModifier {
    @Binding var selection: RootTab
    let isPresented: Bool

    func body(content: Content) -> some View {
        // Only the bar contents change when the edge changes. The tab host
        // keeps its identity, so folding never resets a destination's state.
        content
            .safeAreaBar(edge: .bottom, spacing: 0) {
                if isPresented {
                    GlassTabBar(selection: $selection, axis: .horizontal)
                        .frame(maxWidth: 460)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
    }
}
