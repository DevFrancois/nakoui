//
//  FoodFeedingSection.swift
//  MapsIOS26BottomSheet
//

import SwiftUI

/// Portions derived from the estimated calories; the label's own feeding guide, when given, takes precedence.
struct FoodFeedingSection: View {
    let analysis: PetFoodAnalysis

    /// Dog weights in kilograms.
    private static let weights: [Double] = [5, 10, 20, 30, 40]

    var body: some View {
        AnalysisSection(title: "Feeding estimate", symbol: "scalemass") {
            VStack(alignment: .leading, spacing: 16) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Dog weight")
                        Text("kcal / day")
                            .gridColumnAlignment(.trailing)
                        Text("Cups / day")
                            .gridColumnAlignment(.trailing)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Divider()
                        .gridCellUnsizedAxes(.horizontal)

                    ForEach(Self.weights.map(analysis.dailyPortion(forWeight:))) { portion in
                        GridRow {
                            Text(
                                Measurement(value: portion.weight, unit: UnitMass.kilograms),
                                format: .measurement(width: .abbreviated, usage: .asProvided)
                            )
                            .fontWeight(.medium)
                            Text(portion.kcal, format: .number.precision(.fractionLength(0)))
                            Text(portion.cups, format: .number.precision(.fractionLength(1)))
                        }
                        .font(.subheadline)
                        .monospacedDigit()
                        .accessibilityElement(children: .combine)
                    }
                }

                Text("For a neutered adult dog with normal activity (\(1.6, format: .number) × resting energy), at \(analysis.gramsPerCup, format: .number.precision(.fractionLength(0))) g per cup. Adjust to keep an ideal body condition.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
    }
}

#if DEBUG
#Preview("Feeding estimate · Dark", traits: .fixedLayout(width: 393, height: 500)) {
    ScrollView {
        FoodFeedingSection(analysis: .example)
            .padding(20)
    }
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.dark)
}
#endif
