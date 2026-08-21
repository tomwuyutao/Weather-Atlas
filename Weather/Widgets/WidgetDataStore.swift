//
//  WidgetDataStore.swift
//  Weather
//
//  Purpose: Persists app-owned city identity and widget-owned weather snapshots.
//
//  Reading guide: the main app and widget extension are separate processes.
//  They cannot share in-memory Swift objects, so this file defines Codable
//  payloads and uses an App Group UserDefaults suite as their small shared disk
//  mailbox. The catalog says which cities exist; snapshots hold widget-fetched
//  weather for those cities.
//

import Foundation
import WidgetKit

// MARK: - Widget Data Models

/// Persisted summary of the shared `DaylightRegime` used to validate widgets.
///
/// Widget snapshots cannot persist WeatherKit values directly. This compact
/// representation records whether an empty daylight-hour array is a truthful
/// polar-night result or missing source data. One-event transition regimes are
/// retained only after the shared resolver validates them against hourly
/// daylight flags; calendar edges are clipping boundaries, not invented events.
enum WidgetDaylightRegime: String, Codable, Hashable {
    case normal
    case sunriseOnly
    case sunsetOnly
    case polarDay
    case polarNight
}

/// One normalized daylight-hour condition persisted for the widget charts.
///
/// The date keeps repeated local clock hours distinct on daylight-saving
/// transitions, while the local hour makes chart layout independent of the
/// device's timezone. Widgets used to retain only sunny and partly-sunny
/// buckets, which made rain and drizzle indistinguishable from no sun.
struct WidgetHourlyCondition: Codable, Hashable, Identifiable {
    /// Absolute forecast instant; unique even when a local hour repeats.
    let date: Date
    /// City-local clock hour used by the chart layout.
    let hour: Int
    /// The shared app/widget semantic weather condition.
    let condition: AppWeatherCondition

    /// Stable view identity derived from the source forecast instant.
    var id: Date { date }
}

/// App-group city payload used for widget selection and current rendering.
/// This deliberately contains enough identity and display metadata to configure
/// a widget even when the main app is not running.
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
    /// Stored as city-local clock integers rather than absolute Dates so compact
    /// charts remain simple.
    let daytimeHours: [Int]
    /// Current-day hours classified as sunny.
    let sunnyHours: [Int]
    /// Current-day hours classified as partly sunny.
    let partlySunnyHours: [Int]
    /// Current-day normalized conditions for every available daylight hour.
    /// Optional keeps previously persisted three-bucket widget data decodable
    /// until WidgetKit performs its next forecast refresh.
    var hourlyConditions: [WidgetHourlyCondition]? = nil
    /// Raw current WeatherKit symbol retained only for source diagnostics.
    var currentConditionSymbolName: String? = nil
    /// Current condition normalized by the same resolver as the main app.
    /// Optional keeps older snapshots decodable; the widget refreshes them
    /// before rendering weather content because the semantic value is missing.
    var currentCondition: AppWeatherCondition? = nil
    /// Current-day chart bounds: solar-derived when available, otherwise a
    /// safe domain derived from available WeatherKit hourly records.
    var daylightBounds: SunnyHoursChartBounds? = nil
    /// Optional astronomical regime when WeatherKit supplied enough solar data.
    var daylightRegime: WidgetDaylightRegime? = nil
    /// Available current/future rows for the large chart, capped at ten by its
    /// presentation capacity. A shorter valid forecast remains displayable.
    var sunnyWindowDays: [WidgetSunnyWindowDay]? = nil
    /// Request, place, or basic-forecast issue retained with the snapshot.
    /// Legacy per-field source issues remain decodable, but do not suppress
    /// otherwise usable WeatherKit data in widget presentation.
    var dataIssue: WeatherDataIssue? = nil
}

