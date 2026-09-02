//
//  WidgetDataStore.swift
//  Weather
//
//  Purpose: Defines the app/widget data contract and persists the app-owned
//  configuration catalog shared with the widget extension.
//
//  Reading guide: the main app and widget extension are separate processes.
//  The App Group contains only selectable-place metadata and preferences.
//  Forecast snapshots remain private to the extension in WidgetForecast.
//

import CoreLocation
import Foundation
import SwiftUI
import WidgetKit

#if WEATHER_WIDGETS
import WeatherKit
#else
import UIKit
#endif

// MARK: - Widget Data Models

/// The exact WeatherKit presentation data required by widget views.
///
/// `condition` preserves WeatherKit's raw condition through the shared app
/// wrapper, while `symbolName` is the SF Symbol supplied by WeatherKit. Widgets
/// must draw that original symbol rather than choosing a replacement icon.
struct WidgetWeatherPresentation: Codable, Hashable, Sendable {
    let condition: AppWeatherCondition
    let symbolName: String
}

/// One daylight-hour WeatherKit record persisted for the widget charts.
///
/// The date keeps repeated local clock hours distinct on daylight-saving
/// transitions, while the local hour makes chart layout independent of the
/// device's timezone. `weather` remains optional only so pre-source-payload
/// snapshots decode; those snapshots are refreshed before presentation.
struct WidgetHourlyCondition: Codable, Hashable, Identifiable, Sendable {
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
    /// Historic identifiers that WidgetKit may still have persisted inside an
    /// existing App Intent configuration. Saved Places now use their durable
    /// UUID, while these aliases let widgets created by older releases keep
    /// resolving after country or coordinate metadata changes. Optional
    /// decoding keeps catalogs written before UUID identities compatible.
    var legacyIdentifiers: [String]? = nil
    /// Localized city label published by the main app.
    let cityName: String
    /// Optional disambiguating label shown only in widget configuration UI.
    /// This remains separate from `cityName` so compact widget layouts never
    /// expose additional location metadata. Optional decoding keeps catalogs
    /// written by earlier app versions compatible.
    var configurationSubtitle: String? = nil
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
    /// All covered current-day hours, including night, used to advance the
    /// compact condition icon as WidgetKit renders later timeline entries.
    var hourlyWeatherConditions: [WidgetHourlyCondition]? = nil
    /// Exact current WeatherKit condition and symbol.
    /// Optional supports decoding snapshots written before source data was
    /// persisted; the widget refreshes them before rendering weather content.
    var currentWeather: WidgetWeatherPresentation? = nil
    /// Extension-owned fetch instant for `currentWeather`. The compact widget
    /// keeps that exact observation through its source hour, then advances with
    /// the persisted hourly forecast while the extension is suspended.
    var weatherFetchedAt: Date? = nil
    /// Current local day's exact solar boundaries, when WeatherKit supplies
    /// them. Polar day/night legitimately leaves either event unavailable.
    var sunrise: Date? = nil
    var sunset: Date? = nil
    /// Available current/future rows for the large chart, capped at ten by its
    /// presentation capacity. A shorter valid forecast remains displayable.
    var sunnyWindowDays: [WidgetSunnyWindowDay]? = nil
    /// Request, place, or basic-forecast issue retained with the snapshot.
    /// Legacy per-field source issues remain decodable, but do not suppress
    /// otherwise usable WeatherKit data in widget presentation.
    var dataIssue: WeatherDataIssue? = nil
}

extension WidgetDataCity {
    /// Canonical UUID identity followed by any exact identifiers persisted by
    /// pre-migration App Intent configurations. Empty and duplicate values are
    /// discarded so callers can safely use this list for cache retention.
    var allWidgetIdentifiers: [String] {
        var seen: Set<String> = []
        return ([id] + (legacyIdentifiers ?? [])).filter { identifier in
            !identifier.isEmpty && seen.insert(identifier).inserted
        }
    }

