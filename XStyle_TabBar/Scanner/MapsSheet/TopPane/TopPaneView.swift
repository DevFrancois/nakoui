//
//  TopPaneView.swift
//  MapsIOS26BottomSheet
//

import SwiftUI

/// Rounded pane above the bottom sheet. It resizes with the sheet, then collapses into the
/// top safe area with the selected effect as the sheet rises to full.
struct TopPaneView<Content: View, Underlay: View>: View {
    let sheet: SheetController
    let model: TopPaneModel
    var effect: PaneEffect
    /// Debug settings: whether the stretch narrows the pane and bends its collapse.
    var showsSquash: Bool
    var showsDeformation: Bool
    var onTap: () -> Void
    /// What fills the rounded surface, such as the camera's overlays.
    @ViewBuilder var content: Content
    /// Drawn under `content`, in the same rounded frame but out of its collapse effects, which flatten what they
    /// draw: for what can't be flattened, like a camera layer. It fades out while the pane collapses rather than
    /// leaving the hierarchy.
    @ViewBuilder var underlay: Underlay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack(alignment: .top) {
            /// Keeps the root rendering before the canvas is measured.
            Color.clear

            if let layout = PaneLayout(
                sheetTop: sheet.paneSheetTop,
                canvas: sheet.canvas,
                sideInset: sheet.metrics.paneSideInset,
                collapseEnd: sheet.tops.full,
                reduceMotion: reduceMotion
            ) {
                PaneContainer(
                    layout: layout,
                    stretch: model.stretch,
                    sheetCornerRadius: sheet.metrics.topCornerRadius,
                    effect: effect,
                    showsSquash: showsSquash,
                    showsDeformation: showsDeformation,
                    onTap: onTap,
                    content: content,
                    underlay: underlay
                )
            }
        }
        /// The Wave springs are the only animation on the pane.
        .transaction { transaction in
            transaction.animation = nil
        }
        .task {
            await PaneDisappearModifier.precompile()
        }
    }
}

extension EnvironmentValues {
    /// Whether the pane is collapsing toward the top safe area: the only time its effects flatten it offscreen (see
    /// `PaneDisappearModifier`), and its underlay fades out. It flips only at the collapse threshold, not on every
    /// frame.
    @Entry var paneIsCollapsing = false
}

/// Transforms the card in its own coordinates, then places it below the top safe area.
private struct PaneContainer<Content: View, Underlay: View>: View {
    var layout: PaneLayout
    var stretch: CGFloat
    var sheetCornerRadius: CGFloat
    var effect: PaneEffect
    var showsSquash: Bool
    var showsDeformation: Bool
    var onTap: () -> Void
    var content: Content
    var underlay: Underlay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let displayedStretch = reduceMotion ? 0 : stretch
        let squash = showsSquash ? 1 - PaneTuning.maxSquash * abs(displayedStretch) : 1
        let progress = layout.collapseProgress
        let motion = PaneEffectMotion(
            progress: progress,
            stretch: showsDeformation ? displayedStretch : 0,
            reduceMotion: reduceMotion
        )
        // Safe-area geometry is available on every supported iPhone; no private Island API.
        let safeTop = layout.safeAreaTop
        let destinationHeight = min(26, safeTop * 0.42)
        let destination = CGRect(
            x: 0,
            y: safeTop * 0.55 - destinationHeight / 2 - layout.paneFrame.minY,
            width: min(112, layout.paneFrame.width * 0.3),
            height: destinationHeight
        )
        ZStack(alignment: .top) {
            /// At rest the card's effects are identities, so the underlay lines up with it exactly.
            PaneSurface(sheetCornerRadius: sheetCornerRadius) {
                underlay
            }
            .frame(width: layout.paneFrame.width, height: layout.paneFrame.height)
            .scaleEffect(x: squash, y: 1)
            .opacity(progress > 0 ? 0 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .offset(y: layout.paneFrame.minY)

            PaneSurface(sheetCornerRadius: sheetCornerRadius) {
                content
            }
            .frame(width: layout.paneFrame.width, height: layout.paneFrame.height)
            .contentShape(.rect)
            .onTapGesture(perform: onTap)
            .scaleEffect(x: squash, y: 1)
            .modifier(
                PaneDisappearModifier(
                    motion: motion,
                    effect: effect,
                    size: layout.paneFrame.size,
                    destination: destination,
                    reduceMotion: reduceMotion
                )
            )
            .offset(y: layout.paneFrame.minY)
        }
        .environment(\.paneIsCollapsing, progress > 0)
    }
}

#if DEBUG
#Preview("Medium", traits: .fixedLayout(width: 393, height: 852)) {
    TopPanePreview(detent: .medium)
}

#Preview("Collapsed · Dark", traits: .fixedLayout(width: 393, height: 852)) {
    TopPanePreview(detent: .collapsed)
        .preferredColorScheme(.dark)
}

private struct TopPanePreview: View {
    @State private var sheet: SheetController
    @State private var model = TopPaneModel()

    init(detent: SheetDetent) {
        _sheet = State(initialValue: PreviewFixtures.makeSheet(detent: detent))
    }

    var body: some View {
        TopPaneView(sheet: sheet, model: model, effect: .standard, showsSquash: true, showsDeformation: true, onTap: {}) {
            ScannerBackdropPlaceholder()
        } underlay: {
            Color.black
        }
        .frame(width: PreviewFixtures.canvas.size.width, height: PreviewFixtures.canvas.size.height)
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea()
    }
}
#endif
