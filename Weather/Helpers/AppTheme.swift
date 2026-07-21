//
//  AppTheme.swift
//  Weather
//
//  Purpose: Centralizes theme colors, glass styling, appearance resolution,
//  and small color/view helpers used across the app.
//

import SwiftUI

// MARK: - Theme Style

enum AppThemeStyle: String, CaseIterable {
    case automatic = "automatic"
    case automaticBlack = "automaticBlack"
    case light = "light"
    case dark = "dark"
    case black = "black"

    static let defaultRawValue = AppThemeStyle.automatic.rawValue

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

struct ThemeColors {
    // Palette values
    let titleText: Color
    let secondaryText: Color
    let background: Color
    let destructive: Color
    let dotSun: Color
    let dotPartlyCloudy: Color
    let dotCloudy: Color
    let dotRain: Color
    let dotDrizzle: Color
    let settingsRowFill: Color
    let tutorialBackground: Color

    // Semantic aliases intentionally reuse the compact palette above.
    var primaryText: Color { titleText }
    var popoverBackground: Color { background }
    var mapOcean: Color { background }
    var mapBorder: Color { secondaryText }
    var accent: Color { primaryText }

    var dotSnow: Color { dotCloudy }
    var dotFog: Color { dotCloudy }
    var dotWind: Color { dotCloudy }

    var sunIconColor: Color { dotSun }

    var listCardFill: Color { background }
    var chartPanelFill: Color { settingsRowFill }
    var glassFill: Color { background }
    var filterSunny: Color { dotSun }
    var shadow: Color { AppPalette.light.titleText }

    /// Returns palette foreground styles for a weather SF Symbol icon name.
    func weatherIconPalette(for iconName: String) -> (primary: Color, secondary: Color) {
        switch WeatherSymbolClassification.resolve(iconName) {
        case .clear:
            return (sunIconColor, sunIconColor)
        case .partlySunny, .partlyCloudy:
            return (primaryText, sunIconColor)
        case .rain, .drizzle:
            return (primaryText, dotRain)
        case .cloudy, .snow, .fog, .wind, nil:
            return (primaryText, primaryText)
        }
    }
}

// MARK: - Light Theme

extension ThemeColors {
    static let light = ThemeColors(palette: AppPalette.light)
}

// MARK: - Dark Themes

extension ThemeColors {
    static let dark = ThemeColors(palette: AppPalette.dark)

    static let black = ThemeColors(palette: AppPalette.black)
}

// MARK: - Accessibility - Increased Contrast Palettes

// Accessibility: These palettes activate only with the system Increase Contrast setting.
// Text colors meet a 4.5:1 minimum and meaningful palette colors meet a 3:1 minimum
// against their corresponding base backgrounds.
extension ThemeColors {
    static let increasedContrastLight = ThemeColors(
        palette: AppPalette.increasedContrastValues(for: .light)
    )

    static let increasedContrastDark = ThemeColors(
        palette: AppPalette.increasedContrastValues(for: .dark)
    )

    static let increasedContrastBlack = ThemeColors(
        palette: AppPalette.increasedContrastBlack
    )
}

private extension ThemeColors {
    init(palette: AppPalette.Values) {
        self.init(
            titleText: palette.titleText,
            secondaryText: palette.secondaryText,
            background: palette.background,
            destructive: palette.destructive,
            dotSun: palette.dotSun,
            dotPartlyCloudy: palette.dotPartlyCloudy,
            dotCloudy: palette.dotCloudy,
            dotRain: palette.dotRain,
            dotDrizzle: palette.dotDrizzle,
            settingsRowFill: palette.settingsRow,
            tutorialBackground: palette.tutorialBackground
        )
    }
}

// MARK: - Theme Manager

@Observable
class AppTheme {
    static let shared = AppTheme()

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

