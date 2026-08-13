//
//  WeatherModels.swift
//  Weather
//
//  Purpose: Defines immutable city/forecast values and the shared WeatherModel
//  coordinator. Storage and cache mechanics remain in their dedicated helpers.
//

import CoreLocation
import CryptoKit
import Foundation
import Observation

// MARK: - Forecast Value Types

/// Persistable place identity used before and after weather is fetched.
struct City: Identifiable, Hashable, Codable {
    /// Stable row and persistence identity.
    let id: UUID
    /// User-facing place name, preserving the selected search result when applicable.
    let name: String
    /// Canonical country or region name returned by reverse geocoding.
    let country: String
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
        country: String,
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String? = nil,
        catalogIdentifier: String? = nil
    ) {
        self.id = id
        self.name = name
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.catalogIdentifier = catalogIdentifier
    }

    /// Missing source data remains blank; presentation decides how to label it.
    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Resolved city plus its daily WeatherKit-backed forecast values.
struct CityWeather: Identifiable, Hashable {
    let city: City
    var id: UUID { city.id }
    let dailyForecasts: [DailyForecast]
    let timeZone: TimeZone

    init(city: City, dailyForecasts: [DailyForecast], timeZone: TimeZone) {
        self.city = city
        self.dailyForecasts = dailyForecasts
        self.timeZone = timeZone
    }

    static func == (lhs: CityWeather, rhs: CityWeather) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

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

    /// Invalid numeric readings retained anywhere in this snapshot.
    var numericDataIssues: [WeatherDataIssue] {
        dailyForecasts.flatMap(\.numericDataIssues)
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
    let isFullyClear: Bool
    let hourlyForecasts: [HourlyForecast]
    let cloudCover: Double?
    let precipitationChance: Double?
    let uvIndex: Int?
    let sunrise: Date?
    let sunset: Date?

    var cloudCoverPercent: Int? {
        guard let cloudCover,
              cloudCover.isFinite,
              (0...1).contains(cloudCover) else {
            return nil
        }
        return Int((cloudCover * 100).rounded())
    }

    /// A daily average is usable only when all represented source hours have
    /// visibility, so partial source data never becomes a plausible aggregate.
    var averageVisibilityKilometers: Double? {
        guard !hourlyForecasts.isEmpty,
              hourlyForecasts.allSatisfy({ hour in
                  guard let visibility = hour.visibilityKilometers else {
                      return false
                  }
                  return visibility.isFinite && visibility >= 0
              }) else {
            return nil
        }
        let values = hourlyForecasts.compactMap(\.visibilityKilometers)
        return values.reduce(0, +) / Double(values.count)
    }

    var numericDataIssues: [WeatherDataIssue] {
        dailyNumericDataIssues + hourlyForecasts.flatMap(\.numericDataIssues)
    }

    /// Numeric issues owned by this daily record rather than rolling hourly rows.
    var dailyNumericDataIssues: [WeatherDataIssue] {
        var issues: [WeatherDataIssue] = []

        if !dailyLow.isFinite {
            issues.append(.invalidValue("daily low temperature", at: date))
        }
        if !dailyHigh.isFinite {
            issues.append(.invalidValue("daily high temperature", at: date))
        }
        if dailyLow.isFinite, dailyHigh.isFinite, dailyLow > dailyHigh {
            issues.append(.invalidValue(
                "daily low temperature exceeds daily high temperature",
                at: date
            ))
        }
        if let cloudCover,
           (!cloudCover.isFinite || !(0...1).contains(cloudCover)) {
            issues.append(.invalidValue("daily cloud cover", at: date))
        }
        if let precipitationChance,
           (!precipitationChance.isFinite
               || !(0...1).contains(precipitationChance)) {
            issues.append(.invalidValue("daily precipitation chance", at: date))
        }
        if let uvIndex, uvIndex < 0 {
            issues.append(.invalidValue("daily UV index", at: date))
        }
        return issues
    }

    init(
        date: Date,
        dailyLow: Double,
        dailyHigh: Double,
        symbolName: String,
        condition: AppWeatherCondition?,
        isFullyClear: Bool,
        hourlyForecasts: [HourlyForecast],
        cloudCover: Double?,
        precipitationChance: Double?,
        uvIndex: Int?,
        sunrise: Date?,
        sunset: Date?
    ) {
        self.date = date
        self.dailyLow = dailyLow
        self.dailyHigh = dailyHigh
        self.symbolName = symbolName
        self.condition = condition
        self.isFullyClear = isFullyClear
        self.hourlyForecasts = hourlyForecasts
        self.cloudCover = cloudCover
        self.precipitationChance = precipitationChance
        self.uvIndex = uvIndex
        self.sunrise = sunrise
        self.sunset = sunset
    }
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

    init(
        date: Date,
        symbolName: String,
        condition: AppWeatherCondition?,
        isDaylight: Bool,
        temperature: Double?,
        apparentTemperature: Double?,
        cloudCover: Double?,
        precipitationChance: Double?,
        uvIndex: Int?,
        visibilityKilometers: Double?
    ) {
        self.date = date
        self.symbolName = symbolName
        self.condition = condition
        self.isDaylight = isDaylight
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.cloudCover = cloudCover
        self.precipitationChance = precipitationChance
        self.uvIndex = uvIndex
        self.visibilityKilometers = visibilityKilometers
    }

    var numericDataIssues: [WeatherDataIssue] {
        var issues: [WeatherDataIssue] = []
        if let temperature, !temperature.isFinite {
            issues.append(.invalidValue("hourly temperature", at: date))
        }
        if let apparentTemperature, !apparentTemperature.isFinite {
            issues.append(.invalidValue("hourly apparent temperature", at: date))
        }
        if let cloudCover,
           (!cloudCover.isFinite || !(0...1).contains(cloudCover)) {
            issues.append(.invalidValue("hourly cloud cover", at: date))
        }
        if let precipitationChance,
           (!precipitationChance.isFinite
               || !(0...1).contains(precipitationChance)) {
            issues.append(.invalidValue("hourly precipitation chance", at: date))
        }
        if let uvIndex, uvIndex < 0 {
            issues.append(.invalidValue("hourly UV index", at: date))
        }
        if let visibilityKilometers,
           (!visibilityKilometers.isFinite || visibilityKilometers < 0) {
            issues.append(.invalidValue("hourly visibility", at: date))
        }
        return issues
    }

    func hour(in timeZone: TimeZone) -> Int {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar.component(.hour, from: date)
    }
}

// MARK: - App-Wide Weather Coordinator

// MARK: - Nearby-Sun Result Types

/// A nearby recommendation ranked with the same weather criteria as Best
/// Sunny Places, while retaining the distance needed for Home's local context.
struct NearestSunnyPlaceResult: Identifiable {
    /// Recommendation values shared with Saved Places planning and Map overlays.
    let recommendation: PlaceRecommendation
    /// Straight-line distance from the device coordinate, stored in kilometres.
    let distanceKilometers: Double

