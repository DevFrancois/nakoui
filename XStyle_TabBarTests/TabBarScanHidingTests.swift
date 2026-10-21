import Testing
import UIKit
@testable import XStyle_TabBar

struct TabBarScanHidingTests {
    @Test("The tab bar makes way only for the scan sheet, on a horizontal bar")
    func hidesOnlyForScanSheet() {
        #expect(GlassTabBar.hidesForScanSheet(selection: .scanner, isSheetShown: true, layoutAxis: .horizontal) == true)
        #expect(GlassTabBar.hidesForScanSheet(selection: .scanner, isSheetShown: false, layoutAxis: .horizontal) == false)
        #expect(GlassTabBar.hidesForScanSheet(selection: .home, isSheetShown: true, layoutAxis: .horizontal) == false)
    }

    @Test("The Duo's vertical rail stays while the scan sheet shows")
    func keepsVerticalRail() {
        #expect(GlassTabBar.hidesForScanSheet(selection: .scanner, isSheetShown: true, layoutAxis: .vertical) == false)
    }
}
