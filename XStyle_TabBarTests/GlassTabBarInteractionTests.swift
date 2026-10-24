import Testing
import UIKit
@testable import XStyle_TabBar

@MainActor
struct GlassTabBarInteractionTests {
    @Test("Holding and dragging update only the finger candidate until release")
    func commitsFinalCandidateOnlyOnce() throws {
        let geometry = geometry()
        var interaction = GlassTabBarInteraction(selection: .home)
        interaction.begin(at: center(of: .scanner, in: geometry), geometry: geometry)
        #expect(interaction.tracking?.candidate == .scanner)
        #expect(interaction.selection == .home)

        interaction.move(to: center(of: .search, in: geometry))
        interaction.move(to: center(of: .profile, in: geometry))
        #expect(interaction.tracking?.candidate == .profile)
        #expect(interaction.selection == .home)

        #expect(interaction.release(at: center(of: .profile, in: geometry)) == .profile)
        #expect(interaction.selection == .profile)
        #expect(interaction.tracking == nil)
        #expect(interaction.release(at: center(of: .profile, in: geometry)) == nil)
    }

    @Test("Highlight position follows the finger continuously between destination centers")
    func continuouslyTracksPosition() throws {
        let geometry = geometry()
        var interaction = GlassTabBarInteraction(selection: .home)
        let first = center(of: .home, in: geometry)
        let second = center(of: .scanner, in: geometry)
        interaction.begin(at: first, geometry: geometry)
        let between = CGPoint(x: first.x + (second.x - first.x) * 0.3, y: first.y)
        interaction.move(to: between)
        #expect(interaction.tracking?.position == between.x)
        #expect(interaction.tracking?.candidate == .home)
        #expect(interaction.selection == .home)
        interaction.move(to: CGPoint(x: geometry.bounds.maxX - 1, y: first.y))
        #expect(interaction.tracking?.position == center(of: .search, in: geometry).x)
    }

    @Test("A hold started on the menu follows the finger anywhere and commits its nearest tab on release")
    func followsOffBarFingerAndClampsEndpoints() {
        for (geometry, lowTab, highTab) in [
            (geometry(), RootTab.home, RootTab.search),
            (geometry(rightToLeft: true), RootTab.search, RootTab.home),
            (geometry(axis: .vertical), RootTab.home, RootTab.search),
        ] {
            let isVertical = geometry.axis == .vertical
            let profile = center(of: .profile, in: geometry)
            let outsideProfile = isVertical ? CGPoint(x: -500, y: profile.y) : CGPoint(x: profile.x, y: -500)
            var interaction = GlassTabBarInteraction(selection: .home)
            interaction.begin(at: outsideProfile, geometry: geometry)
            #expect(interaction.tracking == nil, "An off-bar initial touch must not begin navigation")
            #expect(interaction.release(at: outsideProfile) == nil)

            interaction.begin(at: center(of: .home, in: geometry), geometry: geometry)
            interaction.move(to: outsideProfile)
            #expect(interaction.tracking?.candidate == .profile)
            #expect(interaction.tracking?.position == (isVertical ? profile.y : profile.x))
            #expect(interaction.selection == .home)

            let low = isVertical ? CGPoint(x: -500, y: -1000) : CGPoint(x: -1000, y: -500)
            let high = isVertical ? CGPoint(x: -500, y: 1000) : CGPoint(x: 1000, y: -500)
            for (point, tab) in [(low, lowTab), (high, highTab)] {
                interaction.move(to: point)
                let endpoint = center(of: tab, in: geometry)
                #expect(interaction.tracking?.candidate == tab)
                #expect(interaction.tracking?.position == (isVertical ? endpoint.y : endpoint.x))
                #expect(interaction.selection == .home)
            }
            interaction.move(to: center(of: .scanner, in: geometry))
            #expect(interaction.tracking?.candidate == .scanner)
            #expect(interaction.selection == .home)
            #expect(interaction.release(at: outsideProfile) == .profile)
            #expect(interaction.selection == .profile)
            #expect(interaction.release(at: outsideProfile) == nil)
        }
    }

    @Test("Cancellation and releasing on the committed destination never navigate")
    func cancellationAndSameTabAreNoOps() {
        let geometry = geometry()
        var interaction = GlassTabBarInteraction(selection: .home)
        interaction.begin(at: center(of: .search, in: geometry), geometry: geometry)
        interaction.cancel()
        #expect(interaction.release(at: center(of: .search, in: geometry)) == nil)
        #expect(interaction.selection == .home)
        interaction.begin(at: center(of: .home, in: geometry), geometry: geometry)
        #expect(interaction.release(at: center(of: .home, in: geometry)) == nil)
        #expect(interaction.tracking == nil)
    }

    @Test("Horizontal RTL and vertical layouts use actual control positions")
    func followsVisualOrder() {
        for geometry in [geometry(rightToLeft: true), geometry(axis: .vertical)] {
            var interaction = GlassTabBarInteraction(selection: .home)
            interaction.begin(at: center(of: .home, in: geometry), geometry: geometry)
            for tab in RootTab.allCases.reversed() {
                interaction.move(to: center(of: tab, in: geometry))
                #expect(interaction.tracking?.candidate == tab)
                #expect(interaction.selection == .home)
            }
            #expect(interaction.release(at: center(of: .profile, in: geometry)) == .profile)
        }
    }

