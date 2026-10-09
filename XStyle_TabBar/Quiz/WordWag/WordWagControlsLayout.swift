import SwiftUI

/// The controls side by side, each as wide as its title needs plus an even
/// share of the spare room, or stacked full width once the titles can't
/// all fit on one line, as on a 375-point iPhone at large text sizes or in
/// a longer translation. Measuring rather than checking the text size keeps
/// the row wherever it fits, and never squeezes a title onto two lines.
struct WordWagControlsLayout: Layout {
    let spacing: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? Double($0) : nil } ?? rowWidth(of: subviews)
        let height = frames(width: width, subviews: subviews).map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    /// Each control's width with its title on one line.
    private func idealWidths(of subviews: Subviews) -> [Double] {
        subviews.map { Double($0.sizeThatFits(.unspecified).width) }
    }

    private func rowWidth(of subviews: Subviews) -> Double {
        idealWidths(of: subviews).reduce(0, +) + spacing * Double(max(subviews.count - 1, 0))
    }

    private func frames(width: Double, subviews: Subviews) -> [CGRect] {
        guard !subviews.isEmpty else { return [] }
        let ideals = idealWidths(of: subviews)
        let spare = width - ideals.reduce(0, +) - spacing * Double(subviews.count - 1)

        if spare >= 0 {
            let widths = ideals.map { $0 + spare / Double(subviews.count) }
            // One height for the whole row, so the capsules line up.
            let height = zip(subviews, widths).map { subview, width in
                Double(subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height)
            }.max() ?? 0
            var x = 0.0
            return widths.map { width in
                defer { x += width + spacing }
                return CGRect(x: x, y: 0, width: width, height: height)
            }
        }

        var y = 0.0
        return subviews.map { subview in
            let height = Double(subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height)
            defer { y += height + spacing }
            return CGRect(x: 0, y: y, width: width, height: height)
        }
    }
}
