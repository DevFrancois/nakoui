//
//  PaneSheetLayout.swift
//  MapsIOS26BottomSheet
//
//  Created by Balaji Venkatesh on 26/06/25.
//

import SwiftUI

/// The top pane over the custom bottom sheet, both following one `SheetController` across the whole screen.
struct PaneSheetLayout<Pane: View, PaneFooter: View, Header: View, Content: View, PaneEffect: ViewModifier>: View {
    /// Single source of truth for the sheet's position; the sheet and the pane both read it.
    let sheet: SheetController
    let settings: SheetSettings
    /// Applied to the rounded pane before it scales and moves, such as an entrance.
    var paneEffect: PaneEffect
    @ViewBuilder var pane: Pane
    /// Drawn under the pane, one gap above the bottom safe area, while the sheet is hidden. The pane leaves room
    /// for it, and the rising sheet covers it.
    @ViewBuilder var paneFooter: PaneFooter
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @State private var paneModel = TopPaneModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        /// A GeometryReader never grows with its children, so the canvas below stays the screen,
        /// whatever the sheet and the pane draw inside it.
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color(.systemGroupedBackground)

                TopPaneView(
                    sheet: sheet,
                    model: paneModel,
                    showsSquash: settings.paneSquash,
                    mode: settings.viewportMode,
                    paneEffect: paneEffect
                ) {
                    pane
                } footer: {
                    paneFooter
                }

                SheetContainer(controller: sheet) {
                    header
                } content: {
                    content
                }
            }
            /// Top-aligned: a sheet pulled below medium overhangs the screen, and centering the taller
            /// stack would shift everything up by half the overhang.
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .ignoresSafeArea()
        .onGeometryChange(for: PaneCanvas.self) { proxy in
            /// The safe frame plus its insets: the full screen.
            let insets = proxy.safeAreaInsets
            return PaneCanvas(
                size: CGSize(
                    width: proxy.size.width + insets.leading + insets.trailing,
                    height: proxy.size.height + insets.top + insets.bottom
                ),
                safeAreaTop: insets.top,
                safeAreaBottom: insets.bottom
            )
        } action: { newValue in
            sheet.updateCanvas(newValue)
        }
        .onAppear {
            configurePaneMotion()
            let model = paneModel
            sheet.onVelocityChange = { [weak model] velocity in
                model?.sheetVelocityDidChange(velocity)
            }
        }
        .onDisappear {
            sheet.onVelocityChange = nil
            paneModel.stop()
        }
        .onChange(of: settings.smoothStretch) { _, _ in
            configurePaneMotion()
        }
        .onChange(of: settings.paneStretch, initial: true) { _, newValue in
            paneModel.stretchEnabled = newValue
        }
        .onChange(of: settings.sheetBounce, initial: true) { _, newValue in
            sheet.bounces = newValue
        }
        .onChange(of: settings.paneFollowsBounce, initial: true) { _, newValue in
            sheet.paneFollowsBounce = newValue
        }
        .onChange(of: reduceMotion, initial: true) { _, newValue in
            sheet.reduceMotion = newValue
            paneModel.reduceMotion = newValue
        }
    }

    private func configurePaneMotion() {
        paneModel.configure(isSmoothed: settings.smoothStretch)
    }
}

extension PaneSheetLayout where PaneEffect == EmptyModifier {
    init(
        sheet: SheetController, settings: SheetSettings,
        @ViewBuilder pane: () -> Pane, @ViewBuilder paneFooter: () -> PaneFooter,
        @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content
    ) {
        self.init(sheet: sheet, settings: settings, paneEffect: EmptyModifier(),
                  pane: pane, paneFooter: paneFooter, header: header, content: content)
    }
}

#if DEBUG
#Preview("Full") {
    PaneSheetLayoutPreview(detent: .full)
}

#Preview("Medium") {
    PaneSheetLayoutPreview(detent: .medium)
}

#Preview("Hidden · Dark") {
    PaneSheetLayoutPreview(detent: .hidden)
        .preferredColorScheme(.dark)
}

private struct PaneSheetLayoutPreview: View {
    @State private var sheet: SheetController
    @State private var settings = PreviewFixtures.makeSettings()
    @State private var history = PreviewFixtures.makeHistory()

    init(detent: SheetDetent) {
        _sheet = State(initialValue: SheetController(initialDetent: detent))
    }

    var body: some View {
        PaneSheetLayout(sheet: sheet, settings: settings) {
            ScannerBackdropPlaceholder()
        } paneFooter: {
            Text(verbatim: "Footer")
        } header: {
            SheetHeader(title: PetFoodAnalysis.example.recipe, subtitle: Text(ScannedCode.sampleEAN13.value), onClose: {})
        } content: {
            BottomSheetView(
                analysis: .example,
                code: .sampleEAN13,
                settings: settings,
                history: history,
                horizontalPadding: sheet.metrics.scrollContentPadding,
                bottomPadding: sheet.canvas.safeAreaBottom,
                onScanAgain: {}
            )
        }
    }
}
#endif
