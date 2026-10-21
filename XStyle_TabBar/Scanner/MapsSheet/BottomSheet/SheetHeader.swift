//
//  SheetHeader.swift
//  MapsIOS26BottomSheet
//
//  Created by Balaji Venkatesh on 27/06/25.
//

import SwiftUI

/// Header: the analyzed recipe and its description, and a close button; no grabber, no search field.
struct SheetHeader: View {
    let sheet: SheetController
    var title: String
    var subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.bold())
                    .lineLimit(1)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            /// Fades with the sheet's position, not an animation: gone at collapsed, where there is nothing
            /// left to collapse. It keeps its slot so the title never reflows.
            let opacity = sheet.geometry?.closeButtonOpacity ?? 0
            CloseButton(action: sheet.collapse)
                .opacity(opacity)
                .allowsHitTesting(opacity > 0)
                .accessibilityHidden(opacity == 0)
        }
        .frame(maxHeight: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// Circular xmark button: the system glass button on iOS 26, material below.
private struct CloseButton: View {
    var action: () -> Void

    var body: some View {
        if #available(iOS 26, *) {
            Button(action: action) {
                label
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Collapse")
        } else {
            Button(action: action) {
                label
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse")
        }
    }

    private var label: some View {
        Image(systemName: "xmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
    }
}

#if DEBUG
#Preview("Header", traits: .sizeThatFitsLayout) {
    @Previewable @State var sheet = PreviewFixtures.makeSheet(detent: .medium)

    SheetHeader(sheet: sheet, title: PetFoodAnalysis.example.recipe, subtitle: PetFoodAnalysis.example.description)
        .padding(.horizontal, SheetMetrics.contentPadding)
        .frame(width: 393, height: SheetMetrics.current.headerHeight)
        .background(Color(.systemBackground))
}

#Preview("Collapsed · No close button", traits: .sizeThatFitsLayout) {
    @Previewable @State var sheet = PreviewFixtures.makeSheet(detent: .collapsed)

    SheetHeader(sheet: sheet, title: PetFoodAnalysis.example.recipe, subtitle: PetFoodAnalysis.example.description)
        .padding(.horizontal, SheetMetrics.contentPadding)
        .frame(width: 393, height: SheetMetrics.current.headerHeight)
        .background(Color(.systemBackground))
}

#Preview("Narrow · Large text · Dark", traits: .sizeThatFitsLayout) {
    @Previewable @State var sheet = PreviewFixtures.makeSheet(detent: .medium)

    SheetHeader(sheet: sheet, title: PetFoodAnalysis.example.recipe, subtitle: PetFoodAnalysis.example.description)
        .padding(.horizontal, SheetMetrics.contentPadding)
        .frame(width: 320, height: SheetMetrics.current.headerHeight)
        .background(Color(.systemBackground))
        .dynamicTypeSize(.xxLarge)
        .preferredColorScheme(.dark)
}
#endif
