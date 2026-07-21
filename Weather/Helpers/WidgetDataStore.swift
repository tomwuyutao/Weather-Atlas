//
//  WidgetDataStore.swift
//  Weather
//
//  Purpose: Persists the app/widget catalog and shared WeatherKit snapshots.
//

import Foundation
import WidgetKit

// MARK: - Shared Widget Persistence

enum WidgetDataStore {
    static let appGroupIdentifier = "group.Yutao-Wu.Weather"
    static let catalogKey = "bestSunnyPlacesWidgetCatalog"
    // Legacy WidgetKit kind retained for installed medium-widget continuity.
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

    static var appLocale: Locale {
        guard let identifier = catalog()?.appLanguageIdentifier, !identifier.isEmpty else {
            return .autoupdatingCurrent
        }
        return Locale(identifier: identifier)
    }

    static func save(_ catalog: WidgetDataCatalog) {
        guard let data = try? JSONEncoder().encode(catalog) else { return }
        UserDefaults(suiteName: appGroupIdentifier)?.set(data, forKey: catalogKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func weatherSnapshot(for cityID: String, now: Date = .now) -> WidgetWeatherSnapshot? {
        guard let snapshot = latestWeatherSnapshot(for: cityID),
              now.timeIntervalSince(snapshot.fetchedAt) < weatherCacheDuration else {
            return nil
        }
        return snapshot
    }

    /// Returns the last real WeatherKit result even when it is older than the
    /// normal widget freshness window. The provider can display it while asking
    /// WidgetKit for a short retry instead of replacing it with invented data.
    static func latestWeatherSnapshot(for cityID: String) -> WidgetWeatherSnapshot? {
        guard let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: weatherCacheKey(for: cityID)) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetWeatherSnapshot.self, from: data)
    }

    static func saveWeatherSnapshot(_ snapshot: WidgetWeatherSnapshot, for cityID: String) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: appGroupIdentifier)?.set(data, forKey: weatherCacheKey(for: cityID))
    }

    private static func weatherCacheKey(for cityID: String) -> String {
        "\(weatherCacheKeyPrefix)\(cityID)"
    }
}
