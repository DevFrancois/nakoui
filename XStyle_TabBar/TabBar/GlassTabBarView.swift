import SwiftUI
import UIKit

/// One capsule holds all destinations. Its custom Metal material reflects
/// ordinary UI colors and direct Carousel scene textures.
final class GlassTabBarView: UIView {
    var onSelect: ((RootTab) -> Void)?
    var reflectionSource: TabBarReflectionSource? {
        get { optics.reflectionSource }
        set { optics.reflectionSource = newValue }
    }
    var reflectionSettings: TabBarReflectionSettings {
        get { optics.reflectionSettings }
        set { optics.reflectionSettings = newValue }
    }

    private let surface = UIView()
    private let optics = TabBarOpticalSurface(frame: .zero)
    private let selectionHighlight = UIView()
    private let items = RootTab.allCases.map { GlassTabBarItemView(tab: $0) }
    private var selection: RootTab?
    private var axis: Axis = .horizontal
    private var locale: Locale?
    private var layoutDirection: UIUserInterfaceLayoutDirection?

    init() {
        super.init(frame: .zero)

        backgroundColor = .clear
        addSubview(surface)
        surface.addSubview(optics)
        selectionHighlight.cornerConfiguration = .capsule()
        selectionHighlight.backgroundColor = .tertiarySystemFill
        selectionHighlight.isUserInteractionEnabled = false
        selectionHighlight.isAccessibilityElement = false
        surface.addSubview(selectionHighlight)
        accessibilityTraits = .tabBar
        shouldGroupAccessibilityChildren = true
        addInteraction(UILargeContentViewerInteraction())
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (view: GlassTabBarView, _: UITraitCollection) in
            view.setNeedsLayout()
        }

        for item in items {
            surface.addSubview(item)
            item.button.addAction(UIAction { [weak self, weak item] _ in
                guard let self, let item, selection != item.tab else { return }
                onSelect?(item.tab)
            }, for: .primaryActionTriggered)
        }
        accessibilityElements = items.map(\.button)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(selection: RootTab, axis: Axis, locale: Locale, animated: Bool) {
        let direction = effectiveUserInterfaceLayoutDirection
        // Tuning updates only change uniforms. Keep labels and layout untouched
        // unless the actual tab configuration has changed.
        guard self.selection != selection || self.axis != axis || self.locale != locale
                || layoutDirection != direction else { return }
        let selectionChanged = self.selection != selection
        let shouldAnimate = animated && self.axis == axis && self.selection != nil && selectionChanged && window != nil
        layoutIfNeeded()
        self.selection = selection
        self.axis = axis
        self.locale = locale
        layoutDirection = direction

        let changes = {
            for item in self.items {
                item.update(isSelected: item.tab == selection, showsSelectedTitle: axis == .horizontal, locale: locale)
            }
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }

        if shouldAnimate {
            UIView.animate(
                withDuration: 0.36,
                delay: 0,
                usingSpringWithDamping: 0.86,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: changes
            )
        } else {
            UIView.performWithoutAnimation(changes)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let selectedItem = items.first { $0.tab == selection }
        let layout = GlassTabBarLayout(
            bounds: bounds,
            axis: axis,
            itemCount: items.count,
            selectedIndex: items.firstIndex { $0.tab == selection },
            expandedWidth: selectedItem?.expandedWidth ?? 0,
            isRightToLeft: effectiveUserInterfaceLayoutDirection == .rightToLeft
        )

        // Fit the common material to the actual buttons, including the gaps.
        // The surrounding representable can remain wider in a bottom bar.
        let surfaceFrame = layout.frames.reduce(CGRect.null) { $0.union($1) }
        surface.frame = surfaceFrame.isNull ? .zero : surfaceFrame
        optics.frame = surface.bounds
        surface.layoutIfNeeded()

        for (item, frame) in zip(items, layout.frames) {
            item.semanticContentAttribute = semanticContentAttribute
            item.frame = frame.offsetBy(dx: -surface.frame.minX, dy: -surface.frame.minY)
            item.setNeedsLayout()
            item.layoutIfNeeded()
        }

        if let selectedItem {
            let inset = min(4, selectedItem.bounds.width / 2, selectedItem.bounds.height / 2)
            selectionHighlight.frame = selectedItem.frame.insetBy(dx: inset, dy: inset)
            selectionHighlight.isHidden = false
        } else {
            selectionHighlight.isHidden = true
        }
    }

    // Only space outside the shared capsule passes through to the content.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let shape = UIBezierPath(
            roundedRect: surface.frame,
            cornerRadius: min(surface.frame.width, surface.frame.height) / 2
        )
        guard shape.contains(point) else { return nil }
        guard let hit = super.hitTest(point, with: event) else { return nil }
        return hit.isDescendant(of: surface) ? hit : nil
    }
}
