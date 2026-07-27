//
//  WeatherCondition.swift
//  Weather
//
//  Purpose: Defines the app's normalized weather-condition domain model and
//  its localized/icon/color presentation mappings.
//

import SwiftUI

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
    var sunninessRank: Int {
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
    var isSunny: Bool {
        self == .clear
    }

    /// Whether this condition contributes to a favorable sunny window.
    var isSunnyOrPartlySunny: Bool {
        self == .clear || self == .partlySunny
    }

    /// Resolves a WeatherKit symbol without inventing a default classification.
    static func fromWeatherSymbol(_ symbolName: String) -> AppWeatherCondition? {
        guard let classification = WeatherSymbolClassification.resolve(symbolName) else {
            return nil
        }

        switch classification {
        case .clear: return .clear
        case .partlySunny: return .partlySunny
        case .partlyCloudy: return .partlyCloudy
        case .cloudy: return .cloudy
        case .rain: return .rain
        case .drizzle: return .drizzle
        case .snow: return .snow
        case .fog: return .fog
        case .wind: return .wind
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
