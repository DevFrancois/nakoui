import UIKit

/// The page and toolbar are siblings. Keep their connection weak so the live
/// reflection cannot accidentally capture the toolbar or retain a removed page.
@MainActor
final class GlassTabBarReflectionSource {
    private weak var sourceView: UIView?
    private weak var consumer: GlassTabBarView?

    func setView(_ view: UIView?) {
        guard sourceView !== view else { return }
        sourceView = view
        consumer?.setReflectionSource(view)
    }

    func attach(_ view: GlassTabBarView) {
        consumer = view
        view.setReflectionSource(sourceView)
    }

    func clear(ifMatching view: UIView) {
        if sourceView === view { setView(nil) }
    }
}
