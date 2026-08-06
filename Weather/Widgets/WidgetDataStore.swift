//
//  WidgetDataStore.swift
//  Weather
//
//  Purpose: Persists app-owned city identity and widget-owned weather snapshots.
//

import Foundation
import WidgetKit

// MARK: - Shared Widget Persistence

/// Codable app-group persistence shared by the main app and widget extension.
enum WidgetDataStore {
    /// Entitlement-backed application group identifier.
    static let appGroupIdentifier = "group.Yutao-Wu.Weather"
    /// Preference key containing app-owned widget selection metadata.
    static let catalogKey = "bestSunnyPlacesWidgetCatalog"
    /// WidgetKit kind for the unified Home Screen widget.
    static let kind = "BestSunnyPlacesWidget"
    /// Prefix for widget-owned timestamped per-city weather snapshots.
    static let weatherCacheKeyPrefix = "widgetWeatherSnapshot."
    /// Maximum accepted age of a normal widget weather snapshot.
    static let weatherCacheDuration: TimeInterval = 30 * 60

    /// Builds a stable identifier from scope identity and normalized coordinates.
    static func cityIdentifier(country: String, latitude: Double, longitude: Double, scopeID: String) -> String {
        let latitude = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), latitude)
        let longitude = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), longitude)
        return "\(scopeID)|\(country)|\(latitude)|\(longitude)"
    }

    /// Decodes the current cross-process widget catalog.
    static func catalog() -> WidgetDataCatalog? {
        guard let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: catalogKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetDataCatalog.self, from: data)
    }

    /// Locale published by the app, or system locale before first publication.
    static var appLocale: Locale {
        guard let identifier = catalog()?.appLanguageIdentifier,
              !identifier.isEmpty else {
            return .autoupdatingCurrent
        }
        return Locale(identifier: identifier)
    }

    /// Returns copy localized by the main app, falling back before publication.
    static func localizedText(for key: String) -> String {
        catalog()?.localizedStrings[key] ?? key
    }

    /// Encodes the catalog and requests WidgetKit timeline reloads.
    static func save(_ catalog: WidgetDataCatalog) {
        var publishedCatalog = catalog
        let locale = catalog.appLanguageIdentifier.isEmpty
            ? Locale.autoupdatingCurrent
            : Locale(identifier: catalog.appLanguageIdentifier)
        publishedCatalog.localizedStrings = localizedWidgetStrings(locale: locale)

        guard let data = try? JSONEncoder().encode(publishedCatalog) else { return }
        UserDefaults(suiteName: appGroupIdentifier)?.set(data, forKey: catalogKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Clears app-group widget metadata and snapshots during a full app reset.
    static func removeAll() {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Returns a fresh city snapshot, rejecting stale or corrupt payloads.
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

    /// Persists the widget extension's last-known-good snapshot for one city.
    static func saveWeatherSnapshot(_ snapshot: WidgetWeatherSnapshot, for cityID: String) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: appGroupIdentifier)?.set(data, forKey: weatherCacheKey(for: cityID))
    }

    /// Produces the namespaced preference key for one city snapshot.
    private static func weatherCacheKey(for cityID: String) -> String {
        "\(weatherCacheKeyPrefix)\(cityID)"
    }

    /// Resolves the small amount of copy owned by the widget extension while
    /// the main app's String Catalog and selected locale are available.
    private static func localizedWidgetStrings(locale: Locale) -> [String: String] {
        [
            "Sunny Hours": localizedString("Sunny Hours", locale: locale),
            "Track sunny hours for a chosen city.": localizedString(
                "Track sunny hours for a chosen city.",
                locale: locale
            ),
            "Track sunny daytime hours for a chosen city.": localizedString(
                "Track sunny daytime hours for a chosen city.",
                locale: locale
            ),
            "Today": localizedString("Today", locale: locale),
            "Sunny": localizedString("Sunny", locale: locale),
            "Partly Sunny": localizedString("Partly Sunny", locale: locale),
            "No Sun": localizedString("No Sun", locale: locale),
            "Open Weather Atlas to refresh.": localizedString(
                "Open Weather Atlas to refresh.",
                locale: locale
            )
        ]
    }
}
