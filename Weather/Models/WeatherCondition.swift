//
//  WeatherCondition.swift
//  Weather
//
//  Purpose: Defines the app's normalized weather-condition domain model and
//  its localized/icon/color presentation mappings.
//

import SwiftUI
import WeatherKit

// MARK: - Normalized Weather Conditions

/// Finite condition vocabulary recognized by scoring and presentation code.
enum AppWeatherCondition: String, Codable {
    case clear
    case partlySunny
    case partlyCloudy
    case cloudy
    case rain
    case drizzle
    case snow
    case fog
    case wind

    /// Returns the condition's user-facing name in the requested locale.
    func localizedDisplayName(locale: Locale = .current) -> String {
        switch self {
        case .clear: return localizedString("Clear", locale: locale)
        case .partlySunny: return localizedString("Partly Sunny", locale: locale)
        case .partlyCloudy: return localizedString("Partly Cloudy", locale: locale)
        case .cloudy: return localizedString("Cloudy", locale: locale)
        case .rain: return localizedString("Rain", locale: locale)
        case .drizzle: return localizedString("Drizzle", locale: locale)
        case .snow: return localizedString("Snow", locale: locale)
        case .fog: return localizedString("Fog", locale: locale)
        case .wind: return localizedString("Windy", locale: locale)
        }
    }

    /// Selects the semantic map/list dot color from an active theme palette.
    func dotColor(for theme: ThemeColors) -> Color {
        switch self {
        case .clear: return theme.dotSun
        case .partlySunny: return theme.dotPartlyCloudy
        case .partlyCloudy: return theme.dotCloudy
        case .cloudy: return theme.dotCloudy
        case .rain: return theme.dotRain
        case .drizzle: return theme.dotDrizzle
        // Snow, fog, and wind share the neutral cloudy mark.
        case .snow, .fog, .wind: return theme.dotCloudy
        }
    }

    /// Ascending condition rank used before cloud-cover tie-breaking.
    nonisolated var sunninessRank: Int {
        switch self {
        case .clear: return 0
        case .partlySunny: return 1
        case .partlyCloudy: return 2
        case .cloudy: return 3
        case .wind: return 4
        case .fog: return 5
        case .drizzle: return 6
        case .rain: return 7
        case .snow: return 8
        }
    }

    /// Whether this condition belongs to the strict sunny-only filter.
    nonisolated var isSunny: Bool {
        self == .clear
    }

    /// Whether this condition contributes to a favorable sunny window.
    nonisolated var isSunnyOrPartlySunny: Bool {
        self == .clear || self == .partlySunny
    }

    /// Resolves a WeatherKit symbol without inventing a default classification.
    nonisolated static func fromWeatherSymbol(_ symbolName: String) -> AppWeatherCondition? {
        let symbol = symbolName.lowercased()

        if symbol.contains("drizzle") { return .drizzle }
        if symbol.contains("rain")
            || symbol.contains("thunderstorm")
            || symbol.contains("storm") {
            return .rain
        }
        if symbol.contains("snow")
            || symbol.contains("sleet")
            || symbol.contains("flurr") {
            return .snow
        }
        if symbol.contains("wind")
            || symbol.contains("hurricane")
            || symbol.contains("tropicalstorm") {
            return .wind
        }
        if symbol.contains("fog")
            || symbol.contains("haze")
            || symbol.contains("smoke") {
            return .fog
        }
        if symbol.contains("moon") {
            return symbol.contains("cloud") ? .partlyCloudy : .clear
        }
        if symbol.contains("cloud") && symbol.contains("sun") { return .partlySunny }
        if symbol.contains("sun.max") || symbol == "sun" || symbol == "sun.fill" {
            return .clear
        }
        if symbol.contains("partly") && symbol.contains("cloud") { return .partlyCloudy }
        if symbol.contains("cloud") { return .cloudy }
        return nil
    }

    /// Maps WeatherKit's semantic condition into the app's smaller presentation
    /// vocabulary. The source symbol remains available as a compatibility
    /// fallback, but is no longer the primary source for live forecasts.
    nonisolated static func fromWeatherKit(
        _ condition: WeatherKit.WeatherCondition,
        isDaylight: Bool? = nil
    ) -> AppWeatherCondition? {
        switch condition {
        case .clear, .mostlyClear:
            return .clear
        case .partlyCloudy:
            return isDaylight == true ? .partlySunny : .partlyCloudy
        case .cloudy, .mostlyCloudy:
            return .cloudy
        case .drizzle, .freezingDrizzle:
            return .drizzle
        case .rain, .heavyRain, .freezingRain, .sunShowers:
            return .rain
        case .blizzard, .blowingSnow, .flurries, .hail, .heavySnow,
                .sleet, .snow, .sunFlurries, .wintryMix:
            return .snow
        case .blowingDust, .foggy, .haze, .smoky:
            return .fog
        case .breezy, .windy:
            return .wind
        case .hurricane, .isolatedThunderstorms, .scatteredThunderstorms,
                .strongStorms, .thunderstorms, .tropicalStorm:
            return .rain
        case .frigid, .hot:
            // Temperature extremes don't describe the sky or precipitation.
            // Let the source symbol provide the presentation classification.
            return nil
        @unknown default:
            return nil
        }
    }

    /// Canonical SF Symbol used to display the normalized condition.
    var displayIcon: String {
        switch self {
        case .clear: return WeatherIconSymbol.clear
        case .partlySunny, .partlyCloudy: return WeatherIconSymbol.partlyCloudy
        case .cloudy: return WeatherIconSymbol.cloudy
        case .rain: return WeatherIconSymbol.rain
        case .drizzle: return WeatherIconSymbol.drizzle
        case .snow: return WeatherIconSymbol.snow
        case .fog: return WeatherIconSymbol.fog
        case .wind: return WeatherIconSymbol.wind
        }
    }
}
