//
//  WidgetDataStore.swift
//  Weather
//
//  Purpose: Persists app-owned widget configuration and shared widget models.
//
//  Reading guide: the main app and widget extension are separate processes.
//  They cannot share in-memory Swift objects, so this file defines Codable
//  payloads. The App Group contains only the catalog of selectable cities; the
//  widget extension keeps its WeatherKit snapshots in its own private storage.
//

import Foundation
import WidgetKit

// MARK: - Cross-Process Reset State

/// A small App Group marker shared by the app and widget extension.
///
/// Widget forecasts live in the extension's private defaults, which the host
/// app cannot delete. Advancing this value makes every older private snapshot
/// ineligible after Reset App, while a normal first installation has no epoch.
enum WidgetResetEpoch {
    private static let storageKey = "weatherAtlas.widgetResetEpoch"

    static var current: String? {
        UserDefaults(suiteName: WidgetDataStore.appGroupIdentifier)?.string(
            forKey: storageKey
        )
    }

#if !WEATHER_WIDGETS
    static func advance() {
        UserDefaults(suiteName: WidgetDataStore.appGroupIdentifier)?.set(
            UUID().uuidString,
            forKey: storageKey
        )
    }
#endif
}

// MARK: - Widget Data Models

/// The exact WeatherKit presentation data required by widget views.
///
/// `condition` preserves WeatherKit's raw condition through the shared app
/// wrapper, while `symbolName` is the SF Symbol supplied by WeatherKit. Widgets
/// must draw that original symbol rather than choosing a replacement icon.
struct WidgetWeatherPresentation: Codable, Hashable {
    let condition: AppWeatherCondition
    let symbolName: String
}

/// One daylight-hour WeatherKit record persisted for the widget charts.
///
/// The date keeps repeated local clock hours distinct on daylight-saving
/// transitions, while the local hour makes chart layout independent of the
/// device's timezone. `weather` remains optional only so pre-source-payload
/// snapshots decode; those snapshots are refreshed before presentation.
struct WidgetHourlyCondition: Codable, Hashable, Identifiable {
    /// Absolute forecast instant; unique even when a local hour repeats.
    let date: Date
    /// City-local clock hour used by the chart layout.
    let hour: Int
    /// Exact source condition and symbol from WeatherKit.
    var weather: WidgetWeatherPresentation? = nil

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
    /// Latitude used by direct WeatherKit requests and deep links.
    let latitude: Double?
    /// Longitude paired with `latitude` for requests and deep links.
    let longitude: Double?
    /// Current-day WeatherKit source data for every available daylight hour.
    /// Optional supports decoding snapshots written before source condition and
    /// symbol data were persisted.
    var hourlyConditions: [WidgetHourlyCondition]? = nil
    /// Exact current WeatherKit condition and symbol.
    /// Optional supports decoding snapshots written before source data was
    /// persisted; the widget refreshes them before rendering weather content.
    var currentWeather: WidgetWeatherPresentation? = nil
    /// Available current/future rows for the large chart, capped at ten by its
    /// presentation capacity. A shorter valid forecast remains displayable.
    var sunnyWindowDays: [WidgetSunnyWindowDay]? = nil
    /// Request, place, or basic-forecast issue retained with the snapshot.
    /// Legacy per-field source issues remain decodable, but do not suppress
    /// otherwise usable WeatherKit data in widget presentation.
    var dataIssue: WeatherDataIssue? = nil
}

/// App-owned choice that supplies the widget's stable default-location slot.
///
/// The App Intent identifier remains `current-location` for compatibility with
/// widgets configured by earlier releases. This value controls the label and
/// tells a newly launched app whether an existing published coordinate belongs
/// to device location or to the person's fixed home location.
enum WidgetDefaultLocationKind: String, Codable, Hashable {
    case currentLocation
    case homeLocation

    /// Localization key shown for the default option in WidgetKit's editor.
    var displayNameKey: String {
        switch self {
        case .currentLocation:
            "Current Location"
        case .homeLocation:
            "Home Location"
        }
    }
}

/// One available local-date row in the large widget timeline.
/// The row is independent from `WidgetDataCity` so the up-to-ten-day chart can
/// render every WeatherKit forecast row without requiring a full horizon.
struct WidgetSunnyWindowDay: Codable, Hashable, Identifiable {
    /// Literal selection date represented by this row.
    let date: Date
    /// Exact WeatherKit source data for every available daylight hour in this
    /// row. Optional supports snapshots written before detailed source data.
    var hourlyConditions: [WidgetHourlyCondition]? = nil

    /// Uses the literal local date as row identity.
    /// `Identifiable` gives SwiftUI a stable key when it renders rows in a
    /// `ForEach`.
    var id: Date { date }
}

/// Top-level app-group catalog read by App Intents and widget timelines.
/// The main app is the authority for this payload; the widget extension only
/// reads it to resolve the configured city and the app's chosen language.
struct WidgetDataCatalog: Codable, Hashable {
    /// Cities currently available in Saved Places.
    let cities: [WidgetDataCity]
    /// Main-app language used for widget localization consistency.
    let appLanguageIdentifier: String
    /// Latest app-published coordinate for the default Current/Home Location
    /// selection. It stays separate from Saved Places so a person never has to
    /// save that location just to configure a widget.
    var currentLocation: WidgetDataCity? = nil
    /// Whether the stable default slot represents the device or a fixed home.
    /// Optional keeps catalogs written by older app versions decodable; those
    /// payloads predate Home Location and therefore mean Current Location.
    var defaultLocationKind: WidgetDefaultLocationKind? = nil
    /// Widget-only copy resolved by the localized main app before publication.
    var localizedStrings: [String: String] = [:]

    /// Backward-compatible interpretation of the optional persisted mode.
    var resolvedDefaultLocationKind: WidgetDefaultLocationKind {
        defaultLocationKind ?? .currentLocation
    }
}

// MARK: - Shared Widget Persistence

/// Codable app-group persistence shared by the main app and widget extension.
/// This `enum` is a Swift namespace: it has only `static` members, so no store
/// instance or global mutable object needs to be constructed.
enum WidgetDataStore {
    // MARK: - Shared Keys

    /// Entitlement-backed application group identifier.
    static let appGroupIdentifier = "group.Yutao-Wu.Weather"
    /// Preference key containing app-owned widget selection metadata.
    static let catalogKey = "bestSunnyPlacesWidgetCatalog"
    /// WidgetKit kind for the unified Home Screen widget.
    static let kind = "BestSunnyPlacesWidget"
    /// Stable App Intent identity for the shared default selection. The catalog
    /// updates its coordinate, mode, and display name while widget
    /// configurations keep referring to this one backward-compatible ID.
    static let currentLocationIdentifier = "current-location"

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

#if !WEATHER_WIDGETS
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

    // MARK: - Reset

    /// Clears app-group widget configuration during a full app reset. Forecast
    /// snapshots live in the extension's private store, so advancing the shared
    /// reset epoch makes those old snapshots ineligible as well.
    static func removeAll() {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
        WidgetResetEpoch.advance()
        WidgetCenter.shared.reloadAllTimelines()
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
            "Home Location": localizedString("Home Location", locale: locale),
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
            "%@ h": localizedString("%@ h", locale: locale),
            "Weather unavailable.": localizedString(
                "Weather unavailable.",
                locale: locale
            ),
            "less than one minute": localizedString(
                "less than one minute",
                locale: locale
            ),
        ]
    }
#endif
}
