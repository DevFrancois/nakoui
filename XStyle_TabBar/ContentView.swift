//
//  ContentView.swift
//  XStyle_TabBar
//
//  Created by Francois Chaillou on 28/07/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private let mainTitle = "Nako"

    /// The Home pager. Only the views drawing it read it, so paging never
    /// redraws this view and its navigation stack.
    @State private var pager = PagerState()
    /// The bottom tab bar's selection.
    @State private var rootTab: RootTab = .home
    /// Owned here, not by the Scan tab, so passes of this body never
    /// construct a throwaway one.
    @State private var scanner = ScannerModel()
    /// The Scan tab's sheet and its debug settings, owned here for the same
    /// reason.
    @State private var scannerSheet = SheetController(initialDetent: .hidden)
    @State private var sheetSettings = SheetSettings()
    /// The products scanned, kept across launches.
    @State private var scanHistory = ScanHistory()
    /// Holds sidebar routes and articles, so either can be pushed.
    @State private var navigation = RootNavigation()
    @State private var isSidebarExpanded = false
    @State private var pendingSidebarOpen = false
    @State private var revealingRoute: SidebarRoute?
    @State private var isRouteContentVisible = true
    /// Follows the shown page's scroll. Only the menu reads it, so its
    /// per-frame changes redraw the menu alone.
    @State private var logoCollapse = LogoCollapse()
    /// Shared by the For you page and the side menu's debug reset.
    @State private var taskList = ForYouTaskList()
    /// Bumped to move VoiceOver to the menu button. A value, unlike focus
    /// state, reaches the button inside the Home tab's own host.
    @State private var menuButtonFocusRequest = 0
    /// Shared by the feed images and article zoom transitions.
    @Namespace private var zoomNamespace

    var body: some View {
        if AppFeatures.sideMenuEnabled {
            contentWithSidebar
        } else {
            appContent
        }
    }

    private var contentWithSidebar: some View {
        CustomSideMenu(
            // Home only: the other tabs, and anything pushed, have no side menu.
            isEnabled: rootTab == .home && navigation.path.isEmpty && revealingRoute == nil,
            canBeginOpening: canBeginSidebarOpening,
            canOpenFromAnywhere: canOpenSidebarFromAnywhere,
            isExpanded: $isSidebarExpanded,
            onDismissed: sidebarDidDismiss
        ) { _ in
            SideBar(onSelect: selectSidebarRoute) {
                SideMenuQuickActions(onOpen: openQuickAction)
            } footer: {
                #if DEBUG
                SideMenuDebugControls(onResetTasks: resetTasks)
                #endif
            }
            .disabled(revealingRoute != nil)
        } content: { _ in
            appContent
        }
    }

    /// Keep the same navigation, tab and page ownership in either menu mode.
    private var appContent: some View {
        NavigationStack(path: $navigation.path) {
            // Inside the stack, so articles, quizzes and sidebar pages
            // cover the tab bar when pushed.
            RootTabContent(selection: $rootTab, scanner: scanner, scannerSheet: scannerSheet,
                           sheetSettings: sheetSettings, scanHistory: scanHistory,
                           isTabBarVisible: navigation.path.isEmpty) {
                HomeRootView(
                    title: mainTitle,
                    pager: pager,
                    logoCollapse: logoCollapse,
                    taskList: taskList,
                    zoomNamespace: zoomNamespace,
                    onSelect: selectTab,
                    onUpdate: openPendingSidebar
                ) {
                    if AppFeatures.sideMenuEnabled {
                        TopMenuIconButton(title: "Open menu", systemImage: "line.3.horizontal", action: openMenu)
                            .accessibilityIdentifier("navigation.openMenu")
                            .modifier(MenuButtonFocus(request: menuButtonFocusRequest))
                    }
                }
            }
            .onChange(of: rootTab, rootTabDidChange)
            .onChange(of: voiceOverEnabled, voiceOverDidChange)
            .navigationTitle(mainTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: SidebarRoute.self) { route in
                SidebarRouteView(route: route)
                    .onAppear { revealSidebarRoute(route) }
            }
            .navigationDestination(for: Article.self) { article in
                ArticleView(article: article, namespace: zoomNamespace)
            }
            .navigationDestination(for: QuizKind.self) { kind in
                QuizDestination(kind: kind)
            }
        }
        .environment(\.rootNavigation, navigation)
        .opacity(isRouteContentVisible ? 1 : 0)
    }

    /// Asked as a touch begins, outside the pager (the top menu). Touches on
    /// the pager are judged against the live scroll view by the gesture itself.
    private func canOpenSidebarFromAnywhere() -> Bool {
        AppFeatures.sideMenuEnabled && pager.isAtFirstPage
    }

    /// Asked as a touch begins. Pager position and motion are checked by the
    /// gesture against the live scroll view; the pager's recorded phase and
    /// geometry can lag behind it.
    private func canBeginSidebarOpening() -> Bool {
        AppFeatures.sideMenuEnabled && navigation.path.isEmpty && revealingRoute == nil && pager.tapTransition == nil && pager.pendingTab == nil
    }

    private func openPendingSidebar() {
        guard AppFeatures.sideMenuEnabled, pendingSidebarOpen,
              rootTab == .home, navigation.path.isEmpty, revealingRoute == nil,
              pager.isAtRest else { return }
        pendingSidebarOpen = false
        isSidebarExpanded = true
    }

    private func selectSidebarRoute(_ route: SidebarRoute) {
        guard revealingRoute == nil, navigation.path.isEmpty else { return }
        // Replace the contents while the foreground is still shifted right.
        // Suppress only the push; the stack still owns Back and interactive pop.
        withoutAnimation {
            revealingRoute = route
            isRouteContentVisible = false
            navigation.path = NavigationPath([route])
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
        if navigation.path.isEmpty && logoCollapse.isShown {
            menuButtonFocusRequest += 1
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
        guard AppFeatures.sideMenuEnabled else { return }
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

    /// Bookmarks opens like its route below; Likes closes the menu onto the
    /// Likes page.
    private func openQuickAction(_ action: SideMenuQuickAction) {
        switch action {
        case .bookmarks:
            selectSidebarRoute(.bookmarks)
        case .likes:
            isSidebarExpanded = false
            pager.select(.likes)
        }
    }

    private func selectTab(_ tab: AppTab) {
        guard !pendingSidebarOpen else { return }
        pager.select(tab)
        openPendingSidebar()
    }
}

/// Owns the focus state in the hosting tree that draws the button, since
/// accessibility focus does not cross hosting controllers.
private struct MenuButtonFocus: ViewModifier {
    let request: Int
    @AccessibilityFocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityFocused($isFocused)
            .onChange(of: request) { isFocused = true }
    }
}

#Preview {
    ContentView()
}