    /// Reuse the recommendation/city identity so a result stays stable in
    /// SwiftUI lists even when its rank or distance label changes.
    var id: City.ID { recommendation.id }
    /// Shortcuts keep call sites expressive without duplicating the stored data.
    var cityWeather: CityWeather { recommendation.cityWeather }
    var forecast: DailyForecast { recommendation.forecast }
}

/// One saved destination intentionally omitted from a selected-day ranking
/// because that literal date has already passed in the destination's timezone.
struct SavedPlaceDateExclusion: Identifiable {
    /// Persisted place retained even though it has no rank for the selected day.
    let place: SavedPlace
    /// Destination's current local day represented in the app-wide calendar.
    let localCurrentDate: Date

    /// Reuse the persisted place identity for stable SwiftUI rows.
    var id: SavedPlace.ID { place.id }
}

/// Nearby recommendations plus the place-specific source gaps that prevented
/// other loaded candidates from being assessed honestly for the selected day.
struct NearbyRecommendationsAssessment {
    let recommendations: [NearestSunnyPlaceResult]
    let issuesByPlaceID: [City.ID: [WeatherDataIssue]]
}

/// Saved-place recommendations plus missing-data reasons for destinations that
/// could not be assessed for the selected day. Valid non-sunny forecasts remain
/// recommendations so each presentation can apply its own honest filter.
struct SavedRecommendationsAssessment {
    let recommendations: [PlaceRecommendation]
    let issuesByPlaceID: [City.ID: [WeatherDataIssue]]
}

/// Tri-state current-location result. This prevents an unavailable condition
/// from being treated as an ordinary cloudy/non-sunny day.
enum LocationSunninessAssessment {
    case sunny
    case notSunny
    case unavailable([WeatherDataIssue])
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
/// while users compare forecast dates, then the nearest clear city is selected
/// locally from its already loaded WeatherKit snapshot.
private struct NearbySunnyCityCandidate {
    /// Resolved city identity used to retrieve its cached weather snapshot.
    let city: City
    /// Original catalog distance retained after the weather lookup completes.
    let distanceKilometers: Double
}

/// Compass buckets used to make outer nearby-sun suggestions geographically
/// varied. `CaseIterable` lets the algorithm visit all four without a second
/// manually maintained list.
private enum NearbySunnyQuadrant: CaseIterable {
    case northeast
    case southeast
    case southwest
    case northwest
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
    // MARK: - Dependencies

    /// Independent flat Saved Places source of truth.
    let placesStore: PlacesStore
    /// Weather snapshots keyed by stable place identity.
    let weatherStore: PlaceWeatherStore
    /// Current location provider that never prompts during initialization.
    let locationProvider: LocationProvider
    /// Bundled world-cities catalog used by Search and nearest-sunny lookup.
    let citiesCatalog: CitiesCatalog

    // MARK: - Current-Location State

