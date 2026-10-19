import SwiftUI
import UIKit

/// Root destinations share one selection while the enclosing stack owns pushes.
struct RootTabContent<Home: View>: View {
    @Binding var selection: RootTab
    let scanner: ScannerModel
    var isTabBarVisible = true
    @ViewBuilder let home: Home
    @State private var layoutAxis: NSLayoutConstraint.Axis = .horizontal

    var body: some View {
        GeometryReader { geometry in
            RootTabPages(selection: selection, scanner: scanner, layoutAxis: layoutAxis,
                         isVisible: isTabBarVisible, safeAreaInsets: geometry.safeAreaInsets, home: home)
                // Keep the paging viewport full width while explicitly carrying
                // the outer stack's toolbar/rail insets into UIKit's children.
                .ignoresSafeArea(.container)
        }
        // Let the navigation container coordinate the root toolbar's visibility
        // with pushed destinations, including interactive dismissal.
        .toolbar {
            GlassTabBarToolbar(selection: $selection, layoutAxis: $layoutAxis)
        }
        .toolbarVisibility(.visible, for: .bottomBar)
    }
}
