//
//  WidgetForecastStore.swift
//  WeatherWidgets
//
//  Purpose: Keeps WeatherKit snapshots private to the widget extension.
//
//  The main app publishes only a small App Group catalog of configured cities.
//  This store uses the extension's own UserDefaults container, so forecast
//  retrieval, replacement, and recovery remain entirely widget-owned.
//

import Foundation

// MARK: - Persisted Forecast Snapshot

/// Timestamped per-city forecast value owned and persisted only by WeatherWidgets.
/// It stays outside the App Group catalog, so the host app cannot seed, replace,
/// or invalidate a widget forecast.
struct WidgetWeatherSnapshot: Codable, Hashable {
    /// The app-group reset generation current when this forecast was fetched.
    /// A mismatch means the person cleared app data after this snapshot was
    /// written, so the extension must not reuse it as a fallback.
    var resetEpoch: String? = nil
    /// Widget-extension WeatherKit fetch time used to enforce cache freshness.
    let fetchedAt: Date
    /// Destination-local calendar day represented by current-day fields.
    let representedLocalDate: Date?
    /// Time zone resolved from the selected city at fetch time.
    let timeZoneIdentifier: String?
    /// Coordinate paired with this direct WeatherKit response.
    var latitude: Double? = nil
    /// Longitude paired with `latitude` for cache identity validation.
    var longitude: Double? = nil
    /// Exact current WeatherKit condition and its source SF Symbol.
    var currentWeather: WidgetWeatherPresentation? = nil
    /// Detailed current-day conditions used by the shared chart renderer.
    var hourlyConditions: [WidgetHourlyCondition]? = nil
    /// Direct WeatherKit rows for the large widget's upcoming-day chart.
    var sunnyWindowDays: [WidgetSunnyWindowDay]? = nil
    /// Snapshot issue metadata, retained only when usable source data exists.
    var dataIssue: WeatherDataIssue? = nil

    /// Snapshots written before widgets persisted source symbols and raw API
    /// conditions must refresh instead of having an icon or condition guessed.
    var hasDirectWeatherPresentation: Bool {
        guard currentWeather != nil,
              let hourlyConditions,
              let sunnyWindowDays else {
            return false
        }
        return hourlyConditions.allSatisfy { $0.weather != nil }
            && sunnyWindowDays.allSatisfy { day in
                guard let hours = day.hourlyConditions else { return false }
                return hours.allSatisfy { $0.weather != nil }
            }
    }
}

// MARK: - Extension-Private Forecast Cache

/// Widget-extension-only persistence for the last successful forecast per city.
/// WidgetKit can terminate and relaunch this extension between timeline calls,
/// so its private defaults provide the durable boundary for direct WeatherKit
/// fetches without involving the host app or the App Group catalog.
enum WidgetForecastStore {
    // MARK: - Cache Policy

    /// Prefix keeps widget forecast values separate from any extension settings.
    /// Versioned when the persisted sunny-hour semantics change, so widgets
    /// never reuse a snapshot that merged `.mostlyClear` into clear sunshine.
    private static let cacheKeyPrefix = "widgetForecastSnapshot.v2."
    /// Normal timeline freshness before a direct WidgetKit refresh is due.
    private static let freshCacheDuration: TimeInterval = 30 * 60
    /// A failed refresh can reuse the last successful response for the same
    /// 24-hour retention window as the main app's offline forecast cache.
    private static let maximumRetentionInterval: TimeInterval = 24 * 60 * 60

    // MARK: - Snapshot Reads

    /// Returns a current-local-day snapshot within the normal freshness target.
    static func freshSnapshot(
        for cityID: String,
        now: Date = .now
    ) -> WidgetWeatherSnapshot? {
        guard let snapshot = retainedSnapshot(for: cityID, now: now),
              representsCurrentLocalDay(snapshot, now: now) else {
            return nil
        }
        let age = now.timeIntervalSince(snapshot.fetchedAt)
        guard age < freshCacheDuration else {
            return nil
        }
        return snapshot
    }

    /// Returns the extension's last successful response after a direct request
    /// fails. Unlike the normal freshness path, offline fallback may cross local
    /// midnight; exact forecast dates remain in the snapshot and the hard
    /// 24-hour age limit prevents indefinite stale presentation.
    static func fallbackSnapshot(
        for cityID: String,
        now: Date = .now
    ) -> WidgetWeatherSnapshot? {
        retainedSnapshot(for: cityID, now: now)
    }

    // MARK: - Snapshot Writes

    /// Writes only a successful widget-owned WeatherKit response.
    static func save(_ snapshot: WidgetWeatherSnapshot, for cityID: String) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            UserDefaults.standard.removeObject(forKey: cacheKey(for: cityID))
            return
        }
        UserDefaults.standard.set(data, forKey: cacheKey(for: cityID))
    }

    // MARK: - Private Validation

    /// Restores a complete last-known-good response while enforcing the same
    /// hard 24-hour retention limit as the main app. Invalid or expired entries
    /// are deleted lazily on access so extension storage cannot accumulate
    /// unusable weather indefinitely.
    private static func retainedSnapshot(
        for cityID: String,
        now: Date
    ) -> WidgetWeatherSnapshot? {
        let key = cacheKey(for: cityID)
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }

        guard let snapshot = try? JSONDecoder().decode(
            WidgetWeatherSnapshot.self,
            from: data
        ) else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }

        let age = now.timeIntervalSince(snapshot.fetchedAt)
        guard snapshot.resetEpoch == WidgetResetEpoch.current,
              snapshot.hasDirectWeatherPresentation,
              snapshot.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) != nil,
              snapshot.representedLocalDate != nil,
              age >= 0,
              age < maximumRetentionInterval else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }

        return snapshot
    }

    /// Normal 30-minute reuse still requires the snapshot's destination-local
    /// day to be current. Crossing midnight therefore requests new WeatherKit
    /// data first, then falls back to the retained response only if that fails.
    private static func representsCurrentLocalDay(
        _ snapshot: WidgetWeatherSnapshot,
        now: Date
    ) -> Bool {
        guard let timeZoneIdentifier = snapshot.timeZoneIdentifier,
              let timeZone = TimeZone(identifier: timeZoneIdentifier),
              let representedLocalDate = snapshot.representedLocalDate else {
            return false
        }
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar.isDate(representedLocalDate, inSameDayAs: now)
    }

    private static func cacheKey(for cityID: String) -> String {
        "\(cacheKeyPrefix)\(cityID)"
    }
}
