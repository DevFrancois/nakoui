import UIKit

/// Text presented across one card's lower edge.
public struct CarouselCompanionContent: Equatable {
    public enum Alignment: Equatable { case leading, center, trailing }
    public var prompt: String
    public var alignment: Alignment
    public var gap: CGFloat

    public init(prompt: String, alignment: Alignment = .leading, gap: CGFloat = 18) {
        self.prompt = prompt
        self.alignment = alignment
        self.gap = gap
    }
}

/// A cached native text bubble. Its touches are consumed here, never sent to a card.
final class FeatureCompanionBubble: UIView {
    private let label = UILabel()
    private let shape = CAShapeLayer()
    private var content: CarouselCompanionContent
    private var trackedTouches: [UITouch] = []
    private var previousPoints: [CGPoint] = []
    private var swallowingTouches = false
    private var measuredWidth: CGFloat?
    private var measuredSize: CGSize = .zero
    private(set) var hasTouches = false
    var onInteractionBegan: ((TimeInterval) -> Void)?
    /// The fingers' centroid movement, scale factor and rotation, plus their previous
    /// centroid: the pivot the companion's motion keeps under them.
    var onInteractionChanged: ((CGPoint, Double, Double, CGPoint?, TimeInterval) -> Void)?
    var onInteractionEnded: ((Bool) -> Void)?
    var onReset: (() -> Void)?
    var onNudge: ((Double) -> Void)?
    var onContentSizeChanged: (() -> Void)?
    var onTouchesDrained: (() -> Void)?

    init(content: CarouselCompanionContent) {
        self.content = content
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        isAccessibilityElement = true
        layer.addSublayer(shape)
        label.numberOfLines = 0
        label.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(red: 29 / 255, green: 29 / 255, blue: 31 / 255, alpha: 1)
        addSubview(label)
        shape.fillColor = UIColor(red: 239 / 255, green: 239 / 255, blue: 236 / 255, alpha: 1).cgColor
        shape.shadowColor = UIColor.black.cgColor
        shape.shadowOpacity = 0.13
        shape.shadowRadius = 12
        shape.shadowOffset = CGSize(width: 0, height: 5)
        update(content: content, interactive: true)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (view: FeatureCompanionBubble, _: UITraitCollection) in
            view.updateTextMetrics()
            view.onContentSizeChanged?()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(content: CarouselCompanionContent, interactive: Bool) {
        if self.content != content || label.text == nil {
            self.content = content
            updateTextMetrics()
            accessibilityLabel = content.prompt
            setNeedsLayout()
        }
        isUserInteractionEnabled = interactive
        accessibilityTraits = interactive ? [.staticText, .adjustable] : .staticText
        accessibilityHint = interactive ? "Drag, pinch, or rotate this explanation. It returns when released." : nil
        accessibilityCustomActions = interactive ? [
            UIAccessibilityCustomAction(name: "Reset companion", target: self, selector: #selector(resetFromAccessibility)),
            UIAccessibilityCustomAction(name: "Nudge left", target: self, selector: #selector(nudgeLeftFromAccessibility)),
            UIAccessibilityCustomAction(name: "Nudge right", target: self, selector: #selector(nudgeRightFromAccessibility))
        ] : nil
    }

    func preferredSize(maximumWidth: CGFloat) -> CGSize {
        let width = max(100, maximumWidth)
        if measuredWidth == width { return measuredSize }
        let text = label.sizeThatFits(CGSize(width: width - 32, height: .greatestFiniteMagnitude))
        measuredWidth = width
        measuredSize = CGSize(width: min(width, ceil(text.width) + 32), height: ceil(text.height) + 29)
        return measuredSize
    }

    private func updateTextMetrics() {
        measuredWidth = nil
        let metrics = UIFontMetrics(forTextStyle: .subheadline)
        label.font = metrics.scaledFont(for: .systemFont(ofSize: 15))
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = metrics.scaledValue(for: 19)
        paragraph.maximumLineHeight = paragraph.minimumLineHeight
        label.attributedText = NSAttributedString(string: content.prompt, attributes: [.paragraphStyle: paragraph])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let body = bounds
        label.frame = body.insetBy(dx: 16, dy: 14.5)
        let path = UIBezierPath(roundedRect: body, cornerRadius: 24)
        shape.frame = bounds
        shape.path = path.cgPath
        shape.shadowPath = path.cgPath
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden, alpha > 0.05, isUserInteractionEnabled else { return false }
        return shape.path?.contains(point) ?? bounds.contains(point)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasEmpty = trackedTouches.isEmpty
        for touch in touches where !trackedTouches.contains(where: { $0 === touch }) { trackedTouches.append(touch) }
        previousPoints = currentPoints()
        hasTouches = true
        if wasEmpty && !swallowingTouches { onInteractionBegan?(touches.map(\.timestamp).min() ?? 0) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        deliverChange(at: touches.map(\.timestamp).max() ?? 0)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        deliverChange(at: touches.map(\.timestamp).max() ?? 0)
        let wasPinching = trackedTouches.count > 1
        trackedTouches.removeAll { touch in touches.contains(where: { $0 === touch }) }
        previousPoints = currentPoints()
        if trackedTouches.isEmpty {
            hasTouches = false
            if swallowingTouches {
                swallowingTouches = false
                onTouchesDrained?()
            } else { onInteractionEnded?(false) }
        } else if wasPinching, !swallowingTouches {
            // Lifting one finger of a pinch releases the bubble back to its card, like a
            // pinched card. The remaining fingers stay owned and ignored until they lift.
            swallowingTouches = true
            onInteractionEnded?(false)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { cancelTouches() }

    func cancelTouches(preservingOwnership: Bool = false) {
        guard hasTouches else { return }
        if preservingOwnership {
            guard !swallowingTouches else { return }
            swallowingTouches = true
            onInteractionEnded?(true)
            return
        }
        trackedTouches.removeAll()
        previousPoints.removeAll()
        hasTouches = false
        if swallowingTouches {
            swallowingTouches = false
            onTouchesDrained?()
        } else { onInteractionEnded?(true) }
    }

    private func currentPoints() -> [CGPoint] { trackedTouches.map { $0.location(in: superview) } }

    private func deliverChange(at time: TimeInterval) {
        guard !swallowingTouches else { return }
        let points = currentPoints()
        guard points.count == previousPoints.count, !points.isEmpty else { previousPoints = points; return }
        let delta = CarouselTouchGeometry.delta(from: previousPoints, to: points)
        let pivot = CarouselTouchGeometry.centroid(previousPoints)
        previousPoints = points
        onInteractionChanged?(delta.translation, delta.scale, delta.rotation, pivot, time)
    }

    override func accessibilityIncrement() { onNudge?(220) }
    override func accessibilityDecrement() { onNudge?(-220) }
    @objc private func resetFromAccessibility() -> Bool { onReset?(); return true }
    @objc private func nudgeLeftFromAccessibility() -> Bool { onNudge?(-220); return true }
    @objc private func nudgeRightFromAccessibility() -> Bool { onNudge?(220); return true }
}
