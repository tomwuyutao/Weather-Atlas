//
//  AppTheme.swift
//  Weather
//
//  Purpose: Centralizes palette values, localization lookup, theme resolution,
//  responsive layout, interaction feedback, and shared SwiftUI modifiers.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - App Locale Lookup

/// Looks up a localized string for a specific locale supplied by SwiftUI.
func localizedString(_ key: String.LocalizationValue, locale: Locale) -> String {
    // Resolve the resource against the explicit in-app locale.
    var resource = LocalizedStringResource(key)
    resource.locale = locale
    return String(localized: resource)
}

// MARK: - Shared App Palette

/// Primitive semantic colors shared by the app and widget extension.
enum AppPalette {
    /// Complete palette values before they are adapted into app theme aliases.
    struct Values {
        /// Primary foreground color.
        let titleText: Color
        /// Secondary foreground color.
        let secondaryText: Color
        /// Main canvas color.
        let background: Color
        /// Destructive-action color.
        let destructive: Color
        /// Fully sunny semantic color.
        let dotSun: Color
        /// Contrast-safe sunny foreground for symbols and charts.
        let sunForeground: Color
        /// Partly sunny semantic color.
        let dotPartlyCloudy: Color
        /// Contrast-safe partly-sunny foreground.
        let partlySunnyForeground: Color
        /// Cloudy semantic color.
        let dotCloudy: Color
        /// Contrast-safe cloudy foreground.
        let cloudyForeground: Color
        /// Rain semantic color.
        let dotRain: Color
        /// Contrast-safe rain foreground.
        let rainForeground: Color
        /// Drizzle semantic color.
        let dotDrizzle: Color
        /// Contrast-safe drizzle foreground.
        let drizzleForeground: Color
        /// Subdued row and panel fill.
        let settingsRow: Color
    }

    /// Standard light-appearance palette.
    static let light = Values(
        titleText: Color(hex: 0x262626),
        secondaryText: Color(hex: 0x6D6D6D),
        background: Color(hex: 0xFAF8F2),
        destructive: Color(hex: 0xD14D30),
        dotSun: Color(hex: 0xFBC056),
        sunForeground: Color(hex: 0x986000),
        dotPartlyCloudy: Color(hex: 0xFAE38E),
        partlySunnyForeground: Color(hex: 0x786200),
        dotCloudy: Color(hex: 0xC8C8C8),
        cloudyForeground: Color(hex: 0x666666),
        dotRain: Color(hex: 0x5AA4F3),
        rainForeground: Color(hex: 0x5AA4F3),
        dotDrizzle: Color(hex: 0x67D1F0),
        drizzleForeground: Color(hex: 0x67D1F0),
        settingsRow: Color(hex: 0xF4EFE4)
    )

    /// Standard charcoal dark-appearance palette.
    static let dark = Values(
        titleText: Color(hex: 0xFEFEFE),
        secondaryText: Color(hex: 0x929292),
        background: Color(hex: 0x262626),
        destructive: Color(hex: 0xD14D30),
        dotSun: Color(hex: 0xFBC056),
        sunForeground: Color(hex: 0xFBC056),
        dotPartlyCloudy: Color(hex: 0xFAE38E),
        partlySunnyForeground: Color(hex: 0xFAE38E),
        dotCloudy: Color(hex: 0xC8C8C8),
        cloudyForeground: Color(hex: 0xC8C8C8),
        dotRain: Color(hex: 0x5AA4F3),
        rainForeground: Color(hex: 0x5AA4F3),
        dotDrizzle: Color(hex: 0x67D1F0),
        drizzleForeground: Color(hex: 0x67D1F0),
        settingsRow: Color(hex: 0x303030)
    )

