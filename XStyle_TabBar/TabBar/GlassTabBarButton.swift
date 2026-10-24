import UIKit

/// A single accessibility element; its symbol and label share explicit
/// foreground colors above the menu's separate glass background.
final class GlassTabBarButton: UIControl {
    let tab: RootTab
    var onSizeChange: (() -> Void)?
    var reduceMotion = false {
        didSet {
            if reduceMotion && !oldValue { layer.removeAllAnimations() }
        }
    }
    var layoutAxis: NSLayoutConstraint.Axis = .horizontal {
        didSet {
            guard layoutAxis != oldValue else { return }
            titleLabel.isHidden = layoutAxis == .vertical
            invalidateSize()
        }
    }
    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private var symbolSize = GlassTabBarMetrics.symbolSize
    // Finger tracking stays separate from the committed accessibility selection.
    private var trackingCandidate: Bool?
    private var appliedForeground: UIColor?
    private var selectedForegroundOverride: UIColor?
    private var inactiveForegroundOverride: UIColor?
    private static let selectedForeground = UIColor { traits in
        (traits.userInterfaceStyle == .dark ? UIColor.label : UIColor.black)
            .resolvedColor(with: traits)
    }
    private static let unselectedForeground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 121.0 / 255.0, green: 121.0 / 255.0, blue: 121.0 / 255.0, alpha: 1)
            : UIColor.secondaryLabel.resolvedColor(with: traits)
    }

    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    override var isHighlighted: Bool {
        didSet { updateAppearance() }
    }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    init(tab: RootTab) {
        self.tab = tab
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        cornerConfiguration = .capsule()
        isAccessibilityElement = true
        accessibilityIdentifier = tab.accessibilityIdentifier
        // Expose only this named control. SF Symbols can otherwise contribute
        // their own automatic image descriptions to accessibility snapshots.
        accessibilityElements = []

        symbolView.contentMode = .scaleAspectFit
        symbolView.isAccessibilityElement = false
        symbolView.accessibilityElementsHidden = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.isAccessibilityElement = false
        titleLabel.accessibilityElementsHidden = true
        addSubview(symbolView)
        addSubview(titleLabel)

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: GlassTabBarButton, _) in
            view.updateFonts()
        }
        updateFonts()
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateTitle(locale: Locale) {
        var title = tab.title
        title.locale = locale
        let text = String(localized: title)
        guard titleLabel.text != text else { return }
        titleLabel.text = text
        accessibilityLabel = text
        invalidateSize()
    }

    func updateTrackingCandidate(_ isCandidate: Bool?) {
        guard trackingCandidate != isCandidate else { return }
        trackingCandidate = isCandidate
        updateAppearance()
    }

    func updateForeground(selected: UIColor?, inactive: UIColor?) {
        guard selectedForegroundOverride != selected || inactiveForegroundOverride != inactive else { return }
        selectedForegroundOverride = selected
        inactiveForegroundOverride = inactive
        updateAppearance()
    }

    override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        sendActions(for: .touchUpInside)
        return true
    }

    var preferredWidth: CGFloat {
        guard layoutAxis == .horizontal else { return GlassTabBarMetrics.minimumTapSize }
        let labelWidth = titleSize(for: .greatestFiniteMagnitude).width
        return max(GlassTabBarMetrics.minimumTapSize,
                   ceil(max(symbolSize, labelWidth) + GlassTabBarMetrics.itemPadding * 2))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        if layoutAxis == .vertical {
            return CGSize(width: size.width, height: GlassTabBarMetrics.verticalItemHeight)
        }
        let labelSize = titleSize(for: size.width)
        let height = symbolSize + GlassTabBarMetrics.labelSpacing + labelSize.height + GlassTabBarMetrics.itemPadding * 2
        return CGSize(width: size.width, height: max(GlassTabBarMetrics.minimumTapSize, ceil(height)))
    }

    /// The symbol's centre, in this button's bounds.
    var symbolCenter: CGPoint { symbolView.center }

    override func layoutSubviews() {
        super.layoutSubviews()
        if layoutAxis == .vertical {
            symbolView.frame = CGRect(
                x: (bounds.width - symbolSize) / 2,
                y: (bounds.height - symbolSize) / 2,
                width: symbolSize,
                height: symbolSize
            )
            return
        }
        let labelSize = titleSize(for: bounds.width)
        let contentHeight = symbolSize + GlassTabBarMetrics.labelSpacing + labelSize.height
        let top = (bounds.height - contentHeight) / 2
        symbolView.frame = CGRect(x: (bounds.width - symbolSize) / 2, y: top, width: symbolSize, height: symbolSize)
        titleLabel.frame = CGRect(
            x: GlassTabBarMetrics.itemPadding,
            y: top + symbolSize + GlassTabBarMetrics.labelSpacing,
            width: max(0, bounds.width - GlassTabBarMetrics.itemPadding * 2),
            height: labelSize.height
        )
    }

    private func titleSize(for width: CGFloat) -> CGSize {
        titleLabel.sizeThatFits(CGSize(
            width: max(1, width - GlassTabBarMetrics.itemPadding * 2),
            height: .greatestFiniteMagnitude
        ))
    }

    private func updateFonts() {
        titleLabel.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(
            for: .systemFont(ofSize: GlassTabBarMetrics.labelSize, weight: .semibold),
            compatibleWith: traitCollection
        )
        symbolSize = min(
            GlassTabBarMetrics.maximumSymbolSize,
            UIFontMetrics(forTextStyle: .body).scaledValue(for: GlassTabBarMetrics.symbolSize, compatibleWith: traitCollection)
        )
        if tab == .home {
            symbolView.image = UIImage(resource: .homeTabIcon)
        } else {
            symbolView.image = UIImage(systemName: tab.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: symbolSize, weight: .semibold))
        }
        invalidateSize()
    }

    private func invalidateSize() {
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        onSizeChange?()
    }

    private func updateAppearance() {
        let isEmphasized = trackingCandidate ?? (isSelected || isHighlighted)
        let foreground: UIColor = !isEnabled ? .tertiaryLabel
            : (isEmphasized ? selectedForegroundOverride ?? Self.selectedForeground
                           : inactiveForegroundOverride ?? Self.unselectedForeground)
        accessibilityTraits = [.button]
        if isSelected { accessibilityTraits.insert(.selected) }
        if !isEnabled { accessibilityTraits.insert(.notEnabled) }

        // Committing the preview or moving within one tab must not restart its fade.
        guard appliedForeground?.isEqual(foreground) != true else { return }
        let animate = appliedForeground != nil && window != nil && !reduceMotion && UIView.areAnimationsEnabled
        appliedForeground = foreground
        let update = {
            self.symbolView.tintColor = foreground
            self.titleLabel.textColor = foreground
        }
        if animate {
            UIView.transition(with: self, duration: 0.25,
                              options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction],
                              animations: update)
        } else {
            UIView.performWithoutAnimation(update)
        }
    }
}
