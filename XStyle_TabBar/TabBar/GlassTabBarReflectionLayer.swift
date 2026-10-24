import UIKit
import ObjectiveC

/// Experimental private renderer, based on the inspected Netflix 18.51.0 path.
/// CAPortalLayer and CAFilter are unsupported APIs; unavailable factories leave
/// this layer hidden. The installed Netflix version may render differently.
final class GlassTabBarReflectionLayer: CALayer {
    private typealias SourceSetter = @convention(c) (AnyObject, Selector, CALayer?) -> Void

    private var portal: CALayer?
    private var sourceSetter: SourceSetter?
    private weak var currentSource: CALayer?
    private let sourceSelector = NSSelectorFromString("setSourceLayer:")
    private let innerMask = CALayer()
    private let innerShadow = CAShapeLayer()
    private let edgeGradient = CAGradientLayer()

    override init() {
        super.init()
        name = "tabBar.reflection"
        isHidden = true
        masksToBounds = false

        guard let portal = Self.makePortal(),
              portal.responds(to: sourceSelector),
              let setter = class_getInstanceMethod(type(of: portal), sourceSelector),
              let saturation = Self.makeFilter("colorSaturate", key: "inputAmount", value: 2.5),
              let brightness = Self.makeFilter("colorBrightness", key: "inputAmount", value: 0.1),
              let blur = Self.makeFilter("gaussianBlur", key: "inputRadius", value: 15) else { return }

        self.portal = portal
        sourceSetter = unsafeBitCast(method_getImplementation(setter), to: SourceSetter.self)
        portal.name = "tabBar.reflection.portal"
        portal.filters = [saturation, brightness, blur]
        portal.masksToBounds = true
        portal.actions = ["bounds": NSNull(), "cornerRadius": NSNull(),
                          "position": NSNull(), "transform": NSNull()]

        // This is an alpha mask revealing reflected pixels near the inner rim,
        // not another black backing over the capsule's center.
        innerMask.masksToBounds = true
        innerShadow.fillColor = nil
        innerShadow.fillRule = .evenOdd
        innerShadow.masksToBounds = true
        innerShadow.shadowColor = UIColor.black.cgColor
        innerShadow.shadowOpacity = 1
        innerShadow.shadowRadius = 5
        // The inspected implementation leaves CALayer's (0, -3) default offset.
        edgeGradient.colors = [UIColor.clear.cgColor, UIColor.black.cgColor]
        innerShadow.mask = edgeGradient
        innerMask.addSublayer(innerShadow)
        portal.mask = innerMask
        addSublayer(portal)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSourceLayer(_ source: CALayer?) {
        guard let portal, let sourceSetter else {
            isHidden = true
            return
        }
        guard source !== currentSource || isHidden != (source == nil) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sourceSetter(portal, sourceSelector, source)
        currentSource = source
        isHidden = source == nil
        CATransaction.commit()
    }

    func updateLayout(bounds: CGRect, axis: NSLayoutConstraint.Axis, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let localBounds = CGRect(origin: .zero, size: bounds.size)
        self.bounds = localBounds
        position = CGPoint(x: bounds.midX, y: bounds.midY)
        contentsScale = max(scale, 1)
        guard let portal else { return }

        let radius = min(localBounds.width, localBounds.height) / 2
        portal.bounds = localBounds
        portal.position = CGPoint(x: localBounds.midX, y: localBounds.midY)
        portal.cornerRadius = radius
        portal.transform = axis == .vertical
            ? CATransform3DMakeScale(-1, 1, 1)
            : CATransform3DMakeScale(1, -1, 1)
        innerMask.frame = localBounds
        innerMask.cornerRadius = radius
        innerShadow.frame = localBounds

        let ring = UIBezierPath(roundedRect: localBounds.insetBy(dx: -10, dy: -10),
                                cornerRadius: radius)
        ring.append(UIBezierPath(roundedRect: localBounds, cornerRadius: radius).reversing())
        innerShadow.shadowPath = ring.cgPath

        if axis == .vertical {
            edgeGradient.frame = CGRect(x: localBounds.width / 2, y: 0,
                                        width: localBounds.width / 2, height: localBounds.height)
            edgeGradient.startPoint = CGPoint(x: 0, y: 0.5)
            edgeGradient.endPoint = CGPoint(x: 1, y: 0.5)
        } else {
            edgeGradient.frame = CGRect(x: 0, y: localBounds.height / 2,
                                        width: localBounds.width, height: localBounds.height / 2)
            edgeGradient.startPoint = CGPoint(x: 0.5, y: 0)
            edgeGradient.endPoint = CGPoint(x: 0.5, y: 1)
        }
    }

    private static func makePortal() -> CALayer? {
        let selector = NSSelectorFromString("layer")
        guard let type = NSClassFromString("CAPortalLayer"),
              let method = class_getClassMethod(type, selector) else { return nil }
        typealias Factory = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        let factory = unsafeBitCast(method_getImplementation(method), to: Factory.self)
        return factory(type as AnyObject, selector)?.takeUnretainedValue() as? CALayer
    }

    private static func makeFilter(_ name: String, key: String, value: Double) -> NSObject? {
        let selector = NSSelectorFromString("filterWithName:")
        guard let type = NSClassFromString("CAFilter"),
              let method = class_getClassMethod(type, selector) else { return nil }
        typealias Factory = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<AnyObject>?
        let factory = unsafeBitCast(method_getImplementation(method), to: Factory.self)
        guard let filter = factory(type as AnyObject, selector, name as NSString)?
            .takeUnretainedValue() as? NSObject,
              GlassTabBarSetPrivateValue(filter, key, NSNumber(value: value)) else { return nil }
        return filter
    }
}