    /// Coordinate-backed city used to retain current-location weather safely.
    private(set) var locationCity: City?
    /// Weather rendered by the Your Location timeline card.
    private(set) var locationWeather: CityWeather?
    /// Completion time of the most recent current-location weather lookup.
    private(set) var lastLocalRefresh: Date?

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
    /// Loading state shared by the timeline and nearest-sunny cards.
    private(set) var isRefreshingLocation = false
    /// Distinguishes an honest no-match result from an unstarted search.
    private(set) var didSearchNearby = false
    /// Recoverable problem limited to the current-location forecast request.
    private(set) var locationError: String?
    /// Recoverable problem limited to the nearby-city discovery batch. Keeping
    /// it separate prevents a current-forecast failure from being presented as
    /// if the nearby search itself failed (and vice versa).
    private(set) var nearbySearchError: String?
    /// Structured missing-data reasons for native alert presentation. This is
    /// independent of the compatibility string above so views never need to
    /// infer a data category by parsing localized copy.
    private(set) var locationIssues: [WeatherDataIssue] = []
    /// Partial population/row omissions from the catalog used to choose nearby
    /// candidates. Presentation reports these separately from weather failures.
    private(set) var nearbyCatalogIssues: [CitiesCatalogIssue] = []
    /// Fatal bundled-catalog failure kept distinct from network/weather issues
    /// so the native alert names the actual missing source.
    private(set) var nearbyCatalogError: CitiesCatalogError?
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
    /// Results that have been surfaced remain routable for the life of the app
    /// session, even if a later radius or date search replaces the Your Location card.
    @ObservationIgnored
    private var foundCitiesByID: [City.ID: City] = [:]
    // MARK: - Nearby-Sun Sampling Policy

    /// The inner ring begins far enough away to avoid neighbourhood-scale
    /// duplicates of the current location.
    private static let nearbyMinDistance = 25.0
    /// Separates the small local ring from the broader day-trip search area.
    private static let nearbyInnerRadius = 50.0
    /// Farthest accepted nearby-sun suggestion, measured from the device.
    private static let nearbySearchRadius = 200.0
    /// Population-ranked places retained from the 25–50 km ring.
    private static let nearbyCandidateLimit = 5
    /// Maximum population-ranked places retained from each outer compass bucket.
    private static let quadrantLimit = 5
    /// Total outer-ring WeatherKit budget: four quadrants × five places.
    private static let outerCandidateLimit = 20
    /// Catalog records examined before quadrant selection. This can be larger
    /// than the WeatherKit budget because no forecast request happens here.
    private static let catalogScanLimit = 10_000
    /// Reuse successful nearby results for the same 0.001-degree coordinate for
    /// at most one WeatherKit freshness window.
    private static let nearbySearchTimeToLive: TimeInterval = 30 * 60

    // MARK: - Construction

    /// Creates the root model from its independent domain stores.
    init(
        placesStore: PlacesStore,
        weatherStore: PlaceWeatherStore,
        locationProvider: LocationProvider,
        citiesCatalog: CitiesCatalog = .shared
    ) {
        self.placesStore = placesStore
        self.weatherStore = weatherStore
        self.locationProvider = locationProvider
        self.citiesCatalog = citiesCatalog
    }

    /// Live convenience that creates Core Location on the owning main actor.
    convenience init(
        placesStore: PlacesStore,
        weatherStore: PlaceWeatherStore
    ) {
        // A convenience initializer must ultimately call the designated
        // initializer. It supplies the production Core Location dependency.
        self.init(
            placesStore: placesStore,
            weatherStore: weatherStore,
            locationProvider: LocationProvider()
        )
    }

    // MARK: - Saved-Place Forecasts

    /// Forecast snapshots corresponding to the complete saved library.
    var savedWeather: [CityWeather] {
        // `compactMap` skips saved places whose forecast has not loaded yet,
        // rather than manufacturing an empty or misleading weather value.
        placesStore.allPlaces.compactMap {
            weatherStore.weather(for: $0.id)
        }
    }

    /// Loads saved forecasts without requesting or reading current location.
    func loadSavedWeather(
        forceRefresh: Bool = false,
        locale: Locale = .autoupdatingCurrent
    ) async {
        // The model coordinates the operation; PlaceWeatherStore owns fetching,
        // caching, retry policy, and the resulting per-city weather snapshots.
        await weatherStore.load(
            cities: placesStore.allPlaces.map(\.city),
            forceRefresh: forceRefresh,
            locale: locale
        )

        // A legacy saved row may have arrived before its authoritative IANA
        // timezone was known. Keep that row visible while weather loads, then
        // persist WeatherKit/Apple-resolved metadata when it is complete. This
        // repairs the library in place without replacing a user alias or making
        // a missing timezone a global Saved Places load error.
        let resolvedCities = placesStore.allPlaces.compactMap { place -> City? in
            guard let weather = weatherStore.weather(for: place.id),
                  PlacesLibraryValidator.isValidCity(weather.city) else {
                return nil
            }
            return weather.city
        }
        for city in resolvedCities {
            _ = try? placesStore.savePlace(city)
        }
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
        locale: Locale = .autoupdatingCurrent
    ) async {
        guard let coordinate = locationProvider.coordinate,
              CLLocationCoordinate2DIsValid(coordinate),
              !isRefreshingLocation else {
            return
        }

        let currentCity = makeLocationCity(coordinate: coordinate)
        guard locationWeather?.id != currentCity.id else { return }

        currentWeatherRefreshID &+= 1
        let generation = currentWeatherRefreshID

        // The coordinate identifies the cache entry. Keep a matching cached
        // forecast visible while a replacement is attempted; a different
        // coordinate is still never allowed to inherit the prior location.
        locationCity = currentCity
        if locationWeather?.id != currentCity.id {
            locationWeather = weatherStore.weather(for: currentCity.id)
        }
        locationError = nil
        locationIssues = []
        retainWeatherScope()

        let weather = await weatherStore.lookup(
            city: currentCity,
            locale: locale
        )

        guard !Task.isCancelled,
              currentWeatherRefreshID == generation,
              let latestCoordinate = locationProvider.coordinate,
              CLLocationCoordinate2DIsValid(latestCoordinate),
              makeLocationCity(coordinate: latestCoordinate).id == currentCity.id else {
            return
        }

        locationWeather = weather
        if let weather {
            // Preserve WeatherKit's authoritative timezone and metadata while
            // retaining the transient current-location identity.
            locationCity = weather.city
            lastLocalRefresh = .now
            locationIssues = weatherStore.issues(for: weather.id)
        } else {
            locationIssues = unavailableWeatherIssues(
                for: currentCity.id,
                selectedDate: nil
            )
            locationError = missingLocationWeatherMessage(locale: locale)
        }
        retainWeatherScope()
    }

