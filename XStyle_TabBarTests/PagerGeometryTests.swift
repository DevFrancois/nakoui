import SwiftUI
import Testing
@testable import XStyle_TabBar

struct PagerGeometryTests {
    @Test("Page progress uses the measured viewport on every device width")
    func measuredWidthDefinesPageBoundaries() {
        for width: CGFloat in [393, 466, 736] {
            for index in AppTab.allCases.indices {
                let geometry = PagerGeometry(offset: CGFloat(index) * width, width: width)

                #expect(geometry.progress == CGFloat(index))
                #expect(geometry.nearestPageIndex(pageCount: AppTab.allCases.count) == index)
            }

            let halfway = PagerGeometry(offset: width * 1.5, width: width)
            #expect(halfway.progress == 1.5)
        }
    }

    @Test("The nearest page is bounded during edge overscroll")
    func clampsOverscrollToAnExistingPage() {
        let leading = PagerGeometry(offset: -240, width: 400)
        let trailing = PagerGeometry(offset: 2_200, width: 400)

        #expect(leading.nearestPageIndex(pageCount: 5) == 0)
        #expect(trailing.nearestPageIndex(pageCount: 5) == 4)
        #expect(PagerGeometry(offset: 590, width: 400).nearestPageIndex(pageCount: 5) == 1)
        #expect(PagerGeometry(offset: 610, width: 400).nearestPageIndex(pageCount: 5) == 2)
    }

    @Test("An unmeasured viewport has no fractional progress")
    func zeroWidthDoesNotDivideByZero() {
        #expect(PagerGeometry(offset: 400, width: 0).progress == 0)
    }
}
