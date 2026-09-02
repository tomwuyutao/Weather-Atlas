//
//  WeatherModels.swift
//  Weather
//
//  Purpose: Defines immutable city/forecast values and the shared WeatherModel
//  coordinator. Storage and cache mechanics remain in their dedicated helpers.
//
//  Reading guide: source values and recommendation DTOs come first. The
//  main-actor coordinator then composes the place, weather, location, catalog,
//  and widget boundaries without absorbing their persistence/network details.
//

import CoreLocation
import CryptoKit
import Foundation
import Observation
import OSLog

// MARK: - Forecast Value Types

/// Persistable place identity used before and after weather is fetched.
nonisolated struct City: Identifiable, Hashable, Codable, Sendable {
    /// Stable row and persistence identity.
    let id: UUID
    /// User-facing place name, preserving the selected search result when applicable.
    let name: String
    /// Optional fuller locality returned by reverse geocoding, reserved for
    /// the Map information card and forecast-report heading.
    let titleName: String?
    /// Canonical country or region name returned by reverse geocoding.
    let country: String
    /// Stable ISO 3166-1 alpha-2 country identity, when a provider supplies it.
    let countryISO2Code: String?
    /// Geographic latitude used by WeatherKit and MapKit.
    let latitude: Double
    /// Geographic longitude used by WeatherKit and MapKit.
    let longitude: Double
    /// Optional IANA or fixed-offset identifier retained with saved place data.
    let timeZoneIdentifier: String?
    /// Stable source identity when this city came from a bundled city catalog.
    let catalogIdentifier: String?

    init(
        id: UUID = UUID(),
        name: String,
        titleName: String? = nil,
        country: String,
        countryISO2Code: String? = nil,
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String? = nil,
        catalogIdentifier: String? = nil
    ) {
        self.id = id
        self.name = name
        self.titleName = titleName
        self.country = country
        let normalizedCountryCode = countryISO2Code?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        self.countryISO2Code = normalizedCountryCode?.count == 2
            && normalizedCountryCode?.unicodeScalars.allSatisfy {
                $0.value >= 65 && $0.value <= 90
            } == true
            ? normalizedCountryCode
            : nil
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.catalogIdentifier = catalogIdentifier
    }

}

/// Exact current WeatherKit condition retained for surfaces that present the
/// live observation rather than a day-level forecast summary.
struct CurrentWeatherPresentation: Hashable, Sendable {
    /// Instant at which WeatherKit observed this condition.
    let date: Date
    /// Exact SF Symbol supplied by WeatherKit.
    let symbolName: String
    /// Exact WeatherKit semantic condition, when available.
    let condition: AppWeatherCondition?
}

/// Resolved city plus its WeatherKit-backed forecast and current-condition values.
struct CityWeather: Identifiable, Hashable {
    let city: City
    var id: UUID { city.id }
    let dailyForecasts: [DailyForecast]
    /// Live WeatherKit observation from the same response as the forecasts.
    /// A legacy cache may not have this field, in which case Detail leaves the
    /// Today icon empty instead of substituting the daily forecast's icon.
    let currentWeather: CurrentWeatherPresentation?
    let timeZone: TimeZone

    init(
        city: City,
        dailyForecasts: [DailyForecast],
        currentWeather: CurrentWeatherPresentation? = nil,
        timeZone: TimeZone
    ) {
        self.city = city
        self.dailyForecasts = dailyForecasts
        self.currentWeather = currentWeather
        self.timeZone = timeZone
    }

    // MARK: - Stable Identity

    /// Equality follows the place identity rather than the mutable forecast
    /// payload. `SavedPlacesWeatherStore.weatherRevision` separately tells
    /// Observation when a refreshed same-city snapshot should redraw views.
    static func == (lhs: CityWeather, rhs: CityWeather) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - City-Local Date Resolution

    /// Finds the forecast whose city-local date has the same literal calendar
    /// day as the app-wide selected date.
    func forecastIfAvailable(
        on selectedDate: Date,
        selectionCalendar: Calendar = .current
    ) -> DailyForecast? {
        let selectedComponents = selectionCalendar.dateComponents(
            [.year, .month, .day],
            from: selectedDate
        )
        var cityCalendar = selectionCalendar
        cityCalendar.timeZone = timeZone

        return dailyForecasts.first { forecast in
            let components = cityCalendar.dateComponents(
                [.year, .month, .day],
                from: forecast.date
            )
            return components.year == selectedComponents.year
                && components.month == selectedComponents.month
                && components.day == selectedComponents.day
        }
    }

    /// Whether a forecast represents the city's current local calendar day.
    /// This avoids presenting a live current-condition symbol for a historical
    /// or future Detail selection.
    func isCurrentLocalDay(
        _ forecast: DailyForecast,
        now: Date = .now
    ) -> Bool {
        var cityCalendar = Calendar.current
        cityCalendar.timeZone = timeZone
        return cityCalendar.isDate(forecast.date, inSameDayAs: now)
    }

    /// Converts a city-local forecast day to the app-wide selector calendar.
    func selectionDate(
        for forecast: DailyForecast,
        selectionCalendar: Calendar = .current
    ) -> Date? {
        var cityCalendar = selectionCalendar
        cityCalendar.timeZone = timeZone
        let components = cityCalendar.dateComponents(
            [.year, .month, .day],
            from: forecast.date
        )
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let date = selectionCalendar.date(
                from: DateComponents(year: year, month: month, day: day)
              ) else {
            return nil
        }
        return selectionCalendar.startOfDay(for: date)
    }

}

/// One WeatherKit daily forecast and its associated hourly source values.
struct DailyForecast: Identifiable {
    let date: Date
    var id: Date { date }
    let dailyLow: Double
    let dailyHigh: Double
    let symbolName: String
    let condition: AppWeatherCondition?
    let hourlyForecasts: [HourlyForecast]
    let cloudCover: Double?
    let precipitationChance: Double?
    let uvIndex: Int?
    let sunrise: Date?
    let sunset: Date?

}

/// One hourly WeatherKit source record used by sunny-hour and detail charts.
struct HourlyForecast: Identifiable {
    let date: Date
    var id: Date { date }
    let symbolName: String
    let condition: AppWeatherCondition?
    let isDaylight: Bool
    let temperature: Double?
    let apparentTemperature: Double?
    let cloudCover: Double?
    let precipitationChance: Double?
    let uvIndex: Int?
    let visibilityKilometers: Double?

    func hour(in timeZone: TimeZone) -> Int {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar.component(.hour, from: date)
    }
}

// MARK: - Sunny-Place Recommendations

/// One city's usable weather facts for a selected local date.
///
/// A recommendation uses available hourly daylight data. Its icon always
/// reflects the current observation for the city's local Today; other days use
/// their exact daily forecast condition. A missing live observation is kept
/// empty rather than misleadingly falling back to a daily summary.
struct PlaceRecommendation: Identifiable {
    let cityWeather: CityWeather
    /// Exact WeatherKit symbol for the selected presentation condition. Empty
    /// means the city-local Today lacks a current observation and callers must
    /// reserve or hide the icon rather than substitute a daily forecast icon.
    let symbolName: String
    /// Exact WeatherKit condition value paired with `symbolName`.
    let condition: AppWeatherCondition?
    let sunnyHourCount: Double

    var id: City.ID { cityWeather.city.id }

