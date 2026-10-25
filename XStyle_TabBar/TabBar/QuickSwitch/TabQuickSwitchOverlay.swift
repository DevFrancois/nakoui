import SwiftUI

/// Draws a held tab's menu over the pages and under the tab bar: a halo that
/// draws the eye to the bar, and the items. It never takes touches; the bar's
/// recognizer keeps the finger throughout. The bar's frames are window points,
/// so the overlay lays out left to right whatever the language; the items'
/// content keeps the language's direction.
struct TabQuickSwitchOverlay: View {
    let menu: TabQuickSwitchMenu
    @AppStorage(TabQuickSwitchSettings.haloKey) private var halo = TabQuickSwitchHalo.defaultHalo
    @AppStorage(TabQuickSwitchSettings.layoutKey) private var layout = TabQuickSwitchLayout.defaultLayout
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The overlay's safe area, and its whole extent, in global space.
    @State private var safeFrame: CGRect?
    @State private var fullFrame: CGRect?

    nonisolated static let space = "tabQuickSwitch"

    var body: some View {
        Color.clear
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                safeFrame = frame
            }
            .overlay {
                ZStack {
                    if let presentation = menu.presentation, let area {
                        TabQuickSwitchPanel(menu: menu, presentation: presentation, area: area, halo: halo,
                                            layout: layout, contentDirection: layoutDirection)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    fullFrame = frame
                }
                .background {
                    TabQuickSwitchCoordinateSpace(menu: menu)
                }
                .coordinateSpace(.named(Self.space))
                .environment(\.layoutDirection, .leftToRight)
                .ignoresSafeArea()
            }
            .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.25), value: menu.presentation == nil)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Where a menu may go: the safe area less a margin, in the overlay's space.
    private var area: CGRect? {
        guard let safeFrame, let fullFrame else { return nil }
        return safeFrame.offsetBy(dx: -fullFrame.minX, dy: -fullFrame.minY)
            .insetBy(dx: TabQuickSwitchMetrics.margin, dy: TabQuickSwitchMetrics.margin)
    }
}

/// One open menu, made afresh each time one opens.
private struct TabQuickSwitchPanel: View {
    let menu: TabQuickSwitchMenu
    let presentation: TabQuickSwitchMenu.Presentation
    let area: CGRect
    let halo: TabQuickSwitchHalo
    let layout: TabQuickSwitchLayout
    let contentDirection: LayoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var bubbleDiameter = TabQuickSwitchMetrics.bubbleDiameter
    /// Whether the items have come out of the held tab.
    @State private var isExpanded = false
    @State private var itemFrames: [TabQuickSwitchDestination: CGRect] = [:]
    /// The bubble the fan's label last named; it fades rather than leaves.
    @State private var labelIndex: Int?