/// One available local-date row in the large widget timeline.
/// The row is independent from `WidgetDataCity` so the up-to-ten-day chart can
/// render every WeatherKit forecast row without requiring a full horizon.
struct WidgetSunnyWindowDay: Codable, Hashable, Identifiable {
    /// Literal selection date represented by this row.
    let date: Date
    /// Fully sunny hours for the day.
    let sunnyHours: [Int]
    /// Partly sunny hours for the day.
    let partlySunnyHours: [Int]
    /// Normalized conditions for every available daylight hour in this row.
    /// Optional supports snapshots written before five-condition charts.
    var hourlyConditions: [WidgetHourlyCondition]? = nil
    /// Solar-derived or safe fallback chart domain for the row.
    var daylightBounds: SunnyHoursChartBounds? = nil
    /// Optional astronomical regime used to construct the row.
    var daylightRegime: WidgetDaylightRegime? = nil
    /// Legacy per-field issue retained for backward decoding. Presentation uses
    /// available row values and fallback bounds instead of hiding the chart.
    var dataIssue: WeatherDataIssue? = nil

    /// Uses the literal local date as row identity.
    /// `Identifiable` gives SwiftUI a stable key when it renders rows in a
    /// `ForEach`.
    var id: Date { date }
}

/// Timestamped per-city cache used when WidgetKit runs between app launches.
/// A snapshot is widget-owned weather data; it is separate from the catalog so
/// the main app can update Saved Places without writing stale forecast values.
struct WidgetWeatherSnapshot: Codable, Hashable {
    /// Main-app fetch time used to enforce snapshot freshness.
    let fetchedAt: Date
    /// The destination-local calendar day represented by all current-day
    /// fields. An absolute fetch timestamp alone is insufficient around local
    /// midnight, where yesterday's data can still be only minutes old.
    let representedLocalDate: Date?
    /// City timezone copied from the catalog at fetch time.
    let timeZoneIdentifier: String?
    /// Coordinate used for the WeatherKit request. Keeping this with the
    /// snapshot prevents a moved Current Location widget from reusing weather
    /// fetched for an earlier physical location.
    var latitude: Double? = nil
    /// Longitude paired with `latitude` for snapshot identity validation.
    var longitude: Double? = nil
    /// Cached current-condition source symbol retained for diagnostics.
    var currentConditionSymbolName: String? = nil
    /// Cached condition normalized by the shared app/widget WeatherKit adapter.
    /// Optional preserves backward decoding of snapshots from older releases.
    var currentCondition: AppWeatherCondition? = nil
    /// Cached current-day daylight hours.
    let daytimeHours: [Int]
    /// Cached current-day sunny hours.
    let sunnyHours: [Int]
    /// Cached current-day partly-sunny hours.
    let partlySunnyHours: [Int]
    /// Cached normalized conditions for every current-day daylight hour.
    /// Optional preserves backward decoding of existing on-device snapshots.
    var hourlyConditions: [WidgetHourlyCondition]? = nil
    /// Cached current-day chart bounds, solar-derived when available.
    var daylightBounds: SunnyHoursChartBounds? = nil
    /// Cached optional astronomical regime for the represented local day.
    var daylightRegime: WidgetDaylightRegime? = nil
    /// Cached available current/future rows for the large chart, capped at ten
    /// during presentation rather than requiring a full ten-day feed.
    var sunnyWindowDays: [WidgetSunnyWindowDay]? = nil
    /// Cached request, place, or basic-forecast issue. Legacy per-field source
    /// issues remain decodable but do not hide otherwise usable widget data.
    var dataIssue: WeatherDataIssue? = nil
}

/// Top-level app-group catalog read by App Intents and widget timelines.
/// The main app is the authority for this payload; the widget extension only
/// reads it to resolve the configured city and the app's chosen language.
struct WidgetDataCatalog: Codable, Hashable {
    /// Cities currently available in Saved Places.
    let cities: [WidgetDataCity]
    /// Main-app language used for widget localization consistency.
    let appLanguageIdentifier: String
    /// Latest app-published coordinate for the default Current Location
    /// selection. It stays separate from Saved Places so a person never has to
    /// save their current position just to configure a widget.
    var currentLocation: WidgetDataCity? = nil
    /// Widget-only copy resolved by the localized main app before publication.
    var localizedStrings: [String: String] = [:]
}

