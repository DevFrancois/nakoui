//
//  PetFoodAnalysis.swift
//  MapsIOS26BottomSheet
//

import Foundation

/// Illustrative label data for the analysis UI, not a scored or verified product. Only label values are
/// stored; carbohydrates, dry matter, calories and portions are derived from them below.
/// Label text is `String`: it is product data, not UI copy to localize.
nonisolated struct PetFoodAnalysis: Sendable {
    let recipe: String
    let description: String
    /// The guaranteed analysis, as fed.
    let nutrients: [FoodNutrient]
    /// Weight of one standard 8 oz measuring cup of this food.
    let gramsPerCup: Double
    let ingredients: [FoodIngredient]
    let remainingIngredients: String
    let allergens: [String]
    let freeFrom: [String]
    let suitability: FoodSuitability
    let labelDetails: FoodLabelDetails

    static let example = PetFoodAnalysis(
        recipe: "Chicken & oat recipe",
        description: "Dry food · Adult dogs",
        nutrients: [
            FoodNutrient(id: .protein, name: "Crude protein", fraction: 0.28, bound: .minimum),
            FoodNutrient(id: .fat, name: "Crude fat", fraction: 0.16, bound: .minimum),
            FoodNutrient(id: .fibre, name: "Crude fibre", fraction: 0.04, bound: .maximum),
            FoodNutrient(id: .moisture, name: "Moisture", fraction: 0.10, bound: .maximum),
            FoodNutrient(id: .ash, name: "Crude ash", fraction: 0.08, bound: .maximum)
        ],
        gramsPerCup: 110,
        ingredients: [
            FoodIngredient(id: "chicken", name: "Chicken", category: "Animal ingredient", symbol: "fork.knife"),
            FoodIngredient(id: "chicken-meal", name: "Chicken meal", category: "Animal ingredient", symbol: "fork.knife"),
            FoodIngredient(id: "oats", name: "Oats", category: "Grain", symbol: "leaf"),
            FoodIngredient(id: "brown-rice", name: "Brown rice", category: "Grain", symbol: "leaf"),
            FoodIngredient(id: "chicken-fat", name: "Chicken fat", category: "Added fat", symbol: "drop")
        ],
        remainingIngredients: "Also listed: beet pulp, salmon oil, minerals and vitamins.",
        allergens: ["Chicken", "Fish"],
        freeFrom: ["Wheat", "Corn", "Soy", "Beef", "Dairy"],
        suitability: FoodSuitability(
            labelledFor: "Adult dogs",
            animalIngredients: "Chicken & fish",
            grains: "Oats & rice"
        ),
        labelDetails: FoodLabelDetails(
            source: "Example label",
            adequacyStatement: "Not provided",
            feedingGuide: "Not provided"
        )
    )
}

extension PetFoodAnalysis {
    /// A label value as fed, or nil when the label leaves it out.
    func fraction(of kind: FoodNutrient.Kind) -> Double? {
        nutrients.first { $0.id == kind }?.fraction
    }

    /// Nitrogen-free extract: the share the guaranteed analysis leaves unaccounted for. An estimate, since
    /// label values are minimums and maximums; a missing value counts as zero.
    var carbohydrates: Double {
        let kinds: [FoodNutrient.Kind] = [.protein, .fat, .fibre, .moisture, .ash]
        let accounted = kinds.reduce(0) { $0 + (fraction(of: $1) ?? 0) }
        return max(1 - accounted, 0)
    }

    /// The label nutrients followed by the estimated carbohydrates.
    var nutrientProfile: [FoodNutrient] {
        nutrients + [FoodNutrient(id: .carbohydrates, name: "Carbohydrates", fraction: carbohydrates, bound: .estimate)]
    }

    /// The same share with the water removed, so wet and dry foods compare; nil for moisture itself.
    func dryMatter(of nutrient: FoodNutrient) -> Double? {
        let moisture = fraction(of: .moisture) ?? 0
        guard nutrient.id != .moisture, moisture < 1 else { return nil }
        return nutrient.fraction / (1 - moisture)
    }