    /// Orders every recommendation surface consistently: sunny hours first,
    /// then city name, then the stable city identity.
    static func ranked(
        _ recommendations: [PlaceRecommendation],
        locale: Locale
    ) -> [PlaceRecommendation] {
        recommendations.sorted { lhs, rhs in
            if lhs.sunnyHourCount != rhs.sunnyHourCount {
                return lhs.sunnyHourCount > rhs.sunnyHourCount
            }
            let order = lhs.cityWeather.city.localizedDisplayName(
                locale: locale
            ).compare(
                rhs.cityWeather.city.localizedDisplayName(locale: locale),
                options: [.caseInsensitive, .diacriticInsensitive, .numeric],
                locale: locale
            )
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

extension CityWeather {
    /// Chooses the only truthful condition icon for a forecast day. Today's
    /// city-local row represents WeatherKit's live observation; future and
    /// historical rows represent their daily forecast. No daily fallback is
    /// permitted when a legacy cache lacks today's live observation.
    func displayedCondition(
        for forecast: DailyForecast
    ) -> (symbolName: String, condition: AppWeatherCondition?)? {
        if isCurrentLocalDay(forecast) {
            guard let currentWeather,
                  !currentWeather.symbolName.isEmpty else {
                return nil
            }
            return (currentWeather.symbolName, currentWeather.condition)
        }

        guard !forecast.symbolName.isEmpty else { return nil }
        return (forecast.symbolName, forecast.condition)
    }

    /// Builds this city's selected-date recommendation using the app-wide
    /// sunny-hours rule. Missing forecast data produces no recommendation.
    func recommendation(
        on date: Date,
        selectionCalendar: Calendar = .current
    ) -> PlaceRecommendation? {
        guard let forecast = forecastIfAvailable(
            on: date,
            selectionCalendar: selectionCalendar
        ) else {
            return nil
        }

        let sunnyHoursData = SunnyHoursCalculation.sunnyHoursData(
            for: forecast,
            timeZone: timeZone
        )

        let displayedCondition = displayedCondition(for: forecast)
        return PlaceRecommendation(
            cityWeather: self,
            symbolName: displayedCondition?.symbolName ?? "",
            condition: displayedCondition?.condition,
            sunnyHourCount: SunnyHoursCalculation.sunnyHourCount(
                in: sunnyHoursData
            )
        )
    }
}

// MARK: - Nearby-Sun Result Types

/// A nearby recommendation ranked with the same weather criteria as Best
/// Sunny Places, while retaining the distance needed for Home's local context.
struct NearestSunnyPlaceResult: Identifiable {
    /// Recommendation values shared with Saved Places planning and Map overlays.
    let recommendation: PlaceRecommendation
    /// Straight-line distance from the active search origin, stored in kilometres.
    let distanceKilometers: Double

    /// Reuse the recommendation/city identity so a result stays stable in
    /// SwiftUI lists even when its rank or distance label changes.
    var id: City.ID { recommendation.id }
}

/// Stable inputs that make rebuilding Home or changing tabs a no-op.
/// Coordinates are intentionally rounded before becoming this key: minor GPS
/// jitter should not repeat an expensive nearby-city WeatherKit search.
nonisolated private struct NearestSunnySearchKey: Equatable, Sendable {
    /// Latitude rounded to the cache/search precision described above.
    let roundedLatitude: Double
    /// Longitude rounded to the cache/search precision described above.
    let roundedLongitude: Double
}

/// One preloaded nearby city. The population-ranked candidate set stays stable
/// while users compare forecast dates, then cached sunny-hour totals determine
/// which cities outrank the active reference place on that selected date.
private struct NearbySunnyCityCandidate {
    /// Resolved city identity used to retrieve its cached weather snapshot.
    let city: City
    /// Original catalog distance retained after the weather lookup completes.
    let distanceKilometers: Double
}

/// One settled place-detail search retained for native back navigation.
/// Candidate weather remains repository-owned; this value stores only the
/// geographic ordering and enough metadata to enforce the normal 30-minute
/// reuse policy independently for each origin.
private struct PlaceNearbySearchSnapshot {
    let searchKey: NearestSunnySearchKey
    let candidates: [NearbySunnyCityCandidate]
    let retainedPlaceIDs: Set<City.ID>
    let completedAt: Date
    let isFullySuccessful: Bool
}

/// The single shared geographic sampling contract for Nearby Sunnier Places and
/// Find Sun's Near Me scope. Keeping it here prevents the two entry points
/// from slowly acquiring different radii or weather-request budgets.
enum NearbySunSearchPolicy {
    /// Search a practical day-trip radius around the supplied reference coordinate.
    static let radiusKilometers = 200
    /// Request forecasts for this many geographically distinct cities.
    static let candidateLimit = 25
}

/// Shared Find Sun sampling rules. Catalog queries examine a larger
/// population-ranked pool, then discard nearby administrative duplicates before
/// WeatherKit is asked for exactly the requested number of destinations.
enum FindSunCitySamplingPolicy {
    /// Maximum number of cities visible in one Find Sun result set.
    static let resultLimit = 25
    /// Source rows considered before clusters are collapsed. This backfills
    /// places removed from a dense metro without increasing WeatherKit usage.
    static let sourceCandidateLimit = 100
    /// Two source rows at or below this distance represent one metro cluster.
    static let clusterRadiusKilometers = 25.0
}

// MARK: - Shared App Model

/// Root domain model shared by Your Location, Map, Places, Search, and detail views.
///
/// `@MainActor` serializes reads and writes of observable UI state on the main
/// thread. `@Observable` is Swift's modern observation macro: a SwiftUI view
/// redraws only when it reads state that later changes.
@MainActor
@Observable
final class WeatherModel {
#if DEBUG
    private static let nearbySearchLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Yutao-Wu.Weather",
        category: "NearbySearch"
    )
#endif

    // MARK: - Dependencies

    /// Independent flat Saved Places source of truth.
    let placesStore: SavedPlacesStore
    /// Weather snapshots keyed by stable place identity.
    let weatherStore: SavedPlacesWeatherStore
    /// Current location provider that never prompts during initialization.
    let locationProvider: LocationProvider
    /// Bundled world-cities catalog used by Search and nearest-sunny lookup.
    let citiesCatalog: CitiesCatalog
    /// Persisted City, Country, and Continent suggestions shared by Search and
    /// every Map query entry point.
    let recentSearches: RecentSearchStore

    // MARK: - Current-Location State

    /// Coordinate-backed city used to retain current-location weather safely.
    private(set) var locationCity: City?
    /// Weather rendered by every Current/Home Location surface.
    ///
    /// The repository is the single source of truth. Resolving this value at the
    /// read boundary means its 24-hour validity check also governs Home and Map;
    /// a detached copy could otherwise outlive repository expiry indefinitely.
    var locationWeather: CityWeather? {
        guard let placeID = currentLocationWeatherPlaceID else { return nil }
        return weatherStore.weather(for: placeID)
    }
    /// Optional resolved city selected during onboarding instead of device
    /// location. When present, it supplies every current-location surface
    /// until the person explicitly chooses device location again.
    private(set) var homeLocation: City?

    /// Whether the app is currently using a permanent, manually chosen home.
    var isUsingHomeLocation: Bool { homeLocation != nil }

    /// One canonical identity for every current-location surface.
    ///
    /// The forecast and the location provider resolve place metadata
    /// independently. On a cold launch WeatherKit can therefore finish with a
    /// broad city name such as "London" before reverse geocoding supplies the
    /// more precise locality shown in the report, such as "Southwark". Overlay
    /// the latest factual location metadata onto the stable coordinate-backed
    /// city so the heading, Save/Remove menu, Map hand-off, and persisted place
    /// all describe the same location without requiring another weather fetch.
    var currentLocationPlaceCity: City? {
        if let homeLocation {
            return homeLocation
        }

        let baseCity: City?
        if let locationCity {
            baseCity = locationCity
        } else if let weatherCity = locationWeather?.city {
            baseCity = weatherCity
        } else if let coordinate = locationProvider.coordinate,
                  CLLocationCoordinate2DIsValid(coordinate) {
            baseCity = makeLocationCity(coordinate: coordinate)
        } else {
            baseCity = nil
        }

        guard let baseCity else { return nil }
        let metadata = locationProvider.metadata
        let locality = CurrentLocationMetadata.localityName(
            from: metadata?.displayName
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = metadata?.countryName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let validTimeZoneIdentifier = metadata?.timeZoneIdentifier.flatMap {
            TimeZone(identifier: $0) == nil ? nil : $0
        }
        let resolvedName = locality.flatMap { $0.isEmpty ? nil : $0 }
            ?? baseCity.name
        let resolvedCountry = country.flatMap { $0.isEmpty ? nil : $0 }
            ?? baseCity.country

        return City(
            id: baseCity.id,
            name: resolvedName,
            titleName: baseCity.titleName,
            country: resolvedCountry,
            countryISO2Code:
                metadata?.isoCountryCode ?? baseCity.countryISO2Code,
            latitude: baseCity.latitude,
            longitude: baseCity.longitude,
            timeZoneIdentifier:
                validTimeZoneIdentifier ?? baseCity.timeZoneIdentifier,
            catalogIdentifier: baseCity.catalogIdentifier
        )
    }

    /// Resolves the repository identity from the currently authoritative source.
    /// A lost device coordinate deliberately has no fallback to `locationCity`:
    /// that value can describe the previous position until its clearing task runs.
    private var currentLocationWeatherPlaceID: City.ID? {
        if let homeLocation {
            return homeLocation.id
        }
        guard let coordinate = locationProvider.coordinate,
              CLLocationCoordinate2DIsValid(coordinate) else {
            return nil
        }
        return makeLocationCity(coordinate: coordinate).id
    }

    /// Uses the same canonical city as current-location actions. A manually
    /// chosen home retains its catalog localization policy, while a physical
    /// location leads with the reverse-geocoded locality stored on that city.
    func currentLocationDisplayName(locale: Locale) -> String {
        currentLocationPlaceCity?.localizedDisplayName(locale: locale) ?? ""
    }

    /// Repairs only a previously saved row with this exact transient
    /// current-location UUID. A separately saved catalog "London" has a
    /// different identity and is deliberately left untouched.
    func synchronizeSavedCurrentLocationIdentity() throws {
        guard homeLocation == nil,
              let currentLocationPlaceCity,
              PlacesLibraryValidator.isValidCity(
                  currentLocationPlaceCity
              ),
              let savedPlace = placesStore.place(
                  id: currentLocationPlaceCity.id
              ) else {
            return
        }
        let savedCity = savedPlace.city
        let needsMetadataRepair =
            savedCity.name != currentLocationPlaceCity.name
            || savedCity.country != currentLocationPlaceCity.country
            || savedCity.timeZoneIdentifier
                != currentLocationPlaceCity.timeZoneIdentifier
            || (currentLocationPlaceCity.titleName != nil
                && savedCity.titleName != currentLocationPlaceCity.titleName)
        guard needsMetadataRepair else { return }
        _ = try placesStore.savePlace(currentLocationPlaceCity)
    }

    // MARK: - Calendar Policy

    /// The app-wide forecast day follows the user's actual location, rather
    /// than the device's configured time zone. City forecasts still retain
    /// their own zones internally; this calendar supplies the literal day the
    /// user selected everywhere in the interface.
    var forecastCalendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        // A calendar still needs a timezone while the location lookup is in
        // flight. When locationTimeZone is nil this remains a presentation-only
        // device-calendar shell; no location weather is interpreted or rendered
        // until an authoritative timezone arrives with the resolved snapshot.
        if let locationTimeZone {
            calendar.timeZone = locationTimeZone
        }
        return calendar
    }

    /// Uses reverse-geocoded location metadata as soon as it arrives, then the
    /// WeatherKit-resolved city zone, with the device zone only as a safe
    /// fallback before a current location exists.
    var locationTimeZone: TimeZone? {
        if let identifier = homeLocation?.timeZoneIdentifier,
           let timeZone = TimeZone(identifier: identifier) {
            return timeZone
        }
        if let identifier = locationProvider.metadata?.timeZoneIdentifier,
           let timeZone = TimeZone(identifier: identifier) {
            return timeZone
        }
        if let timeZone = locationWeather?.timeZone {
            return timeZone
        }
        if let identifier = locationCity?.timeZoneIdentifier,
           let timeZone = TimeZone(identifier: identifier) {
            return timeZone
        }
        // The device timezone is factual only for the pre-location shell. Once
        // a coordinate exists, returning nil lets presentation blank dependent
        // weather and report the missing timezone instead of guessing its day.
        guard locationProvider.coordinate == nil else { return nil }
        return .autoupdatingCurrent
    }

    // MARK: - Nearby-Sun Search State

    /// Population-ranked nearby candidates preloaded once for the current
    /// coordinate and radius; their weather is reused for every selected date.
    private var nearbyCandidates: [NearbySunnyCityCandidate] = []
    /// Current-location forecast loading, independent of nearby discovery.
    private(set) var isRefreshingLocation = false
    /// Nearby discovery loading is separate so 25 candidate requests do not
    /// invalidate or put spinners back onto the already rendered Home report.
    private(set) var isSearchingNearby = false
    /// Distinguishes an honest no-match result from an unstarted search.
    private(set) var didSearchNearby = false
    /// Recoverable problem limited to the current-location forecast request.
    private(set) var locationError: String?
    /// Recoverable problem limited to the nearby-city discovery batch. Keeping
    /// it separate prevents a current-forecast failure from being presented as
    /// if the nearby search itself failed (and vice versa).
    private(set) var nearbySearchError: String?

    // MARK: Place-Detail Nearby Search State

    /// The active bounded candidate set centered on a non-current Detail View.
    /// Completed sets are also retained per origin below, so a nested route can
    /// replace this compatibility projection without erasing its parent's state.
    private var placeNearbyCandidates: [NearbySunnyCityCandidate] = []
    /// Identifies the place whose coordinates and forecast define this search.
    private(set) var placeNearbySearchOriginID: City.ID?
    /// Place-detail loading and completion are independent of Your Location.
    private(set) var isSearchingPlaceNearby = false
    private(set) var didSearchPlaceNearby = false
    /// Recoverable error for the active place-detail nearby search only.
    private(set) var placeNearbySearchError: String?
    /// Invalidates stale writes from overlapping location work. `@ObservationIgnored`
    /// keeps this implementation detail from triggering a SwiftUI redraw.
    @ObservationIgnored private var refreshID = 0
    /// Separately invalidates the Map's narrow current-location lookup. It must
    /// never write over a later full location refresh or a changed coordinate.
    @ObservationIgnored private var currentWeatherRefreshID = 0
    /// Prevents tab reconstruction from repeating an identical completed search.
    @ObservationIgnored private var lastSearchKey: NearestSunnySearchKey?
    /// Completion instant paired with `lastSearchKey`; successful nearby work
    /// is deliberately short lived and corrupt future timestamps are rejected.
    @ObservationIgnored private var lastSearchCompletedAt: Date?
    /// Small transient cache scope for the last candidate walk.
    @ObservationIgnored private var retainedPlaceIDs: Set<City.ID> = []
    /// Candidate identities protected from cache trimming while their nearby
    /// forecast batch is still running. They become `retainedPlaceIDs` only
    /// after usable results are assembled.
    @ObservationIgnored private var inFlightNearbyPlaceIDs: Set<City.ID> = []
    /// Invalidates a place-detail search when another detail route replaces it.
    @ObservationIgnored private var placeNearbyRefreshID = 0
    /// Bounded cache scope for the active place-detail candidate set.
    @ObservationIgnored private var retainedPlaceNearbyIDs: Set<City.ID> = []
    /// Protects a place-detail batch from cache trimming while it is in flight.
    @ObservationIgnored private var inFlightPlaceNearbyIDs: Set<City.ID> = []
    /// Settled nearby state follows each origin through nested navigation. A
    /// small LRU bound prevents recursive nearby browsing from retaining every
    /// WeatherKit candidate encountered during the entire app session.
    @ObservationIgnored
    private var placeNearbySnapshotsByOriginID:
        [City.ID: PlaceNearbySearchSnapshot] = [:]
    @ObservationIgnored private var placeNearbySnapshotRecency: [City.ID] = []
    /// Find Sun owns a separate, Map-local candidate set. Its forecasts must
    /// survive unrelated Saved Places and Home mutations for as long as that
    /// Map session remains visible.
    @ObservationIgnored private var activeMapCandidateIDs: Set<City.ID> = []
    /// Invalidates unstructured Map searches when a full app reset ends the
    /// entire transient session. A reset can destroy the Map view before an
    /// older catalog lookup has returned.
    @ObservationIgnored private var mapCandidateScopeGeneration = 0
    /// Explicit Map/Search selections remain routable for the app session.
    /// Nearby-card rows instead resolve from the current bounded candidate set.
    @ObservationIgnored
    private var foundCitiesByID: [City.ID: City] = [:]

    // MARK: - Nearby-Sun Sampling Policy

    /// Every nearby surface evaluates the same local area: a 200 km circle
    /// around the current coordinate. There is intentionally no minimum
    /// distance, ring, or geographic-quadrant rule.
    private static let nearbySearchRadius = Double(
        NearbySunSearchPolicy.radiusKilometers
    )
    /// The bounded WeatherKit budget. The catalog orders this complete local
    /// pool by population before a forecast is requested for each city.
    private static let nearbyCandidateLimit = NearbySunSearchPolicy.candidateLimit
    /// Reuse successful nearby results for the same 0.001-degree coordinate for
    /// at most one WeatherKit freshness window.
    private static let nearbySearchTimeToLive: TimeInterval = 30 * 60
    /// Six origins cover ordinary nested exploration while bounding retained
    /// candidate forecasts to at most six nearby-search batches.
    private static let maximumRetainedPlaceNearbyOrigins = 6

    // MARK: - Construction

    /// Creates the root model from its independent domain stores.
    init(
        placesStore: SavedPlacesStore,
        weatherStore: SavedPlacesWeatherStore,
        locationProvider: LocationProvider,
        citiesCatalog: CitiesCatalog = .shared,
        recentSearches: RecentSearchStore,
        initialHomeLocation: City?
    ) {
        self.placesStore = placesStore
        self.weatherStore = weatherStore
        self.locationProvider = locationProvider
        self.citiesCatalog = citiesCatalog
        self.recentSearches = recentSearches
        homeLocation = initialHomeLocation
        if let homeLocation {
            locationProvider.useHomeLocation(homeLocation)
        }
    }

    /// Live convenience that creates Core Location on the owning main actor.
    convenience init(
        placesStore: SavedPlacesStore,
        weatherStore: SavedPlacesWeatherStore,
        recentSearches: RecentSearchStore
    ) {
        // A convenience initializer must ultimately call the designated
        // initializer. It supplies the production Core Location dependency.
        self.init(
            placesStore: placesStore,
            weatherStore: weatherStore,
            locationProvider: LocationProvider(),
            recentSearches: recentSearches,
            initialHomeLocation: HomeLocationStore.load()
        )
    }

    // MARK: - Saved-Place Forecasts

    /// Loads saved forecasts without requesting or reading current location.
    func loadSavedWeather(forceRefresh: Bool = false) async {
        // The model coordinates the operation; SavedPlacesWeatherStore owns fetching,
        // caching, retry policy, and the resulting per-city weather snapshots.
        await weatherStore.load(
            cities: placesStore.allPlaces.map(\.city),
            forceRefresh: forceRefresh
        )

        // A legacy saved row may have arrived before its authoritative IANA
        // timezone was known. Keep that row visible while weather loads, then
        // persist WeatherKit/Apple-resolved metadata when it is complete. This
        // repairs the library in place without replacing a user alias or making
        // a missing timezone a global Saved Places load error.
        let resolvedCities = placesStore.allPlaces.compactMap { place in
            weatherStore.weather(for: place.id)?.city
        }.filter(PlacesLibraryValidator.isValidCity)
        // `savePlaces` applies the same city validation at its persistence
        // boundary, but commits all valid repaired metadata in one atomic write.
        // This avoids a read-back transaction for every saved city.
        _ = try? placesStore.savePlaces(resolvedCities)
    }

    // MARK: - Home Refresh Workflow

    /// Whether the retained forecast belongs to the coordinate currently
    /// supplied by Core Location. A location label can arrive before weather,
    /// so views must not pair a newly resolved name with a previous coordinate's
    /// forecast while a replacement is loading.
    var hasWeatherForCurrentLocation: Bool {
        guard let coordinate = locationProvider.coordinate,
              CLLocationCoordinate2DIsValid(coordinate) else {
            return false
        }
        return locationWeather?.id == makeLocationCity(coordinate: coordinate).id
    }

    /// Loads only the current-location forecast when a surface such as Map
    /// needs it. Unlike the Home workflow this deliberately does not start the
    /// nearby-city prefetch, so selecting the current-location marker is quick
    /// and cannot spend a batch of unnecessary WeatherKit requests.
    func ensureCurrentLocationWeather(
        forceRefresh: Bool = false,
        locale: Locale = .autoupdatingCurrent
    ) async {
        guard let coordinate = locationProvider.coordinate,
              CLLocationCoordinate2DIsValid(coordinate) else {
            clearLocationResults()
            return
        }

        let priorCurrentLocationWeatherID = physicalLocationFallbackPlaceID
        let currentCity = makeLocationCity(coordinate: coordinate)
        // Coordinate-derived IDs may change after only a few metres of normal
        // Core Location drift. Rebind the prior retained snapshot before scope
        // trimming so an offline cold launch keeps its valid 24-hour fallback.
        if !isUsingHomeLocation,
           weatherStore.weather(for: currentCity.id) == nil,
           let priorCurrentLocationWeatherID {
            weatherStore.adoptRetainedLocationWeather(
                from: priorCurrentLocationWeatherID,
                for: currentCity
            )
        }
        let coordinateChanged = locationCity?.id != currentCity.id
        if coordinateChanged {
            // A location change invalidates an older nearby task immediately;
            // its generation guard will reject any results that arrive later.
            refreshID &+= 1
            isSearchingNearby = false
            nearbyCandidates = []
            didSearchNearby = false
            nearbySearchError = nil
            retainedPlaceIDs = []
            inFlightNearbyPlaceIDs = []
            lastSearchKey = nil
            lastSearchCompletedAt = nil
        }

        currentWeatherRefreshID &+= 1
        let generation = currentWeatherRefreshID
        isRefreshingLocation = true
        defer {
            if currentWeatherRefreshID == generation {
                isRefreshingLocation = false
            }
        }

        // A current-location refresh follows the repository's replacement policy.
        // Keep the coordinate identity while the store temporarily hides an older
        // visible value and retains it only as a failure fallback.
        locationCity = currentCity
        locationError = nil
        retainWeatherScope()

        let weather = await weatherStore.lookup(
            city: currentCity,
            forceRefresh: forceRefresh
        )

        guard !Task.isCancelled,
              currentWeatherRefreshID == generation,
              let latestCoordinate = locationProvider.coordinate,
              CLLocationCoordinate2DIsValid(latestCoordinate),
              makeLocationCity(coordinate: latestCoordinate).id == currentCity.id else {
            return
        }

        if let weather {
            // Preserve WeatherKit's authoritative timezone and metadata while
            // retaining the transient current-location identity.
            locationCity = weather.city
            if !isUsingHomeLocation {
                CurrentLocationWeatherIdentityStore.save(weather.id)
            }
        } else {
            locationError = missingLocationWeatherMessage(locale: locale)
        }
        retainWeatherScope()
    }

    /// Loads a bounded nearby-city forecast set. Current-location weather has a
    /// separate lifecycle; date changes only re-rank these retained forecasts.
    func searchNearbyPlaces(
        forceRefresh: Bool = false,
        locale: Locale = .autoupdatingCurrent
    ) async {
#if DEBUG
        let debugStartedAt = Date()
        func debugLog(_ message: String) {
            let elapsed = Date().timeIntervalSince(debugStartedAt)
            let detail = "[NearbySearch +\(String(format: "%.2f", elapsed))s] \(message)"
            Self.nearbySearchLogger.notice("\(detail, privacy: .public)")
        }
#endif
        // Do not ask Core Location from here. The UI requests permission and
        // updates the provider separately; this method only consumes a usable
        // coordinate when one is already available.
        guard let coordinate = locationProvider.coordinate,
              CLLocationCoordinate2DIsValid(coordinate) else {
#if DEBUG
            debugLog("stopped: no valid current coordinate")
#endif
            clearLocationResults()
            return
        }
#if DEBUG
        debugLog("started for \(coordinate.latitude), \(coordinate.longitude)")
#endif

        // A recent, fully successful search is reusable while the user remains
        // at effectively the same coordinate. Date changes filter its forecasts
        // locally; expired, partial, failed, or future-dated work is retried.
        let key = nearbySearchKey(
            coordinate: coordinate
        )
        if !forceRefresh, canReuseNearbySearch(for: key) {
#if DEBUG
            debugLog("reused the recent completed search")
#endif
            return
        }

        // `&+=` is wrapping addition. The exact integer does not matter; it is
        // a monotonically changing token used to reject older async results.
        refreshID &+= 1
        let generation = refreshID
        isSearchingNearby = true
        didSearchNearby = false
        nearbySearchError = nil
        nearbyCandidates = []
        retainedPlaceIDs = []
        inFlightNearbyPlaceIDs = []
        lastSearchKey = nil
        lastSearchCompletedAt = nil

        // `defer` always runs when this async function returns, including every
        // early return below. The generation check stops an old task from
        // clearing the loading state of a newer one.
        defer {
            if refreshID == generation {
                isSearchingNearby = false
                inFlightNearbyPlaceIDs = []
                retainWeatherScope()
            }
        }

        // Removing the previous bounded candidate set before starting the next
        // one prevents transient searches from accumulating in memory or cache.
        retainWeatherScope()
        let hasCurrentWeather = hasWeatherForCurrentLocation

        do {
            // Candidate choice uses only population inside the fixed 200 km
            // radius; actual weather decides which of those candidates are
            // recommended.
            let candidates = try await loadNearbyCandidates(
                centeredAt: coordinate
            )
#if DEBUG
            debugLog("catalog returned \(candidates.count) candidates")
#endif
            guard isActiveRefresh(generation) else { return }

            // Keep only the transient cache entries needed for this search,
            // rather than allowing every explored catalog city to accumulate.
            var retainedIDs: Set<City.ID> = []
            var failedLookupCount = 0
            var loadedCandidates: [NearbySunnyCityCandidate] = []
            loadedCandidates.reserveCapacity(candidates.count)

            // Resolve stable identities first, then issue one batch. The weather
            // store uses at most five requests concurrently and persists the
            // complete batch once, while this model still publishes results only
            // after every candidate has settled.
            let resolvedCandidates = candidates.map { candidate in
                (
                    candidate: candidate,
                    city: resolveCatalogCity(from: candidate.city)
                )
            }
            // Saved-place metadata can finish persisting while this batch is
            // in flight. Its document-change handler trims transient cache
            // data, so keep every requested city in scope before the batch
            // begins; otherwise that save cancels all nearby requests.
            inFlightNearbyPlaceIDs = Set(resolvedCandidates.map(\.city.id))
            retainWeatherScope()
#if DEBUG
            debugLog("starting forecast batch for \(resolvedCandidates.count) cities")
#endif
            await weatherStore.load(
                cities: resolvedCandidates.map { $0.city },
                forceRefresh: forceRefresh
            )
#if DEBUG
            debugLog("forecast batch settled")
#endif
            guard isActiveRefresh(generation) else { return }

            for entry in resolvedCandidates {
                let city = entry.city
                let weather = weatherStore.weather(for: city.id)

                // Do not discard the whole search when one city fails. Record
                // the partial failure and still show every usable result.
                guard let weather else {
                    failedLookupCount += 1
                    continue
                }
                let resolvedCity = weather.city
                retainedIDs.insert(resolvedCity.id)
                loadedCandidates.append(
                    NearbySunnyCityCandidate(
                        city: resolvedCity,
                        distanceKilometers: entry.candidate.distanceKilometers
                    )
                )
            }

            guard isActiveRefresh(generation) else { return }
            retainedPlaceIDs = retainedIDs
            nearbyCandidates = loadedCandidates
            didSearchNearby = true
#if DEBUG
            debugLog(
                "assembled \(loadedCandidates.count) forecasts; \(failedLookupCount) unavailable"
            )
#endif
            // Surface a non-blocking warning only after retaining successful
            // results, so partial network failures are transparent but useful.
            if failedLookupCount > 0 {
                nearbySearchError = localizedString(
                    "Some nearby city forecasts were unavailable.",
                    locale: locale
                )
            }
            // Only complete, successful work earns the same-coordinate TTL.
            // A partial or current-location failure remains retryable instead of
            // masquerading as an intentionally empty/no-sun result.
            if hasCurrentWeather, failedLookupCount == 0 {
                lastSearchKey = key
                lastSearchCompletedAt = .now
            }
            retainWeatherScope()
#if DEBUG
            debugLog("completed")
#endif
        } catch is CancellationError {
            // Cancellation is expected when a newer location search supersedes
            // this one; the newer generation owns the visible state instead.
#if DEBUG
            debugLog("cancelled")
#endif
            return
        } catch is CitiesCatalogError {
#if DEBUG
            debugLog("failed: city catalog error")
#endif
            guard isActiveRefresh(generation) else { return }
            retainedPlaceIDs = []
            nearbyCandidates = []
            didSearchNearby = false
            nearbySearchError = localizedString(
                "Nearby city catalog data is missing.",
                locale: locale
            )
            lastSearchKey = nil
            lastSearchCompletedAt = nil
            retainWeatherScope()
        } catch {
#if DEBUG
            debugLog("failed: \(error.localizedDescription)")
#endif
            guard isActiveRefresh(generation) else { return }
            retainedPlaceIDs = []
            nearbyCandidates = []
            didSearchNearby = false
            nearbySearchError = localizedString(
                "Nearby city forecasts are temporarily unavailable.",
                locale: locale
            )
            lastSearchKey = nil
            lastSearchCompletedAt = nil
            retainWeatherScope()
        }
    }

    /// Loads the same fixed-radius candidate policy around a non-current place.
    /// This state is deliberately independent from Your Location, allowing both
    /// reports to retain correct recommendations while navigation is stacked.
    func searchNearbyPlaces(
        around origin: City,
        forceRefresh: Bool = false,
        locale: Locale = .autoupdatingCurrent
    ) async {
        let coordinate = CLLocationCoordinate2D(
            latitude: origin.latitude,
            longitude: origin.longitude
        )
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            clearPlaceNearbySearch()
            return
        }

        // A recommendation row routes by ID. Promote an unsaved origin to the
        // existing session-scoped route registry before replacing the previous
        // detail candidate set, so a newly pushed report cannot lose its city.
        if placesStore.place(id: origin.id) == nil {
            foundCitiesByID[origin.id] = origin
        }
        retainWeatherScope()

        let key = nearbySearchKey(coordinate: coordinate)
        let fallbackSnapshot = placeNearbySnapshot(
            for: origin.id,
            matching: key
        )
        if !forceRefresh, let fallbackSnapshot {
            // Returning to a completed parent route supersedes any younger
            // detail search still finishing above it in the navigation stack.
            placeNearbyRefreshID &+= 1
            isSearchingPlaceNearby = false
            inFlightPlaceNearbyIDs = []
            applyPlaceNearbySnapshot(fallbackSnapshot, to: origin.id)
            if canReusePlaceNearbySnapshot(fallbackSnapshot) {
                retainWeatherScope()
                return
            }
        }

        placeNearbyRefreshID &+= 1
        let generation = placeNearbyRefreshID
        placeNearbySearchOriginID = origin.id
        isSearchingPlaceNearby = true
        let keepsFallbackVisible = !forceRefresh && fallbackSnapshot != nil
        didSearchPlaceNearby = keepsFallbackVisible
        placeNearbySearchError = nil
        if !keepsFallbackVisible {
            placeNearbyCandidates = []
            retainedPlaceNearbyIDs = []
        }
        inFlightPlaceNearbyIDs = []
        retainWeatherScope()

        defer {
            // Cancellation should still release loading/cache state. Only a
            // newer generation or route may prevent this task from clearing it.
            if placeNearbyRefreshID == generation,
               placeNearbySearchOriginID == origin.id {
                isSearchingPlaceNearby = false
                inFlightPlaceNearbyIDs = []
                retainWeatherScope()
            }
        }

        do {
            let candidates = try await loadNearbyCandidates(
                centeredAt: coordinate
            )
            guard isActivePlaceNearbyRefresh(
                generation,
                originID: origin.id
            ) else { return }

            let resolvedCandidates = candidates.map { candidate in
                (
                    candidate: candidate,
                    city: resolveCatalogCity(from: candidate.city)
                )
            }
            inFlightPlaceNearbyIDs = Set(resolvedCandidates.map(\.city.id))
            retainWeatherScope()

            await weatherStore.load(
                cities: resolvedCandidates.map(\.city),
                forceRefresh: forceRefresh
            )
            guard isActivePlaceNearbyRefresh(
                generation,
                originID: origin.id
            ) else { return }

            var retainedIDs: Set<City.ID> = []
            var failedLookupCount = 0
            var loadedCandidates: [NearbySunnyCityCandidate] = []
            loadedCandidates.reserveCapacity(resolvedCandidates.count)

            for entry in resolvedCandidates {
                guard let weather = weatherStore.weather(for: entry.city.id) else {
                    failedLookupCount += 1
                    continue
                }
                retainedIDs.insert(weather.city.id)
                loadedCandidates.append(
                    NearbySunnyCityCandidate(
                        city: weather.city,
                        distanceKilometers: entry.candidate.distanceKilometers
                    )
                )
            }

            guard isActivePlaceNearbyRefresh(
                generation,
                originID: origin.id
            ) else { return }
            retainedPlaceNearbyIDs = retainedIDs
            placeNearbyCandidates = loadedCandidates
            didSearchPlaceNearby = true
            if failedLookupCount > 0 {
                placeNearbySearchError = localizedString(
                    "Some nearby city forecasts were unavailable.",
                    locale: locale
                )
            }
            cachePlaceNearbySnapshot(
                PlaceNearbySearchSnapshot(
                    searchKey: key,
                    candidates: loadedCandidates,
                    retainedPlaceIDs: retainedIDs,
                    completedAt: .now,
                    isFullySuccessful: failedLookupCount == 0
                ),
                for: origin.id
            )
            retainWeatherScope()
        } catch is CancellationError {
            return
        } catch is CitiesCatalogError {
            guard isActivePlaceNearbyRefresh(
                generation,
                originID: origin.id
            ) else { return }
            let message = localizedString(
                "Nearby city catalog data is missing.",
                locale: locale
            )
            restorePlaceNearbyFallback(
                fallbackSnapshot,
                for: origin.id,
                errorMessage: message
            )
            retainWeatherScope()
        } catch {
            guard isActivePlaceNearbyRefresh(
                generation,
                originID: origin.id
            ) else { return }
            let message = localizedString(
                "Nearby city forecasts are temporarily unavailable.",
                locale: locale
            )
            restorePlaceNearbyFallback(
                fallbackSnapshot,
                for: origin.id,
                errorMessage: message
            )
            retainWeatherScope()
        }
    }

    // MARK: - Nearby-Sun Candidate Selection

    /// Builds the one population-led, geographically distinct candidate set used
    /// by Nearby Sunnier Places. A larger source pool backfills metropolitan
    /// clusters, while WeatherKit still receives no more than 25 requests.
    private func loadNearbyCandidates(
        centeredAt coordinate: CLLocationCoordinate2D
    ) async throws -> [CatalogCityDistanceCandidate] {
        try await citiesCatalog.mostPopulousSpatiallyDistinctCities(
            centeredAt: coordinate,
            withinKilometers: Self.nearbySearchRadius,
            resultLimit: Self.nearbyCandidateLimit,
            sourceCandidateLimit: FindSunCitySamplingPolicy.sourceCandidateLimit,
            clusterRadiusKilometers: FindSunCitySamplingPolicy.clusterRadiusKilometers
        )
    }

    // MARK: - Derived Recommendations

    /// Builds one recommendation using the fixed app-wide sunny-hours rule:
    /// clear and mostly-clear daylight hours count as sun.
    func placeRecommendation(
        for weather: CityWeather,
        on date: Date
    ) -> PlaceRecommendation? {
        weather.recommendation(
            on: date,
            selectionCalendar: forecastCalendar
        )
    }

    /// Builds recommendations for every preloaded nearby candidate with weather
    /// for this date.
    /// The optional `limit` is
    /// applied only after the shared sunny-hours ranking, so a Home preview can
    /// safely request its top three. If current-location weather is unavailable,
    /// the comparison uses zero sunny hours.
    func nearbyRecommendations(
        on selectedDate: Date,
        locale: Locale,
        limit: Int? = nil
    ) -> [NearestSunnyPlaceResult] {
        rankedNearbyRecommendations(
            from: nearbyCandidates,
            comparedWith: locationWeather,
            on: selectedDate,
            locale: locale,
            limit: limit
        )
    }

    /// Ranks the active place-detail candidate set against that place's own
    /// forecast. A stale set from another pushed Detail View is never exposed.
    func nearbyRecommendations(
        around origin: City,
        on selectedDate: Date,
        locale: Locale,
        limit: Int? = nil
    ) -> [NearestSunnyPlaceResult] {
        guard placeNearbySearchOriginID == origin.id else { return [] }
        return rankedNearbyRecommendations(
            from: placeNearbyCandidates,
            comparedWith: weatherStore.weather(for: origin.id),
            on: selectedDate,
            locale: locale,
            limit: limit
        )
    }

    /// Applies the common sunny-hours comparison and ranking to either origin.
    private func rankedNearbyRecommendations(
        from nearbyCandidates: [NearbySunnyCityCandidate],
        comparedWith originWeather: CityWeather?,
        on selectedDate: Date,
        locale: Locale,
        limit: Int?
    ) -> [NearestSunnyPlaceResult] {
        var candidates: [NearestSunnyPlaceResult] = []
        let originSunnyHourCount = originWeather.flatMap {
            placeRecommendation(for: $0, on: selectedDate)
        }?.sunnyHourCount ?? 0

        for candidate in nearbyCandidates {
            guard let weather = weatherStore.weather(for: candidate.city.id) else {
                continue
            }

            guard let recommendation = placeRecommendation(
                for: weather,
                on: selectedDate
            ),
                  recommendation.sunnyHourCount > originSunnyHourCount else {
                continue
            }
            candidates.append(
                NearestSunnyPlaceResult(
                    recommendation: recommendation,
                    distanceKilometers: candidate.distanceKilometers
                )
            )
        }

        // Ranking returns `PlaceRecommendation` values, so temporarily index
        // the richer result values by the same stable city identity to restore
        // each distance after the shared ranking step.
        let candidatesByID = Dictionary(
            uniqueKeysWithValues: candidates.map { ($0.id, $0) }
        )
        let ranked = PlaceRecommendation.ranked(
            candidates.map(\.recommendation),
            locale: locale
        ).compactMap { candidatesByID[$0.id] }
        return nearbyRecommendationLimit(
            ranked,
            limit: limit
        )
    }

    /// Caps a presentation-specific preview after ranking. Negative limits are
    /// treated as zero rather than trapping in `prefix` or exposing rows.
    private func nearbyRecommendationLimit(
        _ recommendations: [NearestSunnyPlaceResult],
        limit: Int?
    ) -> [NearestSunnyPlaceResult] {
        guard let limit else { return recommendations }
        return Array(recommendations.prefix(max(0, limit)))
    }

    /// Builds recommendations for all saved destinations that have weather for
    /// the selected day.
    func savedRecommendations(
        on date: Date,
        locale: Locale
    ) -> [PlaceRecommendation] {
        var recommendations: [PlaceRecommendation] = []

        for place in placesStore.allPlaces {
            guard let weather = weatherStore.weather(for: place.id) else {
                continue
            }

            if let recommendation = placeRecommendation(
                for: weather,
                on: date
            ) {
                recommendations.append(recommendation)
            }
        }

        return PlaceRecommendation.ranked(
            recommendations,
            locale: locale
        )
    }

    // MARK: - Routing and Persistence Bridges

    /// City recents are intentionally limited to unsaved, non-local places.
    /// Re-evaluating this filter at display time makes an existing recent row
    /// disappear immediately when it is saved or becomes the current location;
    /// the lifecycle synchronization below then removes it from storage.
    var recentCitySuggestions: [City] {
        recentSearches.cities.filter { city in
            isEligibleRecentCity(city)
        }
    }

    /// Records a city information-card or full-detail access only while that
    /// place is eligible for the City Recent section.
    func recordRecentCityAccess(_ city: City) {
        pruneIneligibleRecentCities()
        guard isEligibleRecentCity(city) else { return }
        recentSearches.record(city: city)
    }

    /// Saved/current identities are not merely hidden from Recent: remove them
    /// from its durable MRU so they cannot consume one of the backfill slots.
    /// ContentView calls this whenever either eligibility source changes.
    func pruneIneligibleRecentCities() {
        recentSearches.removeCities { city in
            !isEligibleRecentCity(city)
        }
    }

    private func isEligibleRecentCity(_ city: City) -> Bool {
        placesStore.savedPlaceID(matching: city) == nil
            && !isCurrentLocationCity(city)
    }

    private func isCurrentLocationCity(_ city: City) -> Bool {
        guard let currentLocationPlaceCity else { return false }
        return CurrentLocationCityMatcher.matches(
            city,
            currentLocation: currentLocationPlaceCity
        )
    }

    /// Resolves a detail route from the library, Home's current nearby batch, or
    /// an explicitly registered transient Map/Search selection.
    func city(for placeID: City.ID) -> City? {
        // Prefer the persisted library. Transient search entries are a fallback
        // because they exist only to keep a just-tapped result routable.
        if let savedCity = placesStore.place(id: placeID)?.city {
            return savedCity
        }
        if let nearbyCity = nearbyCandidates.first(where: {
            $0.city.id == placeID
        })?.city {
            return nearbyCity
        }
        if let placeNearbyCity = placeNearbyCandidates.first(where: {
            $0.city.id == placeID
        })?.city {
            return placeNearbyCity
        }
        if let transientCity = foundCitiesByID[placeID] {
            return transientCity
        }
        return nil
    }

    /// Keeps a selected search result available to Detail until it is either
    /// explicitly saved or the app session ends.
    func registerTransientCity(_ city: City) {
        // This does not save a place. It extends the in-memory route/cache scope
        // until the user explicitly saves the city or ends the app session.
        foundCitiesByID[city.id] = city
        retainWeatherScope()
    }

    /// Keeps the active Find Sun query's complete candidate batch in the
    /// disposable weather scope. This is deliberately independent of Saved
    /// Places: saving, deleting, or opening one result must not evict its
    /// sibling results from the Map.
    func setActiveMapCandidateCities(_ cities: [City]) {
        let candidateIDs = Set(cities.map(\.id))
        guard candidateIDs != activeMapCandidateIDs else { return }
        activeMapCandidateIDs = candidateIDs
        retainWeatherScope()
    }

    /// Returns a token Map captures before asynchronous candidate discovery.
    /// It changes only for a full app reset, not for ordinary Home/location
    /// work, so an active Find Sun session remains valid across those flows.
    var currentMapCandidateScopeGeneration: Int {
        mapCandidateScopeGeneration
    }

    /// Verifies that an asynchronous Map search still belongs to the current
    /// transient app session before it publishes candidates or starts weather
    /// requests.
    func isCurrentMapCandidateScope(_ generation: Int) -> Bool {
        generation == mapCandidateScopeGeneration
    }

    /// Returns the bundled, curated first-run overview with its authoritative
    /// fixed-city metadata. Forecasts load only after Saved Places has been
    /// restored, so a Settings reset never leaves the library empty while a
    /// network place lookup is pending or unavailable.
    func starterCities() async throws -> [City] {
        let records = try await citiesCatalog.starterCities()
        let cities = records.map(makeCatalogCity)
        guard cities.allSatisfy(PlacesLibraryValidator.isValidCity) else {
            throw WeatherDataIssue.unresolvedPlace("starter places")
        }
        return cities
    }

    // MARK: - Cache Retention and Reset

    /// Keeps the disposable forecast cache aligned with saved places and the
    /// compact transient Home search scope.
    func retainWeatherScope() {
        // Start with saved places, which must always survive cache trimming.
        var retainedIDs = Set(placesStore.allPlaces.map(\.id))
        if let locationCity {
            retainedIDs.insert(locationCity.id)
        } else if let coordinate = locationProvider.coordinate,
                  CLLocationCoordinate2DIsValid(coordinate) {
            // Initial hydration can trim the cache before Home's task publishes
            // `locationCity`; preserve the deterministic current-location entry.
            retainedIDs.insert(makeLocationCity(coordinate: coordinate).id)
        }
        retainedIDs.formUnion(retainedPlaceIDs)
        retainedIDs.formUnion(inFlightNearbyPlaceIDs)
        retainedIDs.formUnion(retainedPlaceNearbyIDs)
        retainedIDs.formUnion(inFlightPlaceNearbyIDs)
        for snapshot in placeNearbySnapshotsByOriginID.values {
            retainedIDs.formUnion(snapshot.retainedPlaceIDs)
        }
        retainedIDs.formUnion(activeMapCandidateIDs)
        retainedIDs.formUnion(foundCitiesByID.keys)
        // The weather store discards every snapshot outside this explicit scope.
        weatherStore.retainWeather(
            for: retainedIDs,
            preservingRestoredWeather:
                shouldPreserveRestoredCurrentLocationWeather
        )
    }

    /// Before an authorized one-shot request publishes a coordinate, the model
    /// cannot yet reconstruct the deterministic current-location UUID. Preserve
    /// restored cache entries through that short identity-resolution window; a
    /// resolved coordinate or terminal location state resumes ordinary trimming.
    private var shouldPreserveRestoredCurrentLocationWeather: Bool {
        guard homeLocation == nil,
              locationCity == nil,
              locationProvider.coordinate == nil else {
            return false
        }

        switch locationProvider.status {
        case .idle, .checkingAvailability, .requestingAuthorization, .locating:
            return true
        case .resolvingPlace, .ready, .readyWithoutMetadata, .denied,
                .restricted, .servicesDisabled, .failed:
            return false
        }
    }

    /// Invalidates the completed key when an explicit app reset occurs.
    func resetLocation() {
        mapCandidateScopeGeneration &+= 1
        activeMapCandidateIDs = []
        homeLocation = nil
        HomeLocationStore.clear()
        CurrentLocationWeatherIdentityStore.clear()
        clearLocationState(keepingTransientCities: false)
        locationProvider.clearLocation()
        retainWeatherScope()
    }

    /// Selects a resolved city as the app's permanent location. The existing
    /// current-location report, map marker, and nearby-place lookup all read
    /// the provider's published coordinate, so they immediately adopt it.
    func setHomeLocation(_ city: City) {
        guard PlacesLibraryValidator.isValidCity(city) else { return }
        clearLocationState(keepingTransientCities: true)
        homeLocation = city
        HomeLocationStore.save(city)
        locationProvider.useHomeLocation(city)
    }

    /// Leaves manual-home mode and explicitly begins the device-location flow.
    /// This is called only from a user action, so the system permission prompt
    /// remains contextual rather than appearing on launch.
    func useCurrentLocation(preferredLocale: Locale = .autoupdatingCurrent) {
        homeLocation = nil
        HomeLocationStore.clear()
        clearLocationState(keepingTransientCities: true)
        locationProvider.clearLocation()
        locationProvider.requestCurrentLocation(preferredLocale: preferredLocale)
    }

    // MARK: - Widget Publishing

    /// Publishes the default Current/Home Location plus Saved Places to every
    /// widget configuration. WidgetKit owns fresh weather requests after
    /// receiving this lightweight coordinate contract.
    func publishWidgetCatalog(locale: Locale) {
        let defaultLocationKind: WidgetDefaultLocationKind = isUsingHomeLocation
            ? .homeLocation
            : .currentLocation
        let previousCatalog = WidgetDataStore.catalog()
        let retainedDefaultLocation: WidgetDataCity?
        let canRetainCurrentLocationWhileRefreshing = !isUsingHomeLocation
            && locationProvider.hasLocationAuthorization
            && [
                LocationProviderStatus.idle,
                .checkingAvailability,
                .locating,
                .resolvingPlace,
            ].contains(locationProvider.status)
        if previousCatalog?.resolvedDefaultLocationKind == defaultLocationKind,
           canRetainCurrentLocationWhileRefreshing {
            // Core Location is intentionally asynchronous. Preserve a confirmed
            // coordinate only while an authorized same-mode launch or refresh
            // is genuinely in flight. Denied, restricted, disabled, and failed
            // states must clear the old coordinate rather than letting widgets
            // continue to fetch a location the person revoked.
            retainedDefaultLocation = previousCatalog?.currentLocation
        } else {
            retainedDefaultLocation = nil
        }

        let savedPlaces = placesStore.allPlaces
        let legacyIdentifiersByPlaceID = widgetLegacyIdentifiers(
            for: savedPlaces,
            previousCatalog: previousCatalog
        )

        // Widgets receive only lightweight place identities here; their own
        // extension code owns fetching and refreshing forecast presentation.
        WidgetDataStore.save(
            WidgetDataCatalog(
                cities: savedPlaces.map {
                    widgetCity(
                        for: $0,
                        locale: locale,
                        legacyIdentifiers: legacyIdentifiersByPlaceID[$0.id]
                            ?? []
                    )
                },
                appLanguageIdentifier: locale.identifier,
                currentLocation: widgetCurrentLocation(locale: locale)
                    ?? retainedDefaultLocation,
                defaultLocationKind: defaultLocationKind
            )
        )
    }

    // MARK: - Private State and Identity Helpers

    private func clearLocationResults() {
        // This path is for an unavailable or invalid device coordinate. It
        // intentionally retains saved places while clearing location-only data.
        clearLocationState(keepingTransientCities: true)
        retainWeatherScope()
    }

    /// Clears all location-derived state. Search-result cities survive a
    /// coordinate failure so an open detail route remains valid; a full reset
    /// intentionally discards that ephemeral session state as well.
    private func clearLocationState(keepingTransientCities: Bool) {
        // Advance the generation first so any lookup still in flight cannot
        // repopulate the just-cleared state after this reset completes.
        refreshID &+= 1
        currentWeatherRefreshID &+= 1
        locationCity = nil
        nearbyCandidates = []
        isRefreshingLocation = false
        isSearchingNearby = false
        didSearchNearby = false
        locationError = nil
        nearbySearchError = nil
        retainedPlaceIDs = []
        inFlightNearbyPlaceIDs = []
        if !keepingTransientCities {
            foundCitiesByID = [:]
            clearPlaceNearbySearch()
        }
        lastSearchKey = nil
        lastSearchCompletedAt = nil
    }

    private func isActiveRefresh(_ generation: Int) -> Bool {
        // Both checks are required: tasks can be cancelled directly, or become
        // stale when a later refresh increments the generation token.
        !Task.isCancelled && refreshID == generation
    }

    /// A detail search is current only while both its generation and route
    /// identity still match; either condition can change during an await.
    private func isActivePlaceNearbyRefresh(
        _ generation: Int,
        originID: City.ID
    ) -> Bool {
        !Task.isCancelled
            && placeNearbyRefreshID == generation
            && placeNearbySearchOriginID == originID
    }

    /// Clears bounded place-detail state and invalidates any older async write.
    private func clearPlaceNearbySearch() {
        placeNearbyRefreshID &+= 1
        placeNearbyCandidates = []
        placeNearbySearchOriginID = nil
        isSearchingPlaceNearby = false
        didSearchPlaceNearby = false
        placeNearbySearchError = nil
        retainedPlaceNearbyIDs = []
        inFlightPlaceNearbyIDs = []
        placeNearbySnapshotsByOriginID = [:]
        placeNearbySnapshotRecency = []
    }

    private func nearbySearchKey(
        coordinate: CLLocationCoordinate2D
    ) -> NearestSunnySearchKey {
        // Three decimal places make a 0.001° coordinate grid. It ignores small
        // GPS noise without merging materially different nearby searches.
        return NearestSunnySearchKey(
            roundedLatitude: (coordinate.latitude * 1_000).rounded() / 1_000,
            roundedLongitude: (coordinate.longitude * 1_000).rounded() / 1_000
        )
    }

    /// Whether the previous same-coordinate search is both complete and fresh.
    /// Negative ages reject timestamps from a future wall clock.
    private func canReuseNearbySearch(
        for key: NearestSunnySearchKey,
        now: Date = .now
    ) -> Bool {
        guard key == lastSearchKey,
              locationWeather != nil,
              let completedAt = lastSearchCompletedAt else {
            return false
        }
        let age = now.timeIntervalSince(completedAt)
        return age >= 0 && age < Self.nearbySearchTimeToLive
    }

    // MARK: Place-Detail Nearby Snapshot Cache

    /// Returns only a snapshot built for the origin's current coordinates. A
    /// saved-place metadata correction may keep its ID while moving its factual
    /// coordinate, in which case the earlier nearby result must be discarded.
    private func placeNearbySnapshot(
        for originID: City.ID,
        matching key: NearestSunnySearchKey
    ) -> PlaceNearbySearchSnapshot? {
        guard let snapshot = placeNearbySnapshotsByOriginID[originID] else {
            return nil
        }
        guard snapshot.searchKey == key else {
            placeNearbySnapshotsByOriginID[originID] = nil
            placeNearbySnapshotRecency.removeAll { $0 == originID }
            return nil
        }
        touchPlaceNearbySnapshot(originID)
        return snapshot
    }

    /// A fully successful snapshot shares the ordinary 30-minute reuse window.
    /// Partial results remain available as refresh fallback but are retried when
    /// their origin becomes active again.
    private func canReusePlaceNearbySnapshot(
        _ snapshot: PlaceNearbySearchSnapshot,
        now: Date = .now
    ) -> Bool {
        guard snapshot.isFullySuccessful else {
            return false
        }
        let age = now.timeIntervalSince(snapshot.completedAt)
        guard age >= 0, age < Self.nearbySearchTimeToLive else {
            return false
        }
        return snapshot.retainedPlaceIDs.allSatisfy {
            weatherStore.weather(for: $0) != nil
        }
    }

    /// Projects one origin-owned snapshot back into the existing observable
    /// properties consumed by `NearbySunnyPlacesSection`.
    private func applyPlaceNearbySnapshot(
        _ snapshot: PlaceNearbySearchSnapshot,
        to originID: City.ID
    ) {
        placeNearbySearchOriginID = originID
        placeNearbyCandidates = snapshot.candidates
        retainedPlaceNearbyIDs = snapshot.retainedPlaceIDs
        didSearchPlaceNearby = true
        placeNearbySearchError = nil
    }

    /// Keeps a prior completed result visible if its replacement cannot finish.
    /// Without a fallback, retain the active origin so the card can present the
    /// newly localized error instead of appearing to have no search context.
    private func restorePlaceNearbyFallback(
        _ snapshot: PlaceNearbySearchSnapshot?,
        for originID: City.ID,
        errorMessage: String
    ) {
        if let snapshot {
            applyPlaceNearbySnapshot(snapshot, to: originID)
        } else {
            placeNearbySearchOriginID = originID
            placeNearbyCandidates = []
            retainedPlaceNearbyIDs = []
            didSearchPlaceNearby = false
        }
        placeNearbySearchError = errorMessage
    }

    /// Inserts or updates one origin and evicts the least recently viewed search
    /// when the bounded navigation cache reaches its limit.
    private func cachePlaceNearbySnapshot(
        _ snapshot: PlaceNearbySearchSnapshot,
        for originID: City.ID
    ) {
        placeNearbySnapshotsByOriginID[originID] = snapshot
        touchPlaceNearbySnapshot(originID)

        while placeNearbySnapshotRecency.count > Self.maximumRetainedPlaceNearbyOrigins {
            let evictedOriginID = placeNearbySnapshotRecency.removeFirst()
            placeNearbySnapshotsByOriginID[evictedOriginID] = nil
        }
    }

    private func touchPlaceNearbySnapshot(_ originID: City.ID) {
        placeNearbySnapshotRecency.removeAll { $0 == originID }
        placeNearbySnapshotRecency.append(originID)
    }

    /// Resolves only identities previously published as the physical current
    /// location. This prevents offline recovery from borrowing an unrelated
    /// Saved Place or transient Map forecast merely because it is nearby.
    private var physicalLocationFallbackPlaceID: City.ID? {
        guard !isUsingHomeLocation else { return nil }

        let knownIDs = [
            locationCity?.id,
            CurrentLocationWeatherIdentityStore.load()
        ].compactMap { $0 }
        if let retainedID = knownIDs.first(where: {
            weatherStore.weather(for: $0) != nil
        }) {
            return retainedID
        }

        guard let catalog = WidgetDataStore.catalog(),
              catalog.resolvedDefaultLocationKind == .currentLocation,
              let previousLocation = catalog.currentLocation,
              let latitude = previousLocation.latitude,
              let longitude = previousLocation.longitude else {
            return nil
        }
        let previousCoordinate = CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
        guard CLLocationCoordinate2DIsValid(previousCoordinate) else {
            return nil
        }
        let previousID = makeLocationCity(coordinate: previousCoordinate).id
        return weatherStore.weather(for: previousID) == nil
            ? nil
            : previousID
    }

    /// Compatibility copy for the existing nearby card.
    private func missingLocationWeatherMessage(locale: Locale) -> String {
        localizedString(
            "Current-location weather data is missing.",
            locale: locale
        )
    }

    private func makeLocationCity(
        coordinate: CLLocationCoordinate2D
    ) -> City {
        // A manually selected home already has a durable catalog identity.
        // Retaining it here lets the same localized label reach Your Location,
        // the Map marker, and the Current Location widget.
        if let homeLocation {
            return homeLocation
        }

        // The coordinate string is deliberately formatted in a fixed POSIX
        // locale so its decimal separator remains stable across app languages.
        let metadata = locationProvider.metadata
        let coordinateKey = String(
            format: "%.4f,%.4f",
            locale: Locale(identifier: "en_US_POSIX"),
            coordinate.latitude,
            coordinate.longitude
        )
        return City(
            id: Self.stableCityID(
                namespace: "current-location",
                value: coordinateKey
            ),
            // Missing locality/country stay empty. In particular, do not store
            // the presentation label "Current Location" as canonical place data.
            name: metadata?.displayName?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? "",
            country: metadata?.countryName?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? "",
            countryISO2Code: metadata?.isoCountryCode,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timeZoneIdentifier: metadata?.timeZoneIdentifier
        )
    }

    private func makeCatalogCity(from record: CatalogCity) -> City {
        // Catalog records do not need reverse geocoding; their bundled name,
        // country, and stable record ID are already the canonical source data.
        City(
            id: Self.stableCityID(namespace: "world-city", value: record.id),
            name: record.name,
            country: record.countryName,
            countryISO2Code: record.isoCountryCode,
            latitude: record.latitude,
            longitude: record.longitude,
            timeZoneIdentifier: record.timeZoneIdentifier,
            catalogIdentifier: record.id
        )
    }

    /// Reuses a durable saved identity for a catalog city whenever Search has
    /// already added it to Saved Places.
    private func resolveCatalogCity(from record: CatalogCity) -> City {
        let catalogCity = makeCatalogCity(from: record)
        // Match by catalog/coordinate identity, not by display name, because a
        // user may have renamed their saved copy of the same city.
        guard let savedID = placesStore.savedPlaceID(matching: catalogCity),
              let savedCity = placesStore.place(id: savedID)?.city else {
            return catalogCity
        }
        return savedCity
    }

    /// Creates the lightweight identity contract whose weather remains owned by
    /// the widget extension.
    private func widgetCity(
        for place: SavedPlace,
        locale: Locale,
        legacyIdentifiers: [String]
    ) -> WidgetDataCity {
        // Prefer a timezone learned from the actual weather response; fall back
        // to the saved city metadata when weather has not loaded yet.
        let city = place.city
        let country = city.country.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let timeZoneID = weatherStore.weather(for: place.id)?
            .timeZone.identifier
            ?? city.timeZoneIdentifier
        let identifier = WidgetDataStore.savedPlaceIdentifier(for: place.id)

        // Weather remains widget-owned; this catalog hand-off carries identity
        // and location metadata only.
        return WidgetDataCity(
            id: identifier,
            legacyIdentifiers: legacyIdentifiers,
            cityName: place.localizedDisplayName(locale: locale),
            configurationSubtitle: country.isEmpty ? nil : country,
            timeZoneIdentifier: timeZoneID,
            latitude: city.latitude,
            longitude: city.longitude,
            sunnyWindowDays: nil,
            dataIssue: nil
        )
    }

    /// Assigns every pre-UUID widget identifier to one durable Saved Place.
    ///
    /// A legacy identifier is a country-and-coordinate string and therefore is
    /// not guaranteed to be globally unique: two very close results can round
    /// to the same four-decimal coordinate. More importantly, a previous
    /// publication must never copy one row's canonical `saved-place:<UUID>` ID
    /// into another row's aliases. Doing either would allow adding or reordering
    /// a nearby Saved Place to retarget an already-configured widget.
    ///
    /// Exact UUID-backed ownership from the previous catalog wins. Unmigrated
    /// catalogs are then matched one-to-one by their historic identifier (with
    /// the old coordinate tolerance as a repair fallback), and only finally do
    /// new coordinate aliases claim identifiers that remain unowned.
    private func widgetLegacyIdentifiers(
        for places: [SavedPlace],
        previousCatalog: WidgetDataCatalog?
    ) -> [SavedPlace.ID: [String]] {
        guard !places.isEmpty else { return [:] }

        let placeIDs = Set(places.map(\.id))
        let canonicalIdentifierByPlaceID = Dictionary(
            uniqueKeysWithValues: places.map {
                ($0.id, WidgetDataStore.savedPlaceIdentifier(for: $0.id))
            }
        )
        let currentLegacyIdentifierByPlaceID = Dictionary(
            uniqueKeysWithValues: places.map { place in
                (
                    place.id,
                    WidgetDataStore.cityIdentifier(
                        country: place.city.country,
                        latitude: place.city.latitude,
                        longitude: place.city.longitude
                    )
                )
            }
        )
        let previousCities = previousCatalog?.cities ?? []

        /// Valid historic aliases exclude every canonical UUID identifier,
        /// including one accidentally propagated by an older buggy catalog.
        func legacyAliases(in city: WidgetDataCity) -> [String] {
            var seen: Set<String> = []
            return city.allWidgetIdentifiers.filter { identifier in
                !identifier.isEmpty
                    && identifier != WidgetDataStore.currentLocationIdentifier
                    && WidgetDataStore.savedPlaceID(from: identifier) == nil
                    && seen.insert(identifier).inserted
            }
        }

        /// Reconstructs the alias represented by a catalog row's own metadata.
        /// This distinguishes the original owner from a later row that merely
        /// inherited the alias through the propagation bug.
        func metadataLegacyIdentifier(for city: WidgetDataCity) -> String? {
            guard let latitude = city.latitude,
                  let longitude = city.longitude else {
                return nil
            }
            return WidgetDataStore.cityIdentifier(
                country: city.configurationSubtitle ?? "",
                latitude: latitude,
                longitude: longitude
            )
        }

        // Collect stable claims first rather than resolving in current library
        // order. This makes a drag reorder unable to change alias ownership.
        var aliasesPreviouslyOwnedByCanonicalRows: Set<String> = []
        var priorCanonicalClaims: [String: [(placeID: SavedPlace.ID, isOwnMetadata: Bool, order: Int)]] = [:]
        for (order, previousCity) in previousCities.enumerated() {
            guard let previousPlaceID = WidgetDataStore.savedPlaceID(
                from: previousCity.id
            ) else {
                continue
            }
            let metadataIdentifier = metadataLegacyIdentifier(for: previousCity)
            for alias in legacyAliases(in: previousCity) {
                aliasesPreviouslyOwnedByCanonicalRows.insert(alias)
                guard placeIDs.contains(previousPlaceID) else { continue }
                priorCanonicalClaims[alias, default: []].append(
                    (
                        placeID: previousPlaceID,
                        isOwnMetadata: metadataIdentifier == alias,
                        order: order
                    )
                )
            }
        }

        var ownerByAlias: [String: SavedPlace.ID] = [:]
        for (alias, claims) in priorCanonicalClaims {
            // Prefer the row whose own country/coordinate metadata produces the
            // alias. If an old collision remains intrinsically ambiguous, keep
            // the earliest previous-catalog owner for deterministic continuity.
            let owner = claims.min { lhs, rhs in
                if lhs.isOwnMetadata != rhs.isOwnMetadata {
                    return lhs.isOwnMetadata && !rhs.isOwnMetadata
                }
                return lhs.order < rhs.order
            }
            if let owner {
                ownerByAlias[alias] = owner.placeID
            }
        }

        /// Finds the sole best current owner for a pre-migration catalog row.
        /// Name/country break the rare rounded-coordinate tie, while the prior
        /// library order remains the deterministic final fallback.
        func ownerForUnmigratedCity(
            _ previousCity: WidgetDataCity
        ) -> SavedPlace.ID? {
            let previousName = previousCity.cityName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let previousCountry = previousCity.configurationSubtitle?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var best: (
                placeID: SavedPlace.ID,
                exactIdentifier: Bool,
                nameMatches: Bool,
                countryMatches: Bool,
                coordinateDistance: Double,
                order: Int
            )?

            for (order, place) in places.enumerated() {
                let exactIdentifier = currentLegacyIdentifierByPlaceID[place.id]
                    == previousCity.id
                let coordinateDistance: Double
                if let previousLatitude = previousCity.latitude,
                   let previousLongitude = previousCity.longitude {
                    coordinateDistance = max(
                        abs(previousLatitude - place.city.latitude),
                        abs(previousLongitude - place.city.longitude)
                    )
                } else {
                    coordinateDistance = .infinity
                }
                guard exactIdentifier || coordinateDistance < 0.000_05 else {
                    continue
                }

                let candidate = (
                    placeID: place.id,
                    exactIdentifier: exactIdentifier,
                    nameMatches: place.displayName.compare(
                        previousName,
                        options: [.caseInsensitive, .diacriticInsensitive]
                    ) == .orderedSame,
                    countryMatches: previousCountry.map {
                        place.city.country.compare(
                            $0,
                            options: [.caseInsensitive, .diacriticInsensitive]
                        ) == .orderedSame
                    } ?? false,
                    coordinateDistance: coordinateDistance,
                    order: order
                )

                guard let currentBest = best else {
                    best = candidate
                    continue
                }
                if candidate.exactIdentifier != currentBest.exactIdentifier {
                    if candidate.exactIdentifier { best = candidate }
                } else if candidate.nameMatches != currentBest.nameMatches {
                    if candidate.nameMatches { best = candidate }
                } else if candidate.countryMatches != currentBest.countryMatches {
                    if candidate.countryMatches { best = candidate }
                } else if candidate.coordinateDistance
                            != currentBest.coordinateDistance {
                    if candidate.coordinateDistance
                        < currentBest.coordinateDistance {
                        best = candidate
                    }
                } else if candidate.order < currentBest.order {
                    best = candidate
                }
            }
            return best?.placeID
        }

        // A catalog whose primary row IDs are still coordinate-based predates
        // the UUID migration. Resolve each row once, then carry all of that
        // row's noncanonical aliases to the same owner if still unclaimed.
        for previousCity in previousCities
        where WidgetDataStore.savedPlaceID(from: previousCity.id) == nil {
            guard previousCity.id != WidgetDataStore.currentLocationIdentifier,
                  let owner = ownerForUnmigratedCity(previousCity) else {
                continue
            }
            for alias in legacyAliases(in: previousCity)
            where ownerByAlias[alias] == nil {
                ownerByAlias[alias] = owner
            }
        }

        // Retain the legacy encoder as a last-resort bridge when the old shared
        // catalog was lost. A prior stable owner always wins, so a newly added
        // nearby place cannot take over an installed widget's identifier.
        for place in places {
            guard let alias = currentLegacyIdentifierByPlaceID[place.id],
                  !aliasesPreviouslyOwnedByCanonicalRows.contains(alias),
                  ownerByAlias[alias] == nil else {
                continue
            }
            ownerByAlias[alias] = place.id
        }

        var result: [SavedPlace.ID: [String]] = [:]
        for place in places {
            var aliases: [String] = []
            var seen: Set<String> = []
            if let currentAlias = currentLegacyIdentifierByPlaceID[place.id],
               ownerByAlias[currentAlias] == place.id,
               seen.insert(currentAlias).inserted {
                aliases.append(currentAlias)
            }
            for previousCity in previousCities {
                for alias in legacyAliases(in: previousCity)
                where ownerByAlias[alias] == place.id
                    && seen.insert(alias).inserted {
                    aliases.append(alias)
                }
            }
            // Defensive invariants: aliases are noncanonical by construction,
            // and one `ownerByAlias` entry can reach only this one result row.
            let canonicalIdentifier = canonicalIdentifierByPlaceID[place.id]
            result[place.id] = aliases.filter { $0 != canonicalIdentifier }
        }

#if DEBUG
        let publishedAliases = result.values.flatMap { $0 }
        assert(
            Set(publishedAliases).count == publishedAliases.count,
            "Every legacy widget identifier must have exactly one owner."
        )
        assert(
            publishedAliases.allSatisfy {
                WidgetDataStore.savedPlaceID(from: $0) == nil
            },
            "A canonical Saved Place identifier must never become an alias."
        )
#endif
        return result
    }

    /// Builds the special default widget location from the app's most recent
    /// physical or chosen-home coordinate. It is intentionally not saved to
    /// Saved Places: the stable widget ID lets configurations follow the chosen
    /// default mode without being invalidated when the device moves.
    private func widgetCurrentLocation(locale: Locale) -> WidgetDataCity? {
        guard let coordinate = locationProvider.coordinate,
              CLLocationCoordinate2DIsValid(coordinate) else {
            return nil
        }

        let metadata = locationProvider.metadata
        let canonicalDisplayName = currentLocationDisplayName(locale: locale)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = canonicalDisplayName.isEmpty
            ? localizedString("Current Location", locale: locale)
            : canonicalDisplayName
        let timeZoneID = locationWeather?.timeZone.identifier
            ?? currentLocationPlaceCity?.timeZoneIdentifier
            ?? metadata?.timeZoneIdentifier
            ?? TimeZone.autoupdatingCurrent.identifier

        return WidgetDataCity(
            id: WidgetDataStore.currentLocationIdentifier,
            cityName: displayName,
            timeZoneIdentifier: timeZoneID,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            sunnyWindowDays: nil,
            dataIssue: nil
        )
    }

    /// Derives a reproducible UUID from a namespaced source identity.
    nonisolated private static func stableCityID(
        namespace: String,
        value: String
    ) -> UUID {
        // Hash a namespaced source key so the same logical city receives the
        // same UUID across launches without persisting a separate mapping.
        var bytes = Array(
            SHA256.hash(
                data: Data("weather-atlas-\(namespace):\(value)".utf8)
            ).prefix(16)
        )
        // Set RFC 4122 version/variant bits after taking 16 SHA-256 bytes. This
        // makes the deterministic identifier look and validate like a UUID v5.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            )
        )
    }

}
