//
//  FoodIngredientsSection.swift
//  MapsIOS26BottomSheet
//

import SwiftUI

struct FoodIngredientsSection: View {
    let ingredients: [FoodIngredient]
    let remainingIngredients: String

    var body: some View {
        AnalysisSection(title: "Ingredients", symbol: "leaf") {
            VStack(alignment: .leading, spacing: 16) {
                Text("First \(ingredients.count) · In label order")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(Array(ingredients.enumerated()), id: \.element.id) { index, ingredient in
                    IngredientRow(position: index + 1, ingredient: ingredient)
                }

                Divider()

                Text(remainingIngredients)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
    }
}

private struct IngredientRow: View {
    /// 1-based label position.
    let position: Int
    let ingredient: FoodIngredient

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(position, format: .number)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 16)

            Image(systemName: ingredient.symbol)
                .font(.subheadline)
                .foregroundStyle(.indigo)
                .frame(width: 34, height: 34)
                .background(.indigo.opacity(0.08), in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(ingredient.name)
                    .font(.subheadline.weight(.medium))

                Text(ingredient.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Ingredients · Large text", traits: .fixedLayout(width: 393, height: 750)) {
    ScrollView {
        FoodIngredientsSection(
            ingredients: PetFoodAnalysis.example.ingredients,
            remainingIngredients: PetFoodAnalysis.example.remainingIngredients
        )
        .padding(20)
    }
    .background(Color(.systemGroupedBackground))
    .dynamicTypeSize(.xxLarge)
}
#endif
