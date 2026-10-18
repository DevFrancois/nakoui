import SwiftUI
import UIKit

/// UIKit owns selection, containment and appearance. Hosting controllers are
/// created once, so changing tabs never recreates Home's state or scroll views.
struct RootTabPages<Home: View>: UIViewControllerRepresentable {
    let selection: RootTab
    let scanner: ScannerModel
    let layoutAxis: NSLayoutConstraint.Axis
    let isVisible: Bool
    let safeAreaInsets: EdgeInsets
    let home: Home

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> RootTabController {
        let coordinator = context.coordinator
        coordinator.home = UIHostingController(rootView: hosted(home, tab: .home, environment: context.environment))
        coordinator.scanner = UIHostingController(rootView: hosted(scannerPage, tab: .scanner, environment: context.environment))
        coordinator.profile = UIHostingController(rootView: hosted(RootTabPlaceholder(tab: .profile), tab: .profile, environment: context.environment))
        coordinator.search = UIHostingController(rootView: hosted(RootTabPlaceholder(tab: .search), tab: .search, environment: context.environment))
        let controllers: [UIViewController] = [coordinator.home, coordinator.scanner, coordinator.profile, coordinator.search].compactMap { $0 }
        for controller in controllers {
            controller.view.backgroundColor = .clear
        }
        return RootTabController(viewControllers: controllers, selection: selection)
    }

    func updateUIViewController(_ controller: RootTabController, context: Context) {
        let isRightToLeft = context.environment.layoutDirection == .rightToLeft
        controller.contentSafeAreaInsets = UIEdgeInsets(
            top: safeAreaInsets.top,
            left: isRightToLeft ? safeAreaInsets.trailing : safeAreaInsets.leading,
            bottom: safeAreaInsets.bottom,
            right: isRightToLeft ? safeAreaInsets.leading : safeAreaInsets.trailing
        )
        // Updating values of the same root type retains each host's SwiftUI tree.
        context.coordinator.home?.rootView = hosted(home, tab: .home, environment: context.environment)
        context.coordinator.scanner?.rootView = hosted(scannerPage, tab: .scanner, environment: context.environment)
        context.coordinator.profile?.rootView = hosted(RootTabPlaceholder(tab: .profile), tab: .profile, environment: context.environment)
        context.coordinator.search?.rootView = hosted(RootTabPlaceholder(tab: .search), tab: .search, environment: context.environment)
        controller.update(
            selection: selection,
            layoutAxis: layoutAxis,
            isRightToLeft: isRightToLeft,
            reduceMotion: context.environment.accessibilityReduceMotion,
            isEnabled: context.environment.isEnabled,
            isVisible: isVisible,
            animated: !context.transaction.disablesAnimations
        )
    }

    private var scannerPage: ScannerView {
        ScannerView(model: scanner, isActive: selection == .scanner && isVisible)
    }

    private func hosted<Content: View>(_ content: Content, tab: RootTab, environment: EnvironmentValues) -> HostedTabPage<Content> {
        HostedTabPage(content: content, environment: environment, isActive: selection == tab && isVisible)
    }

    final class Coordinator {
        var home: UIHostingController<HostedTabPage<Home>>?
        var scanner: UIHostingController<HostedTabPage<ScannerView>>?
        var profile: UIHostingController<HostedTabPage<RootTabPlaceholder>>?
        var search: UIHostingController<HostedTabPage<RootTabPlaceholder>>?
    }
}

struct HostedTabPage<Content: View>: View {
    let content: Content
    let environment: EnvironmentValues
    let isActive: Bool

    var body: some View {
        content
            // Each hosting root must keep its own layout, safe-area and
            // presentation environment. Only copy the public values that the
            // app intentionally shares across this UIKit boundary.
            .environment(\.rootNavigation, environment.rootNavigation)
            .environment(\.scenePhase, environment.scenePhase)
            .environment(\.locale, environment.locale)
            .environment(\.calendar, environment.calendar)
            .environment(\.timeZone, environment.timeZone)
            .environment(\.layoutDirection, environment.layoutDirection)
            .environment(\.dynamicTypeSize, environment.dynamicTypeSize)
            .environment(\.legibilityWeight, environment.legibilityWeight)
            .environment(\.colorScheme, environment.colorScheme)
            .environment(\.displayScale, environment.displayScale)
            .environment(\.horizontalSizeClass, environment.horizontalSizeClass)
            .environment(\.verticalSizeClass, environment.verticalSizeClass)
            .environment(\.isEnabled, environment.isEnabled)
            .environment(\.openURL, environment.openURL)
            // Read-only accessibility values (VoiceOver, motion, transparency
            // and contrast) come from this host's system environment.
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
    }
}