    /// Loads one current-location forecast and a bounded nearby-city forecast
    /// set. Date changes deliberately do not call this method: both cards read
    /// the already loaded forecasts for their newly selected literal date.
    func refreshLocation(
        forceRefresh: Bool = false,
        locale: Locale = .autoupdatingCurrent
    ) async {
        // Do not ask Core Location from here. The UI requests permission and
        // updates the provider separately; this method only consumes a usable
        // coordinate when one is already available.
        guard let coordinate = locationProvider.coordinate,
              CLLocationCoordinate2DIsValid(coordinate) else {
            clearLocationResults()
            return
        }

        // A recent, fully successful search is reusable while the user remains
        // at effectively the same coordinate. Date changes filter its forecasts
        // locally; expired, partial, failed, or future-dated work is retried.
        let key = nearbySearchKey(
            coordinate: coordinate
        )
        if !forceRefresh, canReuseNearbySearch(for: key) {
            return
        }

        // `&+=` is wrapping addition. The exact integer does not matter; it is
        // a monotonically changing token used to reject older async results.
        refreshID &+= 1
        currentWeatherRefreshID &+= 1
        let generation = refreshID
        isRefreshingLocation = true
        didSearchNearby = false
        locationError = nil
        nearbySearchError = nil
        locationIssues = []
        nearbyCatalogIssues = []
        nearbyCatalogError = nil
        // Keep only a cache entry for this exact deterministic location ID.
        // This preserves last-known weather offline without pairing a changed
        // coordinate with the previous place's forecast.
        let currentCity = makeLocationCity(coordinate: coordinate)
        if locationWeather?.id != currentCity.id {
            locationWeather = weatherStore.weather(for: currentCity.id)
            lastLocalRefresh = nil
        }
        nearbyCandidates = []
        retainedPlaceIDs = []
        lastSearchKey = nil
        lastSearchCompletedAt = nil

        // `defer` always runs when this async function returns, including every
        // early return below. The generation check stops an old task from
        // clearing the loading state of a newer one.
        defer {
            if refreshID == generation {
                isRefreshingLocation = false
            }
        }

        // The current location is intentionally not saved to the places library.
        // It gets a reproducible transient city identity so its forecast cache
        // remains stable during this app session.
        locationCity = currentCity
        retainWeatherScope()
        // Await the current forecast before the nearby loop, because Home can
        // render this card independently even if nearby lookups later fail.
        let currentWeather = await weatherStore.lookup(
            city: currentCity,
            forceRefresh: forceRefresh,
            locale: locale
        )
        guard isActiveRefresh(generation) else { return }
        locationWeather = currentWeather
        if let currentWeather {
            // WeatherService returns the authoritatively resolved city while
            // retaining the transient UUID and exact coordinate supplied above.
            locationCity = currentWeather.city
            lastLocalRefresh = .now
            locationIssues = WeatherDataIssue.merging(
                locationIssues,
                weatherStore.issues(for: currentWeather.id)
            )
        } else {
            let issues = unavailableWeatherIssues(
                for: currentCity.id,
                selectedDate: nil
            )
            locationIssues = WeatherDataIssue.merging(locationIssues, issues)
            locationError = missingLocationWeatherMessage(locale: locale)
        }

        do {
            // Candidate choice uses population and geographic diversity only;
            // actual weather decides which of those candidates are recommended.
            let candidateResult = try await loadNearbyCandidates(
                centeredAt: coordinate
            )
            guard isActiveRefresh(generation) else { return }
            let candidates = candidateResult.candidates
            nearbyCatalogIssues = candidateResult.issues

            // Keep only the transient cache entries needed for this search,
            // rather than allowing every explored catalog city to accumulate.
            var retainedIDs: Set<City.ID> = []
            var failedLookupCount = 0
            var nearbyIssues: [WeatherDataIssue] = []
            var loadedCandidates: [NearbySunnyCityCandidate] = []
            loadedCandidates.reserveCapacity(candidates.count)

            // Look up candidates sequentially to respect the deliberately small
            // WeatherKit request budget and to make cancellation inexpensive.
            for candidate in candidates {
                guard isActiveRefresh(generation) else {
                    break
                }

                // A catalog entry may already be a saved place under a durable
                // user-visible identity. Reuse it before accessing the cache.
                let city = resolveCatalogCity(from: candidate.city)
                let weather = await weatherStore.lookup(
                    city: city,
                    forceRefresh: forceRefresh,
                    locale: locale
                )
                guard isActiveRefresh(generation) else { return }

                // Do not discard the whole search when one city fails. Record
                // the partial failure and still show every usable result.
                guard let weather else {
                    failedLookupCount += 1
                    nearbyIssues = WeatherDataIssue.merging(
                        nearbyIssues,
                        unavailableWeatherIssues(
                            for: city.id,
                            selectedDate: nil
                        )
                    )
                    continue
                }
                let resolvedCity = weather.city
                retainedIDs.insert(resolvedCity.id)
                loadedCandidates.append(
                    NearbySunnyCityCandidate(
                        city: resolvedCity,
                        distanceKilometers: candidate.distanceKilometers
                    )
                )
                // Nearby search cities are not persisted automatically, but a
                // surfaced result must keep resolving if a user opens Detail.
                if placesStore.place(id: resolvedCity.id) == nil {
                    foundCitiesByID[resolvedCity.id] = resolvedCity
                }
            }

            guard isActiveRefresh(generation) else { return }
            retainedPlaceIDs = retainedIDs
            nearbyCandidates = loadedCandidates
            didSearchNearby = true
            locationIssues = WeatherDataIssue.merging(locationIssues, nearbyIssues)
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
            if currentWeather != nil, failedLookupCount == 0 {
                lastSearchKey = key
                lastSearchCompletedAt = .now
            }
            retainWeatherScope()
        } catch is CancellationError {
            // Cancellation is expected when a newer location search supersedes
            // this one; the newer generation owns the visible state instead.
            return
        } catch let catalogError as CitiesCatalogError {
            guard isActiveRefresh(generation) else { return }
            retainedPlaceIDs = []
            nearbyCandidates = []
            nearbyCatalogIssues = []
            nearbyCatalogError = catalogError
            didSearchNearby = false
            nearbySearchError = localizedString(
                "Nearby city catalog data is missing.",
                locale: locale
            )
            lastSearchKey = nil
            lastSearchCompletedAt = nil
            retainWeatherScope()
        } catch {
            guard isActiveRefresh(generation) else { return }
            retainedPlaceIDs = []
            nearbyCandidates = []
            nearbyCatalogIssues = []
            nearbyCatalogError = nil
            didSearchNearby = false
            nearbySearchError = localizedString(
                "Nearby city forecasts are temporarily unavailable.",
                locale: locale
            )
            locationIssues = WeatherDataIssue.merging(
                locationIssues,
                [.weatherRequestFailed(error.localizedDescription)]
            )
            lastSearchKey = nil
            lastSearchCompletedAt = nil
            retainWeatherScope()
        }
    }

