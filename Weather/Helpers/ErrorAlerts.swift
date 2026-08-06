//
//  ErrorAlerts.swift
//  Weather
//
//  Purpose: Defines developer diagnostics, localized weather-data issue
//  messages, and the compact notice for expected forecast omissions.
//

import Foundation

// MARK: - Developer Diagnostics

/// Debug-only reporting for internal catalog and geocoder invariants.
enum DeveloperDiagnostics {
    /// Logs implementation diagnostics without exposing them as user alerts.
    static func show(title: String, message: String) {
        #if DEBUG
        print("[DeveloperWarning] \(title): \(message)")
        #endif
    }
}

// MARK: - Localized Issue Messages

/// Builds localized, city-specific native-alert copy for an exact data issue.
func weatherDataIssueMessage(
    _ issue: WeatherDataIssue,
    cityName: String,
    locale: Locale
) -> String {
    switch issue.kind {
    case .missingSunriseOrSunset:
        return String(
            format: localizedString("Missing sunrise or sunset data for %@.", locale: locale),
            locale: locale,
            cityName
        )
    case .missingSunriseData:
        return String(
            format: localizedString("Missing sunrise data for %@.", locale: locale),
            locale: locale,
            cityName
        )
    case .missingSunsetData:
        return String(
            format: localizedString("Missing sunset data for %@.", locale: locale),
            locale: locale,
            cityName
        )
    case .missingHourlyData:
        return String(
            format: localizedString("Missing hourly data for %@.", locale: locale),
            locale: locale,
            cityName
        )
    case .missingForecastData:
        return String(
            format: localizedString("Missing weather data for %@.", locale: locale),
            locale: locale,
            cityName
        )
    case .missingTimeZone:
        return String(
            format: localizedString("Missing time zone for %@.", locale: locale),
            locale: locale,
            cityName
        )
    case .unknownWeatherSymbol:
        let symbol = issue.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let symbol, !symbol.isEmpty {
            return String(
                format: localizedString("Unknown weather symbol \"%@\" for %@.", locale: locale),
                locale: locale,
                symbol,
                cityName
            )
        }
        return String(
            format: localizedString("Missing weather symbol for %@.", locale: locale),
            locale: locale,
            cityName
        )
    }
}
