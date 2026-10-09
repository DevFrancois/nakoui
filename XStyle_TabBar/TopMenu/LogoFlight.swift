import CoreGraphics

/// How far up, and how small, the logo row's items travel when it collapses.
struct LogoFlight: Equatable {
    var travel: CGFloat
    var scale: CGFloat

    static let none = LogoFlight(travel: 0, scale: 1)
}
