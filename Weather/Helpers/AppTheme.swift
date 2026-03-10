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
    
    // Filter
    let filterSunny: Color
}

// MARK: - Predefined Themes

extension ThemeColors {
    static let basic = ThemeColors(
        primaryText: .primary,
        secondaryText: .secondary,
        background: .black,
        searchOverlayBackground: Color.black.opacity(0.95),
        modalOverlay: Color.black.opacity(0.4),
        mapOcean: .black,
        mapLand: Color(red: 28/255.0, green: 28/255.0, blue: 30/255.0),
        mapBorder: Color(red: 45/255.0, green: 45/255.0, blue: 47/255.0),
        svgCountryFill: Color.gray.opacity(0.2),
        accent: .blue,
        destructive: .red,
        dotSun: .yellow,
        dotPartlyCloudy: Color(hue: 0.13, saturation: 0.3, brightness: 1.0),
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
        filterSunny: .yellow
    )
    
    static let light = ThemeColors(
        primaryText: Color(hex: 0x313131),
        secondaryText: .secondary,
        background: Color(hex: 0xEDE7DE),
        searchOverlayBackground: Color(hex: 0xEDE7DE).opacity(0.97),
        modalOverlay: Color.black.opacity(0.3),
        mapOcean: Color(hex: 0xEDE7DE),
        mapLand: Color(hex: 0xE6E0D7),
        mapBorder: Color(hex: 0xD5CFC6),
        svgCountryFill: Color(hex: 0xE6E0D7),
        accent: Color(hex: 0x1579C7),
        destructive: Color(hex: 0xFB4368),
        dotSun: Color(hex: 0xFFB200),
        dotPartlyCloudy: Color(hex: 0xFFC664),
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
        sunIconColor: Color(hex: 0xFFB200),
        cloudIconColor: Color(hex: 0x313131),
        rainIconColor: Color(hex: 0x57D3E5),
        filterSunny: Color(hex: 0xFFB200)
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
