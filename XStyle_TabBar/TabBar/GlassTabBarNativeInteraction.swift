import UIKit
import ObjectiveC

/// Keep UIKit's native lift, deformation and spring while omitting its moving
/// illumination. The capsule's material and reflected rim have their own color.
/// This is an experimental, per-instance private API bridge.
final class GlassTabBarNativeGlassView: UIVisualEffectView {
    override func layoutSubviews() {
        super.layoutSubviews()
        suppressInteractionGlow()
    }

    func suppressInteractionGlow() {
        guard let interactionClass = NSClassFromString("_UIFlexInteraction") else { return }
        suppressInteractionGlow(in: self, interactionClass: interactionClass)
    }

    private func suppressInteractionGlow(in view: UIView, interactionClass: AnyClass) {
        let selector = NSSelectorFromString("glowContainer")
        for interaction in view.interactions {
            guard let object = interaction as? NSObject,
                  object.isKind(of: interactionClass),
                  let method = class_getInstanceMethod(type(of: object), selector) else { continue }
            typealias Getter = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
            let getter = unsafeBitCast(method_getImplementation(method), to: Getter.self)
            guard let glow = getter(object, selector)?.takeUnretainedValue() as? UIView else { continue }
            // UIKit animates this subtree's alpha and transform during a drag;
            // hiding it leaves those animators and the capsule's motion alone.
            glow.isHidden = true
        }
        for child in view.subviews {
            suppressInteractionGlow(in: child, interactionClass: interactionClass)
        }
    }
}
