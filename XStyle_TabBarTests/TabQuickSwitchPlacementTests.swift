import Testing
import SwiftUI
@testable import XStyle_TabBar

@MainActor
struct TabQuickSwitchPlacementTests {
    /// A phone's safe area less the menu margin, over a bottom bar of four
    /// tabs that rests below it.
    private let area = CGRect(x: 16, y: 78, width: 370, height: 682)
    private let bar = CGRect(x: 38, y: 776, width: 326, height: 64)
    /// A Duo-style rail along the leading edge, and one along the trailing.
    private let leadingRail = CGRect(x: 8, y: 300, width: 60, height: 244)
    private let trailingRail = CGRect(x: 334, y: 300, width: 60, height: 244)
    private let spacing = TabQuickSwitchMetrics.spacing
    private let diameter = TabQuickSwitchMetrics.bubbleDiameter

    private func tabs(in bar: CGRect, axis: Axis) -> [CGRect] {
        let content = bar.insetBy(dx: 6, dy: 6)
        return (0..<4).map { index in
            axis == .horizontal
                ? CGRect(x: content.minX + CGFloat(index) * content.width / 4, y: content.minY,
                         width: content.width / 4, height: content.height)
                : CGRect(x: content.minX, y: content.minY + CGFloat(index) * content.height / 4,
                         width: content.width, height: content.height / 4)
        }
    }

    private func railArea(for rail: CGRect) -> CGRect {
        rail == leadingRail
            ? CGRect(x: rail.maxX + 16, y: area.minY, width: 402 - rail.maxX - 32, height: area.height)
            : CGRect(x: 16, y: area.minY, width: rail.minX - 32, height: area.height)
    }

