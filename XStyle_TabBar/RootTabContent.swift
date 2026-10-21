import SwiftUI
import UIKit

/// Root destinations share one selection while the enclosing stack owns pushes.
struct RootTabContent<Home: View>: View {
    @Binding var selection: RootTab
    let scanner: ScannerModel
    let scannerSheet: SheetController
    let sheetSettings: SheetSettings
    var isTabBarVisible = true
    @ViewBuilder let home: Home
    @State private var layoutAxis: NSLayoutConstraint.Axis = .horizontal
    /// The window's bottom edge, in global space: how far the tab bar slides
    /// to leave the screen.
    @State private var windowBottom: CGFloat = 0
    /// The tab bar's top edge, in global space, where it last rested.
    @State private var tabBarTop: CGFloat?

    var body: some View {
        let hidesTabBar = GlassTabBar.hidesForScanResult(
            selection: selection, hasResult: scanner.scannedCode != nil, layoutAxis: layoutAxis
        )
        GeometryReader { geometry in
            RootTabPages(selection: selection, scanner: scanner, scannerSheet: scannerSheet,
                         sheetSettings: sheetSettings, layoutAxis: layoutAxis,
                         isVisible: isTabBarVisible, safeAreaInsets: geometry.safeAreaInsets,
                         scannerTabBarClearance: tabBarClearance(beyond: geometry.safeAreaInsets.bottom), home: home)
                // Keep the paging viewport full width while explicitly carrying
                // the outer stack's toolbar/rail insets into UIKit's children.
                .ignoresSafeArea(.container)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).maxY + proxy.safeAreaInsets.bottom
        } action: { windowBottom in
            self.windowBottom = windowBottom
        }
        // Let the navigation container coordinate the root toolbar's visibility
        // with pushed destinations, including interactive dismissal.
        .toolbar {
            GlassTabBarToolbar(
                selection: $selection, layoutAxis: $layoutAxis,
                isHidden: hidesTabBar,
                windowBottom: windowBottom,
                top: $tabBarTop
            )
        }
        // The bar leaves with its toolbar while a scan result shows: a toolbar
        // left in place keeps taking the touches in its band, which the
        // result's sheet needs.
        .toolbarVisibility(hidesTabBar ? .hidden : .visible, for: .bottomBar)
        .animation(.smooth, value: hidesTabBar)
    }

    /// How far the bottom tab bar's slot reaches above the content's bottom
    /// inset: its glass rises past the toolbar's inset, and the whole slot
    /// once a scan result hides the toolbar. The Scan tab keeps clear of it,
    /// so its camera pane stays put as the bar comes and goes. Nothing for
    /// the Duo's vertical rail.
    private func tabBarClearance(beyond bottomInset: CGFloat) -> CGFloat {
        guard layoutAxis == .horizontal, let tabBarTop else { return 0 }
        return max(0, windowBottom - tabBarTop - bottomInset)
    }
}