    var body: some View {
        ZStack {
            TabQuickSwitchHaloView(halo: halo, bar: presentation.barFrame, focus: focus)
            GlassEffectContainer {
                switch layout {
                case .list: list
                case .bubbles: fan
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: menu.highlighted)
        .onChange(of: menu.highlighted, initial: true) {
            if let index = presentation.items.firstIndex(where: { $0.id == menu.highlighted }) {
                labelIndex = index
            }
        }
        .onAppear {
            if reduceMotion {
                isExpanded = true
            } else {
                withAnimation(.spring(duration: 0.35, bounce: 0.25)) { isExpanded = true }
            }
        }
    }

    /// What the spotlight lights: the bar and the items laid out so far.
    private var focus: CGRect {
        itemFrames.values.reduce(presentation.barFrame) { $0.union($1) }
    }

    private var list: some View {
        TabQuickSwitchListLayout(tab: presentation.tabFrame, bar: presentation.barFrame, area: area,
                                 axis: presentation.axis) {
            VStack(spacing: 0) {
                ForEach(presentation.items) { item in
                    TabQuickSwitchRow(item: item, isHighlighted: item.id == menu.highlighted)
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .named(TabQuickSwitchOverlay.space))
                        } action: { frame in
                            report(frame, for: item.id)
                        }
                }
            }
            .padding(TabQuickSwitchMetrics.listInset)
            // Every row as wide as the widest.
            .fixedSize()
            .glassEffect(.regular, in: .rect(cornerRadius: TabQuickSwitchMetrics.listCornerRadius))
            .environment(\.layoutDirection, contentDirection)
            .scaleEffect(isExpanded ? 1 : 0.6, anchor: towardsBar)
            .opacity(isExpanded ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fan: some View {
        let pivot = CGPoint(x: presentation.tabFrame.midX, y: presentation.tabFrame.midY)
        return TabQuickSwitchFanLayout(tab: presentation.tabFrame, bar: presentation.barFrame, area: area,
                                       axis: presentation.axis, isRightToLeft: contentDirection == .rightToLeft,
                                       labelIndex: labelIndex) {
            ForEach(presentation.items) { item in
                let isHighlighted = item.id == menu.highlighted
                TabQuickSwitchBubble(item: item, isHighlighted: isHighlighted, diameter: bubbleDiameter)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(TabQuickSwitchOverlay.space))
                    } action: { frame in
                        report(frame, for: item.id)
                    }
                    .scaleEffect(isExpanded ? (isHighlighted ? 1.15 : 1) : 0.4)
                    .opacity(isExpanded ? 1 : 0)
                    // Out of the held tab: drawn from its centre, laid out
                    // where it ends, so the finger meets it there at once.
                    .visualEffect { [isExpanded] content, proxy in
                        let frame = proxy.frame(in: .named(TabQuickSwitchOverlay.space))
                        return content.offset(isExpanded ? .zero
                                              : CGSize(width: pivot.x - frame.midX, height: pivot.y - frame.midY))
                    }
            }
            if let labelIndex {
                Text(presentation.items[labelIndex].title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    .environment(\.layoutDirection, contentDirection)
                    .opacity(menu.highlighted == nil ? 0 : 1)
                    .layoutValue(key: TabQuickSwitchFanLabel.self, value: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The list grows out of the bar's side.
    private var towardsBar: UnitPoint {
        switch presentation.axis {
        case .horizontal: .bottom
        case .vertical: presentation.barFrame.midX < area.midX ? .leading : .trailing
        }
    }

    private func report(_ frame: CGRect, for destination: TabQuickSwitchDestination) {
        itemFrames[destination] = frame
        menu.setFrame(frame, for: destination)
    }
}

private struct TabQuickSwitchRow: View {
    let item: TabQuickSwitchItem
    let isHighlighted: Bool
    @ScaledMetric(relativeTo: .body) private var symbolWidth = TabQuickSwitchMetrics.rowSymbolWidth

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbol)
                .font(.body.weight(.semibold))
                .frame(width: symbolWidth)
            Text(item.title)
                .lineLimit(1)
            Spacer(minLength: 16)
            Image(systemName: "checkmark")
                .font(.footnote.weight(.bold))
                .opacity(item.isCurrent ? 1 : 0)
        }
        .font(.body.weight(.medium))
        .padding(.horizontal, 14)
        .frame(minHeight: GlassTabBarMetrics.minimumTapSize)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: TabQuickSwitchMetrics.rowCornerRadius)
                .fill(Color.primary.opacity(isHighlighted ? 0.12 : 0))
        }
    }
}

private struct TabQuickSwitchBubble: View {
    let item: TabQuickSwitchItem
    let isHighlighted: Bool
    let diameter: CGFloat

    var body: some View {
        Image(systemName: item.symbol)
            .font(.title3.weight(.semibold))
            .foregroundStyle(isHighlighted ? HierarchicalShapeStyle.primary : .secondary)
            .frame(width: diameter, height: diameter)
            .glassEffect(isHighlighted ? .regular.tint(.accentColor.opacity(0.35)) : .regular, in: .circle)
            .overlay(alignment: .topTrailing) {
                if item.isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tint)
                }
            }
    }
}

/// Spotlights the bar and its menu, or rings the bar with a glow.
private struct TabQuickSwitchHaloView: View {
    let halo: TabQuickSwitchHalo
    let bar: CGRect
    /// What the spotlight lights.
    let focus: CGRect
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch halo {
            case .spotlight:
                dim
            case .blurredSpotlight:
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .mask { spotlightMask }
                    dim
                }
            case .glowRing:
                glow
            }
        }
        .animation(.smooth(duration: 0.3), value: focus)
    }

    private var dim: some View {
        Rectangle()
            .fill(.black.opacity(colorScheme == .dark ? 0.5 : 0.3))
            .mask { spotlightMask }
    }

    /// Opaque but for a soft round hole around `focus`. The hole's fade
    /// starts past `focus`'s corners, so all of it stays lit.
    private var spotlightMask: some View {
        let diameter = hypot(focus.width, focus.height) + TabQuickSwitchMetrics.spotlightFeather * 2
        return Rectangle()
            .overlay {
                Circle()
                    .frame(width: diameter, height: diameter)
                    .blur(radius: TabQuickSwitchMetrics.spotlightFeather)
                    .position(x: focus.midX, y: focus.midY)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
    }

    private var glow: some View {
        let width = TabQuickSwitchMetrics.glowWidth
        return ZStack {
            Capsule()
                .fill(Color.accentColor.opacity(0.3))
                .frame(width: bar.width + width * 4, height: bar.height + width * 4)
                .blur(radius: TabQuickSwitchMetrics.glowBlur * 2)
            Capsule()
                .stroke(Color.accentColor, lineWidth: width)
                .frame(width: bar.width + width, height: bar.height + width)
                .blur(radius: TabQuickSwitchMetrics.glowBlur)
        }
        .position(x: bar.midX, y: bar.midY)
    }
}