    @Test("A list sits just above the bar, centred on its tab unless that would leave the safe area")
    func listSitsAboveHeldTab() {
        let size = CGSize(width: 200, height: 150)
        let tabs = tabs(in: bar, axis: .horizontal)
        for tab in tabs {
            let frame = TabQuickSwitchPlacement.listFrame(size: size, tab: tab, bar: bar, area: area,
                                                          axis: .horizontal, spacing: spacing)
            #expect(frame.size == size)
            #expect(frame.maxY == bar.minY - spacing)
            let centredX = tab.midX - size.width / 2
            let expectedX = centredX < area.minX ? area.minX
                : (centredX + size.width > area.maxX ? area.maxX - size.width : centredX)
            #expect(frame.minX == expectedX)
            #expect(frame.minX >= area.minX && frame.maxX <= area.maxX)
        }
        // The edge tabs are past centring: the list lines up with the area.
        #expect(TabQuickSwitchPlacement.listFrame(size: size, tab: tabs[0], bar: bar, area: area, axis: .horizontal,
                                                  spacing: spacing).minX == area.minX)
        #expect(TabQuickSwitchPlacement.listFrame(size: size, tab: tabs[3], bar: bar, area: area, axis: .horizontal,
                                                  spacing: spacing).maxX == area.maxX)

        // Too tall for the room above the bar, it takes all of it and scrolls.
        let tall = CGSize(width: 200, height: area.height + 100)
        let tallFrame = TabQuickSwitchPlacement.listFrame(size: tall, tab: tabs[1], bar: bar, area: area,
                                                          axis: .horizontal, spacing: spacing)
        #expect(tallFrame.minY == area.minY)
        #expect(tallFrame.maxY == bar.minY - spacing)
        // Too wide, it takes the area's width.
        let wide = CGSize(width: area.width + 50, height: 150)
        let wideFrame = TabQuickSwitchPlacement.listFrame(size: wide, tab: tabs[1], bar: bar, area: area,
                                                          axis: .horizontal, spacing: spacing)
        #expect(wideFrame.minX == area.minX)
        #expect(wideFrame.width == area.width)
    }

    @Test("On a rail, a list opens beside it, towards the screen, level with its tab")
    func listOpensBesideRail() {
        let size = CGSize(width: 180, height: 132)
        for rail in [leadingRail, trailingRail] {
            let railArea = railArea(for: rail)
            for tab in tabs(in: rail, axis: .vertical) {
                let frame = TabQuickSwitchPlacement.listFrame(size: size, tab: tab, bar: rail, area: railArea,
                                                              axis: .vertical, spacing: spacing)
                if rail == leadingRail {
                    #expect(frame.minX == rail.maxX + spacing)
                } else {
                    #expect(frame.maxX == rail.minX - spacing)
                }
                #expect(frame.midY == tab.midY)
            }
            let tall = TabQuickSwitchPlacement.listFrame(
                size: CGSize(width: size.width, height: railArea.height + 100), tab: tabs(in: rail, axis: .vertical)[0],
                bar: rail, area: railArea, axis: .vertical, spacing: spacing
            )
            #expect(tall.minY == railArea.minY && tall.maxY == railArea.maxY)
        }
    }

    @Test("Bubbles fan out above the bar, apart, leading first, within the safe area's sides, from every tab and language")
    func fanStaysClearAndInside() {
        for count in [2, 3, 5] {
            for isRightToLeft in [false, true] {
                for tab in tabs(in: bar, axis: .horizontal) {
                    let centers = TabQuickSwitchPlacement.fan(
                        count: count, diameter: diameter, tab: tab, bar: bar, area: area, axis: .horizontal,
                        isRightToLeft: isRightToLeft, spacing: spacing
                    )?.centers ?? []
                    #expect(centers.count == count)
                    expectApart(centers)
                    for frame in centers.map(bubbleFrame) {
                        #expect(frame.minX >= area.minX && frame.maxX <= area.maxX && frame.minY >= area.minY,
                                "Bubble \(frame) leaves \(area)")
                        #expect(frame.maxY <= bar.minY, "Bubble \(frame) covers the bar")
                    }
                    let xs = centers.map(\.x)
                    #expect(xs == (isRightToLeft ? xs.sorted(by: >) : xs.sorted()))
                }
            }
        }
    }

    @Test("On a rail, bubbles fan out beside it, top first, clear of it")
    func fanOpensBesideRail() {
        for rail in [leadingRail, trailingRail] {
            let railArea = railArea(for: rail)
            for tab in tabs(in: rail, axis: .vertical) {
                let centers = TabQuickSwitchPlacement.fan(
                    count: 5, diameter: diameter, tab: tab, bar: rail, area: railArea, axis: .vertical,
                    isRightToLeft: false, spacing: spacing
                )?.centers ?? []
                #expect(centers.count == 5)
                expectApart(centers)
                for frame in centers.map(bubbleFrame) {
                    #expect(frame.minY >= railArea.minY && frame.maxY <= railArea.maxY, "Bubble \(frame) leaves \(railArea)")
                    if rail == leadingRail {
                        #expect(frame.minX >= rail.maxX && frame.maxX <= railArea.maxX)
                    } else {
                        #expect(frame.maxX <= rail.minX && frame.minX >= railArea.minX)
                    }
                }
                let ys = centers.map(\.y)
                #expect(ys == ys.sorted())
            }
        }
    }

    @Test("No fan where its bubbles can't all fit, so the list shows instead")
    func fanGivesWayWhenItCantFit() {
        let tab = tabs(in: bar, axis: .horizontal)[1]
        #expect(TabQuickSwitchPlacement.fan(count: 5, diameter: diameter, tab: tab, bar: bar, area: area,
                                            axis: .horizontal, isRightToLeft: false, spacing: spacing) != nil)
        // Accessibility-sized bubbles, or a short window.
        #expect(TabQuickSwitchPlacement.fan(count: 5, diameter: diameter * 3, tab: tab, bar: bar, area: area,
                                            axis: .horizontal, isRightToLeft: false, spacing: spacing) == nil)
        let short = CGRect(x: area.minX, y: bar.minY - 120, width: area.width, height: 100)
        #expect(TabQuickSwitchPlacement.fan(count: 5, diameter: diameter, tab: tab, bar: bar, area: short,
                                            axis: .horizontal, isRightToLeft: false, spacing: spacing) == nil)
        #expect(TabQuickSwitchPlacement.fan(count: 0, diameter: diameter, tab: tab, bar: bar, area: area,
                                            axis: .horizontal, isRightToLeft: false, spacing: spacing) == nil)
    }

    @Test("The label sits past its bubble, clear of it, inside the safe area")
    func labelSitsPastBubble() throws {
        let size = CGSize(width: 90, height: 30)
        for tab in tabs(in: bar, axis: .horizontal) {
            let fan = try #require(TabQuickSwitchPlacement.fan(
                count: 5, diameter: diameter, tab: tab, bar: bar, area: area, axis: .horizontal,
                isRightToLeft: false, spacing: spacing
            ))
            for bubble in fan.centers {
                let label = TabQuickSwitchPlacement.fanLabelCenter(size: size, bubble: bubble, diameter: diameter,
                                                                   pivot: fan.pivot, area: area, spacing: spacing)
                let frame = CGRect(x: label.x - size.width / 2, y: label.y - size.height / 2,
                                   width: size.width, height: size.height)
                #expect(area.contains(frame))
                // Clear of its bubble: the label's nearest point is outside it.
                let gap = CGVector(dx: max(frame.minX - bubble.x, 0, bubble.x - frame.maxX),
                                   dy: max(frame.minY - bubble.y, 0, bubble.y - frame.maxY))
                #expect(hypot(gap.dx, gap.dy) >= diameter / 2)
            }
        }
    }

    private func bubbleFrame(_ center: CGPoint) -> CGRect {
        CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
    }

    private func expectApart(_ centers: [CGPoint]) {
        for (first, second) in zip(centers, centers.dropFirst()) {
            #expect(hypot(second.x - first.x, second.y - first.y) >= diameter)
        }
    }
}
