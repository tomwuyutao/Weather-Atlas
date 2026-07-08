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
    let primaryText: Color
    let secondaryText: Color

    // Backgrounds
    let background: Color
    let searchOverlayBackground: Color
    let modalOverlay: Color
    let glassTint: Color
    let popoverBackground: Color

    // Map
    let mapOcean: Color
    let mapLand: Color
    let mapBorder: Color

    // Colorful map mode
    let colorfulOcean: Color
    let colorfulLand: Color
    let colorfulLandActive: Color
    let colorfulBorder: Color

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

    // Weather effects
    let rainEffect: Color
    let snowEffect: Color
    let cloudEffect: Color
    let windEffect: Color

    // Weather icon colors
    let sunIconColor: Color
    let cloudIconColor: Color
    let rainIconColor: Color
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
    let tutorialDot: Color

    /// Returns palette foreground styles for a weather SF Symbol icon name.
    func weatherIconPalette(for iconName: String) -> (primary: Color, secondary: Color) {
        if iconName.contains("sun") && iconName.contains("cloud") {
            return (cloudIconColor, dotPartlyCloudy)
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
        primaryText: Color(hex: 0x0F4A9C),
        secondaryText: Color(hex: 0x4D70D4),
        background: Color(hex: 0xFDF9F3),
        searchOverlayBackground: Color(hex: 0xFDF9F3).opacity(0.97),
        modalOverlay: Color.black.opacity(0.24),
        glassTint: Color(hex: 0xFDF9F3).opacity(0.45),
        popoverBackground: Color(hex: 0xFDF9F3).opacity(0.86),
        mapOcean: Color(hex: 0xFDF9F3),
        mapLand: Color(hex: 0xFDF9F3),
        mapBorder: Color(hex: 0xC9C4B8),
        colorfulOcean: Color(hex: 0xFDF9F3),
        colorfulLand: Color(hex: 0xFDF9F3),
        colorfulLandActive: Color(hex: 0xFDF9F3),
        colorfulBorder: Color(hex: 0xC9C4B8),
        accent: Color(hex: 0x4D70D4),
        destructive: Color(hex: 0xD03D3B),
        dotSun: Color(hex: 0xFFB84D),
        dotPartlyCloudy: Color(hex: 0xD8C46F),
        dotCloudy: Color(hex: 0xC8C2B5),
        dotRain: Color(hex: 0x4D70D4),
        dotDrizzle: Color(hex: 0x62B9D2),
        dotSnow: Color(hex: 0xC8C2B5),
        dotFog: Color(hex: 0xC8C2B5),
        dotWind: Color(hex: 0xC8C2B5),
        rainEffect: Color(hex: 0x4D70D4).opacity(0.32),
        snowEffect: Color(hex: 0xE3E0D6).opacity(0.62),
        cloudEffect: Color(hex: 0xE3E0D6),
        windEffect: Color(hex: 0xE3E0D6).opacity(0.34),
        sunIconColor: Color(hex: 0xFFB84D),
        cloudIconColor: Color(hex: 0x0F4A9C),
        rainIconColor: Color(hex: 0x8790C4),
        snowIconColor: Color(hex: 0x0F4A9C),
        moonIconColor: Color(hex: 0x5A389F),
        listCardFill: Color(hex: 0xFDF9F3),
        chartPanelFill: Color(hex: 0xFCF6F0),
        settingsRowFill: Color(hex: 0xF6EDE4),
        glassFill: Color(hex: 0xFDF9F3),
        shadow: Color(hex: 0x000000),
        filterSunny: Color(hex: 0xFFB84D),
        tutorialBackground: Color(hex: 0x244F9C),
        tutorialDot: Color(hex: 0xFFB84D)
    )
}

// MARK: - Dark Theme

