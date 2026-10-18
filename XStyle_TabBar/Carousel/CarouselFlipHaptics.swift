import CoreHaptics
import UIKit

/// The haptic of a card turning over: `CarouselFlip.ahap`, adapted from the FWTransition
/// reference, or a single tap. Devices without Core Haptics always get the tap.
@MainActor
final class CarouselFlipHaptics {
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?
    private var pattern: CHHapticPattern?
    private var player: (any CHHapticAdvancedPatternPlayer)?
    private let tapGenerator = UIImpactFeedbackGenerator(style: .rigid)

    /// Starts the engine early, so the haptic begins with the turn.
    func prepare() {
        guard supportsHaptics else { return }
        do {
            if engine == nil {
                let created = try CHHapticEngine()
                created.playsHapticsOnly = true
                created.isAutoShutdownEnabled = true
                engine = created
            }
            if pattern == nil, let url = Bundle.main.url(forResource: "CarouselFlip", withExtension: "ahap") {
                pattern = try CHHapticPattern(contentsOf: url)
            }
            try engine?.start()
        } catch {
            engine = nil
            pattern = nil
        }
    }

    func play() {
        guard supportsHaptics else { playFallback(); return }
        prepare()
        guard let engine, let pattern else { playFallback(); return }
        do {
            player = try engine.makeAdvancedPlayer(with: pattern)
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            self.engine = nil
            self.pattern = nil
            playFallback()
        }
    }

    /// A single tap.
    func tap() {
        tapGenerator.impactOccurred(intensity: 0.8)
        tapGenerator.prepare()
    }

    /// Readies the tap, so it lands with the turn.
    func prepareTap() {
        tapGenerator.prepare()
    }

    private func playFallback() {
        tap()
    }
}
