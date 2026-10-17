import SwiftUI
import Testing
import UIKit
@testable import XStyle_TabBar

@MainActor
@Suite(.serialized)
struct ArticleLayoutTests {
    @Test("Continuous article content stays inside its current window")
    func columnsStayInsideCurrentViewport() {
        for width: CGFloat in [1_032, 736, 466, 393, 320, 736, 466, 1_366] {
            let columns = ArticleColumns(width: width, minimumReadingWidth: 300, prefersStack: false)
            for frame in [columns.gallery, columns.reading] {
                #expect(frame.minX >= ArticleMetrics.pageMargin)
                #expect(frame.maxX <= width - ArticleMetrics.pageMargin)
                #expect(frame.width > 0)
            }
            #expect(columns.gallery.width <= ArticleMetrics.heroMaxWidth)
            #expect(columns.reading.width <= ArticleMetrics.contentMaxWidth)
            if columns.isStacked {
                #expect(columns.gallery.midX == columns.reading.midX)
            } else {
                #expect(columns.gallery.maxX < columns.reading.minX)
                #expect(columns.reading.width >= 300)
            }
        }
    }

    @Test("The continuous reader's text requirement determines when it stacks")
    func scaledTextReflowsWithoutDeviceChecks() {
        let normal = ArticleColumns(width: 736, minimumReadingWidth: 300, prefersStack: false)
        let largerText = ArticleColumns(width: 736, minimumReadingWidth: 500, prefersStack: false)
        let accessibility = ArticleColumns(width: 1_366, minimumReadingWidth: 500, prefersStack: true)
        #expect(!normal.isStacked)
        #expect(largerText.isStacked)
        #expect(accessibility.isStacked)
    }

    @Test("Article selection and reading remain usable across regular and compact presentations")
    func selectedImageAndReaderSurvivePresentationChanges() async throws {
        let fixture = try makeHost()
        defer { fixture.window.isHidden = true }
        let state = fixture.state
        let host = fixture.host

        resize(host, width: 1_032, height: 700)
        try #require(await eventually { articleViewsAreLaidOut(in: host.view) })
        state.selectedImage = state.article.images[1]
        state.isLiked = true
        state.isBookmarked = true
        let lastParagraph = try #require(state.article.paragraphs.last)
        state.readingPosition.scrollTo(id: ArticleReadingPosition.paragraph(lastParagraph.id))
        let initialTargetReached = await eventually {
            selectedImageIsCentered(in: host.view) && readerOffset(in: host.view) > 80
        }
        try #require(initialTargetReached,
                     "The selected image and paragraph must be reached before resizing. \(layoutDescription(in: host.view)); selected=\(String(describing: state.selectedImage)); reader=\(String(describing: state.readingPosition.viewID(type: ArticleReadingPosition.self)))")

        // This exercises actual native scroll views and the size-class branch;
        // simulator posture transitions are verified separately on Duo.
        let configurations: [(CGFloat, CGFloat, UserInterfaceSizeClass)] = [
            (736, 700, .regular),
            (466, 900, .regular),
            (393, 852, .compact),
            (320, 700, .compact),
            (736, 700, .regular),
            (1_032, 700, .regular),
        ]
        for (width, height, sizeClass) in configurations {
            state.sizeClass = sizeClass
            resize(host, width: width, height: height)
            let reflowCompleted = await eventually {
                articleViewsAreLaidOut(in: host.view)
                    && selectedImageIsCentered(in: host.view)
                    && readerOffset(in: host.view) > 20
            }
            try #require(reflowCompleted,
                         "Both article panes and the selected image must survive \(sizeClass) \(width)×\(height). \(layoutDescription(in: host.view)); reader=\(String(describing: state.readingPosition.viewID(type: ArticleReadingPosition.self)))")

