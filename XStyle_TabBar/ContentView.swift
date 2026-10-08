//
//  ContentView.swift
//  XStyle_TabBar
//
//  Created by Balaji Venkatesh on 28/07/26.
//

import SwiftUI

/// Sample Tab Items
enum AppTab: String, XStyleTabItem {
    case bookmarks = "Bookmarks"
    case videos = "Videos"
    case articles = "Articles"
    case likes = "Likes"
    
    var title: String {
        rawValue
    }
    
    var symbol: String {
        switch self {
        case .bookmarks:
            return "bookmark"
        case .videos:
            return "play.square.stack"
        case .articles:
            return "long.text.page.and.pencil"
        case .likes:
            return "heart"
        }
    }
}

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var isMenuButtonFocused: Bool
    private let mainTitle = "Home"

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
                VStack {
                    header
                    historyContent
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
        }
    }

    private var header: some View {
        HStack {
            Button {
                pendingSidebarOpen = true
                openPendingSidebar()
            } label: {
                Image(systemName: "line.3.horizontal")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Open menu")
            .accessibilityIdentifier("navigation.openMenu")
            .accessibilityFocused($isMenuButtonFocused)

            Spacer(minLength: 0)
            
            Button {
                
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Search")
        }
        .font(.title3)
        .overlay {
            Text(mainTitle)
                .fontWeight(.semibold)
                .allowsHitTesting(false)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("navigation.mainTitle")
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 15)
        .padding(.vertical, 3)
    }

    private var historyContent: some View {
        VStack {
            XStyleTabBar<AppTab>(progress: scrollProgress) { tab in
                guard !pendingSidebarOpen else { return }
                pendingTab = tab
                startPendingTransition()
            }
            .padding(.horizontal, 25)
            .background(alignment: .bottom) {
                Rectangle()
                    .fill(.gray.tertiary)
                    .frame(height: 1)
            }
            
            ScrollView(.horizontal) {
                // Distant destinations must exist before they slide into view.
                HStack(spacing: 0) {
                    ForEach(AppTab.allCases, id: \.rawValue) { tab in
                        let isVisible = tapTransition.map {
                            tab == $0.source || tab == $0.destination
                        } ?? true
                        let offsetFactor = tapTransition?.offsetFactor ?? 0

                        Text(tab.rawValue)
                            .containerRelativeFrame(.horizontal)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .padding(.top, 100)
                            .visualEffect { content, geometry in
                                // Compress a multi-tab scroll into one page of visual travel.
                                content.offset(x: geometry.frame(in: .scrollView(axis: .horizontal)).minX * offsetFactor)
                            }
                            .opacity(isVisible ? 1 : 0)
                            .animation(nil, value: isVisible)
                            .animation(nil, value: offsetFactor)
                            .accessibilityHidden(!isVisible)
                            .accessibilityIdentifier("history.page.\(tab.rawValue)")
                            .id(tab)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition($scrollPosition)
            .clipped()
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
        }
    }

    private var canOpenSidebarFromAnywhere: Bool {
        // Used for touches outside the pager (header, tab bar). Touches on the
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
        if navigationPath.isEmpty {
            isMenuButtonFocused = true
        }
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
        withAnimation(.easeInOut(duration: 0.25)) {
            scrollPosition.scrollTo(id: destination, anchor: .leading)
        }
    }

    private func updatePager(_ geometry: PagerGeometry, didFinishScrolling: Bool = false) {
        let widthChanged = pagerGeometry.width != geometry.width
        pagerGeometry = geometry
        guard geometry.width > 0 else { return }

        // Keep the tab bar's original continuous progress, including skipped tabs.
        scrollProgress = geometry.progress

        if let transition = tapTransition {
            let destinationIndex = AppTab.allCases.firstIndex(of: transition.destination) ?? 0
            let reachedDestination = abs(geometry.offset - CGFloat(destinationIndex) * geometry.width) < 0.5

            if reachedDestination && scrollPhase == .idle {
                withoutAnimation {
                    selectedTab = transition.destination
                    tapTransition = nil
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
