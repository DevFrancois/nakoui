//
//  StickySection.swift
//  MapsIOS26BottomSheet
//
//  Adapted from WSSection by Balaji Venkatesh, created on 20/06/26.
//  Purchased source supplied by the project owner.
//

import SwiftUI

/// A card that pins to its enclosing vertical scroll view, folds into a compact header,
/// and fades away as the next section arrives. Scroll effects do not write to view state.
struct StickySection<Content: View, Header: View, MinimisedHeader: View>: View {
    var config: Config = .init()
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content
    @ViewBuilder var header: Header
    @ViewBuilder var minimisedHeader: MinimisedHeader

    @State private var headerSize: CGSize = .zero
    @Namespace private var sectionSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stickySectionScrollContentSpace) private var scrollContentSpace

    var body: some View {
        let coordinateSpace = sectionSpace
        /// The header's offset in the card, which its WSSection fade measures from.
        let headerTopPadding = config.headerTopPadding ?? config.sectionPadding
        let headerFadeDistance = max(config.headerFadeDistance, 0.001)
        let morph = HeaderMorph(
            sectionSpace: coordinateSpace,
            scrollContentSpace: scrollContentSpace,
            lead: max(config.headerMorphLead, 0),
            fadeDistance: headerFadeDistance
        )
        let fadeDistance = max(config.fadeDistance, 0.001)
        let fadeScale = reduceMotion ? 0 : min(max(config.fadeScale, 0), 1)
        /// Pinned height: `headerSize` already includes the top padding; the same space below keeps the
        /// compact header centered in the pinned card.
        let headerHeight = max(headerSize.height + headerTopPadding + config.minimisedHeaderOffset, 0)

        VStack(alignment: .leading, spacing: spacing) {
            header
                .visualEffect { content, proxy in
                    let progress: CGFloat
                    if let travel = morph.travel(of: proxy) {
                        progress = clipUnit(value: travel / headerFadeDistance)
                    } else {
                        let rect = proxy.frame(in: .named(coordinateSpace))
                        let minY = max(rect.minY - headerTopPadding, 0)
                        progress = min(minY / headerFadeDistance, 1)
                    }

                    return content
                        .opacity(1 - progress)
                }
                .background {
                    minimisedHeader
                        .frame(maxHeight: .infinity)
                        .offset(y: config.minimisedHeaderOffset / 2)
                        .visualEffect { content, proxy in
                            let progress: CGFloat
                            if let travel = morph.travel(of: proxy) {
                                progress = clipUnit(value: (travel - headerFadeDistance) / headerFadeDistance)
                            } else {
                                let rect = proxy.frame(in: .named(coordinateSpace))
                                let minY = max(rect.minY - headerTopPadding - headerFadeDistance, 0)
                                progress = min(minY / headerFadeDistance, 1)
                            }

                            return content
                                .opacity(progress)
                        }
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, config.sectionPadding)
                .padding(.top, headerTopPadding)
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { newValue in
                    headerSize = newValue
                }

            content
                .padding([.horizontal, .bottom], config.sectionPadding)
                .visualEffect { content, proxy in
                    let rect = proxy.frame(in: .named(coordinateSpace))
                    let scrollMinY = proxy.frame(in: .scrollView(axis: .vertical)).minY
                    let minY = max(rect.minY - scrollMinY, 0)

                    return content
                        .offset(y: -minY)
                }
                .clipped()
        }
        .mask {
            GeometryReader { proxy in
                let rect = proxy.frame(in: .named(coordinateSpace))
                let cutoffHeight = max(proxy.size.height - headerHeight, 0)
                let bottomPadding = min(max(rect.minY, 0), cutoffHeight)

                RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous)
                    .padding(.bottom, bottomPadding)
            }
        }
        .background {
            GeometryReader { proxy in
                let rect = proxy.frame(in: .named(coordinateSpace))
                let cutoffHeight = max(proxy.size.height - headerHeight, 0)
                let bottomPadding = min(max(rect.minY, 0), cutoffHeight)

                StickySectionSurface(
                    cornerRadius: config.cornerRadius,
                    background: config.background,
                    isGlassBackground: config.isGlassBackground
                )
                .padding(.bottom, bottomPadding)
            }
        }
        .compositingGroup()
        .visualEffect { content, proxy in
            let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY
            let cutoffHeight = max(proxy.size.height - headerHeight, 0)
            let distance = abs(min(cutoffHeight + minY, 0))
            let progress = min(distance / fadeDistance, 1)

            return content
                .scaleEffect(1 - progress * fadeScale, anchor: .top)
                .opacity(1 - progress)
                .offset(y: minY < 0 ? -minY : 0)
        }
        // Keep this outside the visual effect: the inner geometry measures the pinned card.
        .coordinateSpace(.named(coordinateSpace))
    }

    struct Config {
        var sectionPadding: CGFloat = 16
        /// Space above the header; `sectionPadding` when nil, as in WSSection.
        var headerTopPadding: CGFloat? = nil
        var cornerRadius: CGFloat = 22
        /// WSSection's defaults: a fill, with glass opted into per section.
        var background: AnyShapeStyle = .init(.fill.tertiary)
        var isGlassBackground: Bool = false
        var minimisedHeaderOffset: CGFloat = -4
        var headerFadeDistance: CGFloat = 15
        /// How far before the card pins its header starts turning into `minimisedHeader`, when the scroll content is
        /// marked with `stickySectionScrollContent()`. The default, twice `headerFadeDistance`, finishes the cross-fade
        /// as the content starts sliding under the header; WSSection starts it at the pin, as happens without the mark.
        var headerMorphLead: CGFloat = 30
        var fadeDistance: CGFloat = 45
        var fadeScale: CGFloat = 0.05
    }
}

