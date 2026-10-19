// Ported from SplitPaneKit's `SplitPaneView` (https://github.com/jsmmth/SplitPaneKit).
//
// MIT License
//
// Copyright (c) 2025 Joseph Smith
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import CoreGraphics

/// How a drag moves a `SplitPane`'s bottom pane: SplitPaneKit's pan handling,
/// with its default thresholds.
nonisolated enum SplitPaneDrag {
    /// A release moves on a snap point after a drag this long, in points...
    static let distanceThreshold: CGFloat = 70
    /// ...or this fast, in points per second.
    static let velocityThreshold: CGFloat = 300
    /// Past the first or last snap point, a drag moves the pane only
    /// `1 - rubberBandingStrength` as far.
    static let rubberBandingStrength: CGFloat = 0.7

    /// The pane's height for `height`, resisting past `range`.
    static func rubberBanded(_ height: CGFloat, within range: ClosedRange<CGFloat>) -> CGFloat {
        let resistance = 1 - rubberBandingStrength
        if height < range.lowerBound {
            return range.lowerBound - (range.lowerBound - height) * resistance
        }
        if height > range.upperBound {
            return range.upperBound + (height - range.upperBound) * resistance
        }
        return height
    }

    /// Where a released drag settles: one snap point on in the drag's
    /// direction after a long or fast drag, otherwise back at `current`.
    /// - Parameters:
    ///   - startHeight: The pane's height when the drag began.
    ///   - endHeight: Its height at release.
    ///   - velocity: The finger's speed at release; positive moves down,
    ///     shrinking the pane.
    ///   - totalHeight: The split's height, which the ratios are shares of.
    static func target(
        from current: SplitPaneBreakpoint,
        in breakpoints: [SplitPaneBreakpoint],
        startHeight: CGFloat,
        endHeight: CGFloat,
        velocity: CGFloat,
        totalHeight: CGFloat
    ) -> SplitPaneBreakpoint {
        guard totalHeight > 0 else { return current }
        let sorted = breakpoints.sorted { $0.ratio < $1.ratio }
        let ratio = endHeight / totalHeight
        let distanceDown = startHeight - endHeight
        guard abs(distanceDown) > distanceThreshold || abs(velocity) > velocityThreshold else { return current }

        let isMovingDown = velocity > 0 || (velocity == 0 && distanceDown > 0)
        if isMovingDown {
            return sorted.last { $0.ratio < ratio - 0.01 } ?? sorted.first ?? current
        }
        return sorted.first { $0.ratio > ratio + 0.01 } ?? sorted.last ?? current
    }
}
