//
//  SheetHeader.swift
//  MapsIOS26BottomSheet
//
//  Created by Balaji Venkatesh on 27/06/25.
//

import SwiftUI

/// Header: the analyzed recipe and the scanned code, and a close button; no grabber, no search field.
struct SheetHeader: View {
    var title: String
    var subtitle: Text
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.bold())
                    .lineLimit(1)

                subtitle
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            /// Closes the result at every detent, collapsed included: below it there is only the dismissed sheet.
            CloseButton(action: onClose)
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
            .accessibilityLabel("Close")
        } else {
            Button(action: action) {
                label
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
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
    SheetHeader(title: PetFoodAnalysis.example.recipe, subtitle: Text(ScannedCode.sampleEAN13.value), onClose: {})
        .padding(.horizontal, SheetMetrics.contentPadding)
        .frame(width: 393, height: SheetMetrics.current.headerHeight)
        .background(Color(.systemBackground))
}

#Preview("Narrow · Large text · Dark", traits: .sizeThatFitsLayout) {
    SheetHeader(title: PetFoodAnalysis.example.recipe, subtitle: Text(ScannedCode.sampleEAN13.value), onClose: {})
        .padding(.horizontal, SheetMetrics.contentPadding)
        .frame(width: 320, height: SheetMetrics.current.headerHeight)
        .background(Color(.systemBackground))
        .dynamicTypeSize(.xxLarge)
        .preferredColorScheme(.dark)
}
#endif
