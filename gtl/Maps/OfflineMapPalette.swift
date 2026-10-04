import UIKit

struct OfflineMapPalette {
    var background: UIColor
    var water: UIColor
    var land: UIColor
    var park: UIColor
    var building: UIColor
    var buildingOutline: UIColor
    var contour: UIColor
    var border: UIColor
    var waterway: UIColor
    var casing: UIColor
    var road: UIColor
    var tertiary: UIColor
    var secondary: UIColor
    var primary: UIColor
    var motorway: UIColor
    var path: UIColor
    var cycle: UIColor
    var emphasis: UIColor
    var blaze: UIColor
    var poi: UIColor
    var poiStroke: UIColor
    var labelInk: UIColor
    var labelRoad: UIColor
    var labelWater: UIColor
    var labelHalo: UIColor
    var trackCasing: UIColor

    static func palette(dark: Bool) -> OfflineMapPalette { dark ? night : day }

    static let day = OfflineMapPalette(
        background: rgb(0xF3, 0xEF, 0xE4),
        water: UIColor(red: 0.67, green: 0.83, blue: 0.87, alpha: 1),
        land: UIColor(red: 0.76, green: 0.86, blue: 0.70, alpha: 1),
        park: UIColor(red: 0.68, green: 0.84, blue: 0.62, alpha: 1),
        building: UIColor(red: 0.86, green: 0.80, blue: 0.74, alpha: 1),
        buildingOutline: UIColor(red: 0.62, green: 0.55, blue: 0.50, alpha: 1),
        contour: UIColor(red: 0.62, green: 0.48, blue: 0.36, alpha: 0.85),
        border: UIColor(red: 0.55, green: 0.35, blue: 0.62, alpha: 0.9),
        waterway: UIColor(red: 0.45, green: 0.68, blue: 0.78, alpha: 1),
        casing: UIColor(red: 0.55, green: 0.52, blue: 0.48, alpha: 1),
        road: UIColor(red: 1, green: 1, blue: 1, alpha: 1),
        tertiary: UIColor(red: 1, green: 1, blue: 1, alpha: 1),
        secondary: UIColor(red: 0.98, green: 0.86, blue: 0.55, alpha: 1),
        primary: UIColor(red: 0.98, green: 0.70, blue: 0.55, alpha: 1),
        motorway: UIColor(red: 0.91, green: 0.55, blue: 0.62, alpha: 1),
        path: UIColor(red: 0.55, green: 0.40, blue: 0.24, alpha: 1),
        cycle: UIColor(red: 0.16, green: 0.52, blue: 0.72, alpha: 1),
        emphasis: UIColor(red: 0.77, green: 0.0, blue: 0.48, alpha: 1),
        blaze: UIColor(red: 0.12, green: 0.35, blue: 0.66, alpha: 1),
        poi: UIColor(red: 0.12, green: 0.42, blue: 0.38, alpha: 1),
        poiStroke: UIColor.white,
        labelInk: UIColor(red: 0.17, green: 0.13, blue: 0.11, alpha: 1),
        labelRoad: UIColor(red: 0.22, green: 0.18, blue: 0.15, alpha: 1),
        labelWater: UIColor(red: 0.14, green: 0.34, blue: 0.46, alpha: 1),
        labelHalo: UIColor(white: 1, alpha: 0.94),
        trackCasing: UIColor(white: 1, alpha: 0)
    )

    static let night = OfflineMapPalette(
        background: rgb(0x12, 0x17, 0x1C),
        water: UIColor(red: 0.10, green: 0.20, blue: 0.27, alpha: 1),
        land: UIColor(red: 0.12, green: 0.17, blue: 0.13, alpha: 1),
        park: UIColor(red: 0.11, green: 0.20, blue: 0.13, alpha: 1),
        building: UIColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1),
        buildingOutline: UIColor(red: 0.30, green: 0.30, blue: 0.33, alpha: 1),
        contour: UIColor(red: 0.45, green: 0.38, blue: 0.30, alpha: 0.7),
        border: UIColor(red: 0.62, green: 0.45, blue: 0.70, alpha: 0.9),
        waterway: UIColor(red: 0.25, green: 0.45, blue: 0.58, alpha: 1),
        casing: UIColor(red: 0.06, green: 0.07, blue: 0.08, alpha: 1),
        road: UIColor(red: 0.36, green: 0.38, blue: 0.41, alpha: 1),
        tertiary: UIColor(red: 0.42, green: 0.44, blue: 0.47, alpha: 1),
        secondary: UIColor(red: 0.62, green: 0.55, blue: 0.30, alpha: 1),
        primary: UIColor(red: 0.66, green: 0.45, blue: 0.32, alpha: 1),
        motorway: UIColor(red: 0.70, green: 0.38, blue: 0.45, alpha: 1),
        path: UIColor(red: 0.62, green: 0.50, blue: 0.36, alpha: 1),
        cycle: UIColor(red: 0.30, green: 0.62, blue: 0.82, alpha: 1),
        emphasis: UIColor(red: 0.92, green: 0.25, blue: 0.65, alpha: 1),
        blaze: UIColor(red: 0.40, green: 0.60, blue: 0.95, alpha: 1),
        poi: UIColor(red: 0.30, green: 0.70, blue: 0.64, alpha: 1),
        poiStroke: rgb(0x12, 0x17, 0x1C),
        labelInk: UIColor(red: 0.92, green: 0.92, blue: 0.90, alpha: 1),
        labelRoad: UIColor(red: 0.85, green: 0.85, blue: 0.83, alpha: 1),
        labelWater: UIColor(red: 0.55, green: 0.78, blue: 0.92, alpha: 1),
        labelHalo: UIColor(red: 0.05, green: 0.06, blue: 0.07, alpha: 0.9),
        trackCasing: UIColor(white: 1, alpha: 0.75)
    )

    static func luminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    static func contrast(_ foreground: UIColor, _ background: UIColor) -> Double {
        let top = luminance(blend(foreground, over: background))
        let bottom = luminance(background)
        return (max(top, bottom) + 0.05) / (min(top, bottom) + 0.05)
    }

    private static func blend(_ foreground: UIColor, over background: UIColor) -> UIColor {
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        foreground.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        background.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: fr * fa + br * (1 - fa), green: fg * fa + bg * (1 - fa), blue: fb * fa + bb * (1 - fa), alpha: 1)
    }

    private static func rgb(_ red: Int, _ green: Int, _ blue: Int) -> UIColor {
        UIColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
}
