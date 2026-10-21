//
//  AnalysisMeasure.swift
//  MapsIOS26BottomSheet
//
//  The rating card of the Paper Airplanes reconstruction (`RatingCard`), without its own card: it sits in a
//  section's.
//

import SwiftUI

/// A level out of five: its symbol in a gradient, a title over what it measures, the level in a badge, and a bar of
/// five glossy segments, the ones reached solid.
struct AnalysisMeasure: View {
    let title: LocalizedStringResource
    let subtitle: Text
    let symbol: String
    /// From leading to trailing.
    let colors: [Color]
    /// 1 to `maximum`.
    let level: Int
    @ScaledMetric(relativeTo: .title) private var symbolSize = 32.0
    @ScaledMetric(relativeTo: .title) private var symbolWidth = 44.0
    @ScaledMetric(relativeTo: .title2) private var badgeSize = 42.0
    @ScaledMetric(relativeTo: .title2) private var badgeFont = 28.0

    static let maximum = 5

    var body: some View {
        let gradient = LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)

        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(gradient)
                    .frame(width: symbolWidth)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    subtitle
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(level, format: .number)
                    .font(.system(size: badgeFont, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: badgeSize, height: badgeSize)
                    .background(gradient, in: .circle)
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            }

            gradient
                .overlay {
                    LinearGradient(
                        colors: [.white.opacity(0.35), .clear, .black.opacity(0.06), .white.opacity(0.3)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .mask {
                    HStack(spacing: 4) {
                        ForEach(0..<Self.maximum, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 8)
                                .opacity(index < level ? 1 : 0.22)
                        }
                    }
                }
                .frame(height: 20)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(level) out of \(Self.maximum). \(subtitle)"))
    }
}

#if DEBUG
#Preview("Measure", traits: .sizeThatFitsLayout) {
    AnalysisMeasure(
        title: "Protein", subtitle: Text("31 % of dry matter"), symbol: "dumbbell.fill",
        colors: [.cyan, .indigo], level: 5
    )
    .padding()
    .frame(width: 393)
}
#endif
