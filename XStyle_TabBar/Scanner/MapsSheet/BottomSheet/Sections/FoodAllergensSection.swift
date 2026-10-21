//
//  FoodAllergensSection.swift
//  MapsIOS26BottomSheet
//

import SwiftUI

struct FoodAllergensSection: View {
    let allergens: [String]
    let freeFrom: [String]

    var body: some View {
        AnalysisSection(title: "Allergens", symbol: "allergens") {
            VStack(alignment: .leading, spacing: 16) {
                ChipGroup(title: "Contains", items: allergens, symbol: "exclamationmark.circle.fill", tint: .orange)
                ChipGroup(title: "Free from", items: freeFrom, symbol: "checkmark.circle.fill", tint: .green)

                Text("From the ingredient list. Trace amounts and cross-contact are not covered.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
    }
}

private struct ChipGroup: View {
    let title: LocalizedStringResource
    let items: [String]
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 5) {
                        Image(systemName: symbol)
                            .foregroundStyle(tint)
                            .accessibilityHidden(true)

                        Text(item)
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(tint.opacity(0.12), in: .capsule)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Places its children left to right and wraps to a new row when the width runs out.
private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let origins = arrange(width: bounds.width, subviews: subviews).origins
        for (subview, origin) in zip(subviews, origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), origins)
    }
}

#if DEBUG
#Preview("Allergens · Large text", traits: .fixedLayout(width: 393, height: 500)) {
    ScrollView {
        FoodAllergensSection(
            allergens: PetFoodAnalysis.example.allergens,
            freeFrom: PetFoodAnalysis.example.freeFrom
        )
        .padding(20)
    }
    .background(Color(.systemGroupedBackground))
    .dynamicTypeSize(.xxLarge)
}
#endif
