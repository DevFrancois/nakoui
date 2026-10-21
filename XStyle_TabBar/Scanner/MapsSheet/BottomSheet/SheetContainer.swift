//
//  SheetContainer.swift
//  MapsIOS26BottomSheet
//

import SwiftUI
import UIKit

/// The custom bottom sheet.
///
/// A fixed-size column (header + content, as tall as the sheet at full) sits in a surface whose frame and
/// corners follow `sheetTop` every frame: Liquid Glass floating at partial detents and edge-to-edge at full
/// on iOS 26, material edge-to-edge on iOS 18. This is the only sheet view that reads the per-frame position;
/// the column's size never changes, so the content is not laid out again while the sheet moves.
struct SheetContainer<Header: View, Content: View>: View {
    let controller: SheetController
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            /// Not hit-testable: touches outside the surface reach the pane.
            Color.clear

            /// Nothing while the surface rests below the screen: its glass and content leave the hierarchy, so the
            /// next presentation starts from unscrolled content.
            if let geometry = controller.geometry, geometry.surface.minY < controller.canvas.size.height {
                Color.black
                    .opacity(geometry.dimOpacity)
                    .allowsHitTesting(false)

                SheetSurface(
                    geometry: geometry,
                    metrics: controller.metrics,
                    surfaceProgress: controller.surfaceProgress,
                    header: header,
                    content: content
                )
                .gesture(SheetPanGesture(controller: controller))
                .accessibilityAction(named: "Expand") {
                    move(by: 1)
                }
                /// One step down from medium dismisses the sheet.
                .accessibilityAction(named: controller.detent == .medium ? "Close" : "Collapse") {
                    move(by: -1)
                }
                /// Dismissed, it is only sliding away.
                .accessibilityHidden(controller.detent == .hidden)
                /// Padding keeps the surface's layout position, which its concentric corners resolve against.
                .padding(.leading, geometry.surface.minX)
                .padding(.top, geometry.surface.minY)

                /// UIKit hit-tests the scroll view by its frame, the whole column: swallow touches on the column
                /// outside the surface, so the gutters never reach hidden content.
                Color.clear
                    .contentShape(SheetGutterShape(column: geometry.column, surface: geometry.surface))
                    .onTapGesture {}
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sensoryFeedback(.impact(weight: .light), trigger: controller.feedbackTrigger)
        /// The Wave spring is the only animation on the sheet.
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    /// One detent up (positive) or down (negative), for VoiceOver.
    private func move(by step: Int) {
        let detents = SheetDetent.allCases
        guard let index = detents.firstIndex(of: controller.detent) else { return }
        let target = detents[min(max(index + step, 0), detents.count - 1)]
        controller.settle(to: target, velocity: 0)
    }
}

/// The part of the column outside the surface, in the container's (window) coordinates.
private struct SheetGutterShape: Shape {
    var column: CGRect
    var surface: CGRect

    func path(in rect: CGRect) -> Path {
        Path(column).subtracting(Path(surface))
    }
}

/// The surface frame follows the sheet; the column inside keeps its size and is clipped to it.
private struct SheetSurface<Header: View, Content: View>: View {
    /// The grouped backing over the glass: frosted on glass, so the sheet keeps one neutral tone whatever is behind
    /// it, then fully opaque at full. iOS 18's material sheet has no backing.
    private var backingOpacity: CGFloat {
        guard metrics.fadesToOpaqueAtFull else { return 0 }
        let frosted = SheetMetrics.frostedBackingOpacity
        return frosted + (1 - frosted) * surfaceProgress
    }

    var geometry: SheetGeometry
    var metrics: SheetMetrics
    /// `SheetController.surfaceProgress`: the opaque backing over the glass fades with it.
    var surfaceProgress: CGFloat
    var header: Header
    var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: metrics.headerHeight)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: geometry.contentSize.width, height: geometry.contentSize.height, alignment: .top)
        /// The header is drawn over the column, so its per-frame inset never reaches the scroll view's stack.
        .overlay(alignment: .top) {
            header
                .padding(.horizontal, geometry.headerInset)
                .frame(width: geometry.contentSize.width, height: metrics.headerHeight)
        }
        /// Top-aligned and centered: the column stays put horizontally while the surface narrows.
        .frame(width: geometry.surface.width, height: geometry.surface.height, alignment: .top)
        .modifier(SheetBackground(metrics: metrics, backingOpacity: backingOpacity))
    }
}

private struct SheetBackground: ViewModifier {
    var metrics: SheetMetrics
    var backingOpacity: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            glass(content)
        } else {
            material(content)
        }
    }

    /// Fixed top corners like the native sheet; bottom corners concentric with the display while floating.
    @available(iOS 26, *)
    private func glass(_ content: Content) -> some View {
        let shape = ConcentricRectangle(
            uniformTopCorners: .fixed(metrics.sheetTopCornerRadius),
            uniformBottomCorners: .concentric(minimum: .fixed(SheetMetrics.minimumBottomCornerRadius))
        )
        return content
            .clipShape(shape)
            .background {
                shape
                    .fill(Self.elevatedBackground)
                    .opacity(backingOpacity)
            }
            .glassEffect(.regular, in: shape)
            /// This, not the clip, limits hit-testing to the drawn surface.
            .contentShape(shape)
    }

    private func material(_ content: Content) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: metrics.sheetTopCornerRadius,
            topTrailingRadius: metrics.sheetTopCornerRadius,
            style: .continuous
        )
        return content
            .clipShape(shape)
            /// A background view, not `.background(.ultraThinMaterial, in:)`: the material style turns the
            /// content's secondary text and separators vibrant, and the vibrancy never reaches the UIKit scroll
            /// view, so they fade out.
            .background {
                shape
                    .fill(.ultraThinMaterial)
            }
            .contentShape(shape)
    }

    /// The sheet at full, as in Apple Maps: grouped background at the elevated level (#F2F2F7, or #1C1C1E in dark
    /// mode), which `SheetCardFill`'s opaque cards stand out against.
    private static let elevatedBackground = Color(uiColor: UIColor { traits in
        UIColor.systemGroupedBackground.resolvedColor(with: traits.modifyingTraits { mutableTraits in
            mutableTraits.userInterfaceLevel = .elevated
        })
    })
}

#if DEBUG
private struct SheetContainerPreview: View {
    let sheet: SheetController
    @State private var settings = PreviewFixtures.makeSettings()

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)

            SheetContainer(controller: sheet) {
                SheetHeader(title: PetFoodAnalysis.example.recipe, subtitle: Text(ScannedCode.sampleEAN13.value), onClose: {})
            } content: {
                BottomSheetView(
                    analysis: .example,
                    code: .sampleEAN13,
                    settings: settings,
                    horizontalPadding: sheet.metrics.scrollContentPadding,
                    bottomPadding: sheet.canvas.safeAreaBottom,
                    onScanAgain: {}
                )
            }
        }
        .frame(width: sheet.canvas.size.width, height: sheet.canvas.size.height)
        .clipped()
        .ignoresSafeArea()
    }
}

#Preview("Medium sheet", traits: .fixedLayout(width: 393, height: 852)) {
    @Previewable @State var sheet = PreviewFixtures.makeSheet(detent: .medium)

    SheetContainerPreview(sheet: sheet)
}

#Preview("Full sheet · Dark", traits: .fixedLayout(width: 393, height: 852)) {
    @Previewable @State var sheet = PreviewFixtures.makeSheet(detent: .full)

    SheetContainerPreview(sheet: sheet)
        .preferredColorScheme(.dark)
}
#endif
