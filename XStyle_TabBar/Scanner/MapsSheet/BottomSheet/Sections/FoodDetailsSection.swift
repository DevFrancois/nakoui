//
//  FoodDetailsSection.swift
//  MapsIOS26BottomSheet
//

import SwiftUI

/// These sections describe the example label; matching awaits a real pet profile.
struct FoodSuitabilitySection: View {
    let suitability: FoodSuitability

    var body: some View {
        AnalysisSection(title: "Pet suitability", symbol: "pawprint") {
            VStack(alignment: .leading, spacing: 16) {
                AnalysisFact(title: "Labelled for", value: suitability.labelledFor)
                AnalysisFact(title: "Animal ingredients", value: suitability.animalIngredients)
                AnalysisFact(title: "Grains present", value: suitability.grains)

                Divider()

                Label("No pet profile connected", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.subheadline.weight(.medium))

                Text("Age, sensitivities and dietary needs have not been checked against this recipe.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
    }
}

struct FoodLabelDetailsSection: View {
    let details: FoodLabelDetails

    var body: some View {
        AnalysisSection(title: "Label details", symbol: "doc.text.magnifyingglass") {
            VStack(alignment: .leading, spacing: 16) {
                AnalysisFact(title: "Data source", value: details.source)
                AnalysisFact(title: "Nutrient basis", value: String(localized: "As fed"))
                AnalysisFact(title: "Adequacy statement", value: details.adequacyStatement)
                AnalysisFact(title: "Feeding guide", value: details.feedingGuide)

                Divider()

                Text("About this report")
                    .font(.subheadline.weight(.semibold))

                Text("This sample shows how a food analysis will look. Product verification and a nutritional assessment are still needed for a real report.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
    }
}

#if DEBUG
#Preview("Label details · Accessibility", traits: .fixedLayout(width: 393, height: 850)) {
    ScrollView {
        VStack(spacing: 14) {
            FoodSuitabilitySection(suitability: PetFoodAnalysis.example.suitability)
            FoodLabelDetailsSection(details: PetFoodAnalysis.example.labelDetails)
        }
        .padding(20)
    }
    .background(Color(.systemGroupedBackground))
    .dynamicTypeSize(.accessibility1)
}
#endif