    // MARK: - Nearby-Sun Candidate Selection

    /// Builds a geographically balanced, population-first candidate set before
    /// making WeatherKit calls: five places in the 25–50 km ring, then up to
    /// five places in each compass quadrant from 50–200 km. Empty quadrants
    /// donate their unused slots to the remaining outer-ring candidates.
    private func loadNearbyCandidates(
        centeredAt coordinate: CLLocationCoordinate2D
    ) async throws -> (
        candidates: [CatalogCityDistanceCandidate],
        issues: [CitiesCatalogIssue]
    ) {
        // The catalog already orders its result by population. This inner query
        // intentionally leaves room for genuinely local alternatives without
        // consuming the more geographically diverse outer-ring allocation.
        let closeCandidates = try await citiesCatalog.mostPopulousCities(
            centeredAt: coordinate,
            withinKilometers: Self.nearbyInnerRadius,
            fartherThanKilometers: Self.nearbyMinDistance,
            limit: Self.nearbyCandidateLimit
        )
        // Fetch a wider catalog sample first, then partition it locally. This
        // lets an empty quadrant donate its unused slots to other directions.
        let outerCandidates = try await citiesCatalog.mostPopulousCities(
            centeredAt: coordinate,
            withinKilometers: Self.nearbySearchRadius,
            fartherThanKilometers: Self.nearbyInnerRadius,
            limit: Self.catalogScanLimit
        )

        // `Dictionary(grouping:by:)` turns one flat list into four lists while
        // preserving each list's existing population order.
        var candidatesByQuadrant = Dictionary(
            grouping: outerCandidates,
            by: { quadrant(for: $0.city, from: coordinate) }
        )
        var selectedOuterCandidates: [CatalogCityDistanceCandidate] = []

        // Give every compass direction an equal first claim on five slots.
        for quadrant in NearbySunnyQuadrant.allCases {
            let candidates = candidatesByQuadrant[quadrant] ?? []
            selectedOuterCandidates.append(contentsOf: candidates.prefix(
                Self.quadrantLimit
            ))
            // Keep only the unselected tail for potential cross-quadrant
            // backfill below. `prefix`/`dropFirst` return slices, so `Array`
            // materializes an independently stored remaining list.
            candidatesByQuadrant[quadrant] = Array(
                candidates.dropFirst(Self.quadrantLimit)
            )
        }

        // Sparse regions may not populate every quadrant. Reclaim those vacant
        // slots instead of reducing useful candidate coverage for the user.
        let unfilledSlots = max(
            0,
            Self.outerCandidateLimit - selectedOuterCandidates.count
        )
        if unfilledSlots > 0 {
            // Flatten all remaining quadrant tails, deduplicate by catalog ID,
            // then restore global population order before taking only the gap.
            let selectedIDs = Set(selectedOuterCandidates.map(\.city.id))
            selectedOuterCandidates.append(contentsOf: candidatesByQuadrant.values
                .flatMap { $0 }
                .filter { !selectedIDs.contains($0.city.id) }
                .sorted(by: populationOrder)
                .prefix(unfilledSlots)
            )
        }

        // Close-ring candidates come first only as an input order; weather
        // ranking later establishes the presentation order seen by the user.
        return (
            closeCandidates + selectedOuterCandidates,
            try await citiesCatalog.dataIssues()
        )
    }

