//
//  WidgetDataModels.swift
//  Weather
//
//  Purpose: Defines the Codable data contract shared by the app and widget extension.
//

import Foundation

// MARK: - Widget Weather Models

/// App-group city payload used for widget selection and current rendering.
struct WidgetDataCity: Codable, Hashable, Identifiable {
    /// Stable cross-process city identifier.
    let id: String
    /// Localized city label published by the main app.
    let cityName: String
    /// Timezone identifier required for local-day calculations.
    let timeZoneIdentifier: String?
    /// Optional latitude retained for deep links and diagnostics.
    let latitude: Double?
    /// Optional longitude retained for deep links and diagnostics.
    let longitude: Double?
    /// Daylight hours in the selected current-day forecast.
    let daytimeHours: [Int]
    /// Current-day hours classified as sunny.
    let sunnyHours: [Int]
    /// Current-day hours classified as partly sunny.
    let partlySunnyHours: [Int]
    /// Raw current WeatherKit symbol; absent data remains absent.
    var currentConditionSymbolName: String? = nil
    /// Current-day sunrise/sunset-derived chart bounds.
    var daylightBounds: SunnyHoursChartBounds? = nil
    /// Available rows for the large ten-day chart.
    var sunnyWindowDays: [WidgetSunnyWindowDay]? = nil
    /// Exact source issue that should replace widget weather content.
    var dataIssue: WeatherDataIssue? = nil
}

/// One available local-date row in the large widget timeline.
struct WidgetSunnyWindowDay: Codable, Hashable, Identifiable {
    /// Literal selection date represented by this row.
    let date: Date
    /// Fully sunny hours for the day.
    let sunnyHours: [Int]
    /// Partly sunny hours for the day.
    let partlySunnyHours: [Int]
    /// Real daylight domain for the row.
    var daylightBounds: SunnyHoursChartBounds? = nil
    /// Data issue replacing this row's chart content, when present.
    var dataIssue: WeatherDataIssue? = nil

    /// Uses the literal local date as row identity.
    var id: Date { date }
}

/// Timestamped per-city cache used when WidgetKit runs between app launches.
struct WidgetWeatherSnapshot: Codable, Hashable {
    /// Main-app fetch time used to enforce snapshot freshness.
    let fetchedAt: Date
    /// City timezone copied from the catalog at fetch time.
    let timeZoneIdentifier: String?
    /// Cached current-condition source symbol.
    var currentConditionSymbolName: String? = nil
    /// Cached current-day daylight hours.
    let daytimeHours: [Int]
    /// Cached current-day sunny hours.
    let sunnyHours: [Int]
    /// Cached current-day partly-sunny hours.
    let partlySunnyHours: [Int]
    /// Cached current-day chart bounds.
    var daylightBounds: SunnyHoursChartBounds? = nil
    /// Cached available ten-day chart rows.
    var sunnyWindowDays: [WidgetSunnyWindowDay]? = nil
    /// Cached precise missing-data issue.
    var dataIssue: WeatherDataIssue? = nil
}

extension WidgetWeatherSnapshot {
    /// Copies weather-bearing fields from a published city catalog entry.
    init(fetchedAt: Date, city: WidgetDataCity) {
        self.init(
            fetchedAt: fetchedAt,
            timeZoneIdentifier: city.timeZoneIdentifier,
            currentConditionSymbolName: city.currentConditionSymbolName,
            daytimeHours: city.daytimeHours,
            sunnyHours: city.sunnyHours,
            partlySunnyHours: city.partlySunnyHours,
            daylightBounds: city.daylightBounds,
            sunnyWindowDays: city.sunnyWindowDays,
            dataIssue: city.dataIssue
        )
    }
}

// MARK: - Widget Catalog Models

/// Widget-selectable saved list and its published city options.
struct WidgetDataList: Codable, Hashable, Identifiable {
    /// Stable raw `CityListID` value.
    let id: String
    /// User-facing saved or canonical list name.
    let displayName: String
    /// Cities currently configured in this list.
    let cities: [WidgetDataCity]
}

/// Top-level app-group catalog read by App Intents and widget timelines.
struct WidgetDataCatalog: Codable, Hashable {
    /// All widget-selectable saved lists.
    let lists: [WidgetDataList]
    /// Main-app language used for widget localization consistency.
    var appLanguageIdentifier: String? = nil
    /// Widget-only copy resolved by the localized main app before publication.
    ///
    /// Keeping this optional preserves decoding of catalogs written by earlier
    /// app versions whose widget target did not contain localization resources.
    var localizedStrings: [String: String]? = nil
}