            #expect(state.selectedImage == state.article.images[1])
            #expect(state.isLiked)
            #expect(state.isBookmarked)
            #expect(state.readingPosition.viewID(type: ArticleReadingPosition.self) != nil)
            assertFiniteContent(in: host.view)
        }
    }

    @Test("Accessible article text remains reachable in both native presentations")
    func accessibilityReaderHasFiniteScrollableContent() async throws {
        let fixture = try makeHost()
        defer { fixture.window.isHidden = true }
        fixture.state.dynamicTypeSize = .accessibility3
        let lastParagraph = try #require(fixture.state.article.paragraphs.last)
        for (width, sizeClass): (CGFloat, UserInterfaceSizeClass) in [(736, .regular), (393, .compact), (736, .regular)] {
            fixture.state.sizeClass = sizeClass
            resize(fixture.host, width: width, height: 700)
            try #require(await eventually { articleViewsAreLaidOut(in: fixture.host.view) })
            let reader = try #require(readerScrollView(in: fixture.host.view))
            #expect(reader.contentSize.height > reader.bounds.height)
            assertFiniteContent(in: fixture.host.view)

            fixture.state.readingPosition.scrollTo(id: ArticleReadingPosition.paragraph(lastParagraph.id))
            let reached = await eventually { readerOffset(in: fixture.host.view) > 100 }
            try #require(reached,
                         "Large text must remain reachable through the native reader. \(layoutDescription(in: fixture.host.view)); reader=\(String(describing: fixture.state.readingPosition.viewID(type: ArticleReadingPosition.self)))")
        }
    }

    @Test("A compact article can reach a requested paragraph after initial layout")
    func compactReaderResolvesFreshParagraphTarget() async throws {
        let fixture = try makeHost()
        defer { fixture.window.isHidden = true }
        fixture.state.sizeClass = .compact
        resize(fixture.host, width: 393, height: 700)
        try #require(await eventually { articleViewsAreLaidOut(in: fixture.host.view) })
        let lastParagraph = try #require(fixture.state.article.paragraphs.last)
        fixture.state.readingPosition.scrollTo(id: ArticleReadingPosition.paragraph(lastParagraph.id))
        let reached = await eventually { readerOffset(in: fixture.host.view) > 100 }
        try #require(reached,
                     "A fresh paragraph request must reach compact reader content. \(layoutDescription(in: fixture.host.view)); reader=\(String(describing: fixture.state.readingPosition.viewID(type: ArticleReadingPosition.self)))")
    }

    @Test("A compact article restores its initial semantic paragraph")
    func compactReaderRestoresInitialParagraph() async throws {
        let state = ArticlePresentationState()
        state.sizeClass = .compact
        let lastParagraph = try #require(state.article.paragraphs.last)
        state.readingPosition = ScrollPosition(id: ArticleReadingPosition.paragraph(lastParagraph.id))
        let fixture = try makeHost(state: state)
        defer { fixture.window.isHidden = true }
        resize(fixture.host, width: 393, height: 700)
        let reached = await eventually {
            articleViewsAreLaidOut(in: fixture.host.view) && readerOffset(in: fixture.host.view) > 100
        }
        try #require(reached,
                     "Initial native ScrollPosition must restore the saved paragraph. \(layoutDescription(in: fixture.host.view)); reader=\(String(describing: state.readingPosition.viewID(type: ArticleReadingPosition.self)))")
    }

    private func makeHost(state initialState: ArticlePresentationState? = nil) throws -> (
        window: UIWindow, host: UIHostingController<ArticlePresentationFixture>, state: ArticlePresentationState
    ) {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let container = UIViewController()
        window.rootViewController = container
        window.isHidden = false
        let state = initialState ?? ArticlePresentationState()
        let host = UIHostingController(rootView: ArticlePresentationFixture(state: state))
        container.addChild(host)
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        return (window, host, state)
    }

    private func resize(_ host: UIViewController, width: CGFloat, height: CGFloat) {
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
    }

    private func articleViewsAreLaidOut(in root: UIView) -> Bool {
        guard let gallery = galleryScrollView(in: root), let reading = readerScrollView(in: root) else { return false }
        return [gallery, reading].allSatisfy { view in
            let frame = view.convert(view.bounds, to: root)
            return frame.width > 0 && frame.height > 0
                && frame.minX >= -1 && frame.maxX <= root.bounds.width + 1
                && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
        }
    }

    private func selectedImageIsCentered(in root: UIView) -> Bool {
        guard let gallery = galleryScrollView(in: root) else { return false }
        let width = gallery.bounds.width - gallery.adjustedContentInset.left - gallery.adjustedContentInset.right
        guard width > 0 else { return false }
        let offset = gallery.contentOffset.x + gallery.adjustedContentInset.left
        return abs(offset / width - 1) < 0.01
    }

    private func readerOffset(in root: UIView) -> CGFloat {
        guard let reader = readerScrollView(in: root) else { return 0 }
        return reader.contentOffset.y + reader.adjustedContentInset.top
    }

    private func galleryScrollView(in root: UIView) -> UIScrollView? {
        scrollViews(in: root).first { $0.bounds.width > 0 && $0.contentSize.width > $0.bounds.width * 1.5 }
    }

    private func readerScrollView(in root: UIView) -> UIScrollView? {
        let gallery = galleryScrollView(in: root)
        return scrollViews(in: root).first { $0 !== gallery }
    }

    private func layoutDescription(in root: UIView) -> String {
        scrollViews(in: root).map { scroll in
            "scroll frame=\(scroll.convert(scroll.bounds, to: root)) bounds=\(scroll.bounds) content=\(scroll.contentSize) offset=\(scroll.contentOffset) inset=\(scroll.adjustedContentInset)"
        }.joined(separator: "; ")
    }

    private func assertFiniteContent(in root: UIView) {
        for scroll in scrollViews(in: root) {
            #expect(scroll.bounds.width > 0)
            #expect(scroll.bounds.height > 0)
            let geometryIsFinite = [
                scroll.bounds.width, scroll.bounds.height,
                scroll.contentSize.width, scroll.contentSize.height,
                scroll.contentOffset.x, scroll.contentOffset.y,
            ].allSatisfy { $0.isFinite }
            #expect(geometryIsFinite)
        }
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        let ownScroll = (view as? UIScrollView).map { [$0] } ?? []
        return ownScroll + view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        var matches = 0
        for _ in 0..<150 {
            try? await Task.sleep(for: .milliseconds(20))
            matches = condition() ? matches + 1 : 0
            if matches == 2 { return true }
        }
        return false
    }
}

@MainActor
@Observable
private final class ArticlePresentationState {
    let article = Article.placeholder(number: 2, tint: .green)
    var sizeClass = UserInterfaceSizeClass.regular
    var dynamicTypeSize = DynamicTypeSize.large
    var selectedImage: ImageResource?
    var galleryPosition: CGFloat = 0
    var readingPosition = ScrollPosition(idType: ArticleReadingPosition.self)
    var isLiked = false
    var isBookmarked = false
}

private struct ArticlePresentationFixture: View {
    @Bindable var state: ArticlePresentationState

    var body: some View {
        ArticlePresentation(readingPosition: $state.readingPosition) {
            ArticleGalleryPanel(
                images: state.article.images,
                position: $state.galleryPosition,
                selectedImage: $state.selectedImage
            )
        } reading: {
            ArticleReadingContent(
                title: state.article.title, summary: state.article.summary, paragraphs: state.article.paragraphs,
                isLiked: $state.isLiked, isBookmarked: $state.isBookmarked
            )
        }
        .environment(\.horizontalSizeClass, state.sizeClass)
        .environment(\.dynamicTypeSize, state.dynamicTypeSize)
    }
}
