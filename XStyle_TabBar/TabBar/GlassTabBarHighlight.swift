import UIKit

/// A single soft reflection, clipped to the moving selection capsule.
final class GlassTabBarHighlight: UIView {
    private let shimmer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .tertiarySystemFill
        cornerConfiguration = .capsule()
        clipsToBounds = true
        isUserInteractionEnabled = false
        shimmer.name = "tabBar.releaseShimmer"
        shimmer.locations = [0, 0.5, 1]
        shimmer.opacity = 0
        layer.addSublayer(shimmer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func playShimmer(axis: NSLayoutConstraint.Axis, direction: CGFloat) {
        guard !bounds.isEmpty else { return }
        let vertical = axis == .vertical
        let length = vertical ? bounds.height : bounds.width
        let band = length * 0.8
        // A neutral shadow reads against light glass; dark glass catches a white
        // reflection. Choose fresh colors for each release because CGColor is static.
        let isDark = traitCollection.userInterfaceStyle == .dark
        let color = isDark ? UIColor.white : UIColor.black
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shimmer.colors = [color.withAlphaComponent(0).cgColor,
                          color.withAlphaComponent(isDark ? 0.55 : 0.22).cgColor,
                          color.withAlphaComponent(0).cgColor]
        shimmer.bounds = CGRect(x: 0, y: 0,
                                width: vertical ? bounds.width : band,
                                height: vertical ? band : bounds.height)
        shimmer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shimmer.startPoint = vertical ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0, y: 0.5)
        shimmer.endPoint = vertical ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 1, y: 0.5)
        CATransaction.commit()

        let sweep = CABasicAnimation(keyPath: vertical ? "position.y" : "position.x")
        sweep.fromValue = direction > 0 ? -band / 2 : length + band / 2
        sweep.toValue = direction > 0 ? length + band / 2 : -band / 2
        sweep.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.15, 0.65, 1]
        let pulse = CAAnimationGroup()
        pulse.animations = [sweep, fade]
        pulse.duration = 0.28
        // Replacing this key keeps rapid taps from stacking reflections.
        shimmer.add(pulse, forKey: "shimmer")
    }

    func stopShimmer() {
        shimmer.removeAllAnimations()
    }
}