    @Test("Identical layout updates preserve a hold; resizing, placement, axis and RTL changes cancel it")
    func geometryChangesCancelTracking() {
        let original = geometry()
        for replacement in [geometry(width: 320), geometry(origin: CGPoint(x: 40, y: 200)), geometry(axis: .vertical), geometry(rightToLeft: true)] {
            var interaction = GlassTabBarInteraction(selection: .home)
            interaction.begin(at: center(of: .search, in: original), geometry: original)
            interaction.validateGeometry(original)
            #expect(interaction.tracking?.candidate == .search)
            interaction.validateGeometry(replacement)
            #expect(interaction.tracking == nil)
            #expect(interaction.release(at: center(of: .search, in: original)) == nil)
            #expect(interaction.selection == .home)
        }
    }

    @Test("Repeated committed-selection updates preserve a hold; a real external change cancels it")
    func externalSelectionChangesCancelTracking() {
        let geometry = geometry()
        var interaction = GlassTabBarInteraction(selection: .home)
        interaction.begin(at: center(of: .search, in: geometry), geometry: geometry)
        let didReselectHome = interaction.select(.home)
        #expect(!didReselectHome)
        #expect(interaction.tracking?.candidate == .search)
        let didSelectScanner = interaction.select(.scanner)
        #expect(didSelectScanner)
        #expect(interaction.tracking == nil)
        #expect(interaction.selection == .scanner)
        #expect(interaction.release(at: center(of: .search, in: geometry)) == nil)
    }

    @Test("Finger emphasis does not preview the accessibility selection")
    func accessibilitySelectionStaysCommittedDuringTracking() {
        let home = GlassTabBarButton(tab: .home)
        let profile = GlassTabBarButton(tab: .profile)
        home.isSelected = true
        home.updateTrackingCandidate(false)
        profile.updateTrackingCandidate(true)
        #expect(home.accessibilityTraits.contains(.selected))
        #expect(!profile.accessibilityTraits.contains(.selected))
        home.updateTrackingCandidate(nil)
        profile.updateTrackingCandidate(nil)
        #expect(home.isSelected && !profile.isSelected)
    }

    @Test("Accessibility activation commits once and disabled tabs cannot activate")
    func accessibilityActivationUsesCommittedSelection() throws {
        let view = GlassTabBarView(selection: .home)
        view.frame = CGRect(x: 0, y: 0, width: 360, height: 64)
        var committedTabs: [RootTab] = []
        view.onSelect = { committedTabs.append($0) }
        let buttons = try #require(view.accessibilityElements as? [GlassTabBarButton])
        let profile = try #require(buttons.first { $0.tab == .profile })
        let search = try #require(buttons.first { $0.tab == .search })

        #expect(profile.accessibilityActivate())
        #expect(committedTabs == [.profile])
        #expect(buttons.filter { $0.accessibilityTraits.contains(.selected) }.map(\.tab) == [.profile])
        #expect(profile.accessibilityActivate())
        #expect(committedTabs == [.profile])

        view.updateEnvironment(
            locale: Locale(identifier: "en"),
            contentSizeCategory: .large,
            layoutDirection: .leftToRight,
            layoutAxis: .horizontal,
            reduceMotion: true,
            isEnabled: false
        )
        #expect(!search.accessibilityActivate())
        #expect(search.accessibilityTraits.contains(.notEnabled))
        #expect(committedTabs == [.profile])
    }

    private func geometry(
        width: CGFloat = 360,
        origin: CGPoint = .zero,
        axis: NSLayoutConstraint.Axis = .horizontal,
        rightToLeft: Bool = false
    ) -> GlassTabBarInteraction.Geometry {
        let isVertical = axis == .vertical
        let bounds = isVertical ? CGRect(x: 0, y: 0, width: 60, height: 244) : CGRect(x: 0, y: 0, width: width, height: 64)
        let content = bounds.insetBy(dx: isVertical ? 8 : 6, dy: 6)
        let items = RootTab.allCases.enumerated().map { index, tab in
            let visualIndex = !isVertical && rightToLeft ? RootTab.allCases.count - 1 - index : index
            let frame = isVertical
                ? CGRect(x: content.minX, y: content.minY + CGFloat(visualIndex) * 58, width: 44, height: 58)
                : CGRect(x: content.minX + CGFloat(visualIndex) * content.width / 4, y: content.minY, width: content.width / 4, height: content.height)
            return GlassTabBarInteraction.Item(tab: tab, frame: frame)
        }
        return .init(bounds: bounds, axis: axis, items: items, placement: CGPoint(x: origin.x + bounds.midX, y: origin.y + bounds.midY))
    }

    private func center(of tab: RootTab, in geometry: GlassTabBarInteraction.Geometry) -> CGPoint {
        let frame = geometry.items.first { $0.tab == tab }!.frame
        return CGPoint(x: frame.midX, y: frame.midY)
    }
}
