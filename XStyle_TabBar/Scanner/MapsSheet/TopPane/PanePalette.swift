//
//  PanePalette.swift
//  MapsIOS26BottomSheet
//

import SwiftUI

/// Colors for the gradient that fills the top pane.
enum PanePalette {
    static var gradient: LinearGradient {
        LinearGradient(
            colors: [.indigo, .purple, .pink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
