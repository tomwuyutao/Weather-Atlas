//
//  WidgetDataModels.swift
//  Weather
//
//  Purpose: Defines the Codable data contract shared by the app and widget extension.
//

import Foundation

// MARK: - Widget Weather Models

struct WidgetDataCity: Codable, Hashable, Identifiable {
    let id: String
    let cityName: String
    let timeZoneIdentifier: String?
    let latitude: Double?
    let longitude: Double?
    let daytimeHours: [Int]
    let sunnyHours: [Int]
    let partlySunnyHours: [Int]
    var currentConditionSymbolName: String? = nil
    var daylightBounds: SunnyHoursChartBounds? = nil
    var sunnyWindowDays: [WidgetSunnyWindowDay]? = nil
    var dataIssue: WeatherDataIssue? = nil
}

struct WidgetSunnyWindowDay: Codable, Hashable, Identifiable {
    let date: Date
    let sunnyHours: [Int]
    let partlySunnyHours: [Int]
    var daylightBounds: SunnyHoursChartBounds? = nil
    var dataIssue: WeatherDataIssue? = nil

    var id: Date { date }
}

struct WidgetWeatherSnapshot: Codable, Hashable {
    let fetchedAt: Date
    let timeZoneIdentifier: String?
    var currentConditionSymbolName: String? = nil
    let daytimeHours: [Int]
    let sunnyHours: [Int]
    let partlySunnyHours: [Int]
    var daylightBounds: SunnyHoursChartBounds? = nil
    var sunnyWindowDays: [WidgetSunnyWindowDay]? = nil
    var dataIssue: WeatherDataIssue? = nil
}

extension WidgetWeatherSnapshot {
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

struct WidgetDataList: Codable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let cities: [WidgetDataCity]
}

struct WidgetDataCatalog: Codable, Hashable {
    let lists: [WidgetDataList]
    var appLanguageIdentifier: String? = nil
}
