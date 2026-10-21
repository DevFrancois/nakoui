//
//  BottomSheetView.swift
//  MapsIOS26BottomSheet
//
//  Created by Balaji Venkatesh on 27/06/25.
//

import SwiftUI

/// One vertical scroll view shared with the sheet's pan coordinator.
/// The cards observe scroll geometry locally; this view never reads per-frame sheet state.
struct BottomSheetView: View {
    let analysis: PetFoodAnalysis
    @Bindable var settings: SheetSettings
    var horizontalPadding: CGFloat
    var bottomPadding: CGFloat

    var body: some View {
        ScrollView(.vertical) {
            FoodAnalysisSections(analysis: analysis, settings: settings)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 4)
                .padding(.bottom, bottomPadding + 24)
                /// Headers morph before the content slides under them.
                .stickySectionScrollContent()
        }
    }
}

private struct FoodAnalysisSections: View {
    let analysis: PetFoodAnalysis
    let settings: SheetSettings

    var body: some View {
        // Bounded sections stay laid out while their masks collapse during scrolling.
        VStack(alignment: .leading, spacing: 14) {
            FoodOverviewSection(
                recipe: analysis.recipe,
                description: analysis.description,
                energyPer100g: Int(analysis.calories.perHundredGrams.rounded())
            )

            FoodNutrientsSection(analysis: analysis)
            FoodCaloriesSection(calories: analysis.calories)

            FoodIngredientsSection(
                ingredients: analysis.ingredients,
                remainingIngredients: analysis.remainingIngredients
            )

            FoodAllergensSection(allergens: analysis.allergens, freeFrom: analysis.freeFrom)
            FoodFeedingSection(analysis: analysis)

            FoodSuitabilitySection(suitability: analysis.suitability)
            FoodLabelDetailsSection(details: analysis.labelDetails)

            SheetSettingsSection(settings: settings)
                .padding(.top, 10)
        }
    }
}

#if DEBUG
#Preview("Food analysis", traits: .fixedLayout(width: 393, height: 650)) {
    @Previewable @State var settings = PreviewFixtures.makeSettings()

    BottomSheetView(
        analysis: .example,
        settings: settings,
        horizontalPadding: SheetMetrics.current.scrollContentPadding,
        bottomPadding: PreviewFixtures.canvas.safeAreaBottom
    )
    .background(Color(.systemBackground))
}

#Preview("Food analysis · Narrow · Dark", traits: .fixedLayout(width: 320, height: 650)) {
    @Previewable @State var settings = PreviewFixtures.makeSettings()

    BottomSheetView(analysis: .example, settings: settings, horizontalPadding: 18, bottomPadding: 20)
        .background(Color(.systemBackground))
        .preferredColorScheme(.dark)
}
#endif
