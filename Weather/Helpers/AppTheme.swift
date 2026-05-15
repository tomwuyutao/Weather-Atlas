//
//  AppTheme.swift
//  Weather
//
//  Created by Tom on 10/03/2026.
//

import SwiftUI

// MARK: - Theme Style

enum AppThemeStyle: String, CaseIterable {
    case light = "light"
    case dark = "dark"
    case automatic = "automatic"

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
    let svgCountryFill: Color

    // Colorful map mode
    let colorfulOcean: Color
    let colorfulLand: Color
    let colorfulLandActive: Color
    let colorfulBorder: Color

    // Accent / Interactive
    let accent: Color          // add-to-list, radial search handle
    let destructive: Color     // delete, country search pin

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

    // Glass fill for capsule/circle backgrounds
    let glassFill: Color

    // Filter
    let filterSunny: Color

    /// Returns palette foreground styles for a weather SF Symbol icon name.
    func weatherIconPalette(for iconName: String) -> (primary: Color, secondary: Color) {
        if iconName.contains("sun") && iconName.contains("cloud") {
            return (cloudIconColor, sunIconColor)
        } else if iconName.contains("moon") && iconName.contains("cloud") {
            return (cloudIconColor, moonIconColor)
        } else if iconName.contains("rain") || iconName.contains("drizzle") {
            return (cloudIconColor, rainIconColor)
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
        primaryText: Color(hex: 0x282828),
        secondaryText: .secondary,
        background: Color(hex: 0xF4F1EB),
        searchOverlayBackground: Color(hex: 0xF4F1EB).opacity(0.97),
        modalOverlay: Color.black.opacity(0.3),
        glassTint: Color(hex: 0xF4F1EB).opacity(0.4),
        popoverBackground: Color(hex: 0xEAE7E1).opacity(0.7),
        mapOcean: Color(hex: 0xF4F1EB),
        mapLand: Color(hex: 0xE8E5DF),
        mapBorder: Color(hex: 0xDDDAD3),
        svgCountryFill: Color(hex: 0xE8E5DF),
        colorfulOcean: Color(hex: 0xE8F4F0),
        colorfulLand: Color(hex: 0xDFEDE4),
        colorfulLandActive: Color(hex: 0xD8E8DC),
        colorfulBorder: Color(hex: 0xCDDDD2),
        accent: Color(hex: 0x1579C7),
        destructive: Color(hex: 0xFB4368),
        dotSun: Color(hex: 0xFDA409),
        dotPartlyCloudy: Color(hex: 0xF5C563),
        dotCloudy: .white,
        dotRain: Color(hex: 0x1579C7),
        dotDrizzle: Color(hex: 0x57D3E5),
        dotSnow: .white,
        dotFog: .white,
        dotWind: .white,
        rainEffect: Color(hex: 0x57D3E5).opacity(0.55),
        snowEffect: Color.white.opacity(0.6),
        cloudEffect: .white,
        windEffect: Color(hex: 0x313131).opacity(0.15),
        sunIconColor: Color(hex: 0xFDA409),
        cloudIconColor: .white,
        rainIconColor: Color(hex: 0x57D3E5),
        snowIconColor: .white,
        moonIconColor: Color(hex: 0xBE9AED),
        listCardFill: Color(hex: 0xEFEBE5),
        glassFill: Color(hex: 0xEFEBE5),
        filterSunny: Color(hex: 0xFDA409)
    )
}

// MARK: - Dark Theme

extension ThemeColors {
    static let dark = ThemeColors(
        primaryText: Color(hex: 0xE8E4DF),
        secondaryText: Color(hex: 0x8A8A9A),
        background: Color(hex: 0x1A1B2E),
        searchOverlayBackground: Color(hex: 0x1A1B2E).opacity(0.97),
        modalOverlay: Color.black.opacity(0.5),
        glassTint: Color(hex: 0x252640).opacity(0.6),
        popoverBackground: Color(hex: 0x252640).opacity(0.95),
        mapOcean: Color(hex: 0x1A1B2E),
        mapLand: Color(hex: 0x252640),
        mapBorder: Color(hex: 0x353660),
        svgCountryFill: Color(hex: 0x252640),
        colorfulOcean: Color(hex: 0x1A2A3D),
        colorfulLand: Color(hex: 0x2A4A3A),
        colorfulLandActive: Color(hex: 0x345A45),
        colorfulBorder: Color(hex: 0x3D6B55),
        accent: Color(hex: 0x4A9EE0),
        destructive: Color(hex: 0xFB4368),
        dotSun: Color(hex: 0xFDA409),
        dotPartlyCloudy: Color(hex: 0xF5C563),
        dotCloudy: Color(hex: 0xE8E4DF),
        dotRain: Color(hex: 0x4A9EE0),
        dotDrizzle: Color(hex: 0x57D3E5),
        dotSnow: Color(hex: 0xE8E4DF),
        dotFog: Color(hex: 0x8A8A9A),
        dotWind: Color(hex: 0xE8E4DF),
        rainEffect: Color(hex: 0x57D3E5).opacity(0.55),
        snowEffect: Color(hex: 0xE8E4DF).opacity(0.6),
        cloudEffect: Color(hex: 0xE8E4DF),
        windEffect: Color(hex: 0xE8E4DF).opacity(0.15),
        sunIconColor: Color(hex: 0xFDA409),
        cloudIconColor: Color(hex: 0xE8E4DF),
        rainIconColor: Color(hex: 0x57D3E5),
        snowIconColor: Color(hex: 0xE8E4DF),
        moonIconColor: Color(hex: 0xBE9AED),
        listCardFill: Color(hex: 0x252640),
        glassFill: Color(hex: 0x252640),
        filterSunny: Color(hex: 0xFDA409)
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

    /// True when the detailed MapKit map is active — toolbar buttons use material glass.
    var isDetailedMapMode: Bool = false

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
        let raw = UserDefaults.standard.string(forKey: "appThemeStyle") ?? "automatic"
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
    /// Uses full-opacity glassFill in detailed/colorful map modes to match expanded cards.
    @ViewBuilder
    func themedPopoverBackground() -> some View {
        if AppTheme.shared.isDetailedMapMode {
            self.presentationBackground(AppTheme.shared.colors.glassFill)
        } else {
            self.presentationBackground(AppTheme.shared.colors.popoverBackground)
        }
    }

    /// Themed Liquid Glass background.
    func themedGlass(in shape: some InsettableShape) -> some View {
        self.glassEffect(.regular.interactive(), in: shape)
    }

}

extension View {
    /// Themed glass/material background with accent tint (for confirm buttons etc.)
    @ViewBuilder
    func themedAccentGlass(tint: Color, in shape: some InsettableShape) -> some View {
        self.background(tint.opacity(0.15), in: shape)
            .overlay(shape.stroke(tint.opacity(0.3), lineWidth: 0.5))
    }

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
