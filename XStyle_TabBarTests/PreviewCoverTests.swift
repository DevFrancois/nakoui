import Testing
@testable import XStyle_TabBar

struct PreviewCoverTests {
    @Test("A fresh run stays hidden until frames show in a window")
    func freshRunWaitsForWindowAndFrames() {
        #expect(PreviewCover.isCovered(isPreviewing: false, isInWindow: true, wasCovered: true))
        #expect(PreviewCover.isCovered(isPreviewing: true, isInWindow: false, wasCovered: true))
        #expect(!PreviewCover.isCovered(isPreviewing: true, isInWindow: true, wasCovered: true))
    }

    @Test("A live preview moved between containers stays visible")
    func reparentingKeepsLivePreview() {
        #expect(!PreviewCover.isCovered(isPreviewing: true, isInWindow: false, wasCovered: false))
    }

    @Test("Whenever frames stop, the feed hides, in a window or not")
    func everyStopHides() {
        // Under the result sheet at full, or interrupted: it comes back from black.
        #expect(PreviewCover.isCovered(isPreviewing: false, isInWindow: true, wasCovered: false))
        // Leaving the tab.
        #expect(PreviewCover.isCovered(isPreviewing: false, isInWindow: false, wasCovered: false))
    }
}
