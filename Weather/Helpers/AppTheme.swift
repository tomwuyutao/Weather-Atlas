//
//  AppTheme.swift
//  Weather
//
//  Created by Tom on 10/03/2026.
//

import SwiftUI

// MARK: - Theme Enum

enum AppThemeStyle: String, CaseIterable {
    case basic = "basic"
    case light = "light"
    
    var displayName: String {
        switch self {
        case .basic: return "Basic"
        case .light: return "Light"
        }
    }
    
    var colorScheme: ColorScheme {
        switch self {
        case .basic: return .dark
        case .light: return .light
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
    
    // Filter
    let filterSunny: Color
    
    /// Returns palette foreground styles for a weather SF Symbol icon name.
    /// Use with `.symbolRenderingMode(.palette)` and `.foregroundStyle(primary, secondary)`.
    func weatherIconPalette(for iconName: String) -> (primary: Color, secondary: Color) {
        if iconName.contains("sun") && iconName.contains("cloud") {
            // cloud.sun.fill — primary: cloud, secondary: sun
            return (cloudIconColor, sunIconColor)
        } else if iconName.contains("moon") && iconName.contains("cloud") {
            // cloud.moon.fill — primary: cloud, secondary: moon
            return (cloudIconColor, moonIconColor)
        } else if iconName.contains("rain") || iconName.contains("drizzle") {
            // cloud.rain.fill / cloud.drizzle.fill — primary: cloud, secondary: rain
            return (cloudIconColor, rainIconColor)
        } else if iconName.contains("snow") {
            // cloud.snow.fill — primary: cloud, secondary: snow
            return (cloudIconColor, snowIconColor)
        } else if iconName.contains("fog") {
            // cloud.fog.fill — primary: cloud, secondary: fog (use secondary text)
            return (cloudIconColor, cloudIconColor.opacity(0.6))
        } else if iconName.contains("sun") {
            // sun.max.fill — primary: sun
            return (sunIconColor, sunIconColor)
        } else if iconName.contains("moon") {
            // moon.fill — primary: moon
            return (moonIconColor, moonIconColor)
        } else if iconName.contains("cloud") {
            // cloud.fill — primary: cloud
            return (cloudIconColor, cloudIconColor)
        } else if iconName.contains("wind") {
            // wind — primary: cloud color
            return (cloudIconColor, cloudIconColor)
        } else {
            return (cloudIconColor, cloudIconColor)
        }
    }
}

// MARK: - Predefined Themes

extension ThemeColors {
    static let basic = ThemeColors(
        primaryText: .primary,
        secondaryText: .secondary,
        background: .black,
        searchOverlayBackground: Color.black.opacity(0.95),
        modalOverlay: Color.black.opacity(0.4),
        glassTint: .clear,
        popoverBackground: .clear,
        mapOcean: .black,
        mapLand: Color(red: 28/255.0, green: 28/255.0, blue: 30/255.0),
        mapBorder: Color(red: 45/255.0, green: 45/255.0, blue: 47/255.0),
        svgCountryFill: Color.gray.opacity(0.2),
        accent: .blue,
        destructive: .red,
        dotSun: .yellow,
        dotPartlyCloudy: Color(hue: 0.13, saturation: 0.5, brightness: 1.0),
        dotCloudy: .white,
        dotRain: .blue,
        dotDrizzle: Color(red: 0.55, green: 0.65, blue: 0.85),
        dotSnow: Color(red: 0.55, green: 0.65, blue: 0.85),
        dotFog: .gray,
        dotWind: .white,
        rainEffect: Color.cyan.opacity(0.55),
        snowEffect: Color.white.opacity(0.6),
        cloudEffect: .white,
        windEffect: Color.white.opacity(0.3),
        sunIconColor: .yellow,
        cloudIconColor: .white,
        rainIconColor: .blue,
        snowIconColor: Color(red: 0.55, green: 0.65, blue: 0.85),
        moonIconColor: .yellow,
        listCardFill: .clear,
        filterSunny: .yellow
    )
    
    static let light = ThemeColors(
        primaryText: Color(hex: 0x313131),
        secondaryText: .secondary,
        background: Color(hex: 0xEDE7DE),
        searchOverlayBackground: Color(hex: 0xEDE7DE).opacity(0.97),
        modalOverlay: Color.black.opacity(0.3),
        glassTint: Color(hex: 0xEDE7DE).opacity(0.4),
        popoverBackground: Color(hex: 0xE3DDD4).opacity(0.7),
        mapOcean: Color(hex: 0xEDE7DE),
        mapLand: Color(hex: 0xE0DAD1),
        mapBorder: Color(hex: 0xD5CFC6),
        svgCountryFill: Color(hex: 0xE0DAD1),
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
        listCardFill: Color(hex: 0xE8E2D9),
        filterSunny: Color(hex: 0xFDA409)
    )
}

// MARK: - Theme Manager

@Observable
class AppTheme {
    static let shared = AppTheme()
    
    var style: AppThemeStyle {
        didSet {
            UserDefaults.standard.set(style.rawValue, forKey: "appTheme")
        }
    }
    
    var colors: ThemeColors {
        switch style {
        case .basic: return .basic
        case .light: return .light
        }
    }
    
    var colorScheme: ColorScheme {
        style.colorScheme
    }
    
    private init() {
        let raw = UserDefaults.standard.string(forKey: "appTheme") ?? "basic"
        self.style = AppThemeStyle(rawValue: raw) ?? .basic
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

// MARK: - Weather Icon Modifier

extension View {
    /// Applies themed palette rendering to a weather SF Symbol icon.
    func weatherIconStyle(for iconName: String) -> some View {
        let theme = AppTheme.shared.colors
        let palette = theme.weatherIconPalette(for: iconName)
        return self
            .symbolRenderingMode(.palette)
            .foregroundStyle(palette.primary, palette.secondary)
    }
    
    /// Themed popover/presentation background.
    func themedPopoverBackground() -> some View {
        let theme = AppTheme.shared
        if theme.style == .basic {
            return AnyView(self.presentationBackground(.ultraThinMaterial))
        } else {
            return AnyView(self.presentationBackground(theme.colors.popoverBackground))
        }
    }
    
    /// Themed glass/material background for capsule-shaped UI elements.
    @ViewBuilder
    func themedGlass(in shape: some InsettableShape) -> some View {
        let theme = AppTheme.shared
        if theme.style == .basic {
            self.background(Color(white: 0.18), in: shape)
        } else {
            self.background(Color(hex: 0xE8E2D9), in: shape)
        }
    }
    
    /// Themed glass/material background with accent tint (for confirm buttons etc.)
    @ViewBuilder
    func themedAccentGlass(tint: Color, in shape: some InsettableShape) -> some View {
        let theme = AppTheme.shared
        if theme.style == .basic {
            self.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            self.background(tint.opacity(0.15), in: shape)
                .overlay(shape.stroke(tint.opacity(0.3), lineWidth: 0.5))
        }
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
