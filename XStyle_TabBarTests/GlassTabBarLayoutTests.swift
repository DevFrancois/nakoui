import Testing
import UIKit
@testable import XStyle_TabBar

@MainActor
@Suite(.serialized)
struct GlassTabBarLayoutTests {
    @Test("A fresh glass bar accepts repeated text-size updates before entering a window")
    func freshEnvironmentUpdatesDoNotReadUnsetTraitOverrides() throws {
        let view = GlassTabBarView(selection: .home)

        // The representable updates a newly created view before UIKit has
        // necessarily attached it or installed any trait overrides.
        for category: UIContentSizeCategory in [.large, .accessibilityExtraExtraExtraLarge, .large] {
            configure(view, category: category)
            let height = view.fittingHeight(for: 360)
            #expect(height.isFinite && height > 0)
            #expect(view.traitCollection.preferredContentSizeCategory == category)
            view.frame = CGRect(x: 0, y: 0, width: 360, height: height)
            view.layoutIfNeeded()
            try expectUsableButtons(in: view)
        }
    }

    @Test("The same controls remain usable when the bar changes axis and reading direction")
    func axisChangesPreserveControlsAndTouchTargets() throws {
        let view = GlassTabBarView(selection: .home)
        let originalButtons = try buttons(in: view)
        let originalIdentities = originalButtons.map(ObjectIdentifier.init)

        for (axis, direction, width): (NSLayoutConstraint.Axis, UIUserInterfaceLayoutDirection, CGFloat) in [
            (.horizontal, .leftToRight, 360),
            (.vertical, .leftToRight, GlassTabBarMetrics.verticalWidth),
            (.horizontal, .rightToLeft, 360),
        ] {
            configure(view, axis: axis, direction: direction)
            view.frame = CGRect(x: 0, y: 0, width: width, height: view.fittingHeight(for: width))
            view.layoutIfNeeded()

            let controls = try buttons(in: view)
            #expect(controls.map(ObjectIdentifier.init) == originalIdentities)
            try expectUsableButtons(in: view)
            let frames = controls.map { $0.convert($0.bounds, to: view) }

            for (first, second) in zip(frames, frames.dropFirst()) {
                if axis == .vertical {
                    #expect(first.maxY <= second.minY)
                    #expect(abs(first.midX - second.midX) < 0.5)
                } else {
                    #expect(abs(first.midY - second.midY) < 0.5)
                    if direction == .rightToLeft {
                        #expect(second.maxX <= first.minX)
                    } else {
                        #expect(first.maxX <= second.minX)
                    }
                }
            }
        }
    }

    @Test("Selection survives axis changes and VoiceOver activates a new tab only once")
    func adaptationPreservesSelectionAndActivationBehavior() throws {
        let view = GlassTabBarView(selection: .home)
        var selections: [RootTab] = []
        view.onSelect = { selections.append($0) }
        configure(view)
        view.frame = CGRect(x: 0, y: 0, width: 360, height: view.fittingHeight(for: 360))
        view.layoutIfNeeded()
        view.select(.profile, animated: false)

        for (axis, width): (NSLayoutConstraint.Axis, CGFloat) in [
            (.vertical, GlassTabBarMetrics.verticalWidth),
            (.horizontal, 360),
        ] {
            configure(view, axis: axis)
            view.frame = CGRect(x: 0, y: 0, width: width, height: view.fittingHeight(for: width))
            view.layoutIfNeeded()
            let controls = try buttons(in: view)
            #expect(controls.filter { $0.isSelected }.map(\.tab) == [RootTab.profile])
            #expect(controls.filter { $0.accessibilityTraits.contains(.selected) }.map(\.tab) == [RootTab.profile])
        }
        #expect(selections.isEmpty)

        let controls = try buttons(in: view)
        let search = try #require(controls.first { $0.tab == .search })
        #expect(search.accessibilityActivate())
        #expect(selections == [.search])
        #expect(controls.filter { $0.isSelected }.map(\.tab) == [RootTab.search])
        #expect(search.accessibilityTraits.contains(.selected))
        #expect(search.accessibilityActivate())
        #expect(selections == [.search], "Reactivating the selected tab must not change destinations again")
    }

    private func configure(
        _ view: GlassTabBarView,
        category: UIContentSizeCategory = .large,
        axis: NSLayoutConstraint.Axis = .horizontal,
        direction: UIUserInterfaceLayoutDirection = .leftToRight
    ) {
        view.updateEnvironment(
            locale: Locale(identifier: "en"),
            contentSizeCategory: category,
            layoutDirection: direction,
            layoutAxis: axis,
            reduceMotion: true,
            isEnabled: true
        )
    }

    private func buttons(in view: GlassTabBarView) throws -> [GlassTabBarButton] {
        let controls = try #require(view.accessibilityElements as? [GlassTabBarButton])
        try #require(controls.map(\.tab) == RootTab.allCases)
        return controls
    }

    private func expectUsableButtons(in view: GlassTabBarView) throws {
        let controls = try buttons(in: view)
        let frames = controls.map { $0.convert($0.bounds, to: view) }
        for (index, frame) in frames.enumerated() {
            #expect(frame.width >= 44 && frame.height >= 44, "Every destination needs a full touch target")
            #expect(view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame), "Controls must remain inside the glass bar")
            for other in frames.dropFirst(index + 1) {
                #expect(frame.intersection(other).isEmpty, "Destination touch targets must not overlap")
            }
        }
    }
}
