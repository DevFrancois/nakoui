//
//  TopPaneView.swift
//  MapsIOS26BottomSheet
//

import SwiftUI

/// Rounded pane above the bottom sheet. It resizes with the sheet down to medium, then holds its size as the sheet
/// rises to full over it, pushed back a little like the content under a stacked sheet.
struct TopPaneView<Content: View, Footer: View>: View {
    let sheet: SheetController
    let model: TopPaneModel
    /// Debug setting: whether the stretch narrows the pane.
    var showsSquash: Bool
    /// What fills the rounded surface, such as the camera.
    @ViewBuilder var content: Content
    /// Under the pane while the sheet is hidden, one gap above the bottom safe area; see `PaneLayout`.
    @ViewBuilder var footer: Footer
    @State private var footerHeight: CGFloat = 0
    var body: some View {
        ZStack(alignment: .top) {
            /// Keeps the root rendering before the canvas is measured.
            Color.clear

            if let layout = PaneLayout(
                sheetTop: sheet.paneSheetTop,
                canvas: sheet.canvas,
                sideInset: sheet.metrics.paneSideInset,
                tops: sheet.tops,
                footerHeight: footerHeight
            ) {
                PaneContainer(
                    layout: layout,
                    stretch: model.stretch,
                    cornerRadius: PaneMetrics.viewportCornerRadius,
                    showsSquash: showsSquash,
                    content: content
                )

                footer
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        footerHeight = height
                    }
                    .frame(maxWidth: .infinity)
                    /// Placed from the top like the pane, from the same canvas, so the two never part.
                    .frame(height: layout.footerBottom, alignment: .bottom)
            }
        }
        /// Only the Wave springs move the pane and its footer.
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

extension EnvironmentValues {
    /// Whether the sheet has risen past medium, over the pane. It flips only at medium, not on every frame.
    @Entry var paneIsCovered = false
}

/// Scales the card in its own coordinates, then places it below the top safe area.
private struct PaneContainer<Content: View>: View {
    var layout: PaneLayout
    var stretch: CGFloat
    var cornerRadius: CGFloat
    var showsSquash: Bool
    var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let displayedStretch = reduceMotion ? 0 : stretch
        let squash = showsSquash ? 1 - PaneTuning.maxSquash * abs(displayedStretch) : 1
        let progress = layout.coverProgress
        /// Follows the sheet linearly, so the pane recedes as fast as the finger covers it.
        let coverScale = reduceMotion ? 1 : 1 - (1 - PaneTuning.coveredScale) * progress
        PaneSurface(cornerRadius: cornerRadius) {
            content
                .environment(\.paneIsCovered, progress > 0)
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
