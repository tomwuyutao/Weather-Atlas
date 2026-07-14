//
//  AppTheme.swift
//  Weather
//
//  Purpose: Centralizes theme colors, glass styling, appearance resolution,
//  and small color/view helpers used across the app.
//

import SwiftUI
import UIKit

// MARK: - Theme Style

enum AppThemeStyle: String, CaseIterable {
    case light = "light"
    case dark = "dark"
    case automatic = "automatic"

    static let defaultRawValue = AppThemeStyle.automatic.rawValue

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .automatic: return "Auto"
        }
    }
}

// MARK: - Theme Colors

struct ThemeColors {
    // Text
    let titleText: Color
    let primaryText: Color
    let secondaryText: Color

    // Backgrounds
    let background: Color
    let popoverBackground: Color

    // Map
    let mapOcean: Color
    let mapBorder: Color

    // Accent / Interactive
    let accent: Color          // add-to-list, radial search handle
    let destructive: Color     // delete actions

    // Weather dots
    let dotSun: Color
    let dotPartlyCloudy: Color
    let dotCloudy: Color
    let dotRain: Color
    let dotDrizzle: Color
    let dotSnow: Color
    let dotFog: Color
    let dotWind: Color

    // Weather icon colors
    let sunIconColor: Color
    let cloudIconColor: Color
    let snowIconColor: Color
    let moonIconColor: Color

    // List cards
    let listCardFill: Color
    let chartPanelFill: Color
    let settingsRowFill: Color

    // Glass fill for capsule/circle backgrounds
    let glassFill: Color
    let shadow: Color

    // Filter
    let filterSunny: Color

    // Tutorial
    let tutorialBackground: Color

    /// Returns palette foreground styles for a weather SF Symbol icon name.
    func weatherIconPalette(for iconName: String) -> (primary: Color, secondary: Color) {
        if iconName.contains("sun") && iconName.contains("cloud") {
            return (cloudIconColor, sunIconColor)
        } else if iconName.contains("moon") && iconName.contains("cloud") {
            return (cloudIconColor, moonIconColor)
        } else if iconName.contains("drizzle") {
            return (cloudIconColor, cloudIconColor)
        } else if iconName.contains("rain") {
            return (cloudIconColor, cloudIconColor)
        } else if iconName.contains("snow") {
            return (cloudIconColor, snowIconColor)
        } else if iconName.contains("fog") {
            return (cloudIconColor, cloudIconColor.opacity(0.6))
        } else if iconName.contains("sun") {
            return (sunIconColor, sunIconColor)
        } else if iconName.contains("moon") {
            return (moonIconColor, moonIconColor)
        } else {
            return (cloudIconColor, cloudIconColor)
        }
    }
}

// MARK: - Light Theme

extension ThemeColors {
    static let light = ThemeColors(
        titleText: Color(hex: 0x1B3F73),
        primaryText: Color(hex: 0x1B3F73),
        secondaryText: Color(hex: 0x516071),
        background: Color(hex: 0xFDF9F3),
        popoverBackground: Color(hex: 0xFDF9F3).opacity(0.86),
        mapOcean: Color(hex: 0xFDF9F3),
        mapBorder: Color(hex: 0xC9C4B8),
        accent: Color(hex: 0x1B3F73),
        destructive: Color(hex: 0xD03D3B),
        dotSun: Color(hex: 0xFFB84D),
        dotPartlyCloudy: Color(hex: 0xFFDF91),
        dotCloudy: Color(hex: 0xC8C2B5),
        dotRain: Color(hex: 0x4D70D4),
        dotDrizzle: Color(hex: 0x62B9D2),
        dotSnow: Color(hex: 0xC8C2B5),
        dotFog: Color(hex: 0xC8C2B5),
        dotWind: Color(hex: 0xC8C2B5),
        sunIconColor: Color(hex: 0xFFB84D),
        cloudIconColor: Color(hex: 0x0F4A9C),
        snowIconColor: Color(hex: 0x0F4A9C),
        moonIconColor: Color(hex: 0x5A389F),
        listCardFill: Color(hex: 0xFDF9F3),
        chartPanelFill: Color(hex: 0xFCF6F0),
        settingsRowFill: Color(hex: 0xF6EDE4),
        glassFill: Color(hex: 0xFDF9F3),
        shadow: Color(hex: 0x000000),
        filterSunny: Color(hex: 0xFFB84D),
        tutorialBackground: Color(hex: 0x244F9C)
    )
}

