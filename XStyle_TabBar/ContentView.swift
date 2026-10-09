//
//  ContentView.swift
//  XStyle_TabBar
//
//  Created by Francois Chaillou on 28/07/26.
//

import SwiftUI

struct ContentView: View {
    /// The Home pager. Only the views drawing it read it, so paging never
    /// redraws this view and its navigation stack.
    @State private var pager = PagerState()
    /// The bottom tab bar's selection.
    @State private var rootTab: RootTab = .home
    /// Owned here, not by the Scan tab, so passes of this body never
    /// construct a throwaway one.
    @State private var scanner = ScannerModel()
    /// Holds sidebar routes and articles, so either can be pushed.
    @State private var navigationPath = NavigationPath()
    @State private var isSidebarExpanded = false
    @State private var pendingSidebarOpen = false
    @State private var revealingRoute: SidebarRoute?
    @State private var isRouteContentVisible = true
    /// Follows the shown page's scroll. Only the menu reads it, so its
    /// per-frame changes redraw the menu alone.
    @State private var logoCollapse = LogoCollapse()
    /// The safe-area top without the menu, which pages add the menu to.
    @State private var statusBarInset: CGFloat = 0
    /// Shared by the For you page and the side menu's debug reset.
    @State private var taskList = ForYouTaskList()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @AccessibilityFocusState private var isMenuButtonFocused: Bool
    /// Shared by the zoom transitions into articles and quizzes.
    @Namespace private var zoomNamespace
    private let mainTitle = "Nako"

    var body: some View {
        CustomSideMenu(
            // Home only: the other tabs, and anything pushed, have no side menu.
            isEnabled: rootTab == .home && navigationPath.isEmpty && revealingRoute == nil,
            canBeginOpening: canBeginSidebarOpening,
            canOpenFromAnywhere: canOpenSidebarFromAnywhere,
            isExpanded: $isSidebarExpanded,
            onDismissed: sidebarDidDismiss
        ) { _ in
            SideBar(onSelect: selectSidebarRoute) {
                #if DEBUG
                ResetTasksDebugButton(action: resetTasks)
                #endif
            }
            .disabled(revealingRoute != nil)
        } content: { _ in
            NavigationStack(path: $navigationPath) {
                // Inside the stack, so articles, quizzes and sidebar pages
                // cover the tab bar when pushed.
                TabView(selection: $rootTab) {
                    Tab(value: RootTab.home) {
                        HomePager(
                            pager: pager,
                            logoCollapse: logoCollapse,
                            taskList: taskList,
                            topInset: statusBarInset + TopMenuMetrics.expandedHeight,
                            zoomNamespace: zoomNamespace,
                            onUpdate: openPendingSidebar
                        )
                            .safeAreaBar(edge: .top, spacing: 0) {
                                HomeTopMenu(
                                    title: mainTitle,
                                    pager: pager,
                                    logoCollapse: logoCollapse,
                                    onSelect: selectTab
                                ) {
                                    TopMenuIconButton(title: "Open menu", systemImage: "line.3.horizontal", action: openMenu)
                                        .accessibilityIdentifier("navigation.openMenu")
                                        .accessibilityFocused($isMenuButtonFocused)
                                }
                            }
                            .background {
                                HomeBackground(pager: pager)
                            }
                    } label: {
                        Label(RootTab.home.title, systemImage: RootTab.home.symbol)
                    }

                    Tab(value: RootTab.scanner) {
                        ScannerView(model: scanner, isActive: rootTab == .scanner)
                    } label: {
                        Label(RootTab.scanner.title, systemImage: RootTab.scanner.symbol)
                    }

                    ForEach(RootTab.placeholderTabs, id: \.self) { tab in
                        Tab(value: tab) {
                            RootTabPlaceholder(tab: tab)
                        } label: {
                            Label(tab.title, systemImage: tab.symbol)
                        }
                    }

                    Tab(value: RootTab.search, role: .search) {
                        RootTabPlaceholder(tab: .search)
                    } label: {
                        Label(RootTab.search.title, systemImage: RootTab.search.symbol)
                    }
                }
                .onChange(of: rootTab, rootTabDidChange)
                .onChange(of: voiceOverEnabled, voiceOverDidChange)
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
                .navigationDestination(for: Article.self) { article in
                    ArticleView(article: article, namespace: zoomNamespace)
                }
                .navigationDestination(for: QuizKind.self) { kind in
                    QuizDestination(kind: kind, namespace: zoomNamespace)
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

    /// Asked as a touch begins, outside the pager (the top menu). Touches on
    /// the pager are judged against the live scroll view by the gesture itself.
    private func canOpenSidebarFromAnywhere() -> Bool {
        pager.isAtFirstPage
    }

    /// Asked as a touch begins. Pager position and motion are checked by the
    /// gesture against the live scroll view; the pager's recorded phase and
    /// geometry can lag behind it.
    private func canBeginSidebarOpening() -> Bool {
        navigationPath.isEmpty && revealingRoute == nil && pager.tapTransition == nil && pager.pendingTab == nil
    }

    private func openPendingSidebar() {
        guard pendingSidebarOpen, rootTab == .home, navigationPath.isEmpty, revealingRoute == nil,
              pager.isAtRest else { return }
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
            navigationPath = NavigationPath([route])
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
        if navigationPath.isEmpty && logoCollapse.isShown {
            isMenuButtonFocused = true
        }
    }

    #if DEBUG
    /// Brings the For you tasks back and closes the menu, so the stack is
    /// seen refilling.
    private func resetTasks() {
        withAnimation(TaskMetrics.stackAnimation) {
            taskList.reset()
            isSidebarExpanded = false
        }
    }
    #endif

    private func openMenu() {
        pendingSidebarOpen = true
        openPendingSidebar()
    }

    /// A menu tap still waiting for the pager to settle is dropped on leaving
    /// Home, so it can't open the menu later or keep blocking chip taps.
    private func rootTabDidChange() {
        if rootTab != .home {
            pendingSidebarOpen = false
        }
    }

    /// VoiceOver needs the menu button, so the logo row stays put while it runs.
    private func voiceOverDidChange() {
        if voiceOverEnabled {
            logoCollapse.reveal()
        }
    }

    private func selectTab(_ tab: AppTab) {
        guard !pendingSidebarOpen else { return }
        pager.select(tab)
        openPendingSidebar()
    }
}

#Preview {
    ContentView()
}
