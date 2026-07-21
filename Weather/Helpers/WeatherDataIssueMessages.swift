//
//  WeatherDataIssueMessages.swift
//  Weather
//
//  Purpose: Converts structured weather-data issues into localized,
//  city-specific messages for alerts and notices.
//

import Foundation

// MARK: - Localized Issue Messages

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
    case .missingCloudCoverData:
        return String(
            format: localizedString("Missing cloud-cover data for %@.", locale: locale),
            locale: locale,
            cityName
        )
    case .missingPrecipitationData:
        return String(
            format: localizedString("Missing precipitation data for %@.", locale: locale),
            locale: locale,
            cityName
        )
    case .missingUVIndexData:
        return String(
            format: localizedString("Missing UV-index data for %@.", locale: locale),
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