    // Black keeps the dark palette's content colors while replacing its main
    // canvas with true black for OLED displays and a stronger dark appearance.
    /// True-black dark palette used by Black theme modes.
    static let black = Values(
        titleText: dark.titleText,
        secondaryText: dark.secondaryText,
        background: Color(hex: 0x000000),
        destructive: dark.destructive,
        dotSun: dark.dotSun,
        sunForeground: dark.sunForeground,
        dotPartlyCloudy: dark.dotPartlyCloudy,
        partlySunnyForeground: dark.partlySunnyForeground,
        dotCloudy: dark.dotCloudy,
        cloudyForeground: dark.cloudyForeground,
        dotRain: dark.dotRain,
        rainForeground: dark.rainForeground,
        dotDrizzle: dark.dotDrizzle,
        drizzleForeground: dark.drizzleForeground,
        settingsRow: Color(hex: 0x181818)
    )

    /// Returns the standard palette matching a resolved color scheme.
    static func values(for colorScheme: ColorScheme) -> Values {
        colorScheme == .dark ? dark : light
    }

    /// Returns a WCAG-stronger variant for the system contrast preference.
    static func increasedContrastValues(for colorScheme: ColorScheme) -> Values {
        increasedContrastValues(
            for: values(for: colorScheme),
            colorScheme: colorScheme
        )
    }

    /// Increased-contrast variant that retains a true-black canvas.
    static var increasedContrastBlack: Values {
        increasedContrastValues(for: black, colorScheme: .dark)
    }

    /// Strengthens text, border, and fill separation for one base palette.
    private static func increasedContrastValues(
        for palette: Values,
        colorScheme: ColorScheme
    ) -> Values {
        if colorScheme == .dark {
            return Values(
                titleText: palette.titleText,
                secondaryText: palette.secondaryText,
                background: palette.background,
                destructive: palette.destructive.interpolated(with: palette.titleText, by: 0.12),
                dotSun: palette.dotSun,
                sunForeground: palette.sunForeground,
                dotPartlyCloudy: palette.dotPartlyCloudy,
                partlySunnyForeground: palette.partlySunnyForeground,
                dotCloudy: palette.dotCloudy,
                cloudyForeground: palette.cloudyForeground,
                dotRain: palette.dotRain,
                rainForeground: palette.rainForeground,
                dotDrizzle: palette.dotDrizzle,
                drizzleForeground: palette.drizzleForeground,
                settingsRow: palette.settingsRow
            )
        }

        return Values(
            titleText: palette.titleText,
            secondaryText: palette.secondaryText,
            background: palette.background,
            destructive: palette.destructive.interpolated(with: palette.titleText, by: 0.12),
            dotSun: palette.dotSun.interpolated(with: palette.titleText, by: 0.48),
            sunForeground: palette.sunForeground.interpolated(
                with: palette.titleText,
                by: 0.12
            ),
            dotPartlyCloudy: palette.dotPartlyCloudy.interpolated(with: palette.titleText, by: 0.55),
            partlySunnyForeground: palette.partlySunnyForeground.interpolated(
                with: palette.titleText,
                by: 0.12
            ),
            dotCloudy: palette.dotCloudy.interpolated(with: palette.titleText, by: 0.66),
            cloudyForeground: palette.cloudyForeground.interpolated(
                with: palette.titleText,
                by: 0.12
            ),
            dotRain: palette.dotRain.interpolated(with: palette.titleText, by: 0.10),
            rainForeground: palette.rainForeground.interpolated(
                with: palette.titleText,
                by: 0.08
            ),
            dotDrizzle: palette.dotDrizzle.interpolated(with: palette.titleText, by: 0.35),
            drizzleForeground: palette.drizzleForeground.interpolated(
                with: palette.titleText,
                by: 0.08
            ),
            settingsRow: palette.settingsRow
        )
    }
}

// MARK: - Color Construction and Interpolation

extension Color {
    /// Creates an opaque sRGB color from a six-digit RGB hexadecimal value.
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }

    /// Blends two resolved sRGB colors by a clamped interpolation fraction.
    func interpolated(with other: Color, by amount: Double) -> Color {
        let fraction = max(0, min(1, amount))
        let first = UIColor(self)
        let second = UIColor(other)
        var red1: CGFloat = 0
        var green1: CGFloat = 0
        var blue1: CGFloat = 0
        var alpha1: CGFloat = 0
        var red2: CGFloat = 0
        var green2: CGFloat = 0
        var blue2: CGFloat = 0
        var alpha2: CGFloat = 0

        guard first.getRed(&red1, green: &green1, blue: &blue1, alpha: &alpha1),
              second.getRed(&red2, green: &green2, blue: &blue2, alpha: &alpha2) else {
            return fraction < 0.5 ? self : other
        }

        return Color(
            red: Double(red1 + (red2 - red1) * fraction),
            green: Double(green1 + (green2 - green1) * fraction),
            blue: Double(blue1 + (blue2 - blue1) * fraction),
            opacity: Double(alpha1 + (alpha2 - alpha1) * fraction)
        )
    }
}

