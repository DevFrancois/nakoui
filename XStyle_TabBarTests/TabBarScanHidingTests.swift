import Testing
import UIKit
@testable import XStyle_TabBar

struct TabBarScanHidingTests {
    @Test("The tab bar makes way only for a scan result, on a horizontal bar")
    func hidesOnlyForScanResult() {
        #expect(GlassTabBar.hidesForScanResult(selection: .scanner, hasResult: true, layoutAxis: .horizontal) == true)
        #expect(GlassTabBar.hidesForScanResult(selection: .scanner, hasResult: false, layoutAxis: .horizontal) == false)
        #expect(GlassTabBar.hidesForScanResult(selection: .home, hasResult: true, layoutAxis: .horizontal) == false)
    }

    @Test("The Duo's vertical rail stays while a result shows")
    func keepsVerticalRail() {
        #expect(GlassTabBar.hidesForScanResult(selection: .scanner, hasResult: true, layoutAxis: .vertical) == false)
    }
}
