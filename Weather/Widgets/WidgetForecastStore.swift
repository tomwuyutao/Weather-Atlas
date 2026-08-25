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
    /// A direct request may fail temporarily. A same-day forecast remains useful
    /// for a short recovery window while WidgetKit schedules the next retry.
    private static let fallbackCacheDuration: TimeInterval = 2 * 60 * 60

    // MARK: - Snapshot Reads

    /// Returns a current-local-day snapshot within the normal freshness target.
    static func freshSnapshot(
        for cityID: String,
        now: Date = .now
    ) -> WidgetWeatherSnapshot? {
        guard let snapshot = currentLocalDaySnapshot(for: cityID, now: now) else {
            return nil
        }
        let age = now.timeIntervalSince(snapshot.fetchedAt)
        guard snapshot.hasDirectWeatherPresentation,
              age >= 0,
              age < freshCacheDuration else {
            return nil
        }
        return snapshot
    }

    /// Returns the extension's own most recent same-day weather after a direct
    /// request fails. It is intentionally more conservative than an unbounded
    /// offline cache, yet prevents a transient WeatherKit failure from erasing
    /// an otherwise useful widget.
    static func fallbackSnapshot(
        for cityID: String,
        now: Date = .now
    ) -> WidgetWeatherSnapshot? {
        guard let snapshot = currentLocalDaySnapshot(for: cityID, now: now) else {
            return nil
        }
        let age = now.timeIntervalSince(snapshot.fetchedAt)
        guard snapshot.hasDirectWeatherPresentation,
              age >= 0,
              age < fallbackCacheDuration else {
            return nil
        }
        return snapshot
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

    /// Rejects corrupt, future-dated, previous-local-day, and malformed values
    /// before either normal rendering or failure recovery consumes them.
    private static func currentLocalDaySnapshot(
        for cityID: String,
        now: Date
    ) -> WidgetWeatherSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(for: cityID)),
              let snapshot = try? JSONDecoder().decode(
                WidgetWeatherSnapshot.self,
                from: data
              ),
              snapshot.resetEpoch == WidgetResetEpoch.current,
              let timeZoneIdentifier = snapshot.timeZoneIdentifier,
              let timeZone = TimeZone(identifier: timeZoneIdentifier),
              let representedLocalDate = snapshot.representedLocalDate else {
            return nil
        }

        var calendar = Calendar.current
        calendar.timeZone = timeZone
        guard calendar.isDate(representedLocalDate, inSameDayAs: now) else {
            return nil
        }
        return snapshot
    }

    private static func cacheKey(for cityID: String) -> String {
        "\(cacheKeyPrefix)\(cityID)"
    }
}
