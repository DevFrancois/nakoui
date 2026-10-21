import SwiftUI

/// The Home tab's pages, side by side in a paging scroll view. The shown
/// page's vertical scroll drives the logo row.
struct HomePager: View {
    @Bindable var pager: PagerState
    let logoCollapse: LogoCollapse
    let taskList: ForYouTaskList
    let zoomNamespace: Namespace.ID
    /// Called whenever the pager's state moves on, so a side menu waiting
    /// for it to come to rest can open.
    let onUpdate: () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            // Capture the rail's insets before expanding the paging viewport.
            GeometryReader { viewport in
                pages(width: viewport.size.width, horizontalInsets: geometry.safeAreaInsets)
            }
            .ignoresSafeArea(.container, edges: .horizontal)
        }
        .onChange(of: reduceMotion, initial: true) {
            pager.setReduceMotion(reduceMotion)
        }
    }

    private func pages(width: CGFloat, horizontalInsets: EdgeInsets) -> some View {
        ScrollView(.horizontal) {
            // Distant destinations must exist before they slide into view.
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.rawValue) { tab in
                    let isVisible = pager.tapTransition.map {
                        tab == $0.source || tab == $0.destination
                    } ?? true
                    let offsetFactor = pager.tapTransition?.offsetFactor ?? 0

                    FeedPage(tab: tab, zoomNamespace: zoomNamespace, taskList: taskList)
                        .contentMargins(.leading, horizontalInsets.leading, for: .scrollContent)
                        .contentMargins(.trailing, horizontalInsets.trailing, for: .scrollContent)
                        .contentMargins(.trailing, horizontalInsets.trailing, for: .scrollIndicators)
                        .onScrollGeometryChange(for: PageScrollPosition.self) { geometry in
                            PageScrollPosition(geometry)
                        } action: { oldPosition, newPosition in
                            pageDidScroll(tab, from: oldPosition, to: newPosition)
                        }
                        .onScrollPhaseChange { _, newPhase in
                            pageScrollPhaseDidChange(tab, to: newPhase)
                        }
                        // Size in the current layout pass. A stored scroll width
                        // can still describe the open display when Duo closes.
                        .frame(width: width)
                        .background { HomePageBackground(tab: tab) }
                        .visualEffect { content, geometry in
                            // Compress a multi-tab scroll into one page of visual travel.
                            content.offset(x: geometry.frame(in: .scrollView(axis: .horizontal)).minX * offsetFactor)
                        }
                        .opacity(isVisible ? 1 : 0)
                        .animation(nil, value: isVisible)
                        .animation(nil, value: offsetFactor)
                        // At rest, only the shown page is reachable with VoiceOver.
                        .accessibilityHidden(!isVisible || (pager.tapTransition == nil && tab != pager.selectedTab))
                        .accessibilityIdentifier("history.page.\(tab.rawValue)")
                        .id(tab)
                }
            }
            .scrollTargetLayout()
        }
        // Pages keep their vertical indicators.
        .scrollIndicators(.hidden, axes: .horizontal)
        // Keep content clear beneath the top menu's safe-area bar. The pages
        // hide their own bottom effect; the pager's, under the tab bar, would
        // still frost whatever slides there on the Scan tab, like its sheet.
        .scrollEdgeEffectHidden(true, for: [.top, .bottom])
        .scrollTargetBehavior(HomePagingBehavior(
            gestureID: pager.gestureID,
            pageCount: AppTab.allCases.count,
            onTarget: pager.receive
        ))
        .scrollPosition($pager.scrollPosition)
        .allowsHitTesting(pager.tapTransition == nil)
        .onScrollGeometryChange(for: PagerGeometry.self) {
            PagerGeometry($0)
        } action: { _, newValue in
            pager.update(newValue)
            onUpdate()
        }
        .onScrollPhaseChange { oldPhase, newPhase, context in
            pager.scrollPhaseDidChange(from: oldPhase, to: newPhase, geometry: PagerGeometry(context.geometry))
            onUpdate()
        }
        .onChange(of: pager.selectedTab) {
            logoCollapse.selectedPageDidChange(to: pager.selectedTab)
        }
    }

    /// Only the shown page moves the logo row.
    private func pageDidScroll(_ tab: AppTab, from oldPosition: PageScrollPosition, to newPosition: PageScrollPosition) {
        logoCollapse.record(newPosition, for: tab)
        guard tab == pager.selectedTab, pager.tapTransition == nil, !voiceOverEnabled else { return }
        logoCollapse.follow(from: oldPosition, to: newPosition)
    }

    /// The logo row follows only the user scrolling the shown page, and
    /// settles once it stops.
    private func pageScrollPhaseDidChange(_ tab: AppTab, to phase: ScrollPhase) {
        guard tab == pager.selectedTab else { return }
        logoCollapse.scrollPhaseDidChange(to: phase)
    }
}
