//
//  WeatherCondition.swift
//  Weather
//
//  Purpose: Defines the app's normalized weather-condition domain model and
//  its localized/icon/color presentation mappings.
//

import SwiftUI

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

    func dotColor(for theme: ThemeColors) -> Color {
        switch self {
        case .clear: return theme.dotSun
        case .partlySunny: return theme.dotPartlyCloudy
        case .partlyCloudy: return theme.dotCloudy
        case .cloudy: return theme.dotCloudy
        case .rain: return theme.dotRain
        case .drizzle: return theme.dotDrizzle
        case .snow: return theme.dotSnow
        case .fog: return theme.dotFog
        case .wind: return theme.dotWind
        }
    }

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

    var isSunny: Bool {
        self == .clear
    }

    var isSunnyOrPartlySunny: Bool {
        self == .clear || self == .partlySunny
    }

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
