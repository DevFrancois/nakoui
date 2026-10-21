//
//  PaneEffect.swift
//  MapsIOS26BottomSheet
//

import Foundation

/// Disappearance and reappearance styles for the top pane.
nonisolated enum PaneEffect: String, CaseIterable, Identifiable, Sendable {
    case funnel
    case island

    /// The effect used until one is chosen in the debug settings.
    static let standard: PaneEffect = .funnel

    var id: Self {
        self
    }

    var title: LocalizedStringResource {
        switch self {
        case .funnel:
            "Funnel"
        case .island:
            "Island"
        }
    }

    var caption: LocalizedStringResource {
        switch self {
        case .funnel:
            "A faster swipe tightens the neck as the pane flows upward."
        case .island:
            "The pane flexes with your swipe and contracts toward the Dynamic Island."
        }
    }
}
