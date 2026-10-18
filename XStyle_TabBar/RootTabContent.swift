import SwiftUI

/// Root destinations share one selection while the enclosing stack owns pushes.
struct RootTabContent<Home: View>: View {
    @Binding var selection: RootTab
    let scanner: ScannerModel
    var isTabBarVisible = true
    @ViewBuilder let home: Home

    var body: some View {
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
                RootTabPlaceholder(tab: .search)
                    .toolbarVisibility(.hidden, for: .tabBar)
            } label: {
                Label(RootTab.search.title, systemImage: RootTab.search.symbol)
            }
        }
        .tabViewStyle(.tabBarOnly)
        .toolbar {
            if isTabBarVisible {
                GlassTabBarToolbar(selection: $selection)
            }
        }
    }
}
