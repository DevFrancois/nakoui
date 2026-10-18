import Foundation
import Observation
import Synchronization
import Testing
@testable import XStyle_TabBar

struct TabBarReflectionSettingsTests {
    @Test("Shipping reflection defaults match the approved material")
    func defaults() {
        let value = TabBarReflectionSettings.defaults
        #expect(value.mode == .faceAndEdges)
        #expect(value.surfaceOpacity == 0.88)
        #expect(value.faceWash == 0.10)
        #expect(value.reflectionStrength == 1.15)
        #expect(value.reflectionWidth == 11)
        #expect(value.saturation == 1.10)
        #expect(value.softness == 1)
        #expect(value.samplingDistance == 96)
        #expect(value.sharpHighlight == 1.5)
        #expect(value.sharpHighlightWidth == 0.38)
        #expect(value.softGlow == 1.5)
        #expect(value.softGlowWidth == 3.5)
        #expect(value.lightDirectionDegrees == -25)
        #expect(value.warmCoolBalance == 0)
        #expect(value.edgeDarkening == 1)
        #expect(value.sanitized() == value)
    }

    @Test("Every parameter clamps finite outliers and replaces nonfinite values")
    func sanitization() {
        for parameter in TabBarReflectionSettings.Parameter.allCases {
            for (input, expected) in [
                (-Double.greatestFiniteMagnitude, parameter.range.lowerBound),
                (Double.greatestFiniteMagnitude, parameter.range.upperBound),
                (Double.nan, TabBarReflectionSettings.defaults[keyPath: parameter.keyPath]),
                (Double.infinity, TabBarReflectionSettings.defaults[keyPath: parameter.keyPath]),
                (-Double.infinity, TabBarReflectionSettings.defaults[keyPath: parameter.keyPath])
            ] {
                var value = TabBarReflectionSettings.defaults
                value[keyPath: parameter.keyPath] = input
                #expect(value.sanitized()[keyPath: parameter.keyPath] == expected)
            }
        }
    }

    @Test("Both modes encode all shared controls without discarding face wash")
    func codableModes() throws {
        for mode in TabBarReflectionSettings.Mode.allCases {
            var value = TabBarReflectionSettings.defaults
            value.mode = mode
            value.faceWash = 0.23
            value.reflectionStrength = 1.8
            let restored = try JSONDecoder().decode(TabBarReflectionSettings.self,
                from: JSONEncoder().encode(value))
            #expect(restored == value)
        }
    }

    #if DEBUG
    @MainActor
    @Test("Live updates are immediate, but persistence waits until editing ends")
    func editingFlush() throws {
        let fixture = PreferenceFixture()
        defer { fixture.clean() }
        let store = TabBarReflectionTuningStore(defaults: fixture.defaults,
                                               debounce: .seconds(30))
        store.faceWash = 0.21
        store.reflectionStrength = 1.7
        #expect(store.settings.faceWash == 0.21)
        #expect(fixture.data == nil)
        store.flush()
        let restored = TabBarReflectionTuningStore(defaults: fixture.defaults)
        #expect(restored.settings == store.settings)
    }

    @MainActor
    @Test("Mode changes preserve all shared slider values")
    func modeSharing() {
        let fixture = PreferenceFixture()
        defer { fixture.clean() }
        let store = TabBarReflectionTuningStore(defaults: fixture.defaults)
        store.faceWash = 0.18
        store.saturation = 1.6
        var expected = store.settings
        store.mode = .mostlyEdges
        expected.mode = .mostlyEdges
        #expect(store.settings == expected)
        store.mode = .faceAndEdges
        expected.mode = .faceAndEdges
        #expect(store.settings == expected)
        store.flush()
    }

    @MainActor
    @Test("Unrelated sliders do not invalidate each other's observable field")
    func narrowObservation() {
        let fixture = PreferenceFixture()
        defer { fixture.clean() }
        let store = TabBarReflectionTuningStore(defaults: fixture.defaults)
        let changed = Mutex(false)
        withObservationTracking {
            _ = store.faceWash
        } onChange: {
            changed.withLock { $0 = true }
        }
        store.reflectionStrength = 1.9
        #expect(!changed.withLock { $0 })
        store.faceWash = 0.19
        #expect(changed.withLock { $0 })
        store.flush()
    }

    @MainActor
    @Test("Debounced saving coalesces rapid edits and reset cannot be overwritten")
    func debounceAndReset() async throws {
        let fixture = PreferenceFixture()
        defer { fixture.clean() }
        let store = TabBarReflectionTuningStore(defaults: fixture.defaults,
                                               debounce: .milliseconds(20))
        for value in [0.1, 0.15, 0.2] { store.faceWash = value }
        #expect(fixture.data == nil)
        try await Task.sleep(for: .milliseconds(150))
        let saved = try JSONDecoder().decode(TabBarReflectionSettings.self,
                                            from: #require(fixture.data))
        #expect(saved.faceWash == 0.2)
        store.mode = .mostlyEdges
        store.reflectionStrength = 2
        store.resetDefaults()
        #expect(store.settings == .defaults)
        try await Task.sleep(for: .milliseconds(100))
        let restored = TabBarReflectionTuningStore(defaults: fixture.defaults)
        #expect(restored.settings == .defaults)
    }

    @MainActor
    @Test("Loading clamps out-of-range preferences and corrupted data uses defaults")
    func invalidPreferences() throws {
        let fixture = PreferenceFixture()
        defer { fixture.clean() }
        var value = TabBarReflectionSettings.defaults
        value.surfaceOpacity = -10
        value.lightDirectionDegrees = 999
        fixture.defaults.set(try JSONEncoder().encode(value), forKey: TabBarReflectionTuningStore.storageKey)
        let sanitized = TabBarReflectionTuningStore(defaults: fixture.defaults)
        #expect(sanitized.surfaceOpacity == 0.5)
        #expect(sanitized.lightDirectionDegrees == 180)
        fixture.defaults.set(Data("invalid JSON".utf8), forKey: TabBarReflectionTuningStore.storageKey)
        #expect(TabBarReflectionTuningStore(defaults: fixture.defaults).settings == .defaults)
    }

    @MainActor
    @Test("Direct edits and batch updates cannot send invalid values to Metal")
    func invalidLiveChanges() {
        let fixture = PreferenceFixture()
        defer { fixture.clean() }
        let store = TabBarReflectionTuningStore(defaults: fixture.defaults)
        store.faceWash = .nan
        store.reflectionWidth = 100
        store.surfaceOpacity = -.infinity
        #expect(store.faceWash == TabBarReflectionSettings.defaults.faceWash)
        #expect(store.reflectionWidth == 14)
        #expect(store.surfaceOpacity == TabBarReflectionSettings.defaults.surfaceOpacity)
        var invalid = TabBarReflectionSettings.defaults
        for parameter in TabBarReflectionSettings.Parameter.allCases {
            invalid[keyPath: parameter.keyPath] = .nan
        }
        store.update(invalid)
        #expect(store.settings == .defaults)
        store.flush()
    }

    @MainActor
    private struct PreferenceFixture {
        let name = "TabBarReflectionSettingsTests.\(UUID().uuidString)"
        let defaults: UserDefaults

        init() { defaults = UserDefaults(suiteName: name)! }
        var data: Data? { defaults.data(forKey: TabBarReflectionTuningStore.storageKey) }
        func clean() { defaults.removePersistentDomain(forName: name) }
    }
    #endif
}
