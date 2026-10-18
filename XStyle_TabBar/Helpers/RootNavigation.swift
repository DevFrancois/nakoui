import SwiftUI

/// Shared by the outer NavigationStack and the separately hosted tab roots.
/// Pages request pushes through this model; the stack still owns Back and pop.
@MainActor
@Observable
final class RootNavigation {
    var path = NavigationPath()

    func push<Value: Hashable>(_ value: Value) {
        path.append(value)
    }
}

extension EnvironmentValues {
    @Entry var rootNavigation: RootNavigation?
}

/// A hosting boundary has no implicit access to the outer stack's destinations.
/// Standalone previews can still use an ordinary NavigationLink.
struct RootNavigationLink<Value: Hashable, Label: View>: View {
    @Environment(\.rootNavigation) private var navigation
    let value: Value
    @ViewBuilder let label: Label

    var body: some View {
        if let navigation {
            Button { navigation.push(value) } label: { label }
        } else {
            NavigationLink(value: value) { label }
        }
    }
}
