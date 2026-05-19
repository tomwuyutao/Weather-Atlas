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

    // Glass fill for capsule/circle backgrounds
    let glassFill: Color

    // Filter
    let filterSunny: Color

    /// Returns palette foreground styles for a weather SF Symbol icon name.
    func weatherIconPalette(for iconName: String) -> (primary: Color, secondary: Color) {
        if iconName.contains("sun") && iconName.contains("cloud") {
            return (cloudIconColor, dotPartlyCloudy)
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
        primaryText: Color(hex: 0x444444),
        secondaryText: Color(hex: 0x656565),
        background: Color(hex: 0xFFFFFF),
        searchOverlayBackground: Color(hex: 0xFFFFFF).opacity(0.97),
        modalOverlay: Color.black.opacity(0.24),
        glassTint: Color(hex: 0xF8F4F1).opacity(0.45),
        popoverBackground: Color(hex: 0xF8F4F1).opacity(0.86),
        mapOcean: Color(hex: 0xFFFFFF),
        mapLand: Color(hex: 0xF8F4F1),
        mapBorder: Color(hex: 0xE6DDD7),
        colorfulOcean: Color(hex: 0xFFFFFF),
        colorfulLand: Color(hex: 0xF8F4F1),
        colorfulLandActive: Color(hex: 0xF8F4F1),
        colorfulBorder: Color(hex: 0xE6DDD7),
        accent: Color(hex: 0xBCCFDC),
        destructive: Color(hex: 0xC94949),
        dotSun: Color(hex: 0xFF8A65),
        dotPartlyCloudy: Color(hex: 0xEEB368),
        dotCloudy: Color(hex: 0xD3E3EC),
        dotRain: Color(hex: 0xBCCFDC),
        dotDrizzle: Color(hex: 0x6EACE8),
        dotSnow: Color(hex: 0xD3E3EC),
        dotFog: Color(hex: 0xD3E3EC),
        dotWind: Color(hex: 0xD3E3EC),
        rainEffect: Color(hex: 0xBCCFDC).opacity(0.62),
        snowEffect: Color(hex: 0xD3E3EC).opacity(0.52),
        cloudEffect: Color(hex: 0xD3E3EC),
        windEffect: Color(hex: 0xD3E3EC).opacity(0.28),
        sunIconColor: Color(hex: 0xFF8A65),
        cloudIconColor: Color(hex: 0xD5D5D5),
        rainIconColor: Color(hex: 0x6EACE8),
        snowIconColor: Color(hex: 0xD3E3EC),
        moonIconColor: Color(hex: 0xD3E3EC),
        listCardFill: Color(hex: 0xF8F4F1),
        glassFill: Color(hex: 0xF8F4F1),
        filterSunny: Color(hex: 0xFF8A65)
    )
}

// MARK: - Dark Theme

extension ThemeColors {
    static let dark = ThemeColors(
        primaryText: Color(hex: 0xE7E7E8),
        secondaryText: Color(hex: 0xD2D2D2),
        background: Color(hex: 0x2E2961),
        searchOverlayBackground: Color(hex: 0x2E2961).opacity(0.97),
        modalOverlay: Color.black.opacity(0.5),
        glassTint: Color(hex: 0x423D74).opacity(0.6),
        popoverBackground: Color(hex: 0x423D74).opacity(0.95),
        mapOcean: Color(hex: 0x2E2961),
        mapLand: Color(hex: 0x423D74),
        mapBorder: Color(hex: 0x56508B),
        colorfulOcean: Color(hex: 0x2E2961),
        colorfulLand: Color(hex: 0x423D74),
        colorfulLandActive: Color(hex: 0x423D74),
        colorfulBorder: Color(hex: 0x56508B),
        accent: Color(hex: 0x4D70D4),
        destructive: Color(hex: 0xC94949),
        dotSun: Color(hex: 0xFF8A65),
        dotPartlyCloudy: Color(hex: 0xF4DC85),
        dotCloudy: Color(hex: 0xD3E3EC),
        dotRain: Color(hex: 0x4D70D4),
        dotDrizzle: Color(hex: 0x65ABE3),
        dotSnow: Color(hex: 0xD3E3EC),
        dotFog: Color(hex: 0xD3E3EC),
        dotWind: Color(hex: 0xD3E3EC),
        rainEffect: Color(hex: 0x4D70D4).opacity(0.55),
        snowEffect: Color(hex: 0xD3E3EC).opacity(0.6),
        cloudEffect: Color(hex: 0xD3E3EC),
        windEffect: Color(hex: 0xD3E3EC).opacity(0.18),
        sunIconColor: Color(hex: 0xFF8A65),
        cloudIconColor: Color(hex: 0xD3E3EC),
        rainIconColor: Color(hex: 0x65ABE3),
        snowIconColor: Color(hex: 0xD3E3EC),
        moonIconColor: Color(hex: 0xD3E3EC),
        listCardFill: Color(hex: 0x423D74),
        glassFill: Color(hex: 0x423D74),
        filterSunny: Color(hex: 0xFF8A65)
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
        let raw = UserDefaults.standard.string(forKey: "appThemeStyle") ?? "dark"
        self.style = AppThemeStyle(rawValue: raw) ?? .dark
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
