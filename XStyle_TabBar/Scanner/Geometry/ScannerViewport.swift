import CoreGraphics

/// One coherent preview configuration sent from the scene to the camera queues.
/// Revisions keep an older async update from replacing a newer resize/rotation.
nonisolated struct ScannerViewport: Equatable, Sendable {
    let size: CGSize
    let viewfinder: CGRect
    let displayScale: CGFloat
    let rotation: CameraImageRotation
    let revision: UInt64

    func mapper(bufferSize: CGSize) -> AspectFillMapper {
        AspectFillMapper(bufferSize: bufferSize, viewSize: size, rotation: rotation)
    }
}
