import SwiftUI
import UIKit

/// Root destinations share one selection while the enclosing stack owns pushes.
struct RootTabContent<Home: View>: View {
    @Binding var selection: RootTab
    let scanner: ScannerModel
    var isTabBarVisible = true
    @ViewBuilder let home: Home
    @State private var layoutAxis: NSLayoutConstraint.Axis = .horizontal
    /// The window's bottom edge, in global space: how far the tab bar slides
    /// to leave the screen.
    @State private var windowBottom: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            RootTabPages(selection: selection, scanner: scanner, layoutAxis: layoutAxis,
                         isVisible: isTabBarVisible, safeAreaInsets: geometry.safeAreaInsets, home: home)
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
                isHidden: GlassTabBar.hidesForScanResult(
                    selection: selection, hasResult: scanner.scannedCode != nil, layoutAxis: layoutAxis
                ),
                windowBottom: windowBottom
            )
        }
        .toolbarVisibility(.visible, for: .bottomBar)
    }
}