// MARK: - Theme Style

/// Persisted appearance modes offered by the Theme settings screen.
enum AppThemeStyle: String, CaseIterable {
    case automatic = "automatic"
    case automaticBlack = "automaticBlack"
    case light = "light"
    case dark = "dark"
    case black = "black"

    /// Initial theme preference for new installations.
    static let defaultRawValue = AppThemeStyle.automatic.rawValue

    /// Localized row title for this theme mode.
    func displayName(locale: Locale) -> String {
        switch self {
        case .automatic: return localizedString("Automatic", locale: locale)
        case .automaticBlack: return localizedString("Automatic (Black)", locale: locale)
        case .light: return localizedString("Light", locale: locale)
        case .dark: return localizedString("Dark", locale: locale)
        case .black: return localizedString("Black", locale: locale)
        }
    }
}

// MARK: - Theme Colors

/// Semantic colors consumed by app views after appearance resolution.
struct ThemeColors {
    // Palette values
    /// Primary heading and content foreground.
    let titleText: Color
    /// De-emphasized labels and outlines.
    let secondaryText: Color
    /// Main app background.
    let background: Color
    /// Destructive control foreground.
    let destructive: Color
    /// Fully sunny weather mark.
    let dotSun: Color
    /// Contrast-safe sunny foreground.
    let sunForeground: Color
    /// Partly sunny weather mark.
    let dotPartlyCloudy: Color
    /// Contrast-safe partly-sunny foreground.
    let partlySunnyForeground: Color
    /// Cloudy weather mark.
    let dotCloudy: Color
    /// Contrast-safe cloudy foreground.
    let cloudyForeground: Color
    /// Rain weather mark.
    let dotRain: Color
    /// Contrast-safe rain foreground.
    let rainForeground: Color
    /// Drizzle weather mark.
    let dotDrizzle: Color
    /// Contrast-safe drizzle foreground.
    let drizzleForeground: Color
    /// Subdued settings row and chart panel fill.
    let settingsRowFill: Color

    // Semantic aliases intentionally reuse the compact palette above.
    /// Standard primary foreground alias.
    var primaryText: Color { titleText }
    /// Global control tint.
    var accent: Color { primaryText }

    /// Foreground used for standalone sun symbols.
    var sunIconColor: Color { dotSun }

    /// Tint participating in translucent glass surfaces.
    var glassFill: Color { background }
    /// Highlight used by the sunny-only filter.
    var filterSunny: Color { dotSun }

    /// Returns palette foreground styles for a weather SF Symbol icon name.
    func weatherIconPalette(for iconName: String) -> (primary: Color, secondary: Color) {
        switch WeatherSymbolClassification.resolve(iconName) {
        case .clear:
            return (sunIconColor, sunIconColor)
        case .partlySunny, .partlyCloudy:
            return (cloudyForeground, partlySunnyForeground)
        case .rain, .drizzle:
            return (
                cloudyForeground,
                WeatherSymbolClassification.resolve(iconName) == .drizzle
                    ? drizzleForeground
                    : rainForeground
            )
        case .cloudy, .snow, .fog, .wind, nil:
            return (cloudyForeground, cloudyForeground)
        }
    }
}

// MARK: - Light Theme

extension ThemeColors {
    /// Standard light semantic theme.
    static let light = ThemeColors(palette: AppPalette.light)
}

// MARK: - Dark Themes

extension ThemeColors {
    /// Standard charcoal dark semantic theme.
    static let dark = ThemeColors(palette: AppPalette.dark)

    /// True-black dark semantic theme.
    static let black = ThemeColors(palette: AppPalette.black)
}

