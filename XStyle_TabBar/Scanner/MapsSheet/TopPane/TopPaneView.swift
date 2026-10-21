//
//  TopPaneView.swift
//  MapsIOS26BottomSheet
//

import SwiftUI

/// Rounded pane above the bottom sheet. It resizes with the sheet down to medium, then holds its size as the sheet
/// rises to full over it, pushed back a little like the content under a stacked sheet. The other `ViewportMode`s keep
/// its frame, and the sheet slides over it all the way.
struct TopPaneView<Content: View, Footer: View>: View {
    let sheet: SheetController
    let model: TopPaneModel
    /// Debug setting: whether the stretch narrows the pane.
    var showsSquash: Bool
    /// Debug setting: how the pane makes way for the sheet.
    var mode = ViewportMode.resizing
    /// What fills the rounded surface, such as the camera.
    @ViewBuilder var content: Content
    /// Under the pane while the sheet is hidden, one gap above the bottom safe area; see `PaneLayout`.
    @ViewBuilder var footer: Footer
    var body: some View {
        ZStack(alignment: .top) {
            /// Keeps the root rendering before the canvas is measured.
            Color.clear

            if let layout = PaneLayout(
                sheetTop: sheet.paneSheetTop,
                canvas: sheet.canvas,
                sideInset: sheet.metrics.paneSideInset,
                tops: sheet.tops,
                footerHeight: model.footerHeight,
                mode: mode
            ) {
                /// Under the pane: the footer takes its new height at once while the pane eases, so growing it
                /// comes out from under the pane rather than over it.
                footer
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        model.setMeasuredFooter(height)
                    }
                    .frame(maxWidth: .infinity)
                    /// As wide as the pane, so what it leads with lines up with the pane's edge.
                    .padding(.horizontal, sheet.metrics.paneSideInset)
                    /// Placed from the top like the pane, from the same canvas, so the two never part.
                    .frame(height: layout.footerBottom, alignment: .bottom)
                    /// Out of reach under the sheet.
                    .accessibilityHidden(layout.isFooterCovered)

                PaneContainer(
                    layout: layout,
                    isCovered: sheet.isPastMedium,
                    stretch: model.stretch,
                    cornerRadius: PaneMetrics.viewportCornerRadius,
                    /// The stretch only shows on a pane that follows the sheet.
                    showsSquash: showsSquash && mode == .resizing,
                    content: content
                )
            }
        }
        /// Only the Wave springs move the pane and its footer.
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

extension EnvironmentValues {
    /// Whether the sheet has risen past medium, over the pane. It flips as the sheet is carried past medium, not on
    /// every frame, nor as it bounces about a detent.
    @Entry var paneIsCovered = false
}

/// Scales the card in its own coordinates, then places it below the top safe area.
private struct PaneContainer<Content: View>: View {
    var layout: PaneLayout
    /// The sheet past medium, leaving out its bounce: the cover the content reacts to. The scale follows the bounce.
    var isCovered: Bool
    var stretch: CGFloat
    var cornerRadius: CGFloat
    var showsSquash: Bool
    var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let displayedStretch = reduceMotion ? 0 : stretch
        let squash = showsSquash ? 1 - PaneTuning.maxSquash * abs(displayedStretch) : 1
        let progress = layout.coverProgress
        let coverScale = reduceMotion ? 1 : layout.scale
        PaneSurface(cornerRadius: cornerRadius) {
            content
                .environment(\.paneIsCovered, isCovered)
        }
        .frame(width: layout.paneFrame.width, height: layout.paneFrame.height)
        .scaleEffect(x: squash * coverScale, y: coverScale)
        .accessibilityHidden(progress >= 0.5)
        .offset(y: layout.paneFrame.minY)
    }
}

#if DEBUG
#Preview("Medium", traits: .fixedLayout(width: 393, height: 852)) {
    TopPanePreview(detent: .medium)
}

#Preview("Full · Dark", traits: .fixedLayout(width: 393, height: 852)) {
    TopPanePreview(detent: .full)
        .preferredColorScheme(.dark)
}

private struct TopPanePreview: View {
    @State private var sheet: SheetController
    @State private var model = TopPaneModel()

    init(detent: SheetDetent) {
        _sheet = State(initialValue: PreviewFixtures.makeSheet(detent: detent))
    }

    var body: some View {
        TopPaneView(sheet: sheet, model: model, showsSquash: true) {
            ScannerBackdropPlaceholder()
        } footer: {
            EmptyView()
        }
        .frame(width: PreviewFixtures.canvas.size.width, height: PreviewFixtures.canvas.size.height)
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea()
    }
}
#endif