    /// Matches both newly configured UUID-backed widgets and already-installed
    /// widgets whose App Intent still contains the former coordinate identity.
    func matchesWidgetIdentifier(_ identifier: String) -> Bool {
        allWidgetIdentifiers.contains(identifier)
    }
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

/// Exact Dynamic Type category selected by the app after applying its
/// Small...Large cap, including when the setting follows the system.
enum WidgetTextSize: String, Codable, Hashable {
    case small
    case medium
    case large
    case xLarge

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .xLarge
        }
    }

#if !WEATHER_WIDGETS
    /// Resolves the same capped app policy used by the containing app's scene.
    @MainActor
    static var current: WidgetTextSize {
        let defaults = UserDefaults.standard
        let usesSystem = defaults.object(
            forKey: AppTextSizePolicy.useSystemKey
        ) == nil
            ? true
            : defaults.bool(forKey: AppTextSizePolicy.useSystemKey)
        let appLevel = defaults.object(
            forKey: AppTextSizePolicy.appLevelKey
        ) == nil
            ? AppTextSizeLevel.defaultRawValue
            : defaults.integer(forKey: AppTextSizePolicy.appLevelKey)
        let effective = AppTextSizePolicy.effectiveDynamicTypeSize(
            useSystem: usesSystem,
            appLevel: appLevel,
            systemCategory: UIApplication.shared.preferredContentSizeCategory
        )
        if effective <= .small { return .small }
        if effective == .medium { return .medium }
        if effective == .large { return .large }
        return .xLarge
    }
#endif
}

/// One available local-date row in the large widget timeline.
/// The row is independent from `WidgetDataCity` so the up-to-ten-day chart can
/// render every WeatherKit forecast row without requiring a full horizon.
struct WidgetSunnyWindowDay: Codable, Hashable, Identifiable, Sendable {
    /// Literal selection date represented by this row.
    let date: Date
    /// Exact WeatherKit source data for every available daylight hour in this
    /// row. Optional supports snapshots written before detailed source data.
    var hourlyConditions: [WidgetHourlyCondition]? = nil
    /// Complete civil-day hourly conditions, including night. New snapshots
    /// persist these so a still-valid offline response can become tomorrow's
    /// correct Small, Medium, or Lock Screen presentation after local midnight.
    /// Optional decoding preserves same-day use of snapshots from older builds.
    var hourlyWeatherConditions: [WidgetHourlyCondition]? = nil
    /// Exact solar boundaries for this local day. Either value can legitimately
    /// be absent during polar day/night, so the complete hourly product is the
    /// migration marker for a roll-forward-capable day rather than these fields.
    var sunrise: Date? = nil
    var sunset: Date? = nil

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
    /// Identity-only records for Saved Places removed after they had been
    /// published to WidgetKit. App Intents can outlive the source Saved Place;
    /// retaining its last human-readable name lets that configured widget fail
    /// honestly without becoming a generic or silently retargeted selection.
    /// Optional decoding keeps catalogs written before tombstones compatible.
    var retiredCities: [WidgetDataCity]? = nil
    /// Main-app language used for widget localization consistency.
    let appLanguageIdentifier: String
    /// Latest app-published coordinate for the default Current/Home Location
    /// selection. It stays separate from Saved Places so a person never has to
    /// save that location just to configure a widget.
    var currentLocation: WidgetDataCity? = nil
    /// Generation of the app-published default-location identity. A widget-owned
    /// Current Location snapshot captures this value when it fetches. That lets
    /// a later Core Location failure trust an extension snapshot newer than the
    /// app's older coordinate after travel, while rejecting a snapshot after the
    /// app itself has published a genuinely different default location.
    var currentLocationGeneration: String? = nil
    /// Whether the stable default slot represents the device or a fixed home.
    /// Optional keeps catalogs written by older app versions decodable; those
    /// payloads predate Home Location and therefore mean Current Location.
    var defaultLocationKind: WidgetDefaultLocationKind? = nil
    /// App-resolved and capped Dynamic Type category for every widget family.
    /// Optional keeps catalogs from older releases decodable.
    var textSize: WidgetTextSize? = nil
    /// Whether widgets should follow WidgetKit's live system Dynamic Type value.
    /// The extension applies the same app-supported cap itself, so this remains
    /// responsive even while the containing app is terminated.
    var followsSystemTextSize: Bool? = nil
    /// Widget-only copy resolved by the localized main app before publication.
    var localizedStrings: [String: String] = [:]

