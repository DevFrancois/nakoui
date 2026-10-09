import SwiftUI

/// A point on the estimate scale: a symbol in a filled circle.
struct EstimateMarker: View {
    let label: LocalizedStringResource
    let systemImage: String
    let style: AnyShapeStyle

    var body: some View {
        Image(systemName: systemImage)
            .font(.footnote)
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(style, in: .circle)
            .accessibilityLabel(Text(label))
    }
}
