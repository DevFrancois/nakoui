#if DEBUG
import SwiftUI

/// The orange tag marking a side menu control as debug-only.
struct DebugBadge: View {
    var body: some View {
        Text("Debug")
            .font(.caption.bold())
            .textCase(.uppercase)
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange.quaternary, in: .capsule)
    }
}

/// A debug panel's title row, with a Reset button and the debug tag.
struct DebugPanelHeader: View {
    let title: LocalizedStringKey
    let systemImage: String
    /// Whether the panel's values are already at their defaults.
    let isDefault: Bool
    let reset: () -> Void

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.callout.bold())
                .foregroundStyle(.secondary)

            Spacer()

            Button("Reset", action: reset)
                .font(.caption.bold())
                .disabled(isDefault)

            DebugBadge()
        }
        .padding(.top, 6)
    }
}

/// A labeled debug slider showing its value to two decimals.
struct DebugSliderRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption.bold())
                .frame(width: 62, alignment: .leading)

            Slider(value: $value, in: range)

            Text(value, format: .number.precision(.fractionLength(2)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
