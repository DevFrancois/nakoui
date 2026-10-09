import SwiftUI

/// The outline of an empty spot: dashed for an answer slot, lit in mint for
/// the one that fills next, and a faint well where a tray tile used to be.
/// One shape whose styles change, since sockets flip on nearly every tap.
struct WordWagSocket: View {
    let style: WordWagSocketStyle

    var body: some View {
        RoundedRectangle(cornerRadius: WordWagMetrics.tileCornerRadius)
            .fill(fill)
            .strokeBorder(stroke, style: strokeStyle)
            .opacity(style == .hidden ? 0 : 1)
            .accessibilityHidden(true)
    }

    private var fill: AnyShapeStyle {
        switch style {
        case .nextSlot: AnyShapeStyle(QuizKind.wordWag.tint.opacity(0.15))
        case .hole: AnyShapeStyle(.quinary)
        case .slot, .hidden: AnyShapeStyle(.clear)
        }
    }

    private var stroke: AnyShapeStyle {
        switch style {
        case .slot: AnyShapeStyle(.tertiary)
        case .nextSlot: AnyShapeStyle(QuizKind.wordWag.tint)
        case .hole: AnyShapeStyle(.quaternary)
        case .hidden: AnyShapeStyle(.clear)
        }
    }

    private var strokeStyle: StrokeStyle {
        switch style {
        case .slot: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
        case .nextSlot: StrokeStyle(lineWidth: 2)
        case .hole, .hidden: StrokeStyle(lineWidth: 1)
        }
    }
}

#Preview {
    HStack {
        WordWagSocket(style: .slot)
        WordWagSocket(style: .nextSlot)
        WordWagSocket(style: .hole)
    }
    .frame(height: 52)
    .padding()
}
