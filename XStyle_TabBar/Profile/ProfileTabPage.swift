import SwiftUI

/// Debug builds include access to the app's diagnostic settings.
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

/// Uses the production bar, with local selection so a comparison hold never
/// navigates away from the reference. The supplied image coordinates are 3x.
private struct TabBarReferenceComparison: View {
    @State private var selection = RootTab.home

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tab bar comparison")
                .font(.title3.bold())
            Text("Hold and slide on the live menu to compare its glass with the reference.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                TabBarComparisonPair(selection: $selection, scale: 2)
                TabBarComparisonPair(selection: $selection, scale: 1)
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
