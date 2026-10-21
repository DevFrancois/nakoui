//
//  SheetHeader.swift
//  MapsIOS26BottomSheet
//
//  Created by Balaji Venkatesh on 27/06/25.
//

import SwiftUI

/// Header: a title and subtitle, such as the analyzed recipe and the scanned code, an optional back button, an
/// accessory such as the history's Clear, and a close button; no grabber, no search field.
struct SheetHeader<Accessory: View>: View {
    var title: Text
    var subtitle: Text
    var onBack: (() -> Void)?
    var onClose: () -> Void
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                HeaderCircleButton(systemImage: "chevron.backward", label: "Back", action: onBack)
            }

            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.title2.bold())
                    .lineLimit(1)

                subtitle
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            accessory

            /// Closes the sheet at every detent.
            HeaderCircleButton(systemImage: "xmark", label: "Close", action: onClose)
        }
        .frame(maxHeight: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

extension SheetHeader where Accessory == EmptyView {
    init(title: String, subtitle: Text, onBack: (() -> Void)? = nil, onClose: @escaping () -> Void) {
        self.init(title: Text(title), subtitle: subtitle, onBack: onBack, onClose: onClose) {
            EmptyView()
        }
    }
}

/// Circular icon button: the system glass button on iOS 26, material below.
private struct HeaderCircleButton: View {
    var systemImage: String
    var label: LocalizedStringResource
    var action: () -> Void

    var body: some View {
        if #available(iOS 26, *) {
            Button(action: action) {
                icon
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text(label))
        } else {
            Button(action: action) {
                icon
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(label))
        }
    }

    private var icon: some View {
        Image(systemName: systemImage)
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
