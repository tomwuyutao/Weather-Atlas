//
//  WeatherSymbols.swift
//  Weather
//
//  Purpose: Defines canonical weather symbols and classifies WeatherKit symbols.
//

import Foundation

// MARK: - Shared Weather Symbols

/// Canonical SF Symbols for weather conditions, shared by the app and widgets.
enum WeatherIconSymbol {
    static let clear = "sun.max.fill"
    static let partlyCloudy = "cloud.sun"
    static let cloudy = "cloud"
    static let rain = "cloud.rain"
    static let drizzle = "cloud.drizzle"
    static let snow = "cloud.snow"
    static let fog = "cloud.fog"
    static let wind = "wind"
}

// MARK: - Symbol Classification

/// Recognizes every condition family used by the app and widget. An unknown
/// symbol stays unknown so callers can stop rendering dependent content.
enum WeatherSymbolClassification {
    case clear
    case partlySunny
    case partlyCloudy
    case cloudy
    case rain
    case drizzle
    case snow
    case fog
    case wind

    static func resolve(_ symbolName: String) -> WeatherSymbolClassification? {
        let symbol = symbolName.lowercased()

        if symbol.contains("drizzle") { return .drizzle }
        if symbol.contains("rain") || symbol.contains("thunderstorm") || symbol.contains("storm") { return .rain }
        if symbol.contains("snow") || symbol.contains("sleet") || symbol.contains("flurr") { return .snow }
        if symbol.contains("wind") || symbol.contains("hurricane") || symbol.contains("tropicalstorm") { return .wind }
        if symbol.contains("fog") || symbol.contains("haze") || symbol.contains("smoke") { return .fog }
        // WeatherKit can use moon variants for the same underlying clear or
        // partly-cloudy condition. This app presents daytime forecasts only,
        // so normalize those inputs to the equivalent daytime condition.
        if symbol.contains("moon") {
            return symbol.contains("cloud") ? .partlyCloudy : .clear
        }
        if symbol.contains("cloud") && symbol.contains("sun") { return .partlySunny }
        if symbol.contains("sun.max") || symbol == "sun" || symbol == "sun.fill" { return .clear }
        if symbol.contains("partly") && symbol.contains("cloud") { return .partlyCloudy }
        if symbol.contains("cloud") { return .cloudy }
        return nil
    }
}
