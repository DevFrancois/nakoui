import SwiftUI
import UIKit

/// UIKit owns selection, containment and appearance. Hosting controllers are
/// created once, so changing tabs never recreates Home's state or scroll views.
struct RootTabPages<Home: View>: UIViewControllerRepresentable {
    let selection: RootTab
    let scanner: ScannerModel
    let scannerSheet: SheetController
    let sheetSettings: SheetSettings
    let scanHistory: ScanHistory
    let layoutAxis: NSLayoutConstraint.Axis
    let isVisible: Bool
    let safeAreaInsets: EdgeInsets
    /// How far the tab bar's slot rises above `safeAreaInsets.bottom`. The
    /// Scan tab's safe area covers it, so its camera pane stops above the bar.
    let scannerTabBarClearance: CGFloat
    let home: Home

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> RootTabController {
        let coordinator = context.coordinator
        let environment = ForwardedEnvironment(context.environment)
        coordinator.home = UIHostingController(rootView: HostedTabPage(content: home, environment: environment))
        coordinator.scanner = UIHostingController(rootView: HostedTabPage(content: scannerPage, environment: environment))
        coordinator.profile = UIHostingController(rootView: HostedTabPage(content: RootTabPlaceholder(tab: .profile), environment: environment))
        coordinator.search = UIHostingController(rootView: HostedTabPage(content: RootTabPlaceholder(tab: .search), environment: environment))
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
        let environment = ForwardedEnvironment(context.environment)
        context.coordinator.home?.rootView = HostedTabPage(content: home, environment: environment)
        context.coordinator.scanner?.rootView = HostedTabPage(content: scannerPage, environment: environment)
        let scannerInsets = UIEdgeInsets(top: 0, left: 0, bottom: scannerTabBarClearance, right: 0)
        if context.coordinator.scanner?.additionalSafeAreaInsets != scannerInsets {
            context.coordinator.scanner?.additionalSafeAreaInsets = scannerInsets
        }
        context.coordinator.profile?.rootView = HostedTabPage(content: RootTabPlaceholder(tab: .profile), environment: environment)
        context.coordinator.search?.rootView = HostedTabPage(content: RootTabPlaceholder(tab: .search), environment: environment)
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
        ScannerView(model: scanner, sheet: scannerSheet, settings: sheetSettings, history: scanHistory,
                    isActive: selection == .scanner && isVisible)
    }

    final class Coordinator {
        var home: UIHostingController<HostedTabPage<Home>>?
        var scanner: UIHostingController<HostedTabPage<ScannerView>>?
        var profile: UIHostingController<HostedTabPage<RootTabPlaceholder>>?
        var search: UIHostingController<HostedTabPage<RootTabPlaceholder>>?
    }
}

/// Only the public values the app intentionally shares across the UIKit
/// boundary. Equatable, so an unrelated outer environment change leaves the
/// hosted pages alone.
struct ForwardedEnvironment: Equatable {
    var rootNavigation: RootNavigation?
    var scenePhase: ScenePhase
    var locale: Locale
    var calendar: Calendar
    var timeZone: TimeZone
    var layoutDirection: LayoutDirection
    var dynamicTypeSize: DynamicTypeSize
    var legibilityWeight: LegibilityWeight?
    var colorScheme: ColorScheme
    var displayScale: CGFloat
    var horizontalSizeClass: UserInterfaceSizeClass?
    var verticalSizeClass: UserInterfaceSizeClass?
    var isEnabled: Bool

    init(_ environment: EnvironmentValues) {
        rootNavigation = environment.rootNavigation
        scenePhase = environment.scenePhase
        locale = environment.locale
        calendar = environment.calendar
        timeZone = environment.timeZone
        layoutDirection = environment.layoutDirection
        dynamicTypeSize = environment.dynamicTypeSize
        legibilityWeight = environment.legibilityWeight
        colorScheme = environment.colorScheme
        displayScale = environment.displayScale
        horizontalSizeClass = environment.horizontalSizeClass
        verticalSizeClass = environment.verticalSizeClass
        isEnabled = environment.isEnabled
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rootNavigation === rhs.rootNavigation && lhs.scenePhase == rhs.scenePhase
            && lhs.locale == rhs.locale && lhs.calendar == rhs.calendar && lhs.timeZone == rhs.timeZone
            && lhs.layoutDirection == rhs.layoutDirection && lhs.dynamicTypeSize == rhs.dynamicTypeSize
            && lhs.legibilityWeight == rhs.legibilityWeight && lhs.colorScheme == rhs.colorScheme
            && lhs.displayScale == rhs.displayScale && lhs.horizontalSizeClass == rhs.horizontalSizeClass
            && lhs.verticalSizeClass == rhs.verticalSizeClass && lhs.isEnabled == rhs.isEnabled
    }
}

struct HostedTabPage<Content: View>: View {
    let content: Content
    let environment: ForwardedEnvironment

    var body: some View {
        content
            // Each hosting root must keep its own layout, safe-area and
            // presentation environment, including its system openURL.
            // Read-only accessibility values (VoiceOver, motion, transparency
            // and contrast) come from this host's system environment too.
            // RootTabController gates interaction and accessibility per page.
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
    }
}
