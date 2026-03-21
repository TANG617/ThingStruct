import Foundation
import SwiftUI
import UIKit

// Small formatting helpers often live in shared files like this in SwiftUI projects.
// The goal is to keep domain logic elsewhere and put display-only helpers here.
extension Int {
    var formattedTime: String {
        let hour = self / 60
        let minute = self % 60
        return String(format: "%02d:%02d", hour, minute)
    }
}

extension LocalDay {
    var titleText: String {
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = Calendar.current.date(from: components) else {
            return description
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    var nowNavigationTitle: String {
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = Calendar.current.date(from: components) else {
            return description
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d"
        return formatter.string(from: date)
    }
}

struct LayerVisualStyle {
    let surface: Color
    let strongSurface: Color
    let border: Color
    let accent: Color
    let marker: Color
    let badgeBackground: Color
    let badgeForeground: Color

    static func forBlock(layerIndex: Int, isBlank: Bool) -> LayerVisualStyle {
        // Blank blocks deliberately use a neutral palette so user-defined blocks
        // carry the stronger visual hierarchy.
        if isBlank {
            return blank
        }

        // Higher layers reuse the same hue family with deeper shades.
        // This is easier to read than assigning unrelated colors to each layer.
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
        // UIKit still exposes the most direct API for trait-aware dynamic colors.
        // SwiftUI `Color` is then created from the UIKit color.
        Color(
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
    }
}

struct ScreenLoadingView: View {
    let title: String
    let systemImage: String
    var description: String?

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)

            Label(title, systemImage: systemImage)
                .font(.headline)

            if let description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct RecoverableErrorView: View {
    let title: String
    let message: String
    var retryTitle = "Retry"
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button(retryTitle, action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// Many root screens in the app follow the same control flow:
// 1. Show a loading placeholder before the store is ready.
// 2. Try to build a screen model.
// 3. Show either the screen content or a recoverable error.
//
// This shared wrapper keeps that pattern consistent across tabs.
struct RootScreenContainer<Value, Content: View>: View {
    let isLoaded: Bool
    let loadingTitle: String
    let loadingSystemImage: String
    let loadingDescription: String
    let errorTitle: String
    let retry: () -> Void
    let load: () throws -> Value
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        Group {
            if !isLoaded {
                ScreenLoadingView(
                    title: loadingTitle,
                    systemImage: loadingSystemImage,
                    description: loadingDescription
                )
            } else {
                switch Result(catching: load) {
                case let .success(value):
                    content(value)

                case let .failure(error):
                    RecoverableErrorView(
                        title: errorTitle,
                        message: error.localizedDescription,
                        retry: retry
                    )
                }
            }
        }
    }
}

#Preview("Loading State") {
    ScreenLoadingView(
        title: "Loading Today",
        systemImage: "calendar",
        description: "Preparing your timeline and current context."
    )
}

#Preview("Recoverable Error") {
    RecoverableErrorView(
        title: "Unable to Load Templates",
        message: "The preview is simulating a recoverable state."
    ) {}
}

#Preview("Root Screen Container") {
    RootScreenContainer(
        isLoaded: true,
        loadingTitle: "Loading",
        loadingSystemImage: "clock",
        loadingDescription: "Previewing a shared screen wrapper.",
        errorTitle: "Error",
        retry: {}
    ) {
        "Preview"
    } content: { value in
        Text(value)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Layer Palette") {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(0 ... 4, id: \.self) { layer in
            let style = LayerVisualStyle.forBlock(layerIndex: layer, isBlank: false)
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(style.strongSurface)
                    .frame(width: 58, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(style.border, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Layer \(layer)")
                        .font(.headline)
                    Text("Higher layer keeps the same hue, but gets darker.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(style.badgeForeground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(style.badgeBackground, in: Capsule())
            }
            .padding(14)
            .background(style.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }

        let blankStyle = LayerVisualStyle.forBlock(layerIndex: 0, isBlank: true)
        Text("Blank blocks stay neutral.")
            .font(.subheadline)
            .foregroundStyle(blankStyle.accent)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(blankStyle.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
