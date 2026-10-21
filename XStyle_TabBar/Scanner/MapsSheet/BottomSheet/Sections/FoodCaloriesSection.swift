//
//  FoodCaloriesSection.swift
//  MapsIOS26BottomSheet
//

import SwiftUI

struct FoodCaloriesSection: View {
    let calories: FoodCalories

    var body: some View {
        let parts = [
            EnergyPart(id: "protein", name: "Protein", share: calories.proteinShare, tint: .indigo),
            EnergyPart(id: "fat", name: "Fat", share: calories.fatShare, tint: .purple),
            EnergyPart(id: "carbohydrates", name: "Carbohydrates", share: calories.carbohydrateShare, tint: .orange)
        ]

        AnalysisSection(title: "Calories", symbol: "flame") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 28) {
                    CalorieFigure(value: calories.perKilogram, unit: "kcal / kg")
                    CalorieFigure(value: calories.perCup, unit: "kcal / cup")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Where the energy comes from")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    EnergySplitBar(parts: parts)

                    ForEach(parts) { part in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(part.tint)
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)

                            Text(part.name)

                            Spacer(minLength: 0)

                            Text(part.share, format: .percent.precision(.fractionLength(0)))
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                    }
                }

                Text("Estimated from the guaranteed analysis with modified Atwater factors: \(3.5, format: .number) kcal/g for protein and carbohydrates, \(8.5, format: .number) kcal/g for fat.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
    }
}

private struct EnergyPart: Identifiable {
    let id: String
    let name: LocalizedStringResource
    let share: Double
    let tint: Color
}

private struct CalorieFigure: View {
    let value: Double
    let unit: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number.precision(.fractionLength(0)))
                .font(.title2.bold())
                .foregroundStyle(.indigo)
                .monospacedDigit()

            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One bar split by share; the legend rows carry the values for VoiceOver.
private struct EnergySplitBar: View {
    let parts: [EnergyPart]

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 2
            let available = max(proxy.size.width - spacing * CGFloat(max(parts.count - 1, 0)), 0)
            HStack(spacing: spacing) {
                ForEach(parts) { part in
                    Capsule()
                        .fill(part.tint.gradient)
                        .frame(width: available * min(max(part.share, 0), 1))
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Calories", traits: .fixedLayout(width: 393, height: 500)) {
    ScrollView {
        FoodCaloriesSection(calories: PetFoodAnalysis.example.calories)
            .padding(20)
    }
    .background(Color(.systemGroupedBackground))
}
#endif
