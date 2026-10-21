//
//  ContentView.swift
//  MapsIOS26BottomSheet
//
//  Created by Balaji Venkatesh on 26/06/25.
//

import SwiftUI

struct ContentView: View {
    /// Single source of truth for the sheet's position; the sheet and the pane both read it.
    @State private var sheet: SheetController
    @State private var settings: SheetSettings
    /// Illustrative until real label data is wired in.
    private let analysis = PetFoodAnalysis.example
    @State private var paneModel = TopPaneModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(settings: SheetSettings = SheetSettings(), initialDetent: SheetDetent? = nil) {
        _sheet = State(initialValue: SheetController(initialDetent: initialDetent))
        _settings = State(initialValue: settings)
    }

    var body: some View {
        /// A GeometryReader never grows with its children, so the canvas below stays the screen,
        /// whatever the sheet and the pane draw inside it.
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color(.systemGroupedBackground)

                TopPaneView(
                    sheet: sheet,
                    model: paneModel,
                    effect: settings.paneEffect,
                    showsSquash: settings.paneSquash,
                    showsDeformation: settings.paneDeformation,
                    onTap: sheet.collapse
                )

                SheetContainer(controller: sheet) {
                    SheetHeader(sheet: sheet, title: analysis.recipe, subtitle: analysis.description)
                } content: {
                    BottomSheetView(
                        analysis: analysis,
                        settings: settings,
                        horizontalPadding: sheet.metrics.scrollContentPadding,
                        bottomPadding: sheet.canvas.safeAreaBottom
                    )
                }
            }
            /// Top-aligned: a sheet pulled below collapsed overhangs the screen, and centering the taller
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
        .onChange(of: settings.paneEffect) { _, _ in
            configurePaneMotion()
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
        paneModel.configure(effect: settings.paneEffect, isSmoothed: settings.smoothStretch)
    }
}

#if DEBUG
#Preview("Full") {
    ContentView(settings: PreviewFixtures.makeSettings(), initialDetent: .full)
}

#Preview("Medium") {
    ContentView(settings: PreviewFixtures.makeSettings(), initialDetent: .medium)
}

#Preview("Collapsed · Dark") {
    ContentView(settings: PreviewFixtures.makeSettings(), initialDetent: .collapsed)
        .preferredColorScheme(.dark)
}
#endif
