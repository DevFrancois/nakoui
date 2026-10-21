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
    /// The scanned code the report is for; Copy and Scan Again act on it.
    let code: ScannedCode
    @Bindable var settings: SheetSettings
    var horizontalPadding: CGFloat
    var bottomPadding: CGFloat
    var onScanAgain: () -> Void

    var body: some View {
        ScrollView(.vertical) {
            FoodAnalysisSections(analysis: analysis, code: code, settings: settings, onScanAgain: onScanAgain)
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
    let code: ScannedCode
    let settings: SheetSettings
    var onScanAgain: () -> Void

    var body: some View {
        // Bounded sections stay laid out while their masks collapse during scrolling.
        VStack(alignment: .leading, spacing: 14) {
            ScannedCodeActions(code: code, onScanAgain: onScanAgain)
                .frame(maxWidth: .infinity)

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

            #if DEBUG
            SheetSettingsSection(settings: settings)
                .padding(.top, 10)
            #endif
        }
    }
}

#if DEBUG
#Preview("Food analysis", traits: .fixedLayout(width: 393, height: 650)) {
    @Previewable @State var settings = PreviewFixtures.makeSettings()

    BottomSheetView(
        analysis: .example,
        code: .sampleEAN13,
        settings: settings,
        horizontalPadding: SheetMetrics.current.scrollContentPadding,
        bottomPadding: PreviewFixtures.canvas.safeAreaBottom,
        onScanAgain: {}
    )
    .background(Color(.systemBackground))
}

#Preview("Food analysis · Narrow · Dark", traits: .fixedLayout(width: 320, height: 650)) {
    @Previewable @State var settings = PreviewFixtures.makeSettings()

    BottomSheetView(
        analysis: .example, code: .sampleEAN13, settings: settings,
        horizontalPadding: 18, bottomPadding: 20, onScanAgain: {}
    )
    .background(Color(.systemBackground))
    .preferredColorScheme(.dark)
}
#endif
