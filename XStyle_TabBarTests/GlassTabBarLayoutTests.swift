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
            let size = view.fittingSize(proposedWidth: 360)
            #expect(size.height.isFinite && size.height > 0)
            #expect(view.traitCollection.preferredContentSizeCategory == category)
            view.frame = CGRect(origin: .zero, size: size)
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
            (.vertical, .leftToRight, GlassTabBarMetrics.preferredVerticalWidth),
            (.horizontal, .rightToLeft, 360),
        ] {
            configure(view, axis: axis, direction: direction)
            view.frame = CGRect(origin: .zero, size: view.fittingSize(proposedWidth: width))
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
        view.frame = CGRect(origin: .zero, size: view.fittingSize(proposedWidth: 360))
        view.layoutIfNeeded()
        view.select(.profile, animated: false)

        for (axis, width): (NSLayoutConstraint.Axis, CGFloat) in [
            (.vertical, GlassTabBarMetrics.preferredVerticalWidth),
            (.horizontal, 360),
        ] {
            configure(view, axis: axis)
            view.frame = CGRect(origin: .zero, size: view.fittingSize(proposedWidth: width))
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

    @Test("Narrow horizontal proposals preserve four touch targets, identities and VoiceOver selection")
    func horizontalResizingPreservesControlsAndSelection() throws {
        let view = GlassTabBarView(selection: .profile)
        let identities = try buttons(in: view).map(ObjectIdentifier.init)
        var selections: [RootTab] = []
        view.onSelect = { selections.append($0) }

        for direction: UIUserInterfaceLayoutDirection in [.leftToRight, .rightToLeft] {
            configure(view, direction: direction)
            for width: CGFloat in [360, 326, 320, 188, 180, 176, 360] {
                let size = view.fittingSize(proposedWidth: width)
                #expect(size.width == min(width, GlassTabBarMetrics.preferredHorizontalWidth))
                view.frame = CGRect(origin: .zero, size: size)
                view.layoutIfNeeded()
                try expectUsableButtons(in: view)

                let controls = try buttons(in: view)
                #expect(controls.map(ObjectIdentifier.init) == identities)
                #expect(controls.filter { $0.accessibilityTraits.contains(.selected) }.map(\.tab) == [.profile])
                let first = try #require(controls.first)
                let last = try #require(controls.last)
                #expect(direction == .rightToLeft ? first.frame.minX > last.frame.minX : first.frame.minX < last.frame.minX)
                #expect(controls.allSatisfy { !($0.accessibilityLabel ?? "").isEmpty })
            }
        }
        #expect(selections.isEmpty, "Resizing and mirroring must not navigate")

        let search = try #require(buttons(in: view).first { $0.tab == .search })
        #expect(search.accessibilityActivate())
        #expect(search.accessibilityActivate())
        #expect(selections == [.search])
        #expect(search.accessibilityTraits.contains(.selected))
    }

    @Test("Vertical proposals compress capsule padding before any touch target")
    func narrowVerticalProposalsKeepFullTouchTargets() throws {
        let view = GlassTabBarView(selection: .profile)
        let identities = try buttons(in: view).map(ObjectIdentifier.init)
        configure(view, category: .accessibilityExtraExtraExtraLarge, axis: .vertical)

        for width: CGFloat in [56, 50, 44, 56] {
            let size = view.fittingSize(proposedWidth: width)
            #expect(size == CGSize(width: width, height: 188))
            view.frame = CGRect(origin: .zero, size: size)
            view.layoutIfNeeded()
            try expectUsableButtons(in: view)
            let controls = try buttons(in: view)
            #expect(controls.map(ObjectIdentifier.init) == identities)
            #expect(controls.filter { $0.accessibilityTraits.contains(.selected) }.map(\.tab) == [.profile])
            for (first, second) in zip(controls, controls.dropFirst()) {
                #expect(first.frame.maxY <= second.frame.minY)
            }
        }
    }

    @Test("Unspecified and infinite proposals use preferred sizes; minimum probes retain touch targets")
    func proposalExtremesProduceUsableFiniteSizes() throws {
        let view = GlassTabBarView(selection: .home)
        for (axis, preferredWidth, minimumWidth): (NSLayoutConstraint.Axis, CGFloat, CGFloat) in [
            (.horizontal, 326, 176),
            (.vertical, 56, 44),
        ] {
            configure(view, axis: axis)
            for proposal: CGFloat? in [nil, .infinity, .nan, 10_000] {
                let size = view.fittingSize(proposedWidth: proposal)
                #expect(size.width == preferredWidth)
                #expect(size.height.isFinite && size.height > 0)
            }
            for proposal: CGFloat in [-1, 0, 1, minimumWidth - 1] {
                let size = view.fittingSize(proposedWidth: proposal)
                #expect(size.width == minimumWidth)
                view.frame = CGRect(origin: .zero, size: size)
                view.layoutIfNeeded()
                try expectUsableButtons(in: view)
            }
        }
    }

    @Test("Accessibility text grows the preferred width and wraps vertically when width is constrained")
    func dynamicTypeExpandsPreferredWidthAndConstrainedHeight() throws {
        let view = GlassTabBarView(selection: .home)
        configure(view)
        let standardPreferred = view.fittingSize(proposedWidth: nil)
        let standardNarrow = view.fittingSize(proposedWidth: 176)

        configure(view, category: .accessibilityExtraExtraExtraLarge)
        let accessiblePreferred = view.fittingSize(proposedWidth: nil)
        let accessibleNarrow = view.fittingSize(proposedWidth: 176)
        #expect(accessiblePreferred.width > standardPreferred.width)
        #expect(accessibleNarrow.width == 176)
        #expect(accessibleNarrow.height > accessiblePreferred.height,
                "A constrained menu must grow tall enough for its wrapped labels")
        #expect(accessibleNarrow.height > standardNarrow.height)

        for width in [accessiblePreferred.width, 320, 176] {
            let size = view.fittingSize(proposedWidth: width)
            view.frame = CGRect(origin: .zero, size: size)
            view.layoutIfNeeded()
            try expectUsableButtons(in: view)
            for control in try buttons(in: view) {
                let requiredHeight = control.sizeThatFits(CGSize(width: control.bounds.width,
                                                                 height: .greatestFiniteMagnitude)).height
                #expect(control.bounds.height >= requiredHeight,
                        "Every control must fit its measured symbol and wrapped title")
            }
        }

        configure(view)
        #expect(view.fittingSize(proposedWidth: nil) == standardPreferred)
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
