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

/// Provenance for the coordinate represented by a widget-owned forecast.
/// Current and Home Location deliberately share one public App Intent ID for
/// backward compatibility, so their private snapshots must carry this separate
/// source identity to prevent cross-mode cache reuse.
enum WidgetForecastLocationSource: String, Codable, Hashable, Sendable {
    case deviceCurrentLocation
    case fixedLocation
}

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
    /// Place name resolved by the widget for this exact coordinate. Current
    /// Location caches retain it atomically with their weather so a moved
    /// forecast can never be shown under the app's older locality label.
    var resolvedCityName: String? = nil
    /// Locale used for `resolvedCityName`; a later app-language change can
    /// decline to reuse a label from a different language.
    var cityNameLocaleIdentifier: String? = nil
    /// Timestamp supplied by Core Location for device-location snapshots.
    /// Saved and fixed Home locations intentionally leave this nil.
    var locationTimestamp: Date? = nil
    /// Whether the response came from extension-owned Current Location or a
    /// fixed Home/Saved coordinate.
    var locationSource: WidgetForecastLocationSource? = nil
    /// Exact current WeatherKit condition and its source SF Symbol.
    var currentWeather: WidgetWeatherPresentation? = nil
    /// Detailed current-day conditions used by the shared chart renderer.
    var hourlyConditions: [WidgetHourlyCondition]? = nil
    /// Complete current-day hourly conditions, including night, so later
    /// offline timeline entries do not keep the fetch-time condition icon.
    var hourlyWeatherConditions: [WidgetHourlyCondition]? = nil
    /// Exact current-day solar events used to change status copy at the real
    /// sunrise/sunset rather than at a coarse hourly forecast boundary.
    var sunrise: Date? = nil
    var sunset: Date? = nil
    /// Direct WeatherKit rows for the large widget's upcoming-day chart.
    var sunnyWindowDays: [WidgetSunnyWindowDay]? = nil
    /// Snapshot issue metadata, retained only when usable source data exists.
    var dataIssue: WeatherDataIssue? = nil

    /// Snapshots written before widgets persisted source symbols and raw API
    /// conditions must refresh instead of having an icon or condition guessed.
    var hasDirectWeatherPresentation: Bool {
        guard currentWeather != nil,
              let hourlyConditions,
              let hourlyWeatherConditions,
              let sunnyWindowDays else {
            return false
        }
        return hourlyConditions.allSatisfy { $0.weather != nil }
            && hourlyWeatherConditions.allSatisfy { $0.weather != nil }
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

    /// Reads a canonical UUID cache first, then any legacy App Intent aliases.
    /// The caller validates each candidate before lookup stops, so an obsolete
    /// snapshot under the canonical key cannot hide a matching legacy response.
    static func freshSnapshot(
        forAny cityIDs: [String],
        now: Date = .now,
        matching isValidCandidate: (WidgetWeatherSnapshot) -> Bool
    ) -> WidgetWeatherSnapshot? {
        for cityID in cityIDs {
            if let snapshot = freshSnapshot(for: cityID, now: now),
               isValidCandidate(snapshot) {
                return snapshot
            }
        }
        return nil
    }

    /// Returns the extension's last successful same-local-day response after a
    /// direct request fails. Yesterday's current/hourly fields must never be
    /// relabelled as today's weather after local midnight.
    static func fallbackSnapshot(
        for cityID: String,
        now: Date = .now
    ) -> WidgetWeatherSnapshot? {
        guard let snapshot = retainedSnapshot(for: cityID, now: now),
              representsCurrentLocalDay(snapshot, now: now) else {
            return nil
        }
        return snapshot
    }

    /// Applies the same canonical-then-legacy candidate validation to the
    /// bounded offline fallback window used after a direct request fails.
    static func fallbackSnapshot(
        forAny cityIDs: [String],
        now: Date = .now,
        matching isValidCandidate: (WidgetWeatherSnapshot) -> Bool
    ) -> WidgetWeatherSnapshot? {
        for cityID in cityIDs {
            if let snapshot = fallbackSnapshot(for: cityID, now: now),
               isValidCandidate(snapshot) {
                return snapshot
            }
        }
        return nil
    }

    // MARK: - Snapshot Writes

    /// Writes only a successful widget-owned WeatherKit response.
    static func save(_ snapshot: WidgetWeatherSnapshot, for cityID: String) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            // Preserve the last successfully encoded response if replacement
            // encoding ever fails.
            return
        }
        UserDefaults.standard.set(data, forKey: cacheKey(for: cityID))
    }

    /// Removes one private response immediately. Authorization revocation uses
    /// this for Current Location so weather tied to a no-longer-authorized
    /// coordinate cannot remain visible until normal retention expires.
    static func removeSnapshot(for cityID: String) {
        UserDefaults.standard.removeObject(forKey: cacheKey(for: cityID))
    }

    /// Removes legacy, expired, reset-invalid, and no-longer-selectable cache
    /// entries. Widget extensions are long-lived across app launches, so lazy
    /// per-city deletion alone would otherwise leak one defaults value for every
    /// city that was ever configured.
    static func prune(
        keeping cityIDs: Set<String>,
        now: Date = .now
    ) {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("widgetForecastSnapshot.") {
            guard key.hasPrefix(cacheKeyPrefix) else {
                defaults.removeObject(forKey: key)
                continue
            }

            let cityID = String(key.dropFirst(cacheKeyPrefix.count))
            guard cityIDs.contains(cityID) else {
                defaults.removeObject(forKey: key)
                continue
            }

            // `retainedSnapshot` performs decode, epoch, source, timezone, and
            // retention validation and deletes invalid values in place.
            _ = retainedSnapshot(for: cityID, now: now)
        }
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