    private func quadrant(
        for city: CatalogCity,
        from coordinate: CLLocationCoordinate2D
    ) -> NearbySunnyQuadrant {
        // Normalize longitude to -180...180 before comparing east/west. This
        // avoids assigning a city across the international date line to the
        // wrong side of a coordinate near ±180°.
        let longitudeDifference = (city.longitude - coordinate.longitude + 540)
            .truncatingRemainder(dividingBy: 360) - 180
        // Tuple pattern matching keeps the four latitude/longitude sign cases
        // explicit and exhaustive.
        switch (city.latitude >= coordinate.latitude, longitudeDifference >= 0) {
        case (true, true): return .northeast
        case (false, true): return .southeast
        case (false, false): return .southwest
        case (true, false): return .northwest
        }
    }

    private func populationOrder(
        _ lhs: CatalogCityDistanceCandidate,
        _ rhs: CatalogCityDistanceCandidate
    ) -> Bool {
        // This comparator is used only for filling unused quadrant slots. It
        // intentionally mirrors the catalog's population-first ordering.
        if lhs.city.population != rhs.city.population {
            return CitiesCatalog.populationRanksBefore(
                lhs.city.population,
                rhs.city.population
            )
        }
        if lhs.distanceKilometers != rhs.distanceKilometers {
            return lhs.distanceKilometers < rhs.distanceKilometers
        }
        return lhs.city.id < rhs.city.id
    }

    // MARK: - Derived Recommendations

    /// Builds one recommendation using the fixed app-wide sunny-hours rule:
    /// Clear and Partly Sunny each count as one full sunny hour.
    func placeRecommendation(
        for weather: CityWeather,
        on date: Date
    ) -> PlaceRecommendation? {
        placeAssessment(for: weather, on: date).recommendation
    }

    /// Produces a recommendation and its missing-data diagnostics.
    func placeAssessment(
        for weather: CityWeather,
        on date: Date
    ) -> PlaceRecommendationAssessment {
        SunnyPlacesRanking.assessment(
            for: weather,
            on: date,
            selectionCalendar: forecastCalendar
        )
    }

    /// Ranks every sunny nearby city from the stable preloaded candidate set
    /// with the exact ranking used by Best Sunny Places. This is local
    /// filtering only—no network request occurs when the date switcher changes.
    func nearbyRecommendations(
        on selectedDate: Date
    ) -> [NearestSunnyPlaceResult] {
        nearbyRecommendationAssessment(on: selectedDate).recommendations
    }

