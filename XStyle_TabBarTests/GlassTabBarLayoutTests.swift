import SwiftUI
import Testing
@testable import XStyle_TabBar

struct GlassTabBarLayoutTests {
    @Test("A native vertical bar measures to its buttons without blank panel ends", arguments: [CGFloat(32), 40, 44, 56])
    func nativeVerticalWidthFitsTheOccupiedPanel(_ offeredWidth: CGFloat) throws {
        let size = GlassTabBarLayout.fittingSize(
            proposal: ProposedViewSize(width: offeredWidth, height: nil),
            axis: .vertical, itemCount: 4, horizontalHeight: 56
        )
        #expect(size.width <= offeredWidth)
        #expect(size.width == min(offeredWidth, 44))

        let bounds = CGRect(origin: CGPoint(x: 12, y: 24), size: size)
        let result = layout(in: bounds, axis: .vertical, selection: 1)
        try #require(result.frames.count == 4)
        expectContainedNonoverlappingFrames(result.frames, in: bounds)
        #expect(abs(result.frames[0].minY - bounds.minY) < 0.001,
                "The measured panel must begin at its first tab")
        #expect(abs(result.frames[3].maxY - bounds.maxY) < 0.001,
                "The measured panel must end at its last tab")
        for frame in result.frames {
            #expect(frame.width == size.width && frame.height == size.width,
                    "The native width determines the compact circular buttons")
        }
    }

    @Test("A vertical bar respects the offered height without enlarging its panel", arguments: [CGFloat(88), 176, 206, 400])
    func verticalPanelRespectsAvailableHeight(_ offeredHeight: CGFloat) throws {
        let idealSize = GlassTabBarLayout.fittingSize(
            proposal: ProposedViewSize(width: 44, height: nil),
            axis: .vertical, itemCount: 4, horizontalHeight: 56
        )
        let fittedSize = GlassTabBarLayout.fittingSize(
            proposal: ProposedViewSize(width: 44, height: offeredHeight),
            axis: .vertical, itemCount: 4, horizontalHeight: 56
        )
        #expect(fittedSize.width == 44)
        #expect(fittedSize.height == min(offeredHeight, idealSize.height))

        let bounds = CGRect(origin: .zero, size: fittedSize)
        let result = layout(in: bounds, axis: .vertical, selection: nil)
        try #require(result.frames.count == 4)
        expectContainedNonoverlappingFrames(result.frames, in: bounds)
        #expect(abs(result.frames[0].minY - bounds.minY) < 0.001)
        #expect(abs(result.frames[3].maxY - bounds.maxY) < 0.001)
    }

    @Test("Larger horizontal controls do not inflate the native vertical menu", arguments: [CGFloat(56), 80, 112])
    func dynamicTypeHeightOnlyAffectsTheHorizontalMenu(_ horizontalHeight: CGFloat) {
        let compactVerticalSize = GlassTabBarLayout.fittingSize(
            proposal: ProposedViewSize(width: 44, height: nil),
            axis: .vertical, itemCount: 4, horizontalHeight: 56
        )
        let verticalSize = GlassTabBarLayout.fittingSize(
            proposal: ProposedViewSize(width: 44, height: nil),
            axis: .vertical, itemCount: 4, horizontalHeight: horizontalHeight
        )
        #expect(verticalSize == compactVerticalSize)

        let horizontalSize = GlassTabBarLayout.fittingSize(
            proposal: ProposedViewSize(width: 700, height: nil),
            axis: .horizontal, itemCount: 4, horizontalHeight: horizontalHeight
        )
        #expect(horizontalSize.height == horizontalHeight)
        #expect(horizontalSize.width == 460)
    }

    @Test("Unspecified and unlimited measurement probes produce finite menu sizes", arguments: [Axis.horizontal, .vertical])
    func flexibleMeasurementProbesAreFinite(_ axis: Axis) {
        for proposal in [
            ProposedViewSize.unspecified,
            .infinity,
            .zero,
            ProposedViewSize(width: nil, height: .infinity),
            ProposedViewSize(width: .infinity, height: nil),
        ] {
            let size = GlassTabBarLayout.fittingSize(
                proposal: proposal, axis: axis, itemCount: 4, horizontalHeight: 56
            )
            #expect(size.width.isFinite && size.height.isFinite)
            #expect(size.width >= 0 && size.height >= 0)
            #expect(size.width <= (axis == .vertical ? 44 : 460))
            let bounds = CGRect(origin: .zero, size: size)
            let result = layout(in: bounds, axis: axis, selection: 1)
            expectContainedNonoverlappingFrames(result.frames, in: bounds)
        }
    }

    @Test("A vertical menu keeps circular tabs in top-to-bottom order")
    func verticalMenuKeepsItsOrderWhenSelectionOrReadingDirectionChanges() throws {
        let bounds = CGRect(x: 12, y: 24, width: 64, height: 200)
        let baseline = layout(in: bounds, axis: .vertical, selection: nil)
        try #require(baseline.frames.count == 4)
        expectContainedNonoverlappingFrames(baseline.frames, in: bounds)

        for frame in baseline.frames {
            #expect(frame.width == frame.height)
            #expect(abs(frame.midX - bounds.midX) < 0.001)
            #expect(frame.width >= 44)
        }
        #expect(baseline.frames[0].maxY <= baseline.frames[1].minY)
        #expect(baseline.frames[1].maxY <= baseline.frames[2].minY)
        #expect(baseline.frames[2].maxY <= baseline.frames[3].minY)

        for selection in [nil, 0, 1, 2, 3] as [Int?] {
            for rightToLeft in [false, true] {
                let updated = layout(
                    in: bounds, axis: .vertical,
                    selection: selection, expandedWidth: 240,
                    rightToLeft: rightToLeft
                )
                #expect(updated.frames == baseline.frames,
                        "Vertical tabs must keep their positions when selection or reading direction changes")
            }
        }
    }

    @Test("A bottom menu gives its selected tab room for a label", arguments: [0, 1, 2, 3])
    func horizontalSelectionExpandsWhenThereIsRoom(_ selection: Int) throws {
        let bounds = CGRect(x: 18, y: 9, width: 360, height: 56)
        let result = layout(in: bounds, axis: .horizontal, selection: selection, expandedWidth: 128)
        try #require(result.frames.count == 4)
        expectContainedNonoverlappingFrames(result.frames, in: bounds)

        #expect(abs(result.frames[selection].width - 128) < 0.001)
        for (index, frame) in result.frames.enumerated() {
            #expect(frame.width >= 44 && frame.height >= 44)
            #expect(abs(frame.midY - bounds.midY) < 0.001)
            if index != selection {
                #expect(frame.width == frame.height)
                #expect(frame.width < result.frames[selection].width)
            }
        }
        #expect(result.frames[0].maxX <= result.frames[1].minX)
        #expect(result.frames[1].maxX <= result.frames[2].minX)
        #expect(result.frames[2].maxX <= result.frames[3].minX)
    }

    @Test("Right-to-left bottom menus mirror positions while keeping tab identity", arguments: [0, 1, 2, 3])
    func horizontalReadingDirectionMirrorsEachTab(_ selection: Int) throws {
        let bounds = CGRect(x: 37, y: 11, width: 340, height: 56)
        let leftToRight = layout(in: bounds, axis: .horizontal, selection: selection)
        let rightToLeft = layout(in: bounds, axis: .horizontal, selection: selection, rightToLeft: true)
        try #require(leftToRight.frames.count == 4 && rightToLeft.frames.count == 4)
        expectContainedNonoverlappingFrames(rightToLeft.frames, in: bounds)

        for (leftFrame, rightFrame) in zip(leftToRight.frames, rightToLeft.frames) {
            #expect(leftFrame.size == rightFrame.size)
            #expect(leftFrame.minY == rightFrame.minY)
            #expect(abs(leftFrame.midX + rightFrame.midX - bounds.midX * 2) < 0.001)
        }
        #expect(rightToLeft.frames[0].minX >= rightToLeft.frames[1].maxX)
        #expect(rightToLeft.frames[1].minX >= rightToLeft.frames[2].maxX)
        #expect(rightToLeft.frames[2].minX >= rightToLeft.frames[3].maxX)
    }

    @Test("Spacing and label expansion yield before 44-point targets", arguments: [Axis.horizontal, .vertical])
    func compactMenusRetainMinimumTargets(_ axis: Axis) throws {
        let bounds = axis == .horizontal
            ? CGRect(x: 5, y: 7, width: 176, height: 44)
            : CGRect(x: 5, y: 7, width: 44, height: 176)
        let result = layout(in: bounds, axis: axis, selection: 1, expandedWidth: 220)
        try #require(result.frames.count == 4)
        expectContainedNonoverlappingFrames(result.frames, in: bounds)
        for frame in result.frames {
            #expect(frame.width >= 44 && frame.height >= 44)
        }
    }

    @Test("Menus stay inside constrained bounds even when minimum targets cannot fit", arguments: [Axis.horizontal, .vertical])
    func undersizedMenusDoNotOverlapOrOverflow(_ axis: Axis) throws {
        let bounds = axis == .horizontal
            ? CGRect(x: 13, y: 17, width: 90, height: 36)
            : CGRect(x: 13, y: 17, width: 36, height: 90)
        let result = layout(in: bounds, axis: axis, selection: 2, expandedWidth: 300)
        try #require(result.frames.count == 4)
        expectContainedNonoverlappingFrames(result.frames, in: bounds)
        #expect(result.frames.allSatisfy { $0.width > 0 && $0.height > 0 })
    }

    @Test("Unselected horizontal tabs have equal circular targets")
    func noSelectionDoesNotReserveAnExpandedLabel() throws {
        let bounds = CGRect(x: 0, y: 0, width: 340, height: 56)
        let result = layout(in: bounds, axis: .horizontal, selection: nil)
        let first = try #require(result.frames.first)
        try #require(result.frames.count == 4)
        expectContainedNonoverlappingFrames(result.frames, in: bounds)
        for frame in result.frames {
            #expect(frame.size == first.size)
            #expect(frame.width == frame.height)
        }
    }

    @Test("Empty menus and zero dimensions produce no invalid geometry", arguments: [Axis.horizontal, .vertical])
    func emptyAndZeroSizedMenusAreSafe(_ axis: Axis) {
        let empty = GlassTabBarLayout(
            bounds: CGRect(x: 0, y: 0, width: 340, height: 56),
            axis: axis, itemCount: 0, selectedIndex: nil,
            expandedWidth: 128, isRightToLeft: false
        )
        #expect(empty.frames.isEmpty)

        for bounds in [
            CGRect.zero,
            CGRect(x: 8, y: 12, width: 0, height: 200),
            CGRect(x: 8, y: 12, width: 200, height: 0),
        ] {
            let result = layout(in: bounds, axis: axis, selection: 1)
            expectContainedNonoverlappingFrames(result.frames, in: bounds)
        }
    }

    private func layout(
        in bounds: CGRect, axis: Axis, selection: Int?,
        expandedWidth: CGFloat = 128, rightToLeft: Bool = false
    ) -> GlassTabBarLayout {
        GlassTabBarLayout(
            bounds: bounds, axis: axis, itemCount: 4,
            selectedIndex: selection, expandedWidth: expandedWidth,
            isRightToLeft: rightToLeft
        )
    }

    private func expectContainedNonoverlappingFrames(_ frames: [CGRect], in bounds: CGRect) {
        let tolerance: CGFloat = 0.001
        for (index, frame) in frames.enumerated() {
            #expect(frame.origin.x.isFinite && frame.origin.y.isFinite)
            #expect(frame.width.isFinite && frame.height.isFinite)
            #expect(frame.width >= 0 && frame.height >= 0)
            #expect(frame.minX >= bounds.minX - tolerance && frame.maxX <= bounds.maxX + tolerance)
            #expect(frame.minY >= bounds.minY - tolerance && frame.maxY <= bounds.maxY + tolerance)

            for other in frames.dropFirst(index + 1) {
                let overlap = frame.intersection(other)
                #expect(overlap.isNull || overlap.width <= tolerance || overlap.height <= tolerance,
                        "Separate tabs must not overlap: \(frame) and \(other)")
            }
        }
    }
}
