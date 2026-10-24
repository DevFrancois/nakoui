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
    private weak var attachedSource: CALayer?
    private var sourceIsAttached = false
    private var configuration = GlassTabBarReflectionConfiguration.reference
    private var filtersAvailable = false
    private var layoutAxis: NSLayoutConstraint.Axis = .horizontal
    private var displayScale: CGFloat = 1
    private var sourceGeometry: GlassTabBarReflectionGeometry?
    private let sourceSelector = NSSelectorFromString("setSourceLayer:")
    private let viewport = CALayer()
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
              let setter = class_getInstanceMethod(type(of: portal), sourceSelector) else { return }

        self.portal = portal
        sourceSetter = unsafeBitCast(method_getImplementation(setter), to: SourceSetter.self)
        portal.name = "tabBar.reflection.portal"
        let filters = Self.makeFilters(configuration)
        portal.filters = filters
        filtersAvailable = filters != nil
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
        innerShadow.shadowOpacity = Float(configuration.rimOpacity)
        innerShadow.shadowRadius = configuration.rimRadius
        innerShadow.shadowOffset = CGSize(width: configuration.rimOffsetX, height: configuration.rimOffsetY)
        edgeGradient.colors = [UIColor.clear.cgColor, UIColor.black.cgColor]
        innerShadow.mask = edgeGradient
        innerMask.addSublayer(innerShadow)
        viewport.name = "tabBar.reflection.viewport"
        viewport.masksToBounds = true
        viewport.mask = innerMask
        viewport.addSublayer(portal)
        addSublayer(viewport)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSourceLayer(_ source: CALayer?, geometry: GlassTabBarReflectionGeometry? = nil) {
        guard source !== currentSource || geometry != sourceGeometry
                || sourceIsAttached != (source != nil && configuration.isEnabled && filtersAvailable && geometry != nil) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        currentSource = source
        sourceGeometry = geometry
        updatePortalGeometry()
        updateSourceAndVisibility()
        CATransaction.commit()
    }

    func updateConfiguration(_ value: GlassTabBarReflectionConfiguration) {
        let value = value.normalized
        guard value != configuration else { return }
        let needsFilters = value.saturation != configuration.saturation
            || value.brightness != configuration.brightness
            || value.blurRadius != configuration.blurRadius || !filtersAvailable
        configuration = value

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if needsFilters, let portal {
            // Attached CAFilter inputs must be replaced through CALayer. Fresh
            // filters make the compositor notice every slider edit, while the
            // portal, captured source and native press interaction stay alive.
            let filters = Self.makeFilters(value)
            portal.filters = filters
            filtersAvailable = filters != nil
        }
        opacity = Float(value.opacity)
        updateLayout(bounds: bounds, axis: layoutAxis, scale: displayScale)
        updateSourceAndVisibility()
    }

    private func updateSourceAndVisibility() {
        guard let portal, let sourceSetter else {
            isHidden = true
            return
        }
        // Turning the effect off stops capturing. Keep the requested source
        // weakly so re-enabling immediately uses the latest page without layout.
        let source = configuration.isEnabled && filtersAvailable && sourceGeometry != nil ? currentSource : nil
        if source !== attachedSource || sourceIsAttached != (source != nil) {
            sourceSetter(portal, sourceSelector, source)
            attachedSource = source
            sourceIsAttached = source != nil
        }
        isHidden = source == nil
    }

    func updateLayout(bounds: CGRect, axis: NSLayoutConstraint.Axis, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let localBounds = CGRect(origin: .zero, size: bounds.size)
        layoutAxis = axis
        displayScale = max(scale, 1)
        self.bounds = localBounds
        position = CGPoint(x: bounds.midX, y: bounds.midY)
        contentsScale = displayScale
        let radius = min(localBounds.width, localBounds.height) / 2
        viewport.bounds = localBounds
        viewport.position = CGPoint(x: localBounds.midX, y: localBounds.midY)
        viewport.cornerRadius = radius
        viewport.transform = configuration.isMirrored
            ? (axis == .vertical ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DMakeScale(1, -1, 1))
            : CATransform3DIdentity
        innerMask.frame = localBounds
        innerMask.cornerRadius = radius
        innerShadow.frame = localBounds
        innerShadow.shadowRadius = configuration.rimRadius
        innerShadow.shadowOpacity = Float(configuration.rimOpacity)
        innerShadow.shadowOffset = CGSize(width: configuration.rimOffsetX, height: configuration.rimOffsetY)

        let ring = UIBezierPath(roundedRect: localBounds.insetBy(dx: -configuration.rimExpansion,
                                                               dy: -configuration.rimExpansion),
                                cornerRadius: radius)
        ring.append(UIBezierPath(roundedRect: localBounds, cornerRadius: radius).reversing())
        innerShadow.shadowPath = ring.cgPath

        if axis == .vertical {
            let width = localBounds.width * configuration.edgeCoverage
            edgeGradient.frame = CGRect(x: localBounds.width - width, y: 0,
                                        width: width, height: localBounds.height)
            edgeGradient.startPoint = CGPoint(x: 0, y: 0.5)
            edgeGradient.endPoint = CGPoint(x: 1, y: 0.5)
        } else {
            let height = localBounds.height * configuration.edgeCoverage
            edgeGradient.frame = CGRect(x: 0, y: localBounds.height - height,
                                        width: localBounds.width, height: height)
            edgeGradient.startPoint = CGPoint(x: 0.5, y: 0)
            edgeGradient.endPoint = CGPoint(x: 0.5, y: 1)
        }
    }

    private func updatePortalGeometry() {
        guard let portal, let geometry = sourceGeometry else { return }
        portal.bounds = geometry.portalBounds
        portal.position = geometry.portalPosition
        portal.setAffineTransform(geometry.portalTransform)
    }

    private static func makeFilters(_ configuration: GlassTabBarReflectionConfiguration) -> [NSObject]? {
        guard let saturation = makeFilter("colorSaturate", key: "inputAmount", value: configuration.saturation),
              let brightness = makeFilter("colorBrightness", key: "inputAmount", value: configuration.brightness),
              let blur = makeFilter("gaussianBlur", key: "inputRadius", value: configuration.blurRadius) else { return nil }
        return [saturation, brightness, blur]
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
