//
//  WidgetDataStore.swift
//  Weather
//
//  Purpose: Shares city weather data with the WidgetKit extension.
//

import Foundation
import WidgetKit

struct WidgetDataCity: Codable, Hashable, Identifiable {
    let id: String
    let cityName: String
    let timeZoneIdentifier: String?
    let latitude: Double?
    let longitude: Double?
    let daytimeHours: [Int]
    let sunnyHours: [Int]
    let partlySunnyHours: [Int]
}

struct WidgetWeatherSnapshot: Codable, Hashable {
    let fetchedAt: Date
    let timeZoneIdentifier: String?
    let daytimeHours: [Int]
    let sunnyHours: [Int]
    let partlySunnyHours: [Int]
}

struct WidgetDataList: Codable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let cities: [WidgetDataCity]
}

struct WidgetDataCatalog: Codable, Hashable {
    let lists: [WidgetDataList]
}

enum WidgetDataStore {
    static let appGroupIdentifier = "group.Yutao-Wu.Weather"
    static let catalogKey = "bestSunnyPlacesWidgetCatalog"
    static let kind = "BestSunnyPlacesWidget"
    static let weatherCacheKeyPrefix = "widgetWeatherSnapshot."
    static let weatherCacheDuration: TimeInterval = 30 * 60

    static func cityIdentifier(country: String, latitude: Double, longitude: Double, listID: String) -> String {
        let latitude = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), latitude)
        let longitude = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), longitude)
        return "\(listID)|\(country)|\(latitude)|\(longitude)"
    }

    static func catalog() -> WidgetDataCatalog? {
        guard let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: catalogKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetDataCatalog.self, from: data)
    }

    static func save(_ catalog: WidgetDataCatalog) {
        guard let data = try? JSONEncoder().encode(catalog) else { return }
        UserDefaults(suiteName: appGroupIdentifier)?.set(data, forKey: catalogKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func weatherSnapshot(for cityID: String, now: Date = .now) -> WidgetWeatherSnapshot? {
        guard let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: weatherCacheKey(for: cityID)),
              let snapshot = try? JSONDecoder().decode(WidgetWeatherSnapshot.self, from: data),
              now.timeIntervalSince(snapshot.fetchedAt) < weatherCacheDuration else {
            return nil
        }
        return snapshot
    }

    static func saveWeatherSnapshot(_ snapshot: WidgetWeatherSnapshot, for cityID: String) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: appGroupIdentifier)?.set(data, forKey: weatherCacheKey(for: cityID))
    }

    private static func weatherCacheKey(for cityID: String) -> String {
        "\(weatherCacheKeyPrefix)\(cityID)"
    }
}