// MARK: - Shared Widget Persistence

/// Codable app-group persistence shared by the main app and widget extension.
/// This `enum` is a Swift namespace: it has only `static` members, so no store
/// instance or global mutable object needs to be constructed.
enum WidgetDataStore {
    // MARK: - Shared Keys and Freshness Policy

    /// Entitlement-backed application group identifier.
    static let appGroupIdentifier = "group.Yutao-Wu.Weather"
    /// Preference key containing app-owned widget selection metadata.
    static let catalogKey = "bestSunnyPlacesWidgetCatalog"
    /// WidgetKit kind for the unified Home Screen widget.
    static let kind = "BestSunnyPlacesWidget"
    /// Stable App Intent identity for the shared default selection. The
    /// catalog updates its coordinate and display name as the device location
    /// changes, while widget configurations keep referring to this one ID.
    static let currentLocationIdentifier = "current-location"
    /// Prefix for widget-owned timestamped per-city weather snapshots.
    static let weatherCacheKeyPrefix = "widgetWeatherSnapshot."
    /// Maximum accepted age of a normal widget weather snapshot.
    static let weatherCacheDuration: TimeInterval = 30 * 60

    // MARK: - Stable City Identity

    /// Builds a stable identifier from normalized city coordinates.
    /// The fixed POSIX decimal separator makes the key identical regardless of
    /// the main app's language or a user's regional number-format preference.
    static func cityIdentifier(country: String, latitude: Double, longitude: Double) -> String {
        let latitude = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), latitude)
        let longitude = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), longitude)
        return "\(country)|\(latitude)|\(longitude)"
    }

    // MARK: - Catalog Reading and Localization

    /// Decodes the current cross-process widget catalog.
    /// A missing or corrupt payload safely becomes nil, allowing the widget to
    /// show its unavailable state instead of crashing a system-owned extension
    /// process.
    static func catalog() -> WidgetDataCatalog? {
        // `suiteName` opens the entitlement-backed App Group rather than either
        // target's private UserDefaults container.
        guard let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: catalogKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetDataCatalog.self, from: data)
    }

    /// Locale published by the app, or system locale before first publication.
    /// A widget may launch before the app has published anything, so the system
    /// locale is a safe temporary fallback.
    static var appLocale: Locale {
        guard let identifier = catalog()?.appLanguageIdentifier,
              !identifier.isEmpty else {
            return .autoupdatingCurrent
        }
        return Locale(identifier: identifier)
    }

    /// Returns copy localized by the main app, falling back before publication.
    /// Before publication, this returns the source key. Widgets use this because
    /// their extension bundle does not necessarily share the main app's selected
    /// localization context.
    static func localizedText(for key: String) -> String {
        catalog()?.localizedStrings[key] ?? key
    }

    // MARK: - Catalog Publishing

    /// Encodes the catalog and requests WidgetKit timeline reloads.
    /// Reloading asks WidgetKit for replacement timelines; it does not
    /// synchronously force every widget instance to redraw at this exact line.
    static func save(_ catalog: WidgetDataCatalog) {
        // Work on a local copy so the caller's value remains unchanged while we
        // attach the widget-specific strings needed by the extension process.
        var publishedCatalog = catalog
        let locale = catalog.appLanguageIdentifier.isEmpty
            ? Locale.autoupdatingCurrent
            : Locale(identifier: catalog.appLanguageIdentifier)
        publishedCatalog.localizedStrings = localizedWidgetStrings(locale: locale)

        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        guard let data = try? JSONEncoder().encode(publishedCatalog) else {
            // A failed publication invalidates the previous catalog rather than
            // leaving deleted or renamed Saved Places visible as current.
            defaults.removeObject(forKey: catalogKey)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        defaults.set(data, forKey: catalogKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Reset and Snapshot Cache

    /// Clears app-group widget metadata and snapshots during a full app reset.
    /// This intentionally removes every key in this dedicated group, then asks
    /// WidgetKit to replace any timelines based on the removed data.
    static func removeAll() {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Returns a fresh city snapshot, rejecting stale or corrupt payloads.
    /// Freshness is measured at read time so an unchanged persisted snapshot
    /// naturally expires even if the widget process was not launched for a while.
    static func weatherSnapshot(for cityID: String, now: Date = .now) -> WidgetWeatherSnapshot? {
        guard let snapshot = latestWeatherSnapshot(for: cityID) else {
            return nil
        }
        let age = now.timeIntervalSince(snapshot.fetchedAt)
        guard age >= 0, age < weatherCacheDuration,
              let identifier = snapshot.timeZoneIdentifier,
              let timeZone = TimeZone(identifier: identifier),
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

    /// Decodes the last stored result for validation and replacement only.
    /// Presentation callers must use `weatherSnapshot(for:now:)`; an expired
    /// or previous-local-day payload is never a display fallback.
    private static func latestWeatherSnapshot(for cityID: String) -> WidgetWeatherSnapshot? {
        guard let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: weatherCacheKey(for: cityID)) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetWeatherSnapshot.self, from: data)
    }

    /// Persists the widget extension's latest usable response for one city.
    /// Request and basic-forecast issues remain available for an honest
    /// placeholder, while source-field gaps retain their usable weather data.
    static func saveWeatherSnapshot(_ snapshot: WidgetWeatherSnapshot, for cityID: String) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else {
            defaults.removeObject(forKey: weatherCacheKey(for: cityID))
            return
        }
        defaults.set(data, forKey: weatherCacheKey(for: cityID))
    }

    /// Removes one city's snapshot before a network refresh that cannot safely
    /// use it. This prevents a later provider callback from resurrecting an old
    /// result after the refresh has already failed.
    static func removeWeatherSnapshot(for cityID: String) {
        UserDefaults(suiteName: appGroupIdentifier)?.removeObject(
            forKey: weatherCacheKey(for: cityID)
        )
    }

    /// Produces the namespaced preference key for one city snapshot.
    /// Prefixing separates cache entries from the catalog and from each other.
    private static func weatherCacheKey(for cityID: String) -> String {
        "\(weatherCacheKeyPrefix)\(cityID)"
    }

    // MARK: - Published Widget Copy

    /// Resolves the small amount of copy owned by the widget extension while
    /// the main app's String Catalog and selected locale are available.
    private static func localizedWidgetStrings(locale: Locale) -> [String: String] {
        // Use source strings as dictionary keys. Widget views ask for the same
        // keys, so they can fall back to English-like source text if this map is
        // absent during a first launch.
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
            "Current Location": localizedString("Current Location", locale: locale),
            "Today": localizedString("Today", locale: locale),
            "Sunny": localizedString("Sunny", locale: locale),
            "Partly Sunny": localizedString("Partly Sunny", locale: locale),
            "No Sun": localizedString("No Sun", locale: locale),
            "Rain": localizedString("Rain", locale: locale),
            "Drizzle": localizedString("Drizzle", locale: locale),
            "Sun Out Now": localizedString("Sun Out Now", locale: locale),
            "Sun Out in %@": localizedString("Sun Out in %@", locale: locale),
            "No Sun Today": localizedString("No Sun Today", locale: locale),
            "No More Sun Today": localizedString(
                "No More Sun Today",
                locale: locale
            ),
            "Weather unavailable.": localizedString(
                "Weather unavailable.",
                locale: locale
            ),
            "Sunny Hours for %@: %@": localizedString(
                "Sunny Hours for %@: %@",
                locale: locale
            ),
        ]
    }
}
