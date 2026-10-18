import UIKit

/// Navigation expands the menu around its stable center on Duo. Compare that
/// center and its untransformed size, not the expanded window bounding box.
@MainActor
enum TabBarStableLayout {
    static func rect(of view: UIView, in root: UIView) -> CGRect? {
        guard let window = view.window, root.window === window else { return nil }
        let center = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: root)
        return CGRect(x: center.x - view.bounds.width / 2,
                      y: center.y - view.bounds.height / 2,
                      width: view.bounds.width, height: view.bounds.height)
    }
}