    /// Assesses every preloaded nearby candidate without conflating a missing
    /// source field with an ordinary non-sunny result.
    func nearbyRecommendationAssessment(
        on selectedDate: Date
    ) -> NearbyRecommendationsAssessment {
        var candidates: [NearestSunnyPlaceResult] = []
        var issuesByPlaceID: [City.ID: [WeatherDataIssue]] = [:]

        for candidate in nearbyCandidates {
            guard let weather = weatherStore.weather(for: candidate.city.id) else {
                issuesByPlaceID[candidate.city.id] = unavailableWeatherIssues(
                    for: candidate.city.id,
                    selectedDate: selectedDate
                )
                continue
            }

            let assessment = placeAssessment(for: weather, on: selectedDate)
            if !assessment.issues.isEmpty {
                issuesByPlaceID[candidate.city.id] = assessment.issues
            }
            guard let recommendation = assessment.recommendation,
                  recommendation.condition == .clear
                    || recommendation.condition == .partlySunny else {
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
        let ranked = SunnyPlacesRanking.ranked(
            candidates.map(\.recommendation)
        ).compactMap { candidatesByID[$0.id] }
        return NearbyRecommendationsAssessment(
            recommendations: ranked,
            issuesByPlaceID: issuesByPlaceID
        )
    }

    /// Whether the current location is shown as sunny in the app's condition
    /// vocabulary. The nearby card is unnecessary once this is already true.
    func isLocationSunny(on date: Date) -> Bool {
        switch locationSunninessAssessment(on: date) {
        case .sunny:
            return true
        case .notSunny, .unavailable:
            // Compatibility for existing visibility checks. New presentation
            // must use the tri-state method below before showing a no-sun UI.
            return false
        }
    }

    /// Distinguishes a real non-sunny forecast from missing recommendation data.
    func locationSunninessAssessment(
        on date: Date
    ) -> LocationSunninessAssessment {
        let assessment = locationRecommendationAssessment(on: date)
        guard let recommendation = assessment.recommendation else {
            return .unavailable(assessment.issues)
        }
        return recommendation.condition.isSunnyOrPartlySunny ? .sunny : .notSunny
    }

    /// Saved-place recommendations ranked for one literal calendar date.
    func savedRecommendations(on date: Date) -> [PlaceRecommendation] {
        savedRecommendationAssessment(on: date).recommendations
    }

    /// Assesses all saved destinations and retains per-place source failures for
    /// alert presentation instead of silently dropping them from the ranking.
    func savedRecommendationAssessment(
        on date: Date,
        now: Date = .now
    ) -> SavedRecommendationsAssessment {
        var recommendations: [PlaceRecommendation] = []
        var issuesByPlaceID: [City.ID: [WeatherDataIssue]] = [:]

        for place in placesStore.allPlaces {
            guard let weather = weatherStore.weather(for: place.id) else {
                issuesByPlaceID[place.id] = unavailableWeatherIssues(
                    for: place.id,
                    selectedDate: date
                )
                continue
            }

            let assessment = placeAssessment(for: weather, on: date)
            if let recommendation = assessment.recommendation {
                recommendations.append(recommendation)
            }

            // A selected literal day that has already passed at an eastbound
            // destination is an expected timezone exclusion, not missing data.
            let isExpectedDateExclusion = assessment.recommendation == nil
                && selectedDateHasPassed(
                    date,
                    in: weather.timeZone,
                    now: now
                )
            if !assessment.issues.isEmpty, !isExpectedDateExclusion {
                issuesByPlaceID[place.id] = assessment.issues
            }
        }

        return SavedRecommendationsAssessment(
            recommendations: SunnyPlacesRanking.ranked(recommendations),
            issuesByPlaceID: issuesByPlaceID
        )
    }

    /// Saved places omitted because the selected literal date has already
    /// passed there. Injecting `now` keeps the timezone rule deterministic in
    /// tests; missing loads and incomplete weather fields are excluded because
    /// they require different user-facing messages.
    func savedPlaceDateExclusions(
        on date: Date,
        now: Date = .now
    ) -> [SavedPlaceDateExclusion] {
        let selectedDay = forecastCalendar.startOfDay(for: date)

        return placesStore.allPlaces.compactMap { place in
            guard let weather = weatherStore.weather(for: place.id),
                  weather.forecastIfAvailable(
                    on: date,
                    selectionCalendar: forecastCalendar
                  ) == nil,
                  let localCurrentDate = selectionDate(
                    forLocalDayContaining: now,
                    in: weather.timeZone
                  ),
                  forecastCalendar.compare(
                    selectedDay,
                    to: localCurrentDate,
                    toGranularity: .day
                  ) == .orderedAscending else {
                return nil
            }

            return SavedPlaceDateExclusion(
                place: place,
                localCurrentDate: localCurrentDate
            )
        }
    }

    /// Converts an instant's destination-local day into the literal date used
    /// by the shared selector without preserving the absolute clock time.
    private func selectionDate(
        forLocalDayContaining date: Date,
        in timeZone: TimeZone
    ) -> Date? {
        var destinationCalendar = forecastCalendar
        destinationCalendar.timeZone = timeZone
        let components = destinationCalendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        guard let selectionDate = forecastCalendar.date(from: components) else {
            return nil
        }
        return forecastCalendar.startOfDay(for: selectionDate)
    }

    /// Creates the current location's recommendation using the same ranking
    /// rules as Saved Places, without adding it to the persisted library.
    func locationRecommendation(on date: Date) -> PlaceRecommendation? {
        locationRecommendationAssessment(on: date).recommendation
    }

    /// Current-location recommendation plus exact source gaps. This is the
    /// preferred presentation API because a nil recommendation alone cannot say
    /// whether the day was non-sunny or could not be assessed.
    func locationRecommendationAssessment(
        on date: Date
    ) -> PlaceRecommendationAssessment {
        guard let locationWeather else {
            return PlaceRecommendationAssessment(
                recommendation: nil,
                issues: unavailableWeatherIssues(
                    for: locationCity?.id,
                    selectedDate: date
                )
            )
        }
        return placeAssessment(for: locationWeather, on: date)
    }

    // MARK: - Routing and Persistence Bridges

    /// Resolves a detail route from either the library or a preloaded nearby
    /// candidate surfaced by Home.
    func city(for placeID: City.ID) -> City? {
        // Prefer the persisted library. Transient search entries are a fallback
        // because they exist only to keep a just-tapped result routable.
        if let savedCity = placesStore.place(id: placeID)?.city {
            return savedCity
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

    /// Returns the bundled, curated first-run overview with its authoritative
    /// fixed-city metadata. Forecasts load only after Saved Places has been
    /// restored, so a Settings reset never leaves the library empty while a
    /// network place lookup is pending or unavailable.
    func starterCities(
        locale _: Locale = .autoupdatingCurrent
    ) async throws -> [City] {
        let records = try await citiesCatalog.starterCities()
        let cities = records.map(makeCatalogCity)
        guard cities.allSatisfy(PlacesLibraryValidator.isValidCity) else {
            throw WeatherDataIssue.unresolvedPlace("starter places")
        }
        return cities
    }

    /// Saves a recommendation directly into Saved Places.
    @discardableResult
    func saveRecommendation(
        _ recommendation: NearestSunnyPlaceResult
    ) throws -> SavedPlace.ID {
        // PlacesStore owns duplicate validation and disk writes; this façade lets
        // a nearby-search view save a recommendation without knowing that API.
        try placesStore.savePlace(recommendation.cityWeather.city)
    }

    // MARK: - Cache Retention and Reset

    /// Keeps the disposable forecast cache aligned with saved places and the
    /// compact transient Home search scope.
    func retainWeatherScope() {
        // Start with saved places, which must always survive cache trimming.
        var retainedIDs = Set(placesStore.allPlaces.map(\.id))
        if let locationCity {
            retainedIDs.insert(locationCity.id)
        }
        retainedIDs.formUnion(retainedPlaceIDs)
        retainedIDs.formUnion(foundCitiesByID.keys)
        // The weather store discards every snapshot outside this explicit scope.
        weatherStore.retainWeather(for: retainedIDs)
    }

    /// Invalidates the completed key when an explicit app reset occurs.
    func resetLocation() {
        clearLocationState(keepingTransientCities: false)
    }

    // MARK: - Widget Publishing

    /// Publishes Saved Places to the widget extension.
    func publishWidgetCatalog(locale: Locale) {
        // Widgets receive only the lightweight place contract here; their own
        // extension code owns producing and refreshing weather presentation data.
        WidgetDataStore.save(
            WidgetDataCatalog(
                cities: placesStore.allPlaces.map { widgetCity(for: $0) },
                appLanguageIdentifier: locale.identifier
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
        locationWeather = nil
        lastLocalRefresh = nil
        nearbyCandidates = []
        isRefreshingLocation = false
        didSearchNearby = false
        locationError = nil
        nearbySearchError = nil
        locationIssues = []
        nearbyCatalogIssues = []
        nearbyCatalogError = nil
        retainedPlaceIDs = []
        if !keepingTransientCities {
            foundCitiesByID = [:]
        }
        lastSearchKey = nil
        lastSearchCompletedAt = nil
    }

    private func isActiveRefresh(_ generation: Int) -> Bool {
        // Both checks are required: tasks can be cancelled directly, or become
        // stale when a later refresh increments the generation token.
        !Task.isCancelled && refreshID == generation
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

    /// Returns the repository's structured failure, or a date-specific missing
    /// forecast issue when no more precise source error has arrived yet.
    private func unavailableWeatherIssues(
        for placeID: City.ID?,
        selectedDate: Date?
    ) -> [WeatherDataIssue] {
        guard let placeID else {
            return locationIssues.isEmpty
                ? [.missingForecastData(at: selectedDate)]
                : locationIssues
        }
        var issues = weatherStore.issues(for: placeID)
        if let failure = weatherStore.failuresByID[placeID] {
            issues.insert(failure.issue, at: 0)
        }
        if issues.isEmpty {
            issues = [.missingForecastData(at: selectedDate)]
        }
        return WeatherDataIssue.deduplicated(issues)
    }

    /// Compatibility copy for the existing nearby card while structured alert
    /// presentation migrates to `locationIssues`.
    private func missingLocationWeatherMessage(locale: Locale) -> String {
        localizedString(
            "Current-location weather data is missing.",
            locale: locale
        )
    }

    /// True only when the selected literal day precedes today's literal day in
    /// the destination timezone.
    private func selectedDateHasPassed(
        _ selectedDate: Date,
        in timeZone: TimeZone,
        now: Date
    ) -> Bool {
        guard let localCurrentDate = selectionDate(
            forLocalDayContaining: now,
            in: timeZone
        ) else { return false }
        let selectedDay = forecastCalendar.startOfDay(for: selectedDate)
        return forecastCalendar.compare(
            selectedDay,
            to: localCurrentDate,
            toGranularity: .day
        ) == .orderedAscending
    }

    private func makeLocationCity(
        coordinate: CLLocationCoordinate2D
    ) -> City {
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
    private func widgetCity(for place: SavedPlace) -> WidgetDataCity {
        // Prefer a timezone learned from the actual weather response; fall back
        // to the saved city metadata when weather has not loaded yet.
        let city = place.city
        let timeZoneID = weatherStore.weather(for: place.id)?
            .timeZone.identifier
            ?? city.timeZoneIdentifier
        // Empty daytime arrays make this explicitly a catalog hand-off, not a
        // stale weather snapshot pretending to be current widget data.
        return WidgetDataCity(
            id: WidgetDataStore.cityIdentifier(
                country: city.country,
                latitude: city.latitude,
                longitude: city.longitude
            ),
            cityName: place.displayName,
            timeZoneIdentifier: timeZoneID,
            latitude: city.latitude,
            longitude: city.longitude,
            daytimeHours: [],
            sunnyHours: [],
            partlySunnyHours: [],
            currentConditionSymbolName: nil,
            daylightBounds: nil,
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
