import SwiftUI

/// Product information under a found code. Sample content until products are
/// looked up: `Self.samples` and `Self.sampleIngredients` are the one place
/// to replace with real data.
struct ScannedProductSections: View {
    private struct ProductSection: Identifiable {
        let title: LocalizedStringResource
        let rows: [(label: LocalizedStringResource, value: String)]
        var id: String { String(localized: title) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Self.samples) { section in
                card(section.title) {
                    ForEach(section.rows.indices, id: \.self) { index in
                        LabeledContent {
                            Text(section.rows[index].value)
                        } label: {
                            Text(section.rows[index].label)
                        }
                    }
                }
            }

            card("Ingredients") {
                Text(Self.sampleIngredients)
                    .foregroundStyle(.secondary)
            }

            Text("Sample product information")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
    }

    private func card(_ title: LocalizedStringResource, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private static let samples = [
        ProductSection(title: "Product", rows: [
            ("Name", "Sample Hazelnut Spread"),
            ("Brand", "Sample Brand"),
            ("Quantity", "400 g"),
            ("Category", "Spreads"),
        ]),
        ProductSection(title: "Nutrition per 100 g", rows: [
            ("Energy", "2,252 kJ"),
            ("Fat", "30.9 g"),
            ("Carbohydrates", "57.5 g"),
            ("Sugars", "56.3 g"),
            ("Protein", "6.3 g"),
            ("Salt", "0.1 g"),
        ]),
    ]

    private static let sampleIngredients: LocalizedStringResource =
        "Sugar, palm oil, hazelnuts 13%, skimmed milk powder 8.7%, fat-reduced cocoa 7.4%, emulsifier: lecithins (soya), vanillin."
}

#Preview {
    ScrollView {
        ScannedProductSections()
            .padding()
    }
}
