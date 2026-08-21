//
//  WeatherDataValidation.swift
//  Weather
//
//  Purpose: Defines typed missing/invalid weather-data results.
//
//  Reading guide: instead of silently inventing a weather value when WeatherKit
//  omits a field, this type carries a precise, persistable reason that a card or
//  widget should show an unavailable state.
//

import Foundation

// MARK: - Shared Weather Data Validation

/// A missing input that makes weather-derived content unsafe to display.
/// These states are persisted with widget snapshots so the extension never
/// replaces absent source data with plausible-looking hours or conditions.
/// `Error` lets asynchronous validation throw it, while `Codable` and `Hashable`
/// let app and widget snapshots store and compare the same explanation.
struct WeatherDataIssue: Error, Codable, Hashable {
    // MARK: - Issue Categories

    /// Stable issue categories shared by the app, cache, and widget extension.
    enum Kind: String, Codable, Hashable {
        case weatherRequestFailed
        case unresolvedPlace
        case missingSunriseOrSunset
        case missingSunriseData
        case missingSunsetData
        case missingHourlyData
        case missingForecastData
        case missingTimeZone
        case missingConditionData
        case missingTemperatureData
        case missingApparentTemperatureData
        case missingCloudCoverData
        case missingPrecipitationChanceData
        case missingVisibilityData
        case missingUVIndexData
        case unknownWeatherSymbol
        case invalidWeatherValue
    }

    // MARK: - Stored Context

    /// Machine-readable category used to choose localized user-facing copy.
    let kind: Kind
    /// Optional source detail, such as an unrecognized WeatherKit symbol.
    let detail: String?
    /// Forecast day or hourly instant affected by the issue, when known.
    /// Keeping the date structured lets presentation consolidate issues by day
    /// without parsing diagnostic text.
    let forecastDate: Date?

    /// Creates a structured issue. The default date preserves source
    /// compatibility for widget URLs and older call sites that only carry a kind
    /// and diagnostic detail.
    init(
        kind: Kind,
        detail: String? = nil,
        forecastDate: Date? = nil
    ) {
        self.kind = kind
        self.detail = detail
        self.forecastDate = forecastDate
    }

    // MARK: - Common Predefined Issues

    // Shared constants prevent call sites from repeating a category/detail pair
    // whenever the reason has no additional source-specific information.

    /// Both solar events needed to define daylight are absent.
    static let missingSunriseOrSunset = WeatherDataIssue(
        kind: .missingSunriseOrSunset,
        detail: nil,
        forecastDate: nil
    )
    /// No daily forecast exists for the requested city and literal date.
    static let missingForecastData = WeatherDataIssue(
        kind: .missingForecastData,
        detail: nil,
        forecastDate: nil
    )
    /// Place resolution did not supply a usable timezone.
    static let missingTimeZone = WeatherDataIssue(
        kind: .missingTimeZone,
        detail: nil,
        forecastDate: nil
    )

    // MARK: - Contextual Issue Factories

    /// Preserves an unknown source symbol rather than coercing it to cloudy.
    /// The detail is diagnostic data, not user-facing localized text.
    static func unknownWeatherSymbol(
        _ symbolName: String,
        at forecastDate: Date? = nil
    ) -> WeatherDataIssue {
        WeatherDataIssue(
            kind: .unknownWeatherSymbol,
            detail: symbolName,
            forecastDate: forecastDate
        )
    }

    /// A WeatherKit request failed after the one permitted retry.
    static func weatherRequestFailed(_ detail: String? = nil) -> WeatherDataIssue {
        WeatherDataIssue(kind: .weatherRequestFailed, detail: detail)
    }

    /// Place metadata could not be resolved well enough to request weather.
    static func unresolvedPlace(_ detail: String? = nil) -> WeatherDataIssue {
        WeatherDataIssue(kind: .unresolvedPlace, detail: detail)
    }

    /// No daily record matches the requested literal forecast date.
    static func missingForecastData(at date: Date?) -> WeatherDataIssue {
        WeatherDataIssue(kind: .missingForecastData, forecastDate: date)
    }

    /// No hourly source records exist for the affected daily forecast.
    static func missingHourlyData(at date: Date?) -> WeatherDataIssue {
        WeatherDataIssue(kind: .missingHourlyData, forecastDate: date)
    }

    /// Creates a field-specific missing-value issue without converting the
    /// absence into a numeric zero or generic condition.
    static func missing(
        _ kind: Kind,
        at date: Date?
    ) -> WeatherDataIssue {
        WeatherDataIssue(kind: kind, forecastDate: date)
    }

    /// Preserves malformed source/cache values for diagnostics while ensuring
    /// they are never promoted into presentation as valid readings.
    static func invalidValue(
        _ detail: String,
        at date: Date? = nil
    ) -> WeatherDataIssue {
        WeatherDataIssue(
            kind: .invalidWeatherValue,
            detail: detail,
            forecastDate: date
        )
    }

    /// Removes duplicate issue category/context pairs without reordering the
    /// source diagnostics. Validation and ranking share this one rule so a
    /// missing field produces one truthful state rather than duplicate alerts.
    static func deduplicated(
        _ issues: [WeatherDataIssue]
    ) -> [WeatherDataIssue] {
        var seen: Set<WeatherDataIssue> = []
        return issues.filter { seen.insert($0).inserted }
    }

}
