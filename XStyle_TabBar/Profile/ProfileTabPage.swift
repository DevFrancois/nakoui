import SwiftUI

/// The pet the profile shows, which the Profile tab's quick switch menu
/// changes, and whether that menu opens. Debug builds include access to the
/// app's diagnostic settings.
struct ProfileTabPage: View {
    #if DEBUG
    @State private var isShowingDebugSettings = false
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label {
                        Text(RootTab.profile.title)
                    } icon: {
                        Image(systemName: RootTab.profile.symbol)
                    }
                    .font(.title2.bold())

                    Spacer(minLength: 8)

                    #if DEBUG
                    Button("Debug Settings", systemImage: "slider.horizontal.3") {
                        isShowingDebugSettings = true
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("profile.debugSettings")
                    #endif
                }

                ProfilePetHeader()
                QuickSwitchSettingsSection()

                TabBarReferenceComparison()
            }
            .padding()
        }
        .background {
            AmbientGradientBackground(palettes: [.lavenderHealth], progress: 0)
        }
        #if DEBUG
        .sheet(isPresented: $isShowingDebugSettings) {
            ProfileDebugSettings()
        }
        #endif
    }
}

/// The shown pet, chosen here or from the Profile tab's quick switch menu.
private struct ProfilePetHeader: View {
    @AppStorage(PetProfile.storageKey) private var selectedPetID = PetProfile.defaultID

    var body: some View {
        let pet = PetProfile.pet(for: selectedPetID)
        GroupBox {
            HStack(spacing: 16) {
                Image(systemName: pet.symbol)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.tint)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(pet.name)
                        .font(.title3.bold())
                    Text(pet.species)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                Picker("Pet", selection: $selectedPetID) {
                    ForEach(PetProfile.samples) { pet in
                        Text(pet.name).tag(pet.id)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("profile.petPicker")
            }
        }
        .animation(.default, value: selectedPetID)
    }
}

/// Turns the quick switch menus on and off, for every tab.
private struct QuickSwitchSettingsSection: View {
    @AppStorage(TabQuickSwitchSettings.enabledKey) private var isEnabled = TabQuickSwitchSettings.defaultEnabled

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Hold a tab to switch quickly", isOn: $isEnabled)
                    .accessibilityIdentifier("profile.quickSwitch")
                Text("Hold Home, Scan, Profile or Search in the tab bar, then slide onto a page, view or pet and let go. Change how the menu looks in Search.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text("Quick switch")
        }
    }
}

/// Uses the production bar, with local selection so a comparison hold never
/// navigates away from the reference. The supplied image coordinates are 3x.
private struct TabBarReferenceComparison: View {
    @State private var selection = RootTab.home
    @StoredGlassTabBarReflection private var reflection

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tab bar comparison")
                .font(.title3.bold())
            Text("Hold and slide on the live menu to compare its glass with the reference.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    TabBarComparisonPair(selection: $selection, scale: 1.5)
                    GlassTabBarReflectionControls(configuration: $reflection)
                        .frame(width: 300)
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 20) {
                    ViewThatFits(in: .horizontal) {
                        TabBarComparisonPair(selection: $selection, scale: 1.5)
                        TabBarComparisonPair(selection: $selection, scale: 1)
                    }
                    .frame(maxWidth: .infinity)

                    GlassTabBarReflectionControls(configuration: $reflection)
                }
            }
            .frame(maxWidth: .infinity)

            Text("Original photo")
                .font(.headline)
            Image("TabBarComparisonPhoto")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 240)
                .accessibilityLabel("Original comparison photo")
        }
    }
}

private struct TabBarComparisonPair: View {
    @Binding var selection: RootTab
    let scale: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                Text("Netflix reference").font(.caption.bold())
                Image("TabBarComparisonReference")
                    .resizable()
                    .frame(width: 361.0 / 3 * scale, height: 829.0 / 3 * scale)
                    .accessibilityLabel("Netflix reference tab bar over the photo")
            }
            VStack(spacing: 8) {
                Text("Our live tab bar").font(.caption.bold())
                TabBarComparisonCanvas(selection: $selection)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: 361.0 / 3 * scale, height: 829.0 / 3 * scale, alignment: .topLeading)
            }
        }
        .fixedSize()
    }
}

private struct TabBarComparisonCanvas: View {
    @Binding var selection: RootTab
    @State private var reflectionSource = GlassTabBarReflectionSource()

    var body: some View {
        ZStack(alignment: .topLeading) {
            TabBarComparisonBackdrop(source: reflectionSource)
            GlassTabBar(selection: $selection, layoutAxis: .vertical, reflectionSource: reflectionSource)
                .frame(width: 60, height: 244)
                .offset(x: 127.0 / 3, y: 37.0 / 3)
        }
        .frame(width: 361.0 / 3, height: 829.0 / 3)
        .environment(\.colorScheme, .dark)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityIdentifier("profile.tabBarComparison.live")
    }
}

private struct TabBarComparisonBackdrop: UIViewRepresentable {
    let source: GlassTabBarReflectionSource

    func makeCoordinator() -> GlassTabBarReflectionSource { source }

    func makeUIView(context: Context) -> TabBarPhotoBackdropView {
        let view = TabBarPhotoBackdropView()
        source.setView(view)
        return view
    }

    func updateUIView(_ view: TabBarPhotoBackdropView, context: Context) {
        source.setView(view)
    }

    static func dismantleUIView(_ view: TabBarPhotoBackdropView, coordinator: GlassTabBarReflectionSource) {
        coordinator.clear(ifMatching: view)
    }
}

private final class TabBarPhotoBackdropView: UIView {
    private let photo = UIImageView(image: UIImage(named: "TabBarComparisonPhoto"))

    init() {
        super.init(frame: .zero)
        backgroundColor = .black
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        addSubview(photo)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        photo.frame = CGRect(x: 5.0 / 3, y: 116.0 / 3, width: 356.0 / 3, height: 491.0 / 3)
    }
}

#Preview {
    ProfileTabPage()
}
