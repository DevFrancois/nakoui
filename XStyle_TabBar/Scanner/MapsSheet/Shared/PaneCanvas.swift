//
//  PaneCanvas.swift
//  MapsIOS26BottomSheet
//

import CoreGraphics

/// Screen size and safe-area insets shared by the pane and sheet, in window coordinates.
nonisolated struct PaneCanvas: Equatable, Sendable {
    var size: CGSize
    var safeAreaTop: CGFloat
    var safeAreaBottom: CGFloat

    static let zero = PaneCanvas(size: .zero, safeAreaTop: 0, safeAreaBottom: 0)
}
