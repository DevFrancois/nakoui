import SwiftUI

/// Draws the continuous session's spotlight and optional submenu. It never
/// takes touches; the bar's recognizer keeps the finger throughout. The bar's frames are window points,
/// so the overlay lays out left to right whatever the language; the items'
/// content keeps the language's direction.
struct TabQuickSwitchOverlay: View {
    let menu: TabQuickSwitchMenu
    @AppStorage(TabQuickSwitchSettings.layoutKey) private var layout = TabQuickSwitchLayout.defaultLayout
    @StoredTabQuickSwitchListAnimations private var listAnimations
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var bubbleDiameter = TabQuickSwitchMetrics.bubbleDiameter
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
                    if let session = menu.session {
                        TabQuickSwitchSpotlight(menu: menu, barFrame: session.barFrame)
                            .id(session.id)
                            .transition(.opacity)
                    }
                    if let session = menu.session, let area {
                        // Retain one native List surface across replacements
                        // and collapse. Only its target content is optional.
                        TabQuickSwitchListPresenter(menu: menu,
                            presentation: menu.presentation.flatMap { usesList($0, in: area) ? $0 : nil },
                            area: area, contentDirection: layoutDirection, animations: listAnimations)
                            .id(session.id)
                            .transition(.identity)
                            .transaction { $0.animation = nil }
                    }
                    ZStack {
                        if let presentation = menu.presentation, let area, !usesList(presentation, in: area) {
                            TabQuickSwitchBubblePanel(menu: menu, presentation: presentation, area: area,
                                                      contentDirection: layoutDirection, bubbleDiameter: bubbleDiameter)
                                .id(presentation.id)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: menu.presentation?.id)
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
            .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.25), value: menu.isActive)
            .onDisappear { menu.cancel() }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func usesList(_ presentation: TabQuickSwitchMenu.Presentation, in area: CGRect) -> Bool {
        layout == .list || dynamicTypeSize.isAccessibilitySize || TabQuickSwitchPlacement.fan(
            count: presentation.items.count, diameter: bubbleDiameter, tab: presentation.tabFrame,
            bar: presentation.barFrame, area: area, axis: presentation.axis,
            isRightToLeft: layoutDirection == .rightToLeft, spacing: TabQuickSwitchMetrics.spacing
        ) == nil
    }

    /// Where a menu may go: the safe area less a margin, in the overlay's space.
    private var area: CGRect? {
        guard let safeFrame, let fullFrame else { return nil }
        return safeFrame.offsetBy(dx: -fullFrame.minX, dy: -fullFrame.minY)
            .insetBy(dx: TabQuickSwitchMetrics.margin, dy: TabQuickSwitchMetrics.margin)
    }
}

/// One open menu, made afresh each time one opens.
private struct TabQuickSwitchBubblePanel: View {
    let menu: TabQuickSwitchMenu
    let presentation: TabQuickSwitchMenu.Presentation
    let area: CGRect
    let contentDirection: LayoutDirection
    let bubbleDiameter: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether the items have come out of the held tab.
    @State private var isExpanded = false
    /// Keep the previous submenu's resolved focus until all new bubbles
    /// have a frame; partial layout must not shrink the spotlight.
    @State private var bubbleFrames: [TabQuickSwitchDestination: CGRect] = [:]
    /// The bubble the fan's label last named; it fades rather than leaves.
    @State private var labelIndex: Int?

    var body: some View {
        GlassEffectContainer { fan }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: menu.highlighted)
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
                        bubbleFrames[item.id] = frame
                        menu.setFrame(frame, for: item.id, presentationID: presentation.id)
                        reportFanFocus()
                    }
                    .scaleEffect(reduceMotion ? 1 : (isExpanded ? (isHighlighted ? 1.15 : 1) : 0.4))
                    .opacity(isExpanded ? 1 : 0)
                    // Out of the held tab: drawn from its centre, laid out
                    // where it ends, so the finger meets it there at once.
                    .visualEffect { [isExpanded, reduceMotion] content, proxy in
                        let frame = proxy.frame(in: .named(TabQuickSwitchOverlay.space))
                        return content.offset(reduceMotion || isExpanded ? .zero
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

    private func reportFanFocus() {
        let frames = presentation.items.compactMap { bubbleFrames[$0.id] }
        guard frames.count == presentation.items.count,
              frames.allSatisfy({ !$0.isEmpty && !$0.isInfinite && !$0.isNull }) else { return }
        let focus = frames.reduce(presentation.barFrame) { $0.union($1) }
        menu.setFocusFrame(focus, presentationID: presentation.id)
    }

}

/// Shows more rows past a scrolling list's edge.
struct TabQuickSwitchScrollHint: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .background(.ultraThinMaterial, in: .capsule)
            .padding(.vertical, 2)
            .transition(.opacity)
    }
}

struct TabQuickSwitchRow: View {
    let item: TabQuickSwitchItem
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 12) {
            // The symbol and check stop growing at accessibility sizes,
            // leaving the title the room.
            TabQuickSwitchRowSymbol(symbol: item.symbol)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            // Wraps rather than truncates where the card is narrower.
            Text(item.title)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "checkmark")
                .font(.footnote.weight(.bold))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .opacity(item.isCurrent ? 1 : 0)
        }
        .font(.body.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: GlassTabBarMetrics.minimumTapSize)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: TabQuickSwitchMetrics.rowCornerRadius)
                .fill(Color.primary.opacity(isHighlighted ? 0.12 : 0))
        }
    }
}

/// A row's symbol, in a column as wide in every row, so titles line up.
private struct TabQuickSwitchRowSymbol: View {
    let symbol: String
    @ScaledMetric(relativeTo: .body) private var width = TabQuickSwitchMetrics.rowSymbolWidth

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .frame(width: width)
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

/// Lives for the whole touch session, independently of submenu panels, and
/// frames the complete visible active area.
private struct TabQuickSwitchSpotlight: View {
    let menu: TabQuickSwitchMenu
    let barFrame: CGRect
    #if DEBUG
    @AppStorage(TabQuickSwitchSettings.spotlightAnimationDurationKey)
    private var storedDuration = TabQuickSwitchSettings.defaultSpotlightDuration
    #endif
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let geometry = TabQuickSwitchSpotlightGeometry.resolve(focus: menu.focusFrame ?? barFrame)
        let feather = TabQuickSwitchMetrics.spotlightFeather
        let diameter = (geometry.radius + feather) * 2
        Rectangle()
            .fill(.black.opacity(colorScheme == .dark ? 0.5 : 0.3))
            .mask {
                Rectangle()
                    .overlay {
                        Circle()
                            .frame(width: diameter, height: diameter)
                            .blur(radius: feather)
                            .position(x: geometry.center.x, y: geometry.center.y)
                            .blendMode(.destinationOut)
                            .transaction { transaction in
                                if reduceMotion {
                                    // Ancestor entry/end fades must not animate
                                    // the spotlight's center or clear radius.
                                    transaction.animation = nil
                                    transaction.disablesAnimations = true
                                }
                            }
                    }
                    .compositingGroup()
            }
            .animation(reduceMotion ? nil : .smooth(duration: duration, extraBounce: 0), value: geometry)
    }

    private var duration: Double {
        #if DEBUG
        TabQuickSwitchSettings.clampedSpotlightDuration(storedDuration)
        #else
        TabQuickSwitchSettings.defaultSpotlightDuration
        #endif
    }
}
