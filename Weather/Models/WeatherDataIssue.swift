//
//  WeatherDataIssue.swift
//  Weather
//
//  Purpose: Describes missing or invalid source data that prevents honest weather output.
//

import Foundation

// MARK: - Shared Weather Data Validation

/// A missing input that makes weather-derived content unsafe to display.
/// These states are persisted with widget snapshots so the extension never
/// replaces absent source data with plausible-looking hours or conditions.
/// Typed explanation for source data that is absent or cannot be interpreted.
struct WeatherDataIssue: Error, Codable, Hashable {
    /// Stable issue categories shared by the app, cache, and widget extension.
    enum Kind: String, Codable, Hashable {
        case missingSunriseOrSunset
        case missingSunriseData
        case missingSunsetData
        case missingHourlyData
        case missingForecastData
        case missingTimeZone
        case unknownWeatherSymbol
    }

    /// Machine-readable category used to choose localized user-facing copy.
    let kind: Kind
    /// Optional source detail, such as an unrecognized WeatherKit symbol.
    let detail: String?

    /// Both solar events needed to define daylight are absent.
    static let missingSunriseOrSunset = WeatherDataIssue(
        kind: .missingSunriseOrSunset,
        detail: nil
    )
    /// Sunrise is absent while another solar field may still exist.
    static let missingSunriseData = WeatherDataIssue(
        kind: .missingSunriseData,
        detail: nil
    )
    /// Sunset is absent while another solar field may still exist.
    static let missingSunsetData = WeatherDataIssue(
        kind: .missingSunsetData,
        detail: nil
    )
    /// No hourly forecasts are available for the requested daily forecast.
    static let missingHourlyData = WeatherDataIssue(
        kind: .missingHourlyData,
        detail: nil
    )
    /// No daily forecast exists for the requested city and literal date.
    static let missingForecastData = WeatherDataIssue(
        kind: .missingForecastData,
        detail: nil
    )
    /// Place resolution did not supply a usable timezone.
    static let missingTimeZone = WeatherDataIssue(
        kind: .missingTimeZone,
        detail: nil
    )

    /// Preserves an unknown source symbol rather than coercing it to cloudy.
    static func unknownWeatherSymbol(_ symbolName: String) -> WeatherDataIssue {
        WeatherDataIssue(kind: .unknownWeatherSymbol, detail: symbolName)
    }

    /// Names the absent solar event when WeatherKit supplies only one side of
    /// the daylight interval. The combined case is reserved for both missing.
    /// Identifies the exact absent solar event, returning `nil` when both exist.
    static func missingSunEvent(sunrise: Date?, sunset: Date?) -> WeatherDataIssue? {
        switch (sunrise, sunset) {
        case (nil, nil): .missingSunriseOrSunset
        case (nil, _): .missingSunriseData
        case (_, nil): .missingSunsetData
        case (.some, .some): nil
        }
    }
}
