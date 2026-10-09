//
//  ContentView.swift
//  XStyle_TabBar
//
//  Created by Francois Chaillou on 28/07/26.
//

import SwiftUI

struct ContentView: View {
    @State private var scrollProgress: CGFloat = 0
    @State private var scrollPosition: ScrollPosition = .init(idType: AppTab.self)
    @State private var pagerGeometry = PagerGeometry()
    @State private var scrollPhase: ScrollPhase = .idle
    @State private var selectedTab: AppTab = .bookmarks
    @State private var tapTransition: TabTransition?
    @State private var pendingTab: AppTab?
    @State private var navigationPath: [SidebarRoute] = []
    @State private var isSidebarExpanded = false
    @State private var pendingSidebarOpen = false
    @State private var revealingRoute: SidebarRoute?
    @State private var isRouteContentVisible = true
    @State private var isLogoVisible = true
    /// The safe-area top without the menu, which pages add the menu to.
    @State private var statusBarInset: CGFloat = 0
    /// The tapped tab being reached. The chips show it at once and ignore the
    /// pager, so the skipped tabs never light up.
    @State private var lockedTab: AppTab?
    @State private var hapticPage = 0
    @State private var hapticTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @AccessibilityFocusState private var isMenuButtonFocused: Bool
    private let mainTitle = "Nako"

