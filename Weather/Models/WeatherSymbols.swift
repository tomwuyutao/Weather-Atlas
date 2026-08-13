//
//  WeatherSymbols.swift
//  Weather
//
//  Purpose: Defines canonical weather symbols and classifies WeatherKit symbols.
//
//  Reading guide: raw WeatherKit symbol names are input data and can evolve.
//  These two enums first normalize that input into the app's own condition
//  families, then provide one canonical SF Symbol for consistent rendering.
//

import Foundation

// MARK: - Shared Weather Symbols

/// Canonical SF Symbols used after successful WeatherKit classification.
/// Keeping string literals here prevents cards, maps, and widgets from quietly
/// drifting into different icons for the same app-level condition.
enum WeatherIconSymbol {
    /// Icon for clear conditions.
    static let clear = "sun.max.fill"
    /// Icon for partly cloudy or partly sunny conditions.
    static let partlyCloudy = "cloud.sun"
    /// Icon for overcast conditions.
    static let cloudy = "cloud"
    /// Icon for rain conditions.
    static let rain = "cloud.rain"
    /// Icon for drizzle conditions.
    static let drizzle = "cloud.drizzle"
    /// Icon for snow conditions.
    static let snow = "cloud.snow"
    /// Icon for fog or haze conditions.
    static let fog = "cloud.fog"
    /// Icon for windy conditions.
    static let wind = "wind"
}

// MARK: - Symbol Classification

/// Recognizes every condition family used by the app and widget. An unknown
/// symbol stays unknown so callers can stop rendering dependent content.
/// This enum mirrors the app's classification vocabulary without importing
/// WeatherKit, making it useful in shared code that only needs the category.
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

    /// Classifies a source symbol, returning `nil` when its meaning is unknown.
    /// Rules run from specific weather phenomena to broad visual families: for
    /// example, a rainy cloud must be rain before it reaches the cloud fallback.
    static func resolve(_ symbolName: String) -> WeatherSymbolClassification? {
        // Symbol names are strings, so normalize their case once before testing
        // standardized fragments rather than relying on exact spelling/casing.
        let symbol = symbolName.lowercased()

        // Precipitation and hazards take priority over sky-cover words that may
        // also appear in the same multi-part WeatherKit symbol name.
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
        // A simultaneous sun-and-cloud cue is the daytime partly-sunny case.
        if symbol.contains("cloud") && symbol.contains("sun") { return .partlySunny }
        if symbol.contains("sun.max") || symbol == "sun" || symbol == "sun.fill" { return .clear }
        if symbol.contains("partly") && symbol.contains("cloud") { return .partlyCloudy }
        if symbol.contains("cloud") { return .cloudy }
        // Do not guess a generic cloud condition. Callers can then surface a
        // truthful unavailable/unknown state and retain the original symbol.
        return nil
    }
}

// MARK: - Shared Symbol Tint

/// The small semantic color vocabulary shared by weather symbols and Map dots.
///
/// The app target can map a normalized `AppWeatherCondition` directly to one of
/// these tones, while the widget target can derive the same tone from a raw
/// WeatherKit symbol without importing the app-only condition model.
enum WeatherIconTone {
    case clear
    case partlySunny
    case cloudy
    case rain
    case drizzle

    /// Normalizes a raw WeatherKit symbol to the semantic tint used by its Map
    /// marker. Unknown symbols use the neutral cloudy tone rather than gaining
    /// an arbitrary accent color.
    init(symbolName: String) {
        switch WeatherSymbolClassification.resolve(symbolName) {
        case .clear:
            self = .clear
        case .partlySunny:
            self = .partlySunny
        case .rain:
            self = .rain
        case .drizzle:
            self = .drizzle
        case .partlyCloudy, .cloudy, .snow, .fog, .wind, nil:
            self = .cloudy
        }
    }
}
