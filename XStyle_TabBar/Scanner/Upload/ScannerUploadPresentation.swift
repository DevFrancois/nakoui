import SwiftUI

/// Keeps the camera mounted at its original size while moving the two pages together.
struct ScannerUploadPresentation<Camera: View>: View {
    let controller: ScannerUploadController
    @ViewBuilder var camera: Camera
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var controller = controller
        GeometryReader { proxy in
            let distance = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            ZStack(alignment: .top) {
                camera
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .offset(y: reduceMotion ? 0 : -controller.progress * distance)
                    .opacity(reduceMotion ? 1 - controller.progress : 1)
                    .allowsHitTesting(controller.page == .camera)
                    .accessibilityHidden(!controller.isCameraSettled)

                UploadPhotosView(selectedPhotos: $controller.selectedPhotos, onBack: controller.showCamera)
                    .modifier(ScannerUploadDragSurface(controller: controller, source: .upload,
                                                       isEnabled: controller.page == .upload))
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .offset(y: reduceMotion ? 0 : (1 - controller.progress) * distance)
                    .opacity(reduceMotion ? controller.progress : 1)
                    .allowsHitTesting(controller.page == .upload)
                    .accessibilityHidden(!controller.isUploadSettled)
            }
            .onChange(of: distance, initial: true) {
                controller.updateTravelDistance(distance)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onChange(of: reduceMotion, initial: true) {
            if controller.reduceMotion != reduceMotion { controller.finish() }
            controller.reduceMotion = reduceMotion
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background { controller.finish() }
        }
    }
}

/// Measuring the gesture's actual surface here isolates its moving geometry from the scanner layout.
struct ScannerUploadDragSurface: ViewModifier {
    let controller: ScannerUploadController
    let source: ScannerUploadPage
    var isEnabled: Bool
    @State private var hitRegion = CGRect.zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                hitRegion = frame
            }
            .gesture(ScannerUploadPanGesture(controller: controller, source: source,
                                             isEnabled: isEnabled, hitRegion: hitRegion))
    }
}

struct ScannerUploadButton: View {
    var isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Upload photos", systemImage: "photo.on.rectangle.angled")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .disabled(!isEnabled)
        .accessibilityIdentifier("scanner.uploadPhotos")
        .accessibilityHint("You can also swipe up on the scanner.")
    }
}