    /// Nil when the label leaves protein out.
    var proteinLevel: ProteinLevel? {
        guard let protein = nutrients.first(where: { $0.id == .protein }), let share = dryMatter(of: protein) else {
            return nil
        }
        return ProteinLevel(dryMatter: share)
    }

    var calories: FoodCalories {
        FoodCalories(
            protein: fraction(of: .protein) ?? 0,
            fat: fraction(of: .fat) ?? 0,
            carbohydrates: carbohydrates,
            gramsPerCup: gramsPerCup
        )
    }

    /// Daily portion for an adult dog of `weight` kilograms: 1.6 × its resting energy requirement (70 × kg^0.75),
    /// for a neutered adult with normal activity.
    func dailyPortion(forWeight weight: Double) -> FoodPortion {
        let kcal = 1.6 * 70 * pow(weight, 0.75)
        let perCup = calories.perCup
        return FoodPortion(weight: weight, kcal: kcal, cups: perCup > 0 ? kcal / perCup : 0)
    }
}

nonisolated struct FoodNutrient: Identifiable, Sendable {
    nonisolated enum Kind: Sendable {
        case protein, fat, fibre, moisture, ash, carbohydrates
    }

    nonisolated enum Bound: Sendable {
        case minimum, maximum, estimate

        var title: LocalizedStringResource {
            switch self {
            case .minimum: "Minimum"
            case .maximum: "Maximum"
            case .estimate: "Estimated"
            }
        }
    }

    let id: Kind
    let name: LocalizedStringResource
    let fraction: Double
    let bound: Bound
}

/// Label order is the order of `PetFoodAnalysis.ingredients`.
nonisolated struct FoodIngredient: Identifiable, Sendable {
    let id: String
    let name: String
    let category: String
    let symbol: String
}

/// Estimated metabolizable energy with the modified Atwater factors (AAFCO): 3.5 kcal/g for protein and
/// carbohydrates, 8.5 kcal/g for fat.
nonisolated struct FoodCalories: Sendable {
    let perHundredGrams: Double
    let perCup: Double
    /// Shares of the energy, summing to 1.
    let proteinShare: Double
    let fatShare: Double
    let carbohydrateShare: Double

    var perKilogram: Double {
        perHundredGrams * 10
    }

    /// Nutrient shares as fed, as fractions of the food's weight.
    init(protein: Double, fat: Double, carbohydrates: Double, gramsPerCup: Double) {
        /// A fraction × 100 g is grams per 100 g of food.
        let proteinKcal = protein * 100 * 3.5
        let fatKcal = fat * 100 * 8.5
        let carbohydrateKcal = carbohydrates * 100 * 3.5
        let total = proteinKcal + fatKcal + carbohydrateKcal
        perHundredGrams = total
        perCup = total * gramsPerCup / 100
        proteinShare = total > 0 ? proteinKcal / total : 0
        fatShare = total > 0 ? fatKcal / total : 0
        carbohydrateShare = total > 0 ? carbohydrateKcal / total : 0
    }
}

/// Protein as a level out of five, from its dry-matter share, so wet and dry foods compare.
nonisolated struct ProteinLevel: Sendable {
    /// Of the food with the water removed.
    let dryMatter: Double

    /// 1 below the AAFCO minimum for adult dogs, 18 %, then one more from 22, 26 and 30 %: steps of this report,
    /// not a standard.
    var level: Int {
        [0.18, 0.22, 0.26, 0.30].filter { dryMatter >= $0 }.count + 1
    }
}

nonisolated struct FoodPortion: Identifiable, Sendable {
    /// Dog weight in kilograms.
    let weight: Double
    let kcal: Double
    let cups: Double

    var id: Double {
        weight
    }
}

nonisolated struct FoodSuitability: Sendable {
    let labelledFor: String
    let animalIngredients: String
    let grains: String
}

nonisolated struct FoodLabelDetails: Sendable {
    let source: String
    let adequacyStatement: String
    let feedingGuide: String
}
