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
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String? = nil,
        catalogIdentifier: String? = nil
    ) {
        self.id = id
        self.name = name
        self.titleName = titleName
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

    /// The richer reverse-geocoded locality is intentionally limited to
    /// primary headings; all ordinary place labels use `displayName`.
    var titleDisplayName: String {
        let trimmedTitle = titleName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
        return trimmedTitle.isEmpty ? displayName : trimmedTitle
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

    init(
        date: Date,
        dailyLow: Double,
        dailyHigh: Double,
        symbolName: String,
        condition: AppWeatherCondition?,
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

    func hour(in timeZone: TimeZone) -> Int {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar.component(.hour, from: date)
    }
}

// MARK: - Sunny-Place Recommendations

/// One city's usable weather facts for a selected local date.
///
/// A recommendation is valid only when the app has a daily condition and
/// complete daylight-hour data; missing source data is never represented as a
/// plausible zero-hour result.
struct PlaceRecommendation: Identifiable {
    let cityWeather: CityWeather
    let condition: AppWeatherCondition
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
            let order = lhs.cityWeather.city.displayName.compare(
                rhs.cityWeather.city.displayName,
                options: [.caseInsensitive, .diacriticInsensitive, .numeric],
                locale: locale
            )
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

/// The result of assessing one city's selected-day forecast without conflating
/// unavailable source data with an ordinary zero-sun forecast.
struct PlaceRecommendationAssessment {
    let recommendation: PlaceRecommendation?
    let issues: [WeatherDataIssue]
}

extension CityWeather {
    /// Assesses this city's selected-date forecast using the app-wide sunny
    /// hours rule. The computation belongs with the weather value it reads;
    /// presentation layers receive a compact recommendation plus diagnostics.
    func recommendationAssessment(
        on date: Date,
        selectionCalendar: Calendar = .current
    ) -> PlaceRecommendationAssessment {
        guard let forecast = forecastIfAvailable(
            on: date,
            selectionCalendar: selectionCalendar
        ) else {
            return PlaceRecommendationAssessment(
                recommendation: nil,
                issues: [.missingForecastData(at: date)]
            )
        }

        guard let condition = forecast.condition else {
            let symbol = forecast.symbolName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return PlaceRecommendationAssessment(
                recommendation: nil,
                issues: [
                    symbol.isEmpty
                        ? .missing(.missingConditionData, at: forecast.date)
                        : .unknownWeatherSymbol(symbol, at: forecast.date)
                ]
            )
        }

        let sunnyHoursData: SunnyHoursCalculation.SunnyHoursData
        switch SunnyHoursCalculation.sunnyHoursData(
            for: forecast,
            timeZone: timeZone
        ) {
        case .success(let data):
            sunnyHoursData = data
        case .failure(let issue):
            return PlaceRecommendationAssessment(
                recommendation: nil,
                issues: [issue]
            )
        }

        return PlaceRecommendationAssessment(
            recommendation: PlaceRecommendation(
                cityWeather: self,
                condition: condition,
                sunnyHourCount: SunnyHoursCalculation.sunnyHourCount(
                    in: sunnyHoursData
                )
            ),
            issues: []
        )
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
}

/// One saved destination intentionally omitted from a selected-day ranking
/// because that literal date has already passed in the destination's timezone.
struct SavedPlaceDateExclusion: Identifiable {
    /// Persisted place retained even though it has no rank for the selected day.
    let place: SavedPlace
    /// Reuse the persisted place identity for stable SwiftUI rows.
    var id: SavedPlace.ID { place.id }
}

/// Nearby recommendations for a selected date.
struct NearbyRecommendationsAssessment {
    let recommendations: [NearestSunnyPlaceResult]
}

/// Saved-place recommendations plus missing-data reasons for destinations that
/// could not be assessed for the selected day. Valid non-sunny forecasts remain
/// recommendations so each presentation can apply its own honest filter.
struct SavedRecommendationsAssessment {
    let recommendations: [PlaceRecommendation]
    let issuesByPlaceID: [City.ID: [WeatherDataIssue]]
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
/// which cities outrank the current location on that selected date.
private struct NearbySunnyCityCandidate {
    /// Resolved city identity used to retrieve its cached weather snapshot.
    let city: City
    /// Original catalog distance retained after the weather lookup completes.
    let distanceKilometers: Double
}

/// The single shared geographic sampling contract for Nearby Sunnier Places and
/// Find Sun's Near Me scope. Keeping it here prevents the two entry points
/// from slowly acquiring different radii or weather-request budgets.
enum NearbySunSearchPolicy {
    /// Search a practical day-trip radius around the current coordinate.
    static let radiusKilometers = 200
    /// Request forecasts only for the most populous cities inside that radius.
    static let candidateLimit = 25
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
    let placesStore: SavedPlacesStore
    /// Weather snapshots keyed by stable place identity.
    let weatherStore: SavedPlacesWeatherStore
    /// Current location provider that never prompts during initialization.
    let locationProvider: LocationProvider
    /// Bundled world-cities catalog used by Search and nearest-sunny lookup.
    let citiesCatalog: CitiesCatalog

    // MARK: - Current-Location State

    /// Coordinate-backed city used to retain current-location weather safely.
    private(set) var locationCity: City?
    /// Weather rendered by the Your Location timeline card.
    private(set) var locationWeather: CityWeather?
    /// Optional resolved city selected during onboarding instead of device
    /// location. When present, it supplies every current-location surface
    /// until the person explicitly chooses device location again.
    private(set) var homeLocation: City?

    /// Whether the app is currently using a permanent, manually chosen home.
    var isUsingHomeLocation: Bool { homeLocation != nil }

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
    /// Structured missing-data reasons for native alert presentation. This is
    /// independent of the compatibility string above so views never need to
    /// infer a data category by parsing localized copy.
    private(set) var locationIssues: [WeatherDataIssue] = []
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

    // MARK: - Construction

    /// Creates the root model from its independent domain stores.
    init(
        placesStore: SavedPlacesStore,
        weatherStore: SavedPlacesWeatherStore,
        locationProvider: LocationProvider,
        citiesCatalog: CitiesCatalog = .shared,
        initialHomeLocation: City?
    ) {
        self.placesStore = placesStore
        self.weatherStore = weatherStore
        self.locationProvider = locationProvider
        self.citiesCatalog = citiesCatalog
        homeLocation = initialHomeLocation
        if let homeLocation {
            locationProvider.useHomeLocation(homeLocation)
        }
    }

    /// Live convenience that creates Core Location on the owning main actor.
    convenience init(
        placesStore: SavedPlacesStore,
        weatherStore: SavedPlacesWeatherStore
    ) {
        // A convenience initializer must ultimately call the designated
        // initializer. It supplies the production Core Location dependency.
        self.init(
            placesStore: placesStore,
            weatherStore: weatherStore,
            locationProvider: LocationProvider(),
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
        forceRefresh: Bool = false,
        locale: Locale = .autoupdatingCurrent
    ) async {
        guard let coordinate = locationProvider.coordinate,
              CLLocationCoordinate2DIsValid(coordinate) else {
            clearLocationResults()
            return
        }

        let currentCity = makeLocationCity(coordinate: coordinate)
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

        // A current-location refresh follows the same blank-first policy as
        // every other replacement request. Keep the coordinate identity, but
        // do not leave an older forecast visible while the new request settles.
        locationCity = currentCity
        locationWeather = nil
        locationError = nil
        locationIssues = []
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

        locationWeather = weather
        if let weather {
            // Preserve WeatherKit's authoritative timezone and metadata while
            // retaining the transient current-location identity.
            locationCity = weather.city
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

    /// Loads a bounded nearby-city forecast set. Current-location weather has a
    /// separate lifecycle; date changes only re-rank these retained forecasts.
    func searchNearbyPlaces(
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
        let generation = refreshID
        isSearchingNearby = true
        didSearchNearby = false
        nearbySearchError = nil
        nearbyCandidates = []
        retainedPlaceIDs = []
        lastSearchKey = nil
        lastSearchCompletedAt = nil

        // `defer` always runs when this async function returns, including every
        // early return below. The generation check stops an old task from
        // clearing the loading state of a newer one.
        defer {
            if refreshID == generation {
                isSearchingNearby = false
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
            let candidateResult = try await loadNearbyCandidates(
                centeredAt: coordinate
            )
            guard isActiveRefresh(generation) else { return }
            let candidates = candidateResult.candidates

            // Keep only the transient cache entries needed for this search,
            // rather than allowing every explored catalog city to accumulate.
            var retainedIDs: Set<City.ID> = []
            var failedLookupCount = 0
            var loadedCandidates: [NearbySunnyCityCandidate] = []
            loadedCandidates.reserveCapacity(candidates.count)

            // Resolve stable identities first, then issue one batch. The weather
            // store uses at most four requests concurrently and persists the
            // complete batch once, while this model still publishes results only
            // after every candidate has settled.
            let resolvedCandidates = candidates.map { candidate in
                (
                    candidate: candidate,
                    city: resolveCatalogCity(from: candidate.city)
                )
            }
            await weatherStore.load(
                cities: resolvedCandidates.map { $0.city },
                forceRefresh: forceRefresh
            )
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
        } catch is CancellationError {
            // Cancellation is expected when a newer location search supersedes
            // this one; the newer generation owns the visible state instead.
            return
        } catch is CitiesCatalogError {
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

    // MARK: - Nearby-Sun Candidate Selection

    /// Builds the one population-first candidate set used by Nearby Sunnier
    /// Places: up to 25 catalog cities within 200 km of the current coordinate.
    /// Weather is deliberately not considered until after this fixed local pool
    /// is selected, so switching the selected date only re-ranks cached data.
    private func loadNearbyCandidates(
        centeredAt coordinate: CLLocationCoordinate2D
    ) async throws -> (
        candidates: [CatalogCityDistanceCandidate],
        issues: [CitiesCatalogIssue]
    ) {
        let candidates = try await citiesCatalog.mostPopulousCities(
            centeredAt: coordinate,
            withinKilometers: Self.nearbySearchRadius,
            limit: Self.nearbyCandidateLimit
        )
        return (
            candidates,
            try await citiesCatalog.dataIssues()
        )
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
        weather.recommendationAssessment(
            on: date,
            selectionCalendar: forecastCalendar
        )
    }

    /// Assesses every preloaded nearby candidate without conflating a missing
    /// source field with an ordinary non-sunny result. The optional `limit` is
    /// applied only after the shared sunny-hours ranking, so a Home preview can
    /// safely request its top three. If current-location weather cannot be
    /// assessed, the comparison uses zero sunny hours while the location's
    /// missing-data diagnostics remain available through its normal report.
    func nearbyRecommendationAssessment(
        on selectedDate: Date,
        locale: Locale,
        limit: Int? = nil
    ) -> NearbyRecommendationsAssessment {
        var candidates: [NearestSunnyPlaceResult] = []
        let currentSunnyHourCount = locationRecommendationAssessment(
            on: selectedDate
        ).recommendation?.sunnyHourCount ?? 0

        for candidate in nearbyCandidates {
            guard let weather = weatherStore.weather(for: candidate.city.id) else {
                continue
            }

            let assessment = placeAssessment(for: weather, on: selectedDate)
            guard let recommendation = assessment.recommendation,
                  recommendation.sunnyHourCount > currentSunnyHourCount else {
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
        return NearbyRecommendationsAssessment(
            recommendations: nearbyRecommendationLimit(
                ranked,
                limit: limit
            )
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

    /// Assesses all saved destinations and retains per-place source failures for
    /// alert presentation instead of silently dropping them from the ranking.
    func savedRecommendationAssessment(
        on date: Date,
        locale: Locale,
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
            recommendations: PlaceRecommendation.ranked(
                recommendations,
                locale: locale
            ),
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
                place: place
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
        retainedIDs.formUnion(foundCitiesByID.keys)
        // The weather store discards every snapshot outside this explicit scope.
        weatherStore.retainWeather(for: retainedIDs)
    }

    /// Invalidates the completed key when an explicit app reset occurs.
    func resetLocation() {
        homeLocation = nil
        HomeLocationStore.clear()
        clearLocationState(keepingTransientCities: false)
        locationProvider.clearLocation()
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

    /// Publishes the default Current Location plus Saved Places to every widget
    /// configuration. WidgetKit owns fresh weather requests after receiving
    /// this lightweight coordinate contract.
    func publishWidgetCatalog(locale: Locale) {
        // Widgets receive only lightweight place identities here; their own
        // extension code owns fetching and refreshing forecast presentation.
        WidgetDataStore.save(
            WidgetDataCatalog(
                cities: placesStore.allPlaces.map { widgetCity(for: $0) },
                appLanguageIdentifier: locale.identifier,
                currentLocation: widgetCurrentLocation(locale: locale)
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
        nearbyCandidates = []
        isRefreshingLocation = false
        isSearchingNearby = false
        didSearchNearby = false
        locationError = nil
        nearbySearchError = nil
        locationIssues = []
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

    /// Builds the special default widget location from the app's most recent
    /// physical or chosen-home coordinate. It is intentionally not saved to
    /// Saved Places: the stable widget ID means configuration remains on
    /// Current Location even when the device moves.
    private func widgetCurrentLocation(locale: Locale) -> WidgetDataCity? {
        guard let coordinate = locationProvider.coordinate,
              CLLocationCoordinate2DIsValid(coordinate) else {
            return nil
        }

        let metadata = locationProvider.metadata
        let displayName = CurrentLocationMetadata.localityName(
            from: metadata?.displayName
        ) ?? CurrentLocationMetadata.localityName(
            from: locationWeather?.city.name
        ) ?? localizedString("Current Location", locale: locale)
        let timeZoneID = locationWeather?.timeZone.identifier
            ?? metadata?.timeZoneIdentifier
            ?? TimeZone.autoupdatingCurrent.identifier

        return WidgetDataCity(
            id: WidgetDataStore.currentLocationIdentifier,
            cityName: displayName,
            timeZoneIdentifier: timeZoneID,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
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
