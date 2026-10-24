import UIKit

struct GlassTabBarAppearance: Equatable {
    enum Material {
        case regular, clear
    }

    struct RGB: Equatable {
        var red: Double
        var green: Double
        var blue: Double

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        init(_ color: UIColor, style: UIUserInterfaceStyle) {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
                .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            self.init(red: Double(red), green: Double(green), blue: Double(blue))
        }

        func uiColor(opacity: Double = 1) -> UIColor {
            UIColor(red: red, green: green, blue: blue, alpha: opacity)
        }

    }

    var material: Material
    var tintEnabled: Bool
    var tintColor: RGB
    var tintOpacity: Double
    var backingEnabled: Bool
    var backingColor: RGB
    var backingOpacity: Double
    var backingInsideGlass = false
    var selectedIconColor: RGB
    var inactiveIconColor: RGB
    var inactiveIconOpacity: Double
    var selectionColor: RGB
    var selectionOpacity: Double
    var trackingSelectionOpacity: Double

    static let light = Self(
        material: .regular, tintEnabled: false,
        tintColor: RGB(red: 28.0 / 255, green: 28.0 / 255, blue: 30.0 / 255), tintOpacity: 0.9,
        backingEnabled: false, backingColor: RGB(red: 0, green: 0, blue: 0), backingOpacity: 0.3,
        selectedIconColor: RGB(red: 0, green: 0, blue: 0),
        inactiveIconColor: RGB(.secondaryLabel, style: .light),
        inactiveIconOpacity: alpha(of: .secondaryLabel, style: .light),
        selectionColor: RGB(.tertiarySystemFill, style: .light),
        selectionOpacity: alpha(of: .tertiarySystemFill, style: .light),
        trackingSelectionOpacity: alpha(of: .secondarySystemFill, style: .light)
    )
    // Regular glass softens the backdrop; the translucent inner backing keeps
    // it dark while native deformation carries all of its content together.
    static let dark = Self(
        material: .regular, tintEnabled: false,
        tintColor: RGB(red: 0, green: 0, blue: 0), tintOpacity: 0.7,
        backingEnabled: true, backingColor: RGB(red: 0, green: 0, blue: 0), backingOpacity: 0.6,
        backingInsideGlass: true,
        selectedIconColor: RGB(red: 1, green: 1, blue: 1),
        inactiveIconColor: RGB(red: 121.0 / 255, green: 121.0 / 255, blue: 121.0 / 255), inactiveIconOpacity: 1,
        selectionColor: RGB(red: 1, green: 1, blue: 1),
        selectionOpacity: 0.05,
        trackingSelectionOpacity: 0.14
    )

    private static func alpha(of color: UIColor, style: UIUserInterfaceStyle) -> Double {
        Double(color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).cgColor.alpha)
    }
}
