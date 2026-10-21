//
//  FoodOverviewSection.swift
//  MapsIOS26BottomSheet
//

import SwiftUI

struct FoodOverviewSection: View {
    let recipe: String
    let description: String
    let energyPer100g: Int

    var body: some View {
        AnalysisSection(title: "At a glance", symbol: "sparkle.magnifyingglass") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "pawprint.fill")
                        .font(.title2)
                        .foregroundStyle(.indigo)
                        .frame(width: 52, height: 58)
                        .background(.indigo.opacity(0.10), in: .rect(cornerRadius: 16))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe)
                            .font(.title3.weight(.semibold))

                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(energyPer100g, format: .number)
                        .font(.title2.bold())
                        .foregroundStyle(.indigo)

                    Text("kcal / 100 g, estimated")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

                Text("A closer look at the nutrients, ingredients and label behind this recipe.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
    }
}

#if DEBUG
#Preview("Recipe overview", traits: .fixedLayout(width: 393, height: 500)) {
    ScrollView {
        FoodOverviewSection(
            recipe: PetFoodAnalysis.example.recipe,
            description: PetFoodAnalysis.example.description,
            energyPer100g: Int(PetFoodAnalysis.example.calories.perHundredGrams.rounded())
        )
        .padding(20)
    }
    .background(Color(.systemGroupedBackground))
}
#endif