// MARK: - Accessibility - Increased Contrast Palettes

// Accessibility: These palettes activate only with the system Increase Contrast setting.
// Text colors meet a 4.5:1 minimum and meaningful palette colors meet a 3:1 minimum
// against their corresponding base backgrounds.
extension ThemeColors {
    /// Increased-contrast light semantic theme.
    static let increasedContrastLight = ThemeColors(
        palette: AppPalette.increasedContrastValues(for: .light)
    )

    /// Increased-contrast charcoal dark semantic theme.
    static let increasedContrastDark = ThemeColors(
        palette: AppPalette.increasedContrastValues(for: .dark)
    )

    /// Increased-contrast true-black semantic theme.
    static let increasedContrastBlack = ThemeColors(
        palette: AppPalette.increasedContrastBlack
    )
}

private extension ThemeColors {
    /// Maps primitive shared palette values into app semantic aliases.
    init(palette: AppPalette.Values) {
        self.init(
            titleText: palette.titleText,
            secondaryText: palette.secondaryText,
            background: palette.background,
            destructive: palette.destructive,
            dotSun: palette.dotSun,
            sunForeground: palette.sunForeground,
            dotPartlyCloudy: palette.dotPartlyCloudy,
            partlySunnyForeground: palette.partlySunnyForeground,
            dotCloudy: palette.dotCloudy,
            cloudyForeground: palette.cloudyForeground,
            dotRain: palette.dotRain,
            rainForeground: palette.rainForeground,
            dotDrizzle: palette.dotDrizzle,
            drizzleForeground: palette.drizzleForeground,
            settingsRowFill: palette.settingsRow
        )
    }
}

// MARK: - Theme Manager

@Observable
/// Observable theme manager shared across every app window.
class AppTheme {
    /// Process-wide theme manager instance.
    static let shared = AppTheme()

    /// Persisted appearance selection; updates storage whenever it changes.
    var style: AppThemeStyle {
        didSet {
            UserDefaults.standard.set(style.rawValue, forKey: "appThemeStyle")
        }
    }

    /// The effective app color scheme, kept in sync by ThemeContent after the app's
    /// appearance preference has been applied. This lets non-view code and view
    /// modifiers use the exact same palette as the current SwiftUI environment.
    var systemScheme: ColorScheme = .light

    /// The current system contrast preference, kept in sync by ThemeContent.
    var systemContrast: ColorSchemeContrast = .standard

    /// Resolved colors using the stored effective scheme — reactive, used everywhere.
    var colors: ThemeColors {
        resolvedColors(for: systemScheme, contrast: systemContrast)
    }

    /// Resolved colors for an explicit color scheme (used by ThemeContent during environment setup).
    func colors(
        for scheme: ColorScheme,
        contrast: ColorSchemeContrast? = nil
    ) -> ThemeColors {
        resolvedColors(for: scheme, contrast: contrast ?? systemContrast)
    }

    /// The ColorScheme to apply to the window (nil = follow system).
    func preferredColorScheme(for _: ColorScheme) -> ColorScheme? {
        switch style {
        case .light: return .light
        case .dark, .black: return .dark
        case .automatic, .automaticBlack: return nil
        }
    }

    /// Restores the persisted style while normalizing unsupported old values.
    private init() {
        let raw = UserDefaults.standard.string(forKey: "appThemeStyle") ?? AppThemeStyle.defaultRawValue
        self.style = AppThemeStyle(rawValue: raw) ?? .automatic
    }

    /// Chooses the exact semantic palette for scheme, contrast, and theme style.
    private func resolvedColors(
        for resolvedScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> ThemeColors {
        // True-black themes only replace the regular dark palette.
        if resolvedScheme == .dark && (style == .black || style == .automaticBlack) {
            return contrast == .increased ? .increasedContrastBlack : .black
        }
        if contrast == .increased {
            return resolvedScheme == .dark ? .increasedContrastDark : .increasedContrastLight
        }
        return resolvedScheme == .dark ? .dark : .light
    }
}

extension EnvironmentValues {
    /// Observable Weather Atlas theme manager.
    @Entry var appTheme: AppTheme = .shared
}

// MARK: - View Modifiers

/// Applies semantic two-color rendering to recognized weather symbols.
private struct WeatherIconStyleModifier: ViewModifier {
    /// Active theme palette.
    @Environment(\.appTheme) private var theme
    /// Weather symbol whose classification selects the palette.
    let iconName: String

