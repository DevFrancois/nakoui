import UIKit

/// One persistent native glass platter. The container coordinates rendering;
/// the regular glass effect provides the material and follows system settings.
final class GlassTabBarView: UIView {
    var onSelect: ((RootTab) -> Void)?

    private let containerView = UIVisualEffectView(effect: UIGlassContainerEffect())
    private let glassView: UIVisualEffectView
    private let selectionView = UIView()
    private let buttons = RootTab.allCases.map { GlassTabBarButton(tab: $0) }
    private var selection: RootTab
    private var reduceMotion = false
    private var layoutAxis: NSLayoutConstraint.Axis = .horizontal

    init(selection: RootTab) {
        self.selection = selection
        let glass = UIGlassEffect(style: .regular)
        glass.isInteractive = true
        glassView = UIVisualEffectView(effect: glass)
        super.init(frame: .zero)
        isOpaque = false
        isAccessibilityElement = false
        accessibilityTraits = .tabBar
        accessibilityElements = buttons

        glassView.cornerConfiguration = .capsule()
        addSubview(containerView)
        containerView.contentView.addSubview(glassView)

        selectionView.backgroundColor = .tertiarySystemFill
        selectionView.cornerConfiguration = .capsule()
        selectionView.isUserInteractionEnabled = false
        glassView.contentView.addSubview(selectionView)
        for button in buttons {
            glassView.contentView.addSubview(button)
            button.isSelected = button.tab == selection
            button.addTarget(self, action: #selector(selectButton(_:)), for: .touchUpInside)
            button.onSizeChange = { [weak self] in
                self?.invalidateIntrinsicContentSize()
                self?.setNeedsLayout()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateEnvironment(
        locale: Locale,
        contentSizeCategory: UIContentSizeCategory,
        layoutDirection: UIUserInterfaceLayoutDirection,
        layoutAxis: NSLayoutConstraint.Axis,
        reduceMotion: Bool,
        isEnabled: Bool
    ) {
        // Never read an unset override. Apply traits before SwiftUI measures
        // the bar, including when it has not entered a window yet.
        traitOverrides.preferredContentSizeCategory = contentSizeCategory
        updateTraitsIfNeeded()
        semanticContentAttribute = layoutDirection == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        if reduceMotion && !self.reduceMotion {
            selectionView.layer.removeAllAnimations()
        }
        self.reduceMotion = reduceMotion
        self.layoutAxis = layoutAxis
        for button in buttons {
            button.layoutAxis = layoutAxis
            button.updateTitle(locale: locale)
            button.isEnabled = isEnabled
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func fittingHeight(for width: CGFloat) -> CGFloat {
        if layoutAxis == .vertical {
            return CGFloat(buttons.count) * GlassTabBarMetrics.minimumTapSize + GlassTabBarMetrics.contentInset * 2
        }
        let itemWidth = max(0, width - GlassTabBarMetrics.contentInset * 2) / CGFloat(buttons.count)
        let itemHeight = buttons.map { $0.sizeThatFits(CGSize(width: itemWidth, height: .greatestFiniteMagnitude)).height }.max() ?? 0
        return max(GlassTabBarMetrics.minimumHeight, itemHeight + GlassTabBarMetrics.contentInset * 2)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        containerView.frame = bounds
        glassView.frame = containerView.bounds
        let content = bounds.insetBy(dx: GlassTabBarMetrics.contentInset, dy: GlassTabBarMetrics.contentInset)
        let isVertical = layoutAxis == .vertical
        let itemWidth = max(0, content.width) / (isVertical ? 1 : CGFloat(buttons.count))
        let itemHeight = max(0, content.height) / (isVertical ? CGFloat(buttons.count) : 1)
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        for (index, button) in buttons.enumerated() {
            let visualIndex = !isVertical && isRightToLeft ? buttons.count - 1 - index : index
            button.frame = CGRect(
                x: content.minX + (isVertical ? 0 : CGFloat(visualIndex) * itemWidth),
                y: content.minY + (isVertical ? CGFloat(visualIndex) * itemHeight : 0),
                width: itemWidth,
                height: itemHeight
            )
        }
        // A resize or direction change replaces the old geometry immediately.
        // During selection animation the model frame already equals this frame.
        if let selectedButton = buttons.first(where: { $0.tab == selection }), selectionView.frame != selectedButton.frame {
            selectionView.layer.removeAllAnimations()
            selectionView.frame = selectedButton.frame
        }
    }

    func select(_ tab: RootTab, animated: Bool) {
        guard selection != tab else { return }
        layoutIfNeeded()
        selection = tab
        for button in buttons {
            button.isSelected = button.tab == tab
        }
        guard let selectedButton = buttons.first(where: { $0.tab == tab }) else { return }
        guard animated, !reduceMotion, window != nil, !selectionView.frame.isEmpty else {
            selectionView.layer.removeAllAnimations()
            selectionView.frame = selectedButton.frame
            return
        }
        UIView.animate(
            withDuration: GlassTabBarMetrics.selectionDuration,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.selectionView.frame = selectedButton.frame
        }
    }

    @objc private func selectButton(_ button: GlassTabBarButton) {
        guard button.tab != selection else { return }
        select(button.tab, animated: true)
        onSelect?(button.tab)
    }
}