    /// Backward-compatible interpretation of the optional persisted mode.
    var resolvedDefaultLocationKind: WidgetDefaultLocationKind {
        defaultLocationKind ?? .currentLocation
    }

    /// Older catalogs predate the app-wide widget typography contract and use
    /// the app's long-standing default category until the next publication.
    var resolvedTextSize: WidgetTextSize {
        textSize ?? .large
    }

    /// Older catalogs published one exact size and therefore retain that fixed
    /// behavior until the containing app next republishes its preferences.
    var resolvedFollowsSystemTextSize: Bool {
        followsSystemTextSize ?? false
    }

    /// Backward-compatible view of retired widget-selection identities.
    var resolvedRetiredCities: [WidgetDataCity] {
        retiredCities ?? []
    }
}

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
    /// Namespace separating durable Saved Place UUIDs from legacy coordinate
    /// identifiers and the special Current/Home Location slot.
    private static let savedPlaceIdentifierPrefix = "saved-place:"

    // MARK: - Stable City Identity

    /// Builds the durable identifier used by every newly configured Saved Place
    /// widget. A Saved Place UUID survives renames, country repair, and
    /// coordinate correction because it is the app library's canonical ID.
    static func savedPlaceIdentifier(for id: UUID) -> String {
        savedPlaceIdentifierPrefix + id.uuidString.lowercased()
    }

    /// Recovers a Saved Place UUID from a current widget/deep-link identity.
    /// Legacy country-and-coordinate identifiers deliberately return nil and
    /// are resolved through aliases in the published catalog instead.
    static func savedPlaceID(from identifier: String) -> UUID? {
        guard identifier.hasPrefix(savedPlaceIdentifierPrefix) else {
            return nil
        }
        return UUID(
            uuidString: String(identifier.dropFirst(savedPlaceIdentifierPrefix.count))
        )
    }

    /// Builds the pre-UUID identifier used by released widget configurations.
    /// Keep this encoder unchanged: App Intents can rehydrate an installed
    /// legacy selection only when the app continues publishing its exact ID as
    /// an alias during migration.
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
    @MainActor
    static func save(_ catalog: WidgetDataCatalog) {
        // Work on a local copy so the caller's value remains unchanged while we
        // attach the widget-specific strings needed by the extension process.
        var publishedCatalog = catalog
        let previousCatalog = self.catalog()
        publishedCatalog.currentLocationGeneration = currentLocationGeneration(
            from: previousCatalog,
            for: publishedCatalog
        )
        publishedCatalog.retiredCities = retiredWidgetCities(
            from: previousCatalog,
            keepingActive: publishedCatalog.cities
        )
        publishedCatalog.textSize = .current
        let defaults = UserDefaults.standard
        publishedCatalog.followsSystemTextSize = defaults.object(
            forKey: AppTextSizePolicy.useSystemKey
        ) == nil
            ? true
            : defaults.bool(forKey: AppTextSizePolicy.useSystemKey)
        let locale = catalog.appLanguageIdentifier.isEmpty
            ? Locale.autoupdatingCurrent
            : Locale(identifier: catalog.appLanguageIdentifier)
        publishedCatalog.localizedStrings = localizedWidgetStrings(locale: locale)

        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        // Catalog publication happens from several normal app lifecycle paths.
        // Avoid spending WidgetKit refresh budget (and causing duplicate
        // WeatherKit work in the extension) when the published value has not
        // actually changed.
        guard publishedCatalog != previousCatalog else { return }
        guard let data = try? JSONEncoder().encode(publishedCatalog) else {
            // Keep the last successfully encoded catalog. A transient encoding
            // failure must not strand every installed widget until the app is
            // opened again.
            return
        }
        defaults.set(data, forKey: catalogKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Retains one generation through ordinary GPS jitter and metadata/name
    /// refinement. A mode switch, timezone change, or meaningful coordinate
    /// change creates a new generation that invalidates an older widget-owned
    /// Current Location snapshot without touching Saved/Home caches.
    private static func currentLocationGeneration(
        from previousCatalog: WidgetDataCatalog?,
        for catalog: WidgetDataCatalog
    ) -> String {
        guard let previousCatalog,
              defaultLocationIdentityMatches(previousCatalog, catalog),
              let generation = previousCatalog.currentLocationGeneration else {
            return UUID().uuidString
        }
        return generation
    }

    private static func defaultLocationIdentityMatches(
        _ previous: WidgetDataCatalog,
        _ current: WidgetDataCatalog
    ) -> Bool {
        guard previous.resolvedDefaultLocationKind
                == current.resolvedDefaultLocationKind,
              previous.currentLocation?.timeZoneIdentifier
                == current.currentLocation?.timeZoneIdentifier else {
            return false
        }

        switch (previous.currentLocation, current.currentLocation) {
        case (nil, nil):
            return true
        case let (previousCity?, currentCity?):
            guard let previousLatitude = previousCity.latitude,
                  let previousLongitude = previousCity.longitude,
                  let currentLatitude = currentCity.latitude,
                  let currentLongitude = currentCity.longitude else {
                return false
            }
            let previousLocation = CLLocation(
                latitude: previousLatitude,
                longitude: previousLongitude
            )
            let currentLocation = CLLocation(
                latitude: currentLatitude,
                longitude: currentLongitude
            )
            let tolerance: CLLocationDistance =
                current.resolvedDefaultLocationKind == .currentLocation
                ? 2_000
                : 50
            return previousLocation.distance(from: currentLocation) <= tolerance
        default:
            return false
        }
    }

    /// Carries deleted Saved Place identities forward without carrying weather
    /// or fetchable coordinates. An active city matching the former canonical
    /// row ID means it is a continuous migration and prevents a tombstone. A
    /// retained tombstone can still own its historic alias ahead of a later
    /// unrelated active city, preventing an installed widget from retargeting.
    private static func retiredWidgetCities(
        from previousCatalog: WidgetDataCatalog?,
        keepingActive activeCities: [WidgetDataCity]
    ) -> [WidgetDataCity] {
        let previousCities = (previousCatalog?.cities ?? [])
            + (previousCatalog?.resolvedRetiredCities ?? [])
        var seenIdentifiers: Set<String> = []

        return previousCities.compactMap { city in
            guard city.id != currentLocationIdentifier,
                  !activeCities.contains(where: {
                      $0.matchesWidgetIdentifier(city.id)
                  }),
                  seenIdentifiers.insert(city.id).inserted else {
                return nil
            }

            return WidgetDataCity(
                id: city.id,
                legacyIdentifiers: city.legacyIdentifiers?.filter {
                    $0 != currentLocationIdentifier
                        && savedPlaceID(from: $0) == nil
                },
                cityName: city.cityName,
                configurationSubtitle: city.configurationSubtitle,
                timeZoneIdentifier: nil,
                latitude: nil,
                longitude: nil
            )
        }
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
            "Saved Place": localizedString("Saved Place", locale: locale),
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

#if WEATHER_WIDGETS
// MARK: - Extension-Only Presentation Data

/// Builds deterministic source-shaped WeatherKit data for Xcode previews.
private func widgetPreviewWeather(
    _ condition: WeatherCondition,
    symbolName: String
) -> WidgetWeatherPresentation {
    WidgetWeatherPresentation(
        condition: AppWeatherCondition(weatherKit: condition),
        symbolName: symbolName
    )
}

extension WidgetSunnyWindowDay {
    /// Full source conditions for a five-color row. Pre-source-payload snapshots
    /// are refreshed instead of fabricating a weather condition or symbol.
    var chartHourlyConditions: [WidgetHourlyCondition] {
        (hourlyConditions ?? []).filter { $0.weather != nil }
    }
}

extension WidgetDataCity {
    // MARK: - Preview Fixture

    /// Deterministic multi-day city fixture used by WidgetKit previews.
    static var preview: WidgetDataCity {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        var city = WidgetDataCity(
            id: "barcelona",
            cityName: "Barcelona",
            timeZoneIdentifier: "Europe/Madrid",
            latitude: 41.3874,
            longitude: 2.1686
        )
        city.hourlyConditions = (6...21).compactMap { hour in
            guard let date = calendar.date(
                bySettingHour: hour,
                minute: 0,
                second: 0,
                of: .now
            ) else {
                return nil
            }
            let weather: WidgetWeatherPresentation
            switch hour {
            case 8...16:
                weather = widgetPreviewWeather(.clear, symbolName: "sun.max.fill")
            case 17:
                weather = widgetPreviewWeather(.mostlyClear, symbolName: "cloud.sun.fill")
            case 7, 20:
                weather = widgetPreviewWeather(.partlyCloudy, symbolName: "cloud.sun.fill")
            case 18:
                weather = widgetPreviewWeather(.rain, symbolName: "cloud.rain.fill")
            case 19:
                weather = widgetPreviewWeather(.drizzle, symbolName: "cloud.drizzle.fill")
            default:
                weather = widgetPreviewWeather(.cloudy, symbolName: "cloud.fill")
            }
            return WidgetHourlyCondition(
                date: date,
                hour: hour,
                weather: weather
            )
        }
        city.currentWeather = widgetPreviewWeather(
            .mostlyClear,
            symbolName: "cloud.sun.fill"
        )
        city.weatherFetchedAt = .now
        city.hourlyWeatherConditions = city.hourlyConditions
        city.sunrise = calendar.date(
            bySettingHour: 6,
            minute: 30,
            second: 0,
            of: .now
        )
        city.sunset = calendar.date(
            bySettingHour: 21,
            minute: 0,
            second: 0,
            of: .now
        )
        // Vary hours by day so previews exercise differing spans and source
        // symbols without requiring a live WeatherKit request.
        city.sunnyWindowDays = (0..<10).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: .now) else { return nil }
            let sunnyStart = 7 + (offset % 4)
            let sunnyEnd = 15 + (offset % 5)
            let hours = (6...21).compactMap { hour -> WidgetHourlyCondition? in
                guard let hourDate = calendar.date(
                    bySettingHour: hour,
                    minute: 0,
                    second: 0,
                    of: date
                ) else {
                    return nil
                }
                let weather: WidgetWeatherPresentation
                if (sunnyStart..<sunnyEnd).contains(hour) {
                    weather = widgetPreviewWeather(.clear, symbolName: "sun.max.fill")
                } else if hour == sunnyEnd {
                    weather = widgetPreviewWeather(
                        .mostlyClear,
                        symbolName: "cloud.sun.fill"
                    )
                } else if hour == 6 || hour == sunnyEnd + 1 {
                    weather = widgetPreviewWeather(.partlyCloudy, symbolName: "cloud.sun.fill")
                } else if hour == 18, offset.isMultiple(of: 3) {
                    weather = widgetPreviewWeather(.rain, symbolName: "cloud.rain.fill")
                } else if hour == 19, offset.isMultiple(of: 3) {
                    weather = widgetPreviewWeather(.drizzle, symbolName: "cloud.drizzle.fill")
                } else {
                    weather = widgetPreviewWeather(.cloudy, symbolName: "cloud.fill")
                }
                return WidgetHourlyCondition(
                    date: hourDate,
                    hour: hour,
                    weather: weather
                )
            }
            return WidgetSunnyWindowDay(
                date: calendar.startOfDay(for: date),
                hourlyConditions: hours,
                hourlyWeatherConditions: hours,
                sunrise: calendar.date(
                    bySettingHour: 6,
                    minute: 30,
                    second: 0,
                    of: date
                ),
                sunset: calendar.date(
                    bySettingHour: 21,
                    minute: 0,
                    second: 0,
                    of: date
                )
            )
        }
        return city
    }

    // MARK: - Derived Presentation

    /// The large chart has room for at most ten rows, but it does not validate
    /// or require a complete ten-day horizon. It presents WeatherKit's available
    /// current/future rows in their received order.
    var widgetSunnyWindowDays: [WidgetSunnyWindowDay] {
        Array((sunnyWindowDays ?? []).prefix(10))
    }

    /// Valid timezone represented by the published identifier.
    /// `flatMap` both unwraps the optional identifier and discards invalid
    /// timezone strings.
    var widgetTimeZone: TimeZone? {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }

    /// A rendering-safe current-day domain derived from WeatherKit's available
    /// daylight-marked hourly records. A full-day domain is used only when that
    /// source list is empty.
    var widgetCurrentDaylightBounds: SunnyHoursChartBounds {
        let sourceHours = hourlyConditions?.map(\.hour) ?? []
        return widgetFallbackChartBounds(for: sourceHours)
    }

    /// Exact place-identity issue preventing a trustworthy fetch or deep link.
    var widgetIdentityIssue: WeatherDataIssue? {
        guard !cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .unresolvedPlace("city name")
        }
        guard let latitude,
              latitude.isFinite,
              (-90...90).contains(latitude),
              let longitude,
              longitude.isFinite,
              (-180...180).contains(longitude) else {
            return .unresolvedPlace("coordinates")
        }
        return nil
    }

    /// Whether a catalog location has stable identity and coordinates for a
    /// direct request. Time zone is intentionally excluded because the widget
    /// extension can repair legacy fixed places from its bundled lookup data.
    var hasResolvableWidgetLocation: Bool {
        widgetIdentityIssue == nil
    }

    /// Exact issue preventing current-day widget content. Source-level solar,
    /// hourly, condition, and metric gaps are presentation fallbacks, not an
    /// unavailable state; only a failed request, explicit no-forecast state,
    /// unsafe identity, or missing timezone blocks the widget.
    var widgetCurrentIssue: WeatherDataIssue? {
        if let dataIssue = widgetBlockingDataIssue { return dataIssue }
        if let identityIssue = widgetIdentityIssue { return identityIssue }
        guard widgetTimeZone != nil else { return .missingTimeZone }
        return nil
    }

    /// Exact issue preventing the large multi-day chart.
    /// Its requirements differ from the daily widget only because it needs at
    /// least one available forecast row to draw.
    var widgetSunnyWindowIssue: WeatherDataIssue? {
        if let dataIssue = widgetBlockingDataIssue { return dataIssue }
        if let identityIssue = widgetIdentityIssue { return identityIssue }
        guard widgetTimeZone != nil else { return .missingTimeZone }
        guard !widgetSunnyWindowDays.isEmpty else { return .missingForecastData }
        return nil
    }

    /// Returns only issues that mean the snapshot cannot safely identify or
    /// represent a place at all. Legacy field-level issues remain decodable but
    /// no longer hide otherwise usable WeatherKit data.
    var widgetBlockingDataIssue: WeatherDataIssue? {
        guard let dataIssue else { return nil }
        switch dataIssue.kind {
        case .weatherRequestFailed,
             .unresolvedPlace,
             .missingForecastData,
             .missingTimeZone:
            return dataIssue
        default:
            return nil
        }
    }

    // MARK: - Combining Catalog and Snapshot Data

    /// Replaces weather-bearing catalog fields with a fetched cached snapshot.
    /// A retained response can cross local midnight while still inside its
    /// 24-hour cache lifetime. In that case, promote the matching future-day
    /// payload to the current-day fields and drop yesterday from the large chart.
    /// Older snapshots remain usable on their represented day, but safely return
    /// nil after midnight because they did not persist complete future-day hours.
    func applying(
        _ snapshot: WidgetWeatherSnapshot,
        preservesResolvedCityName: Bool = false,
        at referenceDate: Date = .now
    ) -> WidgetDataCity? {
        guard let timeZoneIdentifier = snapshot.timeZoneIdentifier,
              let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            return nil
        }
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let referenceDay = calendar.startOfDay(for: referenceDate)

        let hourlyConditions: [WidgetHourlyCondition]?
        let hourlyWeatherConditions: [WidgetHourlyCondition]?
        let currentWeather: WidgetWeatherPresentation?
        let sunrise: Date?
        let sunset: Date?

        if snapshot.representsLocalDay(containing: referenceDate) {
            hourlyConditions = snapshot.hourlyConditions
            hourlyWeatherConditions = snapshot.hourlyWeatherConditions
            currentWeather = snapshot.currentWeather
            sunrise = snapshot.sunrise
            sunset = snapshot.sunset
        } else {
            guard let day = snapshot.sunnyWindowDays?.first(where: {
                calendar.isDate($0.date, inSameDayAs: referenceDate)
            }),
            let dayHourlyConditions = day.hourlyConditions,
            let dayWeatherConditions = day.hourlyWeatherConditions,
            dayHourlyConditions.allSatisfy({ $0.weather != nil }),
            dayWeatherConditions.allSatisfy({ $0.weather != nil }) else {
                return nil
            }

            hourlyConditions = dayHourlyConditions
            hourlyWeatherConditions = dayWeatherConditions
            currentWeather = dayWeatherConditions.first(where: {
                $0.date <= referenceDate
                    && referenceDate < $0.date.addingTimeInterval(60 * 60)
            })?.weather ?? dayWeatherConditions.min(by: {
                abs($0.date.timeIntervalSince(referenceDate))
                    < abs($1.date.timeIntervalSince(referenceDate))
            })?.weather
            sunrise = day.sunrise
            sunset = day.sunset
        }

        let snapshotName: String? = {
            guard !preservesResolvedCityName,
                  id == WidgetDataStore.currentLocationIdentifier,
                  snapshot.locationSource == .deviceCurrentLocation,
                  WidgetDataStore.catalog()?.resolvedDefaultLocationKind
                    == .currentLocation,
                  snapshot.cityNameLocaleIdentifier
                    == WidgetDataStore.appLocale.identifier else {
                return nil
            }
            return snapshot.resolvedCityName
        }()
        return WidgetDataCity(
            id: id,
            legacyIdentifiers: legacyIdentifiers,
            cityName: snapshotName ?? cityName,
            configurationSubtitle: configurationSubtitle,
            timeZoneIdentifier: timeZoneIdentifier,
            latitude: snapshot.latitude ?? latitude,
            longitude: snapshot.longitude ?? longitude,
            hourlyConditions: hourlyConditions,
            hourlyWeatherConditions: hourlyWeatherConditions,
            currentWeather: currentWeather,
            weatherFetchedAt: snapshot.fetchedAt,
            sunrise: sunrise,
            sunset: sunset,
            sunnyWindowDays: snapshot.sunnyWindowDays?.filter {
                calendar.startOfDay(for: $0.date) >= referenceDay
            },
            dataIssue: snapshot.dataIssue
        )
    }

    /// Clears weather-bearing content while retaining identity and exact issue.
    /// The resulting value is still routable and configurable, but cannot be
    /// mistaken for a valid all-cloudy/zero-sun forecast.
    func markingUnavailable(_ issue: WeatherDataIssue) -> WidgetDataCity {
        WidgetDataCity(
            id: id,
            legacyIdentifiers: legacyIdentifiers,
            cityName: cityName,
            configurationSubtitle: configurationSubtitle,
            timeZoneIdentifier: timeZoneIdentifier,
            latitude: latitude,
            longitude: longitude,
            hourlyConditions: nil,
            hourlyWeatherConditions: nil,
            currentWeather: nil,
            weatherFetchedAt: nil,
            sunrise: nil,
            sunset: nil,
            sunnyWindowDays: [],
            dataIssue: issue
        )
    }

    /// Returns the same catalog/snapshot value with one locally resolved zone.
    func replacingTimeZone(with identifier: String) -> WidgetDataCity {
        WidgetDataCity(
            id: id,
            legacyIdentifiers: legacyIdentifiers,
            cityName: cityName,
            configurationSubtitle: configurationSubtitle,
            timeZoneIdentifier: identifier,
            latitude: latitude,
            longitude: longitude,
            hourlyConditions: hourlyConditions,
            hourlyWeatherConditions: hourlyWeatherConditions,
            currentWeather: currentWeather,
            weatherFetchedAt: weatherFetchedAt,
            sunrise: sunrise,
            sunset: sunset,
            sunnyWindowDays: sunnyWindowDays,
            dataIssue: dataIssue
        )
    }
}
#endif
