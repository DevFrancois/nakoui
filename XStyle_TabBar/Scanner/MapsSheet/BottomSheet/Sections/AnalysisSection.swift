//
//  AnalysisSection.swift
//  MapsIOS26BottomSheet
//

import SwiftUI

/// Consistent expanded and compact headers for the WSSection card behavior.
struct AnalysisSection<Content: View>: View {
    let title: LocalizedStringResource
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        /// Opaque `SheetCardFill` cards: the incoming card slides over the pinned one as it fades, as in WSSection.
        /// A shorter title row than WSSection's: 12 pt above the title and 4 pt below it. `spacing` belongs to the
        /// header: it stays under the title while the card is pinned.
        StickySection(
            config: .init(
                headerTopPadding: 12,
                background: AnyShapeStyle(SheetCardFill.color)
            ),
            spacing: 4
        ) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                /// Space at the top of the content itself: it scrolls under the header with the content.
                .padding(.top, 6)
        } header: {
            /// Icon before the title, like the compact header it turns into.
            Label {
                Text(title)
                    .font(.headline)
            } icon: {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.indigo)
            }
            .labelStyle(SectionTitleLabelStyle())
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
        } minimisedHeader: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
            }
            .labelStyle(SectionTitleLabelStyle())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Icon then title with one explicit gap, so the full and compact headers match: `Label`'s own gap changes with
/// the font.
private struct SectionTitleLabelStyle: LabelStyle {
    /// Between the icon and the title; the symbols' own margins add about 2.5 pt on screen.
    static let spacing: CGFloat = 5

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Self.spacing) {
            configuration.icon
            configuration.title
        }
    }
}

/// A compact fact that also reflows vertically at accessibility text sizes.
struct AnalysisFact: View {
    let title: LocalizedStringResource
    /// Label data, shown verbatim.
    let value: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 16))

        layout {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
        }
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}
