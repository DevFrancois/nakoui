import CoreGraphics

/// Where the found code ends up: lifted flat, turned into a white card, with
/// an icon on it. Everything is in the camera pane's points, centred where
/// the viewfinder is.
nonisolated struct RevealLayout: Equatable, Sendable {
    /// The flattened code at the end of the lift.
    let liftTarget: CGRect
    /// The white card the code turns into: a little larger than the code.
    let card: CGRect
    let cardCornerRadius: CGFloat
    let iconSize: CGFloat

    init(viewSize: CGSize, codeQuad: Quad) {
        let aspect = min(max(codeQuad.width / max(codeQuad.height, 1), Self.minimumAspect), Self.maximumAspect)
        let availableHeight = viewSize.height * 2 * min(Self.centerFraction, 1 - Self.centerFraction)
        let heightLimitedWidth = availableHeight / (1 / aspect + 2 * Self.cardOutset)
        let width = max(0, min(viewSize.width * Self.widthFraction, Self.maximumWidth, heightLimitedWidth))
        let height = width / aspect
        let center = CGPoint(x: viewSize.width / 2, y: viewSize.height * Self.centerFraction)
        liftTarget = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        card = liftTarget.insetBy(dx: -width * Self.cardOutset, dy: -width * Self.cardOutset)
        // An app icon's continuous corner, relative to the card's short side.
        cardCornerRadius = min(card.width, card.height) * 0.2237
        iconSize = min(card.height * 0.55, Self.maximumIconSize)
    }

    private static let widthFraction = 0.62
    private static let maximumWidth = 320.0
    /// Card centre as a share of the camera pane's height.
    private static let centerFraction = ScannerMetrics.viewfinderCenterFraction
    private static let cardOutset = 0.05
    private static let minimumAspect = 1.1
    private static let maximumAspect = 2.4
    private static let maximumIconSize = 76.0
}
