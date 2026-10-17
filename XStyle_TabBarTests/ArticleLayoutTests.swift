import CoreGraphics
import Testing
@testable import XStyle_TabBar

struct ArticleLayoutTests {
    @Test("Article content reflows within the current window through repeated folds")
    func columnsStayInsideCurrentViewport() {
        for width: CGFloat in [1_032, 736, 466, 393, 320, 736, 466, 1_366] {
            let columns = ArticleColumns(width: width, minimumReadingWidth: 300, prefersStack: false, division: nil)
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

    @Test("The reading column's text requirement determines when the article stacks")
    func scaledTextReflowsWithoutDeviceChecks() {
        let normal = ArticleColumns(width: 736, minimumReadingWidth: 300, prefersStack: false, division: nil)
        let largerText = ArticleColumns(width: 736, minimumReadingWidth: 500, prefersStack: false, division: nil)
        let accessibility = ArticleColumns(width: 1_366, minimumReadingWidth: 500, prefersStack: true, division: nil)
        #expect(!normal.isStacked)
        #expect(largerText.isStacked)
        #expect(accessibility.isStacked)
    }

    @Test("An active vertical division separates gallery and text without guessed hinge dimensions")
    func nativeDivisionDefinesColumns() {
        let division = CGRect(x: 340, y: 0, width: 12, height: 800)
        let columns = ArticleColumns(width: 736, minimumReadingWidth: 300, prefersStack: false, division: division)
        #expect(!columns.isStacked)
        #expect(columns.gallery.maxX < division.minX)
        #expect(columns.reading.minX > division.maxX)

        let enlarged = ArticleColumns(width: 736, minimumReadingWidth: 600, prefersStack: true, division: division)
        #expect(enlarged.isStacked)
        #expect(enlarged.gallery.minX > division.maxX)
        #expect(enlarged.reading.minX > division.maxX)
        #expect(enlarged.reading.maxX <= 720)
    }
}