    private init() {
        let raw = UserDefaults.standard.string(forKey: "appThemeStyle") ?? AppThemeStyle.defaultRawValue
        self.style = AppThemeStyle(rawValue: raw) ?? .automatic
    }

    private func resolvedColors(
        for resolvedScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> ThemeColors {
        if usesBlackPalette(for: resolvedScheme) {
            return contrast == .increased ? .increasedContrastBlack : .black
        }
        if contrast == .increased {
            return resolvedScheme == .dark ? .increasedContrastDark : .increasedContrastLight
        }
        return resolvedScheme == .dark ? .dark : .light
    }

    private func usesBlackPalette(for resolvedScheme: ColorScheme) -> Bool {
        guard resolvedScheme == .dark else { return false }
        return style == .black || style == .automaticBlack
    }
}

// MARK: - Environment Key

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.shared
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

// MARK: - View Modifiers

private struct WeatherIconStyleModifier: ViewModifier {
    @Environment(\.appTheme) private var theme
    let iconName: String

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

private struct ThemedPopoverBackgroundModifier: ViewModifier {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency || colorSchemeContrast == .increased {
            // Accessibility: `background` is fully opaque in every palette, unlike
            // the standard popover color's intentional translucency.
            content.presentationBackground(
                colorSchemeContrast == .increased
                    ? theme.colors.popoverBackground
                    : theme.colors.background
            )
        } else if #available(iOS 26.0, *) {
            content.presentationBackground {
                Color.clear
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
        } else {
            content.presentationBackground(.ultraThinMaterial)
        }
    }
}

private struct ThemedGlassModifier<Shape: InsettableShape>: ViewModifier {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let shape: Shape

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency || colorSchemeContrast == .increased {
            content.highLegibilityGlass(
                theme: theme.colors,
                contrast: colorSchemeContrast,
                in: shape
            )
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content
                .background(theme.colors.glassFill, in: shape)
                .overlay(shape.stroke(theme.colors.primaryText.opacity(0.18), lineWidth: 0.6))
        }
    }
}

private struct DetailTranslucentCardModifier<Shape: InsettableShape>: ViewModifier {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let colorScheme: ColorScheme
    let shape: Shape

    @ViewBuilder
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

// MARK: - Translucent Cards with Embedded Media

/// Places Liquid Glass behind live media so its foreground treatment cannot
/// pick up colors from an embedded map or video layer.
private struct DetailTranslucentMediaCardModifier<Shape: InsettableShape>: ViewModifier {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let colorScheme: ColorScheme
    let shape: Shape

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency || colorSchemeContrast == .increased {
            content.highLegibilityGlass(
                theme: theme.colors,
                contrast: colorSchemeContrast,
                in: shape
            )
        } else if #available(iOS 26.0, *) {
            content
                .background {
                    shape
                        .fill(theme.colors.glassFill.opacity(colorScheme == .dark ? 0.18 : 0.22))
                        .glassEffect(.regular.interactive(), in: shape)
                }
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

// MARK: - View Modifier APIs

extension View {
    func weatherIconStyle(for iconName: String) -> some View {
        modifier(WeatherIconStyleModifier(iconName: iconName))
    }

    func themedPopoverBackground() -> some View {
        modifier(ThemedPopoverBackgroundModifier())
    }

    func symbolReplaceTransition() -> some View {
        contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
    }

    func themedGlass<Shape: InsettableShape>(in shape: Shape) -> some View {
        modifier(ThemedGlassModifier(shape: shape))
    }

    func detailTranslucentCard<Shape: InsettableShape>(colorScheme: ColorScheme, in shape: Shape) -> some View {
        modifier(DetailTranslucentCardModifier(colorScheme: colorScheme, shape: shape))
    }

    func detailTranslucentMediaCard<Shape: InsettableShape>(colorScheme: ColorScheme, in shape: Shape) -> some View {
        modifier(DetailTranslucentMediaCardModifier(colorScheme: colorScheme, shape: shape))
    }

}
