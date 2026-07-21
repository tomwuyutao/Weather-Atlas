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
struct WeatherDataIssue: Error, Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case missingSunriseOrSunset
        case missingSunriseData
        case missingSunsetData
        case missingHourlyData
        case missingForecastData
        case missingCloudCoverData
        case missingPrecipitationData
        case missingUVIndexData
        case missingTimeZone
        case unknownWeatherSymbol
    }

    let kind: Kind
    let detail: String?

    static let missingSunriseOrSunset = WeatherDataIssue(
        kind: .missingSunriseOrSunset,
        detail: nil
    )
    static let missingSunriseData = WeatherDataIssue(
        kind: .missingSunriseData,
        detail: nil
    )
    static let missingSunsetData = WeatherDataIssue(
        kind: .missingSunsetData,
        detail: nil
    )
    static let missingHourlyData = WeatherDataIssue(
        kind: .missingHourlyData,
        detail: nil
    )
    static let missingForecastData = WeatherDataIssue(
        kind: .missingForecastData,
        detail: nil
    )
    static let missingCloudCoverData = WeatherDataIssue(
        kind: .missingCloudCoverData,
        detail: nil
    )
    static let missingPrecipitationData = WeatherDataIssue(
        kind: .missingPrecipitationData,
        detail: nil
    )
    static let missingUVIndexData = WeatherDataIssue(
        kind: .missingUVIndexData,
        detail: nil
    )
    static let missingTimeZone = WeatherDataIssue(
        kind: .missingTimeZone,
        detail: nil
    )

    static func unknownWeatherSymbol(_ symbolName: String) -> WeatherDataIssue {
        WeatherDataIssue(kind: .unknownWeatherSymbol, detail: symbolName)
    }

    /// Names the absent solar event when WeatherKit supplies only one side of
    /// the daylight interval. The combined case is reserved for both missing.
    static func missingSunEvent(sunrise: Date?, sunset: Date?) -> WeatherDataIssue? {
        switch (sunrise, sunset) {
        case (nil, nil): .missingSunriseOrSunset
        case (nil, _): .missingSunriseData
        case (_, nil): .missingSunsetData
        case (.some, .some): nil
        }
    }
}