extension ThemeColors {
    static let dark = ThemeColors(
        primaryText: Color(hex: 0xF7F3EA),
        secondaryText: Color(hex: 0x6F86FF),
        background: Color(hex: 0x040C1A),
        searchOverlayBackground: Color(hex: 0x040C1A).opacity(0.97),
        modalOverlay: Color.black.opacity(0.5),
        glassTint: Color(hex: 0x0C1828).opacity(0.72),
        popoverBackground: Color(hex: 0x0C1828).opacity(0.96),
        mapOcean: Color(hex: 0x040C1A),
        mapLand: Color(hex: 0x0B1628),
        mapBorder: Color(hex: 0x223A5C),
        colorfulOcean: Color(hex: 0x040C1A),
        colorfulLand: Color(hex: 0x0B1628),
        colorfulLandActive: Color(hex: 0x10213A),
        colorfulBorder: Color(hex: 0x223A5C),
        accent: Color(hex: 0x6F86FF),
        destructive: Color(hex: 0xFF4940),
        dotSun: Color(hex: 0xDD8019),
        dotPartlyCloudy: Color(hex: 0xB88A45),
        dotCloudy: Color(hex: 0x8792A8),
        dotRain: Color(hex: 0x6F86FF),
        dotDrizzle: Color(hex: 0x5EC4DA),
        dotSnow: Color(hex: 0xA9B1C4),
        dotFog: Color(hex: 0x78849A),
        dotWind: Color(hex: 0x78849A),
        rainEffect: Color(hex: 0x6F86FF).opacity(0.55),
        snowEffect: Color(hex: 0xA9B1C4).opacity(0.48),
        cloudEffect: Color(hex: 0x8792A8),
        windEffect: Color(hex: 0x78849A).opacity(0.28),
        sunIconColor: Color(hex: 0xDD8019),
        cloudIconColor: Color(hex: 0x6F86FF),
        rainIconColor: Color(hex: 0x8EA0F8),
        snowIconColor: Color(hex: 0xAEBBFF),
        moonIconColor: Color(hex: 0x957DF6),
        listCardFill: Color(hex: 0x0C1828),
        chartPanelFill: Color(hex: 0x101C2D),
        settingsRowFill: Color(hex: 0x0B1628),
        glassFill: Color(hex: 0x0C1828),
        shadow: Color(hex: 0x000000),
        filterSunny: Color(hex: 0xDD8019),
        tutorialBackground: Color(hex: 0x244F9C),
        tutorialDot: Color(hex: 0xDD8019)
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

    /// Resolved colors using the stored system scheme — reactive, used everywhere.
    var colors: ThemeColors {
        switch style {
        case .light: return .light
        case .dark: return .dark
        case .automatic: return systemScheme == .dark ? .dark : .light
        }
    }

    /// Resolved colors for an explicit color scheme (used by ThemeContent during environment setup).
    func colors(for scheme: ColorScheme) -> ThemeColors {
        switch style {
        case .light: return .light
        case .dark: return .dark
        case .automatic: return scheme == .dark ? .dark : .light
        }
    }

    /// The ColorScheme to apply to the window (nil = follow system).
    func preferredColorScheme(for systemScheme: ColorScheme) -> ColorScheme? {
        switch style {
        case .light: return .light
        case .dark: return .dark
        case .automatic: return nil
        }
    }

    /// The effective color scheme after resolving "automatic".
    func resolvedScheme(for systemScheme: ColorScheme) -> ColorScheme {
        switch style {
        case .light: return .light
        case .dark: return .dark
        case .automatic: return systemScheme
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: "appThemeStyle") ?? AppThemeStyle.defaultRawValue
        self.style = AppThemeStyle(rawValue: raw) ?? .automatic
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

// MARK: - Resolved Theme Colors Environment Key
// Views read `\.themeColors` to get the already-resolved ThemeColors for the current scheme.

private struct ThemeColorsKey: EnvironmentKey {
    static let defaultValue: ThemeColors = .light
}

extension EnvironmentValues {
    var themeColors: ThemeColors {
        get { self[ThemeColorsKey.self] }
        set { self[ThemeColorsKey.self] = newValue }
    }
}

// MARK: - Color Helpers
extension Color {
    func compatMix(with other: Color, by amount: Double) -> Color {
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
extension View {
    /// Applies palette icon coloring for a weather SF Symbol.
    func weatherIconStyle(for iconName: String) -> some View {
        let palette = AppTheme.shared.colors.weatherIconPalette(for: iconName)
        return self
            .symbolRenderingMode(.palette)
            .foregroundStyle(palette.primary, palette.secondary)
    }

    /// Themed popover/presentation background.
    @ViewBuilder
    func themedPopoverBackground() -> some View {
        self.presentationBackground(AppTheme.shared.colors.popoverBackground)
    }

    @ViewBuilder
    func compatSymbolReplaceTransition() -> some View {
        if #available(iOS 18.0, *) {
            self.contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
        } else {
            self.contentTransition(.opacity)
        }
    }

    /// Themed Liquid Glass background.
    @ViewBuilder
    func themedGlass(in shape: some InsettableShape) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(AppTheme.shared.colors.glassFill, in: shape)
                .overlay(shape.stroke(.white.opacity(0.18), lineWidth: 0.6))
        }
    }

    /// Softer translucent card treatment for detail screens with tinted backgrounds.
    @ViewBuilder
    func detailTranslucentCard(colorScheme: ColorScheme, in shape: some InsettableShape) -> some View {
        if #available(iOS 26.0, *) {
            self
                .background(
                    AppTheme.shared.colors.glassFill.opacity(colorScheme == .dark ? 0.18 : 0.22),
                    in: shape
                )
                .glassEffect(.regular.interactive(), in: shape)
                .overlay(shape.stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.36), lineWidth: 0.6))
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .background(
                    AppTheme.shared.colors.glassFill.opacity(colorScheme == .dark ? 0.30 : 0.38),
                    in: shape
                )
                .overlay(shape.stroke(.white.opacity(colorScheme == .dark ? 0.14 : 0.32), lineWidth: 0.6))
        }
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