// MARK: - Dark Theme

extension ThemeColors {
    static let dark = ThemeColors(
        titleText: Color(hex: 0xF5F6F8),
        primaryText: Color(hex: 0xF5F6F8),
        secondaryText: Color(hex: 0xB9C6DD),
        background: Color(hex: 0x08111F),
        popoverBackground: Color(hex: 0x0C1828).opacity(0.96),
        mapOcean: Color(hex: 0x08111F),
        mapBorder: Color(hex: 0x2D3B50),
        accent: Color(hex: 0xB9C6DD),
        destructive: Color(hex: 0xD03D3B),
        dotSun: Color(hex: 0xFFB84D),
        dotPartlyCloudy: Color(hex: 0xFFDF91),
        dotCloudy: Color(hex: 0xC8C2B5),
        dotRain: Color(hex: 0x8FA8E8),
        dotDrizzle: Color(hex: 0x62B9D2),
        dotSnow: Color(hex: 0xC8C2B5),
        dotFog: Color(hex: 0xC8C2B5),
        dotWind: Color(hex: 0xC8C2B5),
        sunIconColor: Color(hex: 0xFFB84D),
        cloudIconColor: Color(hex: 0xB9C6DD),
        snowIconColor: Color(hex: 0xB9C6DD),
        moonIconColor: Color(hex: 0x5A389F),
        listCardFill: Color(hex: 0x0C1828),
        chartPanelFill: Color(hex: 0x101C2D),
        settingsRowFill: Color(hex: 0x0B1628),
        glassFill: Color(hex: 0x0C1828),
        shadow: Color(hex: 0x000000),
        filterSunny: Color(hex: 0xFFB84D),
        tutorialBackground: Color(hex: 0x244F9C)
    )
}

// MARK: - Accessibility - Increased Contrast Palettes

// Accessibility: These palettes activate only with the system Increase Contrast setting.
// Text colors meet a 4.5:1 minimum and meaningful palette colors meet a 3:1 minimum
// against their corresponding base backgrounds.
extension ThemeColors {
    static let increasedContrastLight = ThemeColors(
        titleText: Color(hex: 0x032343),
        primaryText: Color(hex: 0x032343),
        secondaryText: Color(hex: 0x34485B),
        background: Color(hex: 0xFFFDF8),
        popoverBackground: Color(hex: 0xFFFDF8),
        mapOcean: Color(hex: 0xFFFDF8),
        mapBorder: Color(hex: 0x626B75),
        accent: Color(hex: 0x032343),
        destructive: Color(hex: 0xB3261E),
        dotSun: Color(hex: 0xC88000),
        dotPartlyCloudy: Color(hex: 0xA66A00),
        dotCloudy: Color(hex: 0x596675),
        dotRain: Color(hex: 0x1847A1),
        dotDrizzle: Color(hex: 0x006A84),
        dotSnow: Color(hex: 0x1847A1),
        dotFog: Color(hex: 0x596675),
        dotWind: Color(hex: 0x596675),
        sunIconColor: Color(hex: 0xC88000),
        cloudIconColor: Color(hex: 0x1847A1),
        snowIconColor: Color(hex: 0x1847A1),
        moonIconColor: Color(hex: 0x5630A6),
        listCardFill: Color(hex: 0xFFFFFF),
        chartPanelFill: Color(hex: 0xFFFFFF),
        settingsRowFill: Color(hex: 0xFFFDF8),
        glassFill: Color(hex: 0xFFFFFF),
        shadow: Color(hex: 0x000000),
        filterSunny: Color(hex: 0xC88000),
        tutorialBackground: Color(hex: 0x032343)
    )

