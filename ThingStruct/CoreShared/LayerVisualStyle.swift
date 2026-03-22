import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct LayerVisualStyle {
    let surface: Color
    let strongSurface: Color
    let border: Color
    let accent: Color
    let marker: Color
    let badgeBackground: Color
    let badgeForeground: Color

    static func forBlock(layerIndex: Int, isBlank: Bool) -> LayerVisualStyle {
        if isBlank {
            return blank
        }

        let depth = max(0, min(layerIndex, palette.count - 1))
        return palette[depth]
    }

    private static let blank = LayerVisualStyle(
        surface: .adaptive(
            light: RGBColor(red: 244, green: 245, blue: 247),
            dark: RGBColor(red: 34, green: 36, blue: 40)
        ),
        strongSurface: .adaptive(
            light: RGBColor(red: 234, green: 237, blue: 241),
            dark: RGBColor(red: 44, green: 47, blue: 52)
        ),
        border: .adaptive(
            light: RGBColor(red: 212, green: 217, blue: 224),
            dark: RGBColor(red: 74, green: 79, blue: 87)
        ),
        accent: .adaptive(
            light: RGBColor(red: 96, green: 103, blue: 114),
            dark: RGBColor(red: 192, green: 197, blue: 206)
        ),
        marker: .adaptive(
            light: RGBColor(red: 142, green: 149, blue: 160),
            dark: RGBColor(red: 124, green: 130, blue: 140)
        ),
        badgeBackground: .adaptive(
            light: RGBColor(red: 226, green: 230, blue: 236),
            dark: RGBColor(red: 58, green: 62, blue: 70)
        ),
        badgeForeground: .adaptive(
            light: RGBColor(red: 90, green: 95, blue: 105),
            dark: RGBColor(red: 220, green: 223, blue: 228)
        )
    )

    private static let palette: [LayerVisualStyle] = [
        LayerVisualStyle(
            surface: .adaptive(
                light: RGBColor(red: 242, green: 248, blue: 255),
                dark: RGBColor(red: 23, green: 37, blue: 61)
            ),
            strongSurface: .adaptive(
                light: RGBColor(red: 230, green: 240, blue: 255),
                dark: RGBColor(red: 30, green: 46, blue: 76)
            ),
            border: .adaptive(
                light: RGBColor(red: 183, green: 210, blue: 245),
                dark: RGBColor(red: 69, green: 99, blue: 149)
            ),
            accent: .adaptive(
                light: RGBColor(red: 50, green: 96, blue: 174),
                dark: RGBColor(red: 171, green: 201, blue: 255)
            ),
            marker: .adaptive(
                light: RGBColor(red: 74, green: 120, blue: 198),
                dark: RGBColor(red: 132, green: 173, blue: 240)
            ),
            badgeBackground: .adaptive(
                light: RGBColor(red: 215, green: 233, blue: 255),
                dark: RGBColor(red: 42, green: 63, blue: 101)
            ),
            badgeForeground: .adaptive(
                light: RGBColor(red: 28, green: 69, blue: 132),
                dark: RGBColor(red: 230, green: 238, blue: 255)
            )
        ),
        LayerVisualStyle(
            surface: .adaptive(
                light: RGBColor(red: 228, green: 238, blue: 255),
                dark: RGBColor(red: 20, green: 32, blue: 53)
            ),
            strongSurface: .adaptive(
                light: RGBColor(red: 207, green: 224, blue: 251),
                dark: RGBColor(red: 26, green: 40, blue: 67)
            ),
            border: .adaptive(
                light: RGBColor(red: 145, green: 188, blue: 240),
                dark: RGBColor(red: 58, green: 89, blue: 138)
            ),
            accent: .adaptive(
                light: RGBColor(red: 28, green: 76, blue: 156),
                dark: RGBColor(red: 180, green: 208, blue: 255)
            ),
            marker: .adaptive(
                light: RGBColor(red: 49, green: 97, blue: 179),
                dark: RGBColor(red: 143, green: 179, blue: 243)
            ),
            badgeBackground: .adaptive(
                light: RGBColor(red: 190, green: 215, blue: 251),
                dark: RGBColor(red: 36, green: 54, blue: 89)
            ),
            badgeForeground: .adaptive(
                light: RGBColor(red: 18, green: 58, blue: 118),
                dark: RGBColor(red: 234, green: 241, blue: 255)
            )
        ),
        LayerVisualStyle(
            surface: .adaptive(
                light: RGBColor(red: 214, green: 229, blue: 252),
                dark: RGBColor(red: 17, green: 27, blue: 46)
            ),
            strongSurface: .adaptive(
                light: RGBColor(red: 184, green: 208, blue: 246),
                dark: RGBColor(red: 22, green: 34, blue: 58)
            ),
            border: .adaptive(
                light: RGBColor(red: 113, green: 165, blue: 232),
                dark: RGBColor(red: 49, green: 79, blue: 124)
            ),
            accent: .adaptive(
                light: RGBColor(red: 16, green: 60, blue: 136),
                dark: RGBColor(red: 188, green: 216, blue: 255)
            ),
            marker: .adaptive(
                light: RGBColor(red: 33, green: 81, blue: 159),
                dark: RGBColor(red: 154, green: 188, blue: 247)
            ),
            badgeBackground: .adaptive(
                light: RGBColor(red: 165, green: 196, blue: 246),
                dark: RGBColor(red: 31, green: 47, blue: 80)
            ),
            badgeForeground: .adaptive(
                light: RGBColor(red: 12, green: 46, blue: 100),
                dark: RGBColor(red: 236, green: 243, blue: 255)
            )
        ),
        LayerVisualStyle(
            surface: .adaptive(
                light: RGBColor(red: 198, green: 220, blue: 248),
                dark: RGBColor(red: 15, green: 24, blue: 40)
            ),
            strongSurface: .adaptive(
                light: RGBColor(red: 158, green: 192, blue: 239),
                dark: RGBColor(red: 20, green: 30, blue: 51)
            ),
            border: .adaptive(
                light: RGBColor(red: 83, green: 143, blue: 221),
                dark: RGBColor(red: 43, green: 69, blue: 110)
            ),
            accent: .adaptive(
                light: RGBColor(red: 8, green: 45, blue: 114),
                dark: RGBColor(red: 196, green: 221, blue: 255)
            ),
            marker: .adaptive(
                light: RGBColor(red: 20, green: 66, blue: 138),
                dark: RGBColor(red: 166, green: 196, blue: 249)
            ),
            badgeBackground: .adaptive(
                light: RGBColor(red: 137, green: 176, blue: 238),
                dark: RGBColor(red: 26, green: 40, blue: 69)
            ),
            badgeForeground: .adaptive(
                light: RGBColor(red: 7, green: 34, blue: 83),
                dark: RGBColor(red: 239, green: 245, blue: 255)
            )
        )
    ]
}

private struct RGBColor {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
}

private extension Color {
    static func adaptive(light: RGBColor, dark: RGBColor, alpha: CGFloat = 1) -> Color {
        #if canImport(UIKit)
        return Color(
            uiColor: UIColor { traits in
                let palette = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(
                    red: palette.red / 255,
                    green: palette.green / 255,
                    blue: palette.blue / 255,
                    alpha: alpha
                )
            }
        )
        #elseif canImport(AppKit)
        return Color(
            nsColor: NSColor(name: nil) { appearance in
                let palette = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
                return NSColor(
                    deviceRed: palette.red / 255,
                    green: palette.green / 255,
                    blue: palette.blue / 255,
                    alpha: alpha
                )
            }
        )
        #else
        return Color(
            .sRGB,
            red: light.red / 255,
            green: light.green / 255,
            blue: light.blue / 255,
            opacity: alpha
        )
        #endif
    }
}
