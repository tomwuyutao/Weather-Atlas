//
//  WeatherSymbols.swift
//  Weather
//
//  Purpose: Defines canonical weather symbols and their semantic tint family.
//
//  Reading guide: raw WeatherKit symbol names are input data and can evolve.
//  `AppWeatherCondition` owns classification; this file only provides
//  presentation constants shared by the app and widget.
//

// MARK: - Shared Weather Symbols

/// Canonical SF Symbols used after successful WeatherKit classification.
/// Keeping string literals here prevents cards, maps, and widgets from quietly
/// drifting into different icons for the same app-level condition.
nonisolated enum WeatherIconSymbol {
    /// Icon for clear conditions.
    static let clear = "sun.max.fill"
    /// Gray cloud-and-sun icon for partly cloudy conditions.
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

// MARK: - Shared Symbol Tint

/// The small semantic color vocabulary shared by weather symbols and Map dots.
///
/// The app target can map a normalized `AppWeatherCondition` directly to one of
/// these tones, while the widget target can derive the same tone from a raw
/// WeatherKit symbol without importing the app-only condition model.
nonisolated enum WeatherIconTone: Sendable {
    case clear
    case partlySunny
    case cloudy
    case rain
    case drizzle

}
