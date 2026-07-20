//
//  ErrorAlert.swift
//  Weather
//
//  Purpose: Routes unexpected data-integrity failures to one visible alert
//  instead of silently replacing missing values with fallbacks.

import Foundation
import SwiftUI

// MARK: - Warning Model

struct DeveloperWarning: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - Warning Delivery

enum DeveloperWarningCenter {
    static let notification = Notification.Name("WeatherAtlasDeveloperWarning")
    @MainActor private static var reportedKeys: Set<String> = []
    @MainActor private static var recentAutomaticMissingDataReports: [String: Date] = [:]
    private static let automaticMissingDataDeduplicationInterval: TimeInterval = 30

    static func show(title: String, message: String) {
        Task { @MainActor in
            post(title: title, message: message)
        }
    }

    /// Routes every missing-data state through the same system alert. Callers
    /// must remove the dependent weather content before reporting the issue.
    static func showMissingData(message: String, locale: Locale) {
        show(
            title: localizedString("Weather Data Missing", locale: locale),
            message: message
        )
    }

    /// Prevents the same automatic notice from firing again when SwiftUI
    /// replaces an unsaved search result with its saved-city detail view. A
    /// deliberate user action still calls `showMissingData` and always alerts.
    static func showAutomaticMissingData(message: String, locale: Locale) {
        Task { @MainActor in
            let now = Date()
            if let lastReport = recentAutomaticMissingDataReports[message],
               now.timeIntervalSince(lastReport) < automaticMissingDataDeduplicationInterval {
                return
            }
            recentAutomaticMissingDataReports[message] = now
            recentAutomaticMissingDataReports = recentAutomaticMissingDataReports.filter {
                now.timeIntervalSince($0.value) < automaticMissingDataDeduplicationInterval
            }
            post(
                title: localizedString("Weather Data Missing", locale: locale),
                message: message
            )
        }
    }

    static func showOnce(key: String, title: String, message: String) {
        Task { @MainActor in
            guard reportedKeys.insert(key).inserted else { return }
            post(title: title, message: message)
        }
    }

    @MainActor
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

// MARK: - Missing Weather Data Presentation

/// Reports missing weather content through the app's queued native alert.
/// The dependent chart, metric, or condition must not render beside this view.
struct WeatherDataUnavailableNotice: View {
    let message: String

    @Environment(\.locale) private var locale
    @State private var hasReportedIssue = false

    var body: some View {
        Color.clear
            .frame(height: 1)
            .onAppear {
                guard !hasReportedIssue else { return }
                hasReportedIssue = true
                DeveloperWarningCenter.showAutomaticMissingData(message: message, locale: locale)
            }
            .onChange(of: message) { _, updatedMessage in
                DeveloperWarningCenter.showAutomaticMissingData(message: updatedMessage, locale: locale)
            }
            .onDisappear {
                // A later appearance represents a fresh attempt to render the
                // missing content, so it may report the still-current failure.
                hasReportedIssue = false
            }
    }
}

// MARK: - Expected Forecast Omissions

/// A compact informational box for cities omitted because the selected calendar
/// date sits outside the real forecast range WeatherKit returned for them.
/// Unlike a genuine missing-data failure, this range edge never opens an alert.
struct ForecastOmissionNotice: View {
    let droppedCityCount: Int

    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        let message = forecastOmissionMessage(
            droppedCityCount: droppedCityCount,
            locale: locale
        )

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.footnote.weight(.semibold))

            Text(message)
                .font(.footnote.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(theme.colors.secondaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedGlass(in: .rect(cornerRadius: 16))
    }
}

func forecastOmissionMessage(droppedCityCount: Int, locale: Locale) -> String {
    if droppedCityCount == 1 {
        return localizedString("1 city is dropped due to missing data.", locale: locale)
    }
    return String(
        format: localizedString("%lld cities are dropped due to missing data.", locale: locale),
        locale: locale,
        droppedCityCount
    )
}

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