    static let increasedContrastDark = ThemeColors(
        titleText: Color(hex: 0xFFFFFF),
        primaryText: Color(hex: 0xFFFFFF),
        secondaryText: Color(hex: 0xD5E0F2),
        background: Color(hex: 0x020814),
        popoverBackground: Color(hex: 0x071426),
        mapOcean: Color(hex: 0x020814),
        mapBorder: Color(hex: 0xA8B6CB),
        accent: Color(hex: 0xD5E0F2),
        destructive: Color(hex: 0xFF8A87),
        dotSun: Color(hex: 0xFFD166),
        dotPartlyCloudy: Color(hex: 0xFFE39A),
        dotCloudy: Color(hex: 0xD1D8E2),
        dotRain: Color(hex: 0xAFC3FF),
        dotDrizzle: Color(hex: 0x86E1F3),
        dotSnow: Color(hex: 0xFFFFFF),
        dotFog: Color(hex: 0xD1D8E2),
        dotWind: Color(hex: 0xD1D8E2),
        sunIconColor: Color(hex: 0xFFD166),
        cloudIconColor: Color(hex: 0xD5E0F2),
        snowIconColor: Color(hex: 0xFFFFFF),
        moonIconColor: Color(hex: 0xD4B7FF),
        listCardFill: Color(hex: 0x071426),
        chartPanelFill: Color(hex: 0x0A182A),
        settingsRowFill: Color(hex: 0x071426),
        glassFill: Color(hex: 0x071426),
        shadow: Color(hex: 0x000000),
        filterSunny: Color(hex: 0xFFD166),
        tutorialBackground: Color(hex: 0x032343)
    )
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

    /// The current system color scheme, kept in sync by ThemeContent.
    /// Allows non-view code (e.g. view modifiers) to reactively read the correct colors.
    var systemScheme: ColorScheme = .light

    /// The current system contrast preference, kept in sync by ThemeContent.
    var systemContrast: ColorSchemeContrast = .standard

    /// Resolved colors using the stored system scheme — reactive, used everywhere.
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
    func preferredColorScheme(for systemScheme: ColorScheme) -> ColorScheme? {
        switch style {
        case .light: return .light
        case .dark: return .dark
        case .automatic: return nil
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: "appThemeStyle") ?? AppThemeStyle.defaultRawValue
        self.style = AppThemeStyle(rawValue: raw) ?? .automatic
    }

    private func resolvedColors(
        for systemScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> ThemeColors {
        let resolvedScheme: ColorScheme
        switch style {
        case .light:
            resolvedScheme = .light
        case .dark:
            resolvedScheme = .dark
        case .automatic:
            resolvedScheme = systemScheme
        }

        if contrast == .increased {
            return resolvedScheme == .dark ? .increasedContrastDark : .increasedContrastLight
        }
        return resolvedScheme == .dark ? .dark : .light
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
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

// MARK: - Color Helpers
extension Color {
    func interpolated(with other: Color, by amount: Double) -> Color {
        let t = max(0, min(1, amount))

        let first = UIColor(self)
        let second = UIColor(other)
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0

        guard first.getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              second.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else {
            return t < 0.5 ? self : other
        }

        return Color(
            red: Double(r1 + (r2 - r1) * t),
            green: Double(g1 + (g2 - g1) * t),
            blue: Double(b1 + (b2 - b1) * t),
            opacity: Double(a1 + (a2 - a1) * t)
        )
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
            content
                .background(theme.colors.glassFill, in: shape)
                .overlay(
                    shape.stroke(
                        theme.colors.primaryText.opacity(colorSchemeContrast == .increased ? 0.90 : 0.18),
                        lineWidth: colorSchemeContrast == .increased ? 1 : 0.8
                    )
                )
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content
                .background(theme.colors.glassFill, in: shape)
                .overlay(shape.stroke(.white.opacity(0.18), lineWidth: 0.6))
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
            content
                .background(theme.colors.glassFill, in: shape)
                .overlay(
                    shape.stroke(
                        theme.colors.primaryText.opacity(colorSchemeContrast == .increased ? 0.90 : 0.18),
                        lineWidth: colorSchemeContrast == .increased ? 1 : 0.8
                    )
                )
        } else if #available(iOS 26.0, *) {
            content
                .background(
                    theme.colors.glassFill.opacity(colorScheme == .dark ? 0.18 : 0.22),
                    in: shape
                )
                .glassEffect(.regular.interactive(), in: shape)
                .overlay(shape.stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.36), lineWidth: 0.6))
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(
                    theme.colors.glassFill.opacity(colorScheme == .dark ? 0.30 : 0.38),
                    in: shape
                )
                .overlay(shape.stroke(.white.opacity(colorScheme == .dark ? 0.14 : 0.32), lineWidth: 0.6))
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
}

extension View {
    /// Conditionally applies a transform to a view.
    @ViewBuilder
    func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
