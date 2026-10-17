import UIKit

/// A transparent button inside the shared glass capsule, with a persistent
/// accessibility element and an inline title when space permits.
final class GlassTabBarItemView: UIView {
    let tab: RootTab
    let button = UIButton(type: .custom)

    private let icon = UIImageView()
    private let titleLabel = UILabel()
    private var isSelected = false
    private var showsSelectedTitle = true
    private let iconSize: CGFloat = 24
    private let contentSpacing: CGFloat = 8
    private let horizontalPadding: CGFloat = 18

    var expandedWidth: CGFloat {
        iconSize + contentSpacing + titleLabel.intrinsicContentSize.width + horizontalPadding * 2
    }

    init(tab: RootTab) {
        self.tab = tab
        super.init(frame: .zero)
        addSubview(button)
        button.addSubview(icon)
        button.addSubview(titleLabel)
        button.isPointerInteractionEnabled = true
        button.showsLargeContentViewer = true
        button.scalesLargeContentImage = true
        button.accessibilityIdentifier = "tabBar.\(tab)"
        icon.contentMode = .scaleAspectFit
        icon.image = UIImage(
            systemName: tab.symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        )
        icon.tintColor = .label
        button.largeContentImage = icon.image
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.isAccessibilityElement = false
        icon.isAccessibilityElement = false
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (view: GlassTabBarItemView, _: UITraitCollection) in
            view.updateFont()
        }
        updateFont()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(isSelected: Bool, showsSelectedTitle: Bool, locale: Locale) {
        self.isSelected = isSelected
        self.showsSelectedTitle = showsSelectedTitle
        var title = tab.title
        title.locale = locale
        titleLabel.text = String(localized: title)
        button.accessibilityLabel = titleLabel.text
        button.largeContentTitle = titleLabel.text
        button.isSelected = isSelected
        button.accessibilityTraits = isSelected ? [.button, .selected] : [.button]

        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        button.frame = bounds
        let titleWidth = titleLabel.intrinsicContentSize.width
        let showsTitle = showsSelectedTitle && isSelected && bounds.width >= expandedWidth - 1
        let contentWidth = showsTitle ? iconSize + contentSpacing + titleWidth : iconSize
        let start = (bounds.width - contentWidth) / 2
        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
        icon.frame = CGRect(
            x: isRTL ? bounds.width - start - iconSize : start,
            y: (bounds.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        titleLabel.frame = CGRect(
            x: isRTL ? start : start + iconSize + contentSpacing,
            y: 0,
            width: showsTitle ? titleWidth : 0,
            height: bounds.height
        )
        titleLabel.alpha = showsTitle ? 1 : 0
    }

    private func updateFont() {
        titleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 15, weight: .semibold),
            maximumPointSize: 23,
            compatibleWith: traitCollection
        )
        setNeedsLayout()
    }
}