    var body: some View {
        CustomSideMenu(
            isEnabled: navigationPath.isEmpty && revealingRoute == nil,
            canBeginOpening: canBeginSidebarOpening,
            canOpenFromAnywhere: canOpenSidebarFromAnywhere,
            isExpanded: $isSidebarExpanded,
            onDismissed: sidebarDidDismiss
        ) { _ in
            SideBar(onSelect: selectSidebarRoute)
                .disabled(revealingRoute != nil)
        } content: { _ in
            NavigationStack(path: $navigationPath) {
                historyContent
                    .safeAreaBar(edge: .top, spacing: 0) {
                        TopMenuBar(
                            title: mainTitle,
                            selection: chipSelection,
                            selectedTab: lockedTab ?? selectedTab,
                            isSelectionLocked: lockedTab != nil,
                            isLogoVisible: isLogoVisible,
                            onSelect: selectTab
                        ) {
                            Button(action: openMenu) {
                                Label("Open menu", systemImage: "line.3.horizontal")
                                    .labelStyle(.iconOnly)
                                    .frame(width: TopMenuMetrics.minimumTapSize, height: TopMenuMetrics.minimumTapSize)
                                    .contentShape(.rect)
                            }
                            .accessibilityIdentifier("navigation.openMenu")
                            .accessibilityFocused($isMenuButtonFocused)
                        } trailing: {
                            Button(action: search) {
                                Label("Search", systemImage: "magnifyingglass")
                                    .labelStyle(.iconOnly)
                                    .frame(width: TopMenuMetrics.minimumTapSize, height: TopMenuMetrics.minimumTapSize)
                                    .contentShape(.rect)
                            }
                        }
                    }
                    .background {
                        AmbientGradientBackground(palettes: gradientPalettes, progress: gradientProgress)
                    }
                    // VoiceOver needs the menu button, so the logo row stays put.
                    .onChange(of: voiceOverEnabled) { _, isEnabled in
                        if isEnabled {
                            isLogoVisible = true
                        }
                    }
                    .navigationTitle(mainTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarVisibility(.hidden, for: .navigationBar)
                    .navigationDestination(for: SidebarRoute.self) { route in
                        Text("Hello World")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.background)
                            .navigationTitle(route.title)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbarVisibility(.visible, for: .navigationBar)
                            .accessibilityIdentifier("destination.\(route.rawValue)")
                            .onAppear { revealSidebarRoute(route) }
                    }
            }
            .opacity(isRouteContentVisible ? 1 : 0)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.safeAreaInsets.top
            } action: { inset in
                statusBarInset = inset
            }
        }
    }

    private var historyContent: some View {
        ScrollView(.horizontal) {
            // Distant destinations must exist before they slide into view.
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.rawValue) { tab in
                    let isVisible = tapTransition.map {
                        tab == $0.source || tab == $0.destination
                    } ?? true
                    let offsetFactor = tapTransition?.offsetFactor ?? 0

                    FeedPage(tab: tab, topInset: statusBarInset + TopMenuMetrics.expandedHeight)
                        .onScrollGeometryChange(for: CGFloat.self) { geometry in
                            geometry.contentOffset.y + geometry.contentInsets.top
                        } action: { oldOffset, newOffset in
                            pageDidScroll(tab, from: oldOffset, to: newOffset)
                        }
                        .containerRelativeFrame(.horizontal)
                        .visualEffect { content, geometry in
                            // Compress a multi-tab scroll into one page of visual travel.
                            content.offset(x: geometry.frame(in: .scrollView(axis: .horizontal)).minX * offsetFactor)
                        }
                        .opacity(isVisible ? 1 : 0)
                        .animation(nil, value: isVisible)
                        .animation(nil, value: offsetFactor)
                        // At rest, only the shown page is reachable with VoiceOver.
                        .accessibilityHidden(!isVisible || (tapTransition == nil && tab != selectedTab))
                        .accessibilityIdentifier("history.page.\(tab.rawValue)")
                        .id(tab)
                }
            }
            .scrollTargetLayout()
        }
        // Pages keep their vertical indicators.
        .scrollIndicators(.hidden, axes: .horizontal)
        // The top menu's safe-area bar extends this scroll view's edge effect,
        // not the nested pages', so the soft edge under the menu lives here.
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollTargetBehavior(.paging)
        .scrollPosition($scrollPosition)
        .allowsHitTesting(tapTransition == nil)
        .onScrollGeometryChange(for: PagerGeometry.self) {
            PagerGeometry($0)
        } action: { _, newValue in
            updatePager(newValue)
        }
        .onScrollPhaseChange { oldPhase, newPhase, context in
            scrollPhase = newPhase
            updatePager(
                PagerGeometry(context.geometry),
                didFinishScrolling: oldPhase != .idle && newPhase == .idle
            )
        }
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.7), trigger: hapticTick)
    }

    private var chipSelection: CGFloat {
        lockedTab.map { CGFloat($0.index) } ?? scrollProgress
    }

    /// During a tap transition only the two endpoints' palettes blend, so a
    /// distant tab is reached without passing through the skipped tabs' colors.
    private var gradientPalettes: [AmbientGradientPalette] {
        guard let transition = tapTransition else { return AppTab.allCases.map(\.palette) }
        return [transition.source.palette, transition.destination.palette]
    }

    private var gradientProgress: CGFloat {
        guard let transition = tapTransition else { return scrollProgress }
        let source = CGFloat(transition.source.index)
        let destination = CGFloat(transition.destination.index)
        return min(max((scrollProgress - source) / (destination - source), 0), 1)
    }

    private var canOpenSidebarFromAnywhere: Bool {
        // Used for touches outside the pager (the top menu). Touches on the
        // pager are judged against the live scroll view by the gesture itself.
        pagerGeometry.width > 0 && pagerGeometry.offset <= 0.5
    }

    private var canBeginSidebarOpening: Bool {
        // Pager position and motion are checked by the gesture against the live
        // scroll view; SwiftUI's scrollPhase/pagerGeometry can lag behind it.
        navigationPath.isEmpty && revealingRoute == nil && tapTransition == nil && pendingTab == nil
    }

    private func openPendingSidebar() {
        guard pendingSidebarOpen, navigationPath.isEmpty, revealingRoute == nil,
              scrollPhase == .idle, tapTransition == nil, pendingTab == nil else { return }
        pendingSidebarOpen = false
        isSidebarExpanded = true
    }

    private func selectSidebarRoute(_ route: SidebarRoute) {
        guard revealingRoute == nil, navigationPath.isEmpty else { return }
        // Replace the contents while the foreground is still shifted right.
        // Suppress only the push; the stack still owns Back and interactive pop.
        withoutAnimation {
            revealingRoute = route
            isRouteContentVisible = false
            navigationPath = [route]
        }
    }

    private func revealSidebarRoute(_ route: SidebarRoute) {
        guard revealingRoute == route, !isRouteContentVisible else { return }
        // Destination appearance is the hand-off: fade it in as the same
        // foreground surface closes over the sidebar, with no timed delay.
        var transaction = Transaction(animation: reduceMotion ? nil : .easeInOut(duration: 0.22))
        transaction.disablesAnimations = reduceMotion
        withTransaction(transaction) {
            isRouteContentVisible = true
            isSidebarExpanded = false
        }
    }

    private func sidebarDidDismiss() {
        revealingRoute = nil
        // A collapsed logo row hides the menu button from VoiceOver.
        if navigationPath.isEmpty && isLogoVisible {
            isMenuButtonFocused = true
        }
    }

    private func openMenu() {
        pendingSidebarOpen = true
        openPendingSidebar()
    }

    /// Search isn't built yet.
    private func search() {}

    private func selectTab(_ tab: AppTab) {
        guard !pendingSidebarOpen else { return }
        pendingTab = tab
        startPendingTransition()
    }

    /// Only the shown page drives the logo row, from the change since its
    /// previous scroll update. Page switches leave the row as it is.
    private func pageDidScroll(_ tab: AppTab, from oldOffset: CGFloat, to newOffset: CGFloat) {
        guard tab == selectedTab, tapTransition == nil, !voiceOverEnabled,
              let visible = LogoVisibilityRule.visibility(previousOffset: oldOffset, offset: newOffset),
              visible != isLogoVisible else { return }
        // Unanimated: the menu animates its chips and logo row itself, while its
        // footprint, and the safe area the pages sit in, change in one step.
        // An animated safe area would move the pages' offsets mid-scroll and
        // feed back into this rule.
        isLogoVisible = visible
    }

    private func startPendingTransition() {
        defer { openPendingSidebar() }
        // A tap during a swipe or another tap animation replaces the queued choice.
        guard scrollPhase == .idle, tapTransition == nil,
              pagerGeometry.width > 0, let destination = pendingTab else { return }

        pendingTab = nil
        guard destination != selectedTab else { return }

        withoutAnimation {
            tapTransition = TabTransition(source: selectedTab, destination: destination)
        }
        // A transaction of its own: the chip highlight fades straight to the
        // destination, which withoutAnimation would turn into a jump.
        withAnimation(TopMenuMetrics.selectionAnimation) {
            lockedTab = destination
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            scrollPosition.scrollTo(id: destination, anchor: .leading)
        }
    }

    private func updatePager(_ geometry: PagerGeometry, didFinishScrolling: Bool = false) {
        let widthChanged = pagerGeometry.width != geometry.width
        pagerGeometry = geometry
        guard geometry.width > 0 else { return }

        // Continuous progress, including skipped tabs during a tap transition.
        scrollProgress = geometry.progress
        updateHapticPage(geometry.progress)

        if let transition = tapTransition {
            let destinationIndex = AppTab.allCases.firstIndex(of: transition.destination) ?? 0
            let reachedDestination = abs(geometry.offset - CGFloat(destinationIndex) * geometry.width) < 0.5

            if reachedDestination && scrollPhase == .idle {
                withoutAnimation {
                    selectedTab = transition.destination
                    tapTransition = nil
                    lockedTab = nil
                }
                startPendingTransition()
            } else if !reachedDestination && (widthChanged || didFinishScrolling) {
                // Keep other pages hidden until an interrupted/resized scroll reaches its target.
                withoutAnimation {
                    scrollPosition.scrollTo(id: transition.destination, anchor: .leading)
                }
            }
        } else if scrollPhase == .idle {
            let index = min(max(Int(geometry.progress.rounded()), 0), AppTab.allCases.count - 1)
            selectedTab = AppTab.allCases[index]
            startPendingTransition()
        }
    }

    /// One tick each time the pager passes a page's midpoint. A tap transition
    /// ticks once, at its compressed midpoint, not once per skipped page.
    private func updateHapticPage(_ progress: CGFloat) {
        let page: Int
        if let transition = tapTransition {
            let source = transition.source.index
            let destination = transition.destination.index
            page = abs(progress - CGFloat(source)) <= abs(progress - CGFloat(destination)) ? source : destination
        } else {
            page = min(max(Int(progress.rounded()), 0), AppTab.allCases.count - 1)
        }
        guard page != hapticPage else { return }

        // Programmatic scrolls, such as the side menu's snap, move silently.
        if tapTransition != nil || scrollPhase == .interacting || scrollPhase == .decelerating {
            hapticTick += 1
        }
        hapticPage = page
    }

    private func withoutAnimation(_ action: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, action)
    }
}

private struct TabTransition {
    let source: AppTab
    let destination: AppTab

    var offsetFactor: CGFloat {
        let sourceIndex = AppTab.allCases.firstIndex(of: source) ?? 0
        let destinationIndex = AppTab.allCases.firstIndex(of: destination) ?? 0
        let distance = max(abs(destinationIndex - sourceIndex), 1)
        return 1 / CGFloat(distance) - 1
    }
}

private struct PagerGeometry: Equatable {
    var offset: CGFloat = 0
    var width: CGFloat = 0

    init() {}

    init(_ geometry: ScrollGeometry) {
        offset = geometry.contentOffset.x + geometry.contentInsets.leading
        width = geometry.containerSize.width
    }

    var progress: CGFloat {
        width > 0 ? offset / width : 0
    }
}

#Preview {
    ContentView()
}
