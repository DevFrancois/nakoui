import CoreGraphics

/// How small the logo row's items become as they fade during collapse.
struct LogoFlight: Equatable {
    var scale: CGFloat

    static let none = LogoFlight(scale: 1)
}
