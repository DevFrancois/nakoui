//
//  FoodNutrientsSection.swift
//  MapsIOS26BottomSheet
//

import SwiftUI

struct FoodNutrientsSection: View {
    let analysis: PetFoodAnalysis

    var body: some View {
        AnalysisSection(title: "Nutrient profile", symbol: "chart.bar.xaxis") {
            VStack(alignment: .leading, spacing: 18) {
                Text("Guaranteed analysis · As fed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(analysis.nutrientProfile) { nutrient in
                    NutrientRow(nutrient: nutrient, dryMatter: analysis.dryMatter(of: nutrient))
                }

                Text("Each bar uses a 0–100% scale. DM is the dry-matter share, with the water removed, so wet and dry foods compare. Carbohydrates are what the label leaves unaccounted for; minimum and maximum values make them an estimate.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
    }
}

private struct NutrientRow: View {
    let nutrient: FoodNutrient
    /// Nil for moisture, which has no dry-matter share.
    let dryMatter: Double?

    private var tint: Color {
        switch nutrient.id {
        case .protein: .indigo
        case .fat: .purple
        case .fibre: .teal
        case .moisture: .blue
        case .ash: .secondary
        case .carbohydrates: .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(nutrient.name)
                        .font(.subheadline.weight(.medium))

                    HStack(spacing: 4) {
                        Text(nutrient.bound.title)

                        if let dryMatter {
                            Text(verbatim: "·")
                                .accessibilityHidden(true)

                            Text("\(dryMatter, format: .percent.precision(.fractionLength(0...1))) DM")
                                .monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text(nutrient.fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                Capsule()
                    .fill(tint.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(tint.gradient)
                            .frame(width: proxy.size.width * min(max(nutrient.fraction, 0), 1))
                    }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Nutrients · Dark", traits: .fixedLayout(width: 393, height: 650)) {
    ScrollView {
        FoodNutrientsSection(analysis: .example)
            .padding(20)
    }
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.dark)
}
#endif