/// Where a header is in its morph, from how far its card is from pinning. Needs the scroll content's coordinate space
/// to know the scroll offset, which a visual effect cannot read directly.
private nonisolated struct HeaderMorph: Sendable {
    let sectionSpace: Namespace.ID
    let scrollContentSpace: String?
    let lead: CGFloat
    let fadeDistance: CGFloat

    /// Points of travel into the morph: 0 where it starts, `fadeDistance` once the header is gone, twice that once
    /// the compact header is in. Nil without a marked scroll content, for WSSection's own timing.
    func travel(of proxy: GeometryProxy) -> CGFloat? {
        guard let scrollContentSpace else { return nil }
        let inScrollView = proxy.frame(in: .scrollView(axis: .vertical)).minY
        /// Signed distance past the pinned position: negative while the card approaches, the pin offset after.
        let pastPin = proxy.frame(in: .named(sectionSpace)).minY - inScrollView
        /// Both frames include the pin offset, so their difference is the scroll offset.
        let scrollOffset = proxy.frame(in: .named(scrollContentSpace)).minY - inScrollView
        /// A card that rests closer to the pin than `lead`, like the first one, can only start once scrolling starts.
        let restDistance = max(scrollOffset - pastPin, 0)
        return pastPin + min(lead, restDistance)
    }
}

extension EnvironmentValues {
    /// The scroll content's coordinate space name, set by `stickySectionScrollContent()`.
    @Entry var stickySectionScrollContentSpace: String? = nil
}

extension View {
    /// Marks a vertical scroll view's content so its sticky sections know the scroll offset, which lets each header
    /// morph before its content starts sliding under it (see `StickySection.Config.headerMorphLead`).
    /// Apply it to the content inside the `ScrollView`, after its padding.
    func stickySectionScrollContent() -> some View {
        let name = "StickySection.scrollContent"
        return coordinateSpace(.named(name))
            .environment(\.stickySectionScrollContentSpace, name)
    }
}

private struct StickySectionSurface: View {
    var cornerRadius: CGFloat
    var background: AnyShapeStyle
    var isGlassBackground: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        /// Reduce Transparency replaces glass with the fill.
        if isGlassBackground, !reduceTransparency {
            if #available(iOS 26, *) {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(.regular, in: shape)
            } else {
                shape.fill(.thinMaterial)
            }
        } else {
            shape.fill(background)
        }
    }
}

#if DEBUG
#Preview("Sticky sections · Pet food", traits: .fixedLayout(width: 393, height: 650)) {
    ScrollView {
        VStack(spacing: 14) {
            StickySection {
                Text("Chicken, brown rice, oats and salmon oil.")
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            } header: {
                Label("Ingredients", systemImage: "leaf")
                    .font(.headline)
            } minimisedHeader: {
                Label("Ingredients", systemImage: "leaf")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            StickySection {
                Text("Protein 28% · Fat 16% · Fiber 4%")
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            } header: {
                Label("Nutrients", systemImage: "chart.bar")
                    .font(.headline)
            } minimisedHeader: {
                Label("Nutrients", systemImage: "chart.bar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .padding(.bottom, 400)
    }
    .background(Color(.systemGroupedBackground))
}
#endif
