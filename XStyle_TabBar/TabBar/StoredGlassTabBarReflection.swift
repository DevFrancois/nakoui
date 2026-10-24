import SwiftUI

@propertyWrapper
struct StoredGlassTabBarReflection: DynamicProperty {
    @AppStorage("tabBar.reflection.v1") private var persistedData = Data()

    var wrappedValue: GlassTabBarReflectionConfiguration {
        get {
            (try? JSONDecoder().decode(GlassTabBarReflectionConfiguration.self, from: persistedData))?
                .normalized ?? .reference
        }
        nonmutating set {
            let value = newValue.normalized
            guard value != wrappedValue, let data = try? JSONEncoder().encode(value) else { return }
            persistedData = data
        }
    }

    var projectedValue: Binding<GlassTabBarReflectionConfiguration> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}
