import SwiftUI

/// The search scope, which the Search tab's quick switch menu changes, and
/// how the quick switch menus look. Search itself isn't built yet.
struct SearchTabPage: View {
    @AppStorage(SearchScope.storageKey) private var scope = SearchScope.defaultScope

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label {
                    Text(RootTab.search.title)
                } icon: {
                    Image(systemName: RootTab.search.symbol)
                }
                .font(.title2.bold())

                Picker("Search in", selection: $scope) {
                    ForEach(SearchScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("search.scope")

                ContentUnavailableView {
                    Label {
                        Text(scope.title)
                    } icon: {
                        Image(systemName: scope.symbol)
                    }
                } description: {
                    Text(scope.placeholderDescription)
                }

                QuickSwitchAppearanceSection()
            }
            .padding()
        }
        .background {
            AmbientGradientBackground(palettes: [.lavenderHealth], progress: 0)
        }
    }
}

/// How the quick switch menus draw the eye and lay out their items. The
/// menus themselves are turned on and off on the Profile page.
private struct QuickSwitchAppearanceSection: View {
    @AppStorage(TabQuickSwitchSettings.enabledKey) private var isEnabled = TabQuickSwitchSettings.defaultEnabled
    @AppStorage(TabQuickSwitchSettings.haloKey) private var halo = TabQuickSwitchHalo.defaultHalo
    @AppStorage(TabQuickSwitchSettings.layoutKey) private var layout = TabQuickSwitchLayout.defaultLayout

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Halo")
                        .font(.subheadline.weight(.semibold))
                    Picker("Halo", selection: $halo) {
                        ForEach(TabQuickSwitchHalo.allCases) { halo in
                            Text(halo.title).tag(halo)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("search.quickSwitch.halo")
                    Text(halo.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Layout")
                        .font(.subheadline.weight(.semibold))
                    Picker("Layout", selection: $layout) {
                        ForEach(TabQuickSwitchLayout.allCases) { layout in
                            Text(layout.title).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("search.quickSwitch.layout")
                    Text(layout.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!isEnabled)

            if !isEnabled {
                Text("Quick switch is off. Turn it on in Profile.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
        } label: {
            Text("Quick switch")
        }
    }
}

#Preview {
    SearchTabPage()
}