    /// Applies hierarchical palette rendering to the source image.
    func body(content: Content) -> some View {
        let palette = theme.colors.weatherIconPalette(for: iconName)
        content
            .symbolRenderingMode(.palette)
            .foregroundStyle(palette.primary, palette.secondary)
    }
}

// MARK: - Accessibility - Legible Translucent Surfaces

// Accessibility: These surface modifiers replace translucency with opaque, outlined surfaces
// when Reduce Transparency or Increase Contrast is enabled.
private extension View {
    /// Replaces translucency with an opaque outlined surface when required.
    func highLegibilityGlass<Shape: InsettableShape>(
        theme: ThemeColors,
        contrast: ColorSchemeContrast,
        in shape: Shape
    ) -> some View {
        background(theme.glassFill, in: shape)
            .overlay(
                shape.stroke(
                    theme.primaryText.opacity(contrast == .increased ? 0.90 : 0.18),
                    lineWidth: contrast == .increased ? 1 : 0.8
                )
            )
    }
}

/// Translucent card surface shared by Detail View's report sections.
private struct DetailTranslucentCardModifier<Shape: InsettableShape>: ViewModifier {
    /// Active theme palette.
    @Environment(\.appTheme) private var theme
    /// System preference that replaces translucency with an opaque surface.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// System preference requiring a stronger card outline.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// Resolved scheme used to tune translucent fill opacity.
    let colorScheme: ColorScheme
    /// Insettable card boundary.
    let shape: Shape

    @ViewBuilder
    /// Applies the detail-card surface appropriate to OS and accessibility state.
    func body(content: Content) -> some View {
        if reduceTransparency || colorSchemeContrast == .increased {
            content.highLegibilityGlass(
                theme: theme.colors,
                contrast: colorSchemeContrast,
                in: shape
            )
        } else if #available(iOS 26.0, *) {
            content
                .background(
                    theme.colors.glassFill.opacity(colorScheme == .dark ? 0.18 : 0.22),
                    in: shape
                )
                .glassEffect(.regular.interactive(), in: shape)
                .overlay(
                    shape.stroke(
                        theme.colors.primaryText.opacity(0.16),
                        lineWidth: 0.6
                    )
                )
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(
                    theme.colors.glassFill.opacity(colorScheme == .dark ? 0.30 : 0.38),
                    in: shape
                )
                .overlay(
                    shape.stroke(
                        theme.colors.primaryText.opacity(0.16),
                        lineWidth: 0.6
                    )
                )
        }
    }
}

/// Applies the warm Weather Atlas canvas while retaining a native List or Form.
private struct WeatherAtlasScrollableBackgroundModifier: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(theme.colors.background)
    }
}

/// Applies the palette canvas to native stacks and empty states.
private struct WeatherAtlasScreenBackgroundModifier: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content.background(theme.colors.background.ignoresSafeArea())
    }
}

// MARK: - View Modifier APIs

extension View {
    /// Applies semantic palette rendering to a weather SF Symbol.
    func weatherIconStyle(for iconName: String) -> some View {
        modifier(WeatherIconStyleModifier(iconName: iconName))
    }

    /// Wraps Detail content in its shared translucent card treatment.
    func detailTranslucentCard<Shape: InsettableShape>(colorScheme: ColorScheme, in shape: Shape) -> some View {
        modifier(DetailTranslucentCardModifier(colorScheme: colorScheme, shape: shape))
    }

    /// Keeps system List/Form behavior while replacing only its canvas color.
    func weatherAtlasScrollableBackground() -> some View {
        modifier(WeatherAtlasScrollableBackgroundModifier())
    }

    /// Uses the active Weather Atlas canvas behind native screen content.
    func weatherAtlasScreenBackground() -> some View {
        modifier(WeatherAtlasScreenBackgroundModifier())
    }

}
