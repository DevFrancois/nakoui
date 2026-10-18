import SwiftUI

/// Root destinations share one selection while the enclosing stack owns pushes.
struct RootTabContent<Home: View>: View {
    @Binding var selection: RootTab
    var navigationPathIsEmpty = true
    let scanner: ScannerModel
    @ViewBuilder let home: Home
    @State private var reflections = TabBarReflectionSource()
    #if DEBUG
    @State private var reflectionTuning = TabBarReflectionTuningStore()
    @Environment(\.scenePhase) private var scenePhase
    #endif

    var body: some View {
        // Preserve destination state and lifecycle, while each destination
        // asks its containing TabView to hide the stock bar.
        TabView(selection: $selection) {
            Tab(value: RootTab.home) {
                home
                    .toolbarVisibility(.hidden, for: .tabBar)
            } label: {
                Label(RootTab.home.title, systemImage: RootTab.home.symbol)
            }

            Tab(value: RootTab.scanner) {
                ScannerView(model: scanner, isActive: selection == .scanner)
                    .toolbarVisibility(.hidden, for: .tabBar)
            } label: {
                Label(RootTab.scanner.title, systemImage: RootTab.scanner.symbol)
            }

            ForEach(RootTab.placeholderTabs, id: \.self) { tab in
                Tab(value: tab) {
                    RootTabPlaceholder(tab: tab)
                        .toolbarVisibility(.hidden, for: .tabBar)
                } label: {
                    Label(tab.title, systemImage: tab.symbol)
                }
            }

            Tab(value: RootTab.search) {
                Group {
                    #if DEBUG
                    CarouselDebugView(isActive: selection == .search)
                    #else
                    RootTabPlaceholder(tab: .search)
                    #endif
                }
                .toolbarVisibility(.hidden, for: .tabBar)
            } label: {
                Label(RootTab.search.title, systemImage: RootTab.search.symbol)
            }
        }
        // Inside the navigation root, so pushed pages cover the custom menu.
        .modifier(GlassTabBarInset(selection: $selection))
        .background {
            TabBarRootLifecycleObserver(source: reflections, pathIsEmpty: navigationPathIsEmpty)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .environment(\.tabBarReflectionSource, reflections)
        .onChange(of: selection) { reflections.clear() }
        #if DEBUG
        .environment(\.tabBarReflectionTuning, reflectionTuning)
        .onChange(of: scenePhase) {
            if scenePhase != .active { reflectionTuning.flush() }
        }
        #endif
    }
}
