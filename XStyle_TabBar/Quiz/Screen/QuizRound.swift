import SwiftUI

/// Keeps the prompt and controls in one view tree while the available space
/// changes. Both remain visible in the scroll view at every window size.
struct QuizRound<Prompt: View, Answers: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var minimumColumnWidth = QuizRoundLayout.baseMinimumColumnWidth

    @ViewBuilder let prompt: Prompt
    @ViewBuilder let answers: Answers

    var body: some View {
        QuizRoundLayout(
            minimumColumnWidth: minimumColumnWidth,
            stacksVertically: dynamicTypeSize.isAccessibilitySize
        ) {
            prompt
            answers
        }
    }
}

/// A readable pair of columns when both fit; otherwise a centered stack.
/// Measuring the proposal directly avoids a geometry/state feedback cycle.
struct QuizRoundLayout: Layout {
    /// The minimum column width at the default text size.
    static let baseMinimumColumnWidth: CGFloat = 280
    static let defaultSpacing: CGFloat = 24

    var minimumColumnWidth: CGFloat
    var stacksVertically: Bool
    var spacing = Self.defaultSpacing

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = min(proposal.width ?? QuizMetrics.contentMaxWidth, QuizMetrics.expandedContentMaxWidth)
        let columns = usesColumns(width: width, count: subviews.count)
        let childWidth = columns ? (width - spacing) / 2 : min(width, QuizMetrics.contentMaxWidth)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: childWidth, height: nil)).height }
        let height = columns
            ? heights.max() ?? 0
            : heights.reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = usesColumns(width: bounds.width, count: subviews.count)
        let childWidth = columns ? (bounds.width - spacing) / 2 : min(bounds.width, QuizMetrics.contentMaxWidth)
        let childProposal = ProposedViewSize(width: childWidth, height: nil)
        var y = bounds.minY

        for (index, subview) in subviews.enumerated() {
            let x = columns
                ? bounds.minX + CGFloat(index) * (childWidth + spacing)
                : bounds.midX - childWidth / 2
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: childProposal)
            if !columns {
                y += subview.sizeThatFits(childProposal).height + spacing
            }
        }
    }

    private func usesColumns(width: CGFloat, count: Int) -> Bool {
        !stacksVertically && count == 2 && width >= minimumColumnWidth * 2 + spacing
    }
}
