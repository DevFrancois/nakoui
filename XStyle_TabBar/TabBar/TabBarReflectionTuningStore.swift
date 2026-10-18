#if DEBUG
import Foundation
import Observation
import SwiftUI

/// The root retains this reference. Individual rows observe only their field;
/// the renderer bridge alone reads the complete immutable settings value.
@MainActor
@Observable
final class TabBarReflectionTuningStore {
    nonisolated static let storageKey = "tabBar.reflectionTuning.v1"

    var mode: TabBarReflectionSettings.Mode {
        didSet { if mode != oldValue { didEdit() } }
    }
    var surfaceOpacity: Double {
        didSet {
            let value = TabBarReflectionSettings.Parameter.surfaceOpacity.clamp(surfaceOpacity)
            if surfaceOpacity != value { surfaceOpacity = value; return }
            if surfaceOpacity != oldValue { didEdit() }
        }
    }
    var faceWash: Double {
        didSet {
            let value = TabBarReflectionSettings.Parameter.faceWash.clamp(faceWash)
            if faceWash != value { faceWash = value; return }
            if faceWash != oldValue { didEdit() }
        }
    }
    var reflectionStrength: Double {
        didSet {
            let value = TabBarReflectionSettings.Parameter.reflectionStrength.clamp(reflectionStrength)
            if reflectionStrength != value { reflectionStrength = value; return }
            if reflectionStrength != oldValue { didEdit() }
        }
    }
    var reflectionWidth: Double {
        didSet {
            let value = TabBarReflectionSettings.Parameter.reflectionWidth.clamp(reflectionWidth)
            if reflectionWidth != value { reflectionWidth = value; return }
            if reflectionWidth != oldValue { didEdit() }
        }
    }
    var saturation: Double {
        didSet {
            let value = TabBarReflectionSettings.Parameter.saturation.clamp(saturation)
            if saturation != value { saturation = value; return }
            if saturation != oldValue { didEdit() }
        }
    }
    var softness: Double {
        didSet {
            let value = TabBarReflectionSettings.Parameter.softness.clamp(softness)
            if softness != value { softness = value; return }
            if softness != oldValue { didEdit() }
        }
    }
    var samplingDistance: Double {
        didSet {
            let value = TabBarReflectionSettings.Parameter.samplingDistance.clamp(samplingDistance)
            if samplingDistance != value { samplingDistance = value; return }
            if samplingDistance != oldValue { didEdit() }
        }
    }
    var sharpHighlight: Double {
        didSet {
            let value = TabBarReflectionSettings.Parameter.sharpHighlight.clamp(sharpHighlight)
            if sharpHighlight != value { sharpHighlight = value; return }
            if sharpHighlight != oldValue { didEdit() }
        }
    }
    var sharpHighlightWidth: Double {
        didSet {
            let value = TabBarReflectionSettings.Parameter.sharpHighlightWidth.clamp(sharpHighlightWidth)
            if sharpHighlightWidth != value { sharpHighlightWidth = value; return }
            if sharpHighlightWidth != oldValue { didEdit() }
        }
    }
    var softGlow: Double {
        didSet {
            let value = TabBarReflectionSettings.Parameter.softGlow.clamp(softGlow)
            if softGlow != value { softGlow = value; return }
            if softGlow != oldValue { didEdit() }
        }
    }
    var softGlowWidth: Double {
        didSet {
            let value = TabBarReflectionSettings.Parameter.softGlowWidth.clamp(softGlowWidth)
            if softGlowWidth != value { softGlowWidth = value; return }
            if softGlowWidth != oldValue { didEdit() }
        }
    }
    var lightDirectionDegrees: Double {
        didSet {
            let value = TabBarReflectionSettings.Parameter.lightDirectionDegrees.clamp(lightDirectionDegrees)
            if lightDirectionDegrees != value { lightDirectionDegrees = value; return }
            if lightDirectionDegrees != oldValue { didEdit() }
        }
    }
    var warmCoolBalance: Double {
        didSet {
            let value = TabBarReflectionSettings.Parameter.warmCoolBalance.clamp(warmCoolBalance)
            if warmCoolBalance != value { warmCoolBalance = value; return }
            if warmCoolBalance != oldValue { didEdit() }
        }
    }
    var edgeDarkening: Double {
        didSet {
            let value = TabBarReflectionSettings.Parameter.edgeDarkening.clamp(edgeDarkening)
            if edgeDarkening != value { edgeDarkening = value; return }
            if edgeDarkening != oldValue { didEdit() }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var isApplying = false
    @ObservationIgnored private var isDirty = false

    init(defaults: UserDefaults = .standard, key: String = storageKey,
         debounce: Duration = .milliseconds(250)) {
        self.defaults = defaults
        self.key = key
        self.debounce = debounce
        let initial = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(TabBarReflectionSettings.self, from: $0) }?
            .sanitized() ?? .defaults
        mode = initial.mode
        surfaceOpacity = initial.surfaceOpacity
        faceWash = initial.faceWash
        reflectionStrength = initial.reflectionStrength
        reflectionWidth = initial.reflectionWidth
        saturation = initial.saturation
        softness = initial.softness
        samplingDistance = initial.samplingDistance
        sharpHighlight = initial.sharpHighlight
        sharpHighlightWidth = initial.sharpHighlightWidth
        softGlow = initial.softGlow
        softGlowWidth = initial.softGlowWidth
        lightDirectionDegrees = initial.lightDirectionDegrees
        warmCoolBalance = initial.warmCoolBalance
        edgeDarkening = initial.edgeDarkening
    }

    var settings: TabBarReflectionSettings {
        TabBarReflectionSettings(
            mode: mode,
            surfaceOpacity: surfaceOpacity,
            faceWash: faceWash,
            reflectionStrength: reflectionStrength,
            reflectionWidth: reflectionWidth,
            saturation: saturation,
            softness: softness,
            samplingDistance: samplingDistance,
            sharpHighlight: sharpHighlight,
            sharpHighlightWidth: sharpHighlightWidth,
            softGlow: softGlow,
            softGlowWidth: softGlowWidth,
            lightDirectionDegrees: lightDirectionDegrees,
            warmCoolBalance: warmCoolBalance,
            edgeDarkening: edgeDarkening
        )
    }

    func update(_ settings: TabBarReflectionSettings) {
        let value = settings.sanitized()
        guard self.settings != value else { return }
        isApplying = true
        mode = value.mode
        surfaceOpacity = value.surfaceOpacity
        faceWash = value.faceWash
        reflectionStrength = value.reflectionStrength
        reflectionWidth = value.reflectionWidth
        saturation = value.saturation
        softness = value.softness
        samplingDistance = value.samplingDistance
        sharpHighlight = value.sharpHighlight
        sharpHighlightWidth = value.sharpHighlightWidth
        softGlow = value.softGlow
        softGlowWidth = value.softGlowWidth
        lightDirectionDegrees = value.lightDirectionDegrees
        warmCoolBalance = value.warmCoolBalance
        edgeDarkening = value.edgeDarkening
        isApplying = false
        didEdit()
    }

    func resetDefaults() {
        update(.defaults)
        flush()
    }

    /// Editing-end and scene-inactive events flush without waiting for debounce.
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        guard isDirty, let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
        isDirty = false
    }

    private func didEdit() {
        guard !isApplying else { return }
        isDirty = true
        pendingSave?.cancel()
        let delay = debounce
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }
}

extension EnvironmentValues {
    // The optional default is stable and never allocates a model during reads.
    @Entry var tabBarReflectionTuning: TabBarReflectionTuningStore? = nil
}
#endif
