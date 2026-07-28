//
//  ErrorAlerts.swift
//  Weather
//
//  Purpose: Defines queued error alerts, localized weather-data issue messages,
//  and the compact notice for expected forecast omissions.
//

import Foundation
import SwiftUI

// MARK: - Warning Model

/// Native-alert payload for actionable missing or inconsistent app data.
struct DeveloperWarning: Identifiable, Equatable {
    /// Presentation identity allowing repeated messages to remain distinct.
    let id = UUID()
    /// Short native alert title.
    let title: String
    /// Specific description of the missing or inconsistent data.
    let message: String
}

// MARK: - Warning Delivery

/// Process-wide bridge from services and helpers to the root native alert queue.
enum DeveloperWarningCenter {
    /// Notification observed by the root `ContentView`.
    static let notification = Notification.Name("WeatherAtlasDeveloperWarning")
    /// Deduplication keys already emitted by `showOnce` in this process.
    @MainActor private static var reportedKeys: Set<String> = []

    /// Enqueues a warning on the main actor from any calling context.
    static func show(title: String, message: String) {
        Task { @MainActor in
            post(title: title, message: message)
        }
    }

    /// Routes missing source data through the same queued system alert used by
    /// developer warnings, with a title localized for the selected app language.
    static func showMissingData(message: String, locale: Locale) {
        show(
            title: localizedString("Weather Data Missing", locale: locale),
            message: message
        )
    }

    /// Emits one warning per process for a stable diagnostic key.
    static func showOnce(key: String, title: String, message: String) {
        Task { @MainActor in
            guard reportedKeys.insert(key).inserted else { return }
            post(title: title, message: message)
        }
    }

    @MainActor
    /// Posts the notification payload consumed by the app shell.
    private static func post(title: String, message: String) {
        #if DEBUG
        print("[DeveloperWarning] \(title): \(message)")
        #endif

        NotificationCenter.default.post(
            name: notification,
            object: DeveloperWarning(
                title: title,
                message: message
            )
        )
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
