import UIKit

/// A single accessibility element; its symbol and label share the glass's
/// semantic foreground treatment without adding another glass surface.
final class GlassTabBarButton: UIControl {
    let tab: RootTab
    var onSizeChange: (() -> Void)?
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
        cornerConfiguration = .capsule()
        isAccessibilityElement = true
        accessibilityIdentifier = tab.accessibilityIdentifier

        symbolView.contentMode = .scaleAspectFit
        symbolView.isAccessibilityElement = false
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.isAccessibilityElement = false
        addSubview(symbolView)
        addSubview(titleLabel)

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitLegibilityWeight.self]) { (view: GlassTabBarButton, _) in
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

    override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        sendActions(for: .touchUpInside)
        return true
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        if layoutAxis == .vertical {
            return CGSize(width: size.width, height: GlassTabBarMetrics.minimumTapSize)
        }
        let labelSize = titleSize(for: size.width)
        let height = symbolSize + GlassTabBarMetrics.labelSpacing + labelSize.height + GlassTabBarMetrics.itemPadding * 2
        return CGSize(width: size.width, height: max(GlassTabBarMetrics.minimumTapSize, ceil(height)))
    }

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
        titleLabel.font = .preferredFont(forTextStyle: .caption2, compatibleWith: traitCollection)
        symbolSize = min(
            GlassTabBarMetrics.maximumSymbolSize,
            UIFontMetrics(forTextStyle: .body).scaledValue(for: GlassTabBarMetrics.symbolSize, compatibleWith: traitCollection)
        )
        let weight: UIImage.SymbolWeight = traitCollection.legibilityWeight == .bold ? .semibold : .regular
        symbolView.image = UIImage(systemName: tab.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: symbolSize, weight: weight))
        invalidateSize()
    }

    private func invalidateSize() {
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        onSizeChange?()
    }

    private func updateAppearance() {
        let foreground: UIColor = !isEnabled ? .tertiaryLabel : (isSelected || isHighlighted ? .label : .secondaryLabel)
        symbolView.tintColor = foreground
        titleLabel.textColor = foreground
        backgroundColor = isHighlighted ? .tertiarySystemFill : .clear
        accessibilityTraits = [.button]
        if isSelected { accessibilityTraits.insert(.selected) }
        if !isEnabled { accessibilityTraits.insert(.notEnabled) }
    }
}
