import SwiftUI

/// A checked slot's verdict: a check, or a cross over an arrow and the
/// position the pet belongs at. Symbols and numbers, not just color. It
/// stacks to stay narrow beside the pet, and lies in a row on its own line
/// at accessibility sizes.
struct LineUpMarkLabel: View {
    let mark: LineUpMark
    /// The slot's own position, counting from 1.
    let position: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(spacing: 2))
    }

    var body: some View {
        layout {
            if let symbol = mark.choiceState.symbol {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(mark.choiceState.symbolTint)
            }

            if case .wrong(let rightPosition) = mark {
                Label {
                    Text(rightPosition, format: .number)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: rightPosition < position ? "arrow.up" : "arrow.down")
                }
                .labelStyle(.titleAndIcon)
                .font(.subheadline)
                .bold()
                .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
        .accessibilityHidden(true)
    }
}
