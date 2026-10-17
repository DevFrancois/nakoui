import SwiftUI
import Testing
import UIKit
@testable import XStyle_TabBar

@MainActor
@Suite(.serialized)
struct FeedStableLayoutTests {
    @Test("Feed components keep their heights and vertical positions while narrowing beside the rail", arguments: [DynamicTypeSize.large, .accessibility3])
    func horizontalTravelDoesNotReflowComponents(_ textSize: DynamicTypeSize) async throws {
        let fixture = try makeHost(textSize: textSize)
        defer { fixture.window.isHidden = true }
        // Components measure their resting widths before the page moves.
        let baseline = try await frames(in: fixture.host, width: 382)
        fixture.model.holdsSettledWidth = true

        // Small steps cover line-wrap thresholds and both directions.
        let expandingWidths = stride(from: CGFloat(389), through: 466, by: 7)
        let shrinkingWidths = stride(from: CGFloat(459), through: 382, by: -7)
        for width in Array(expandingWidths) + Array(shrinkingWidths) {
            let rendered = try await frames(in: fixture.host, width: width)
            for component in FeedComponent.allCases {
                let actual = try #require(rendered[component])
                let original = try #require(baseline[component])
                #expect(actual.height == original.height,
                        "\(component) height changed during horizontal travel at width \(width), text \(textSize): \(actual.height) vs \(original.height)")
                #expect(actual.minY == original.minY,
                        "\(component) moved vertically during horizontal travel at width \(width), text \(textSize): \(actual.minY) vs \(original.minY)")
                #expect(actual.width == width,
                        "\(component)'s surface must still adopt the available width; fixing the entire component width cannot pass")
            }
        }
    }

    @Test("A real window resize remeasures feed components and returning restores their layout")
    func settledWidthChangesStillAdaptComponents() async throws {
        let fixture = try makeHost(textSize: .large)
        defer { fixture.window.isHidden = true }
        let narrow = try await frames(in: fixture.host, width: 382)

        let wide = try await frames(in: fixture.host, width: 600)
        let narrowTask = try #require(narrow[.tasks])
        let wideTask = try #require(wide[.tasks])
        let narrowGrid = try #require(narrow[.tiles])
        let wideGrid = try #require(wide[.tiles])
        #expect(narrowTask.height > wideTask.height,
                "The real task message must use the extra window width instead of keeping a cached height")
        #expect(narrowGrid.height != wideGrid.height,
                "The actual tile grid must recompute columns and tile heights for a resized window")

        let restored = try await frames(in: fixture.host, width: 382)
        for component in FeedComponent.allCases {
            let actual = try #require(restored[component])
            let original = try #require(narrow[component])
            #expect(actual.height == original.height)
            #expect(actual.minY == original.minY)
        }
    }

    @Test("Larger accessibility text can grow every feed component")
    func dynamicTypeStillChangesComponentHeights() async throws {
        let fixture = try makeHost(textSize: .large)
        defer { fixture.window.isHidden = true }
        let normal = try await frames(in: fixture.host, width: 382)

        fixture.model.textSize = .accessibility3
        let accessible = try await frames(in: fixture.host, width: 382)
        for component in FeedComponent.allCases {
            let normalFrame = try #require(normal[component])
            let accessibleFrame = try #require(accessible[component])
            #expect(accessibleFrame.height > normalFrame.height,
                    "\(component) must grow for accessibility text rather than use a hard-coded height")
        }
    }

    private func makeHost(textSize: DynamicTypeSize) throws -> (
        window: UIWindow, host: UIHostingController<FeedComponentFixture>, model: FeedComponentModel
    ) {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let container = UIViewController()
        window.rootViewController = container
        window.isHidden = false
        let model = FeedComponentModel(textSize: textSize)
        let host = UIHostingController(rootView: FeedComponentFixture(model: model))
        // Test the components' proposed widths independently of the device's
        // own rail, status bar, or hosting window safe area.
        host.safeAreaRegions = []
        container.addChild(host)
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        return (window, host, model)
    }

    private func frames(
        in host: UIHostingController<FeedComponentFixture>, width: CGFloat
    ) async throws -> [FeedComponent: CGRect] {
        // A tall host gives every real grid item room to render, including
        // the accessibility layout. Markers are backgrounds, so they don't
        // contribute any size to the components being measured.
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: 20_000)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        var previous: [FeedComponent: CGRect] = [:]
        var consecutiveMatches = 0
        for _ in 0..<80 {
            try await Task.sleep(for: .milliseconds(20))
            host.view.layoutIfNeeded()
            var current: [FeedComponent: CGRect] = [:]
            for component in FeedComponent.allCases {
                if let marker = marker(for: component, in: host.view) {
                    let frame = marker.convert(marker.bounds, to: host.view)
                    if frame.height > 0 && abs(frame.width - width) < 0.5 {
                        current[component] = frame
                    }
                }
            }
            consecutiveMatches = current.count == FeedComponent.allCases.count && current == previous
                ? consecutiveMatches + 1 : 0
            if consecutiveMatches == 2 { return current }
            previous = current
        }
        Issue.record("Components did not settle at width \(width): \(previous)")
        return previous
    }

    private func marker(for component: FeedComponent, in root: UIView) -> UIView? {
        if root.accessibilityIdentifier == component.markerIdentifier { return root }
        for child in root.subviews {
            if let match = marker(for: component, in: child) { return match }
        }
        return nil
    }
}

private enum FeedComponent: String, CaseIterable {
    case tasks, whatsNew, tiles, post

    var markerIdentifier: String { "test.feed.component.\(rawValue)" }
}

@Observable
private final class FeedComponentModel {
    var textSize: DynamicTypeSize
    var holdsSettledWidth = false

    init(textSize: DynamicTypeSize) {
        self.textSize = textSize
    }
}

private struct FeedComponentFixture: View {
    let model: FeedComponentModel

    var body: some View {
        VStack(spacing: 0) {
            TaskStack(tasks: ForYouTask.samples, onOpen: {}, onDismiss: { _ in })
                .background(FeedComponentMarker(component: .tasks))
            WhatsNewRow(tint: .blue, action: {})
                .background(FeedComponentMarker(component: .whatsNew))
            ForYouTileGrid(onSelect: { _ in })
                .background(FeedComponentMarker(component: .tiles))
            FeedRow(tab: .bookmarks, number: 10)
                .background(FeedComponentMarker(component: .post))
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.holdsSettledWidth, model.holdsSettledWidth)
        .environment(\.dynamicTypeSize, model.textSize)
        .environment(\.layoutDirection, .leftToRight)
        .environment(\.locale, Locale(identifier: "en_US"))
    }
}

private struct FeedComponentMarker: UIViewRepresentable {
    let component: FeedComponent

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.accessibilityIdentifier = component.markerIdentifier
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
