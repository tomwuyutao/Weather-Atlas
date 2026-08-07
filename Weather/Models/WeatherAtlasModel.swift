//
//  WeatherAtlasModel.swift
//  Weather
//
//  Purpose: Coordinates the independent places library, place-keyed forecasts,
//  current-location weather, and the query-budgeted nearest-sunny search.
//

import CoreLocation
import CryptoKit
import Foundation
import Observation

/// A nearby recommendation ranked with the same weather criteria as Best
/// Sunny Places, while retaining the distance needed for Home's local context.
struct NearestSunnyPlaceResult: Identifiable {
    let recommendation: PlaceRecommendation
    let distanceKilometers: Double

    var id: City.ID { recommendation.id }
    var cityWeather: CityWeather { recommendation.cityWeather }
    var forecast: DailyForecast { recommendation.forecast }
}

/// Stable inputs that make rebuilding Home or changing tabs a no-op.
nonisolated private struct NearestSunnySearchKey: Equatable, Sendable {
    let roundedLatitude: Double
    let roundedLongitude: Double
}

/// One preloaded nearby city. The population-ranked candidate set stays stable
/// while users compare forecast dates, then the nearest clear city is selected
/// locally from its already loaded WeatherKit snapshot.
private struct NearbySunnyCityCandidate {
    let city: City
    let distanceKilometers: Double
}

/// Root domain model shared by Home, Map, Places, Search, and detail views.
@MainActor
@Observable
final class WeatherAtlasModel {
    /// Independent flat Saved Places source of truth.
    let placesStore: PlacesStore
    /// Weather snapshots keyed by stable place identity.
    let weatherStore: PlaceWeatherStore
    /// Current location provider that never prompts during initialization.
    let locationProvider: LocationProvider
    /// Bundled world-cities catalog used by Search and nearest-sunny lookup.
    let worldCitiesCatalog: WorldCitiesCatalog

    /// Coordinate-backed city used to retain current-location weather safely.
    private(set) var currentLocationCity: City?
    /// Weather rendered by the Home timeline card.
    private(set) var currentLocationWeather: CityWeather?
    /// Completion time of the most recent current-location weather lookup.
    private(set) var lastHomeRefreshDate: Date?

    /// The app-wide forecast day follows the user's actual location, rather
    /// than the device's configured time zone. City forecasts still retain
    /// their own zones internally; this calendar supplies the literal day the
    /// user selected everywhere in the interface.
    var forecastCalendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = currentLocationTimeZone
        return calendar
    }

    /// Uses reverse-geocoded location metadata as soon as it arrives, then the
    /// WeatherKit-resolved city zone, with the device zone only as a safe
    /// fallback before a current location exists.
    var currentLocationTimeZone: TimeZone {
        if let identifier = locationProvider.metadata?.timeZoneIdentifier,
           let timeZone = TimeZone(identifier: identifier) {
            return timeZone
        }
        if let timeZone = currentLocationWeather?.timeZone {
            return timeZone
        }
        if let identifier = currentLocationCity?.timeZoneIdentifier,
           let timeZone = TimeZone(identifier: identifier) {
            return timeZone
        }
        return .autoupdatingCurrent
    }
    /// Population-ranked nearby candidates preloaded once for the current
    /// coordinate and radius; their weather is reused for every selected date.
    private var nearbySunnyCityCandidates: [NearbySunnyCityCandidate] = []
    /// Loading state shared by the timeline and nearest-sunny cards.
    private(set) var isRefreshingHomeWeather = false
    /// Distinguishes an honest no-match result from an unstarted search.
    private(set) var hasCompletedNearestSunnySearch = false
    /// Recoverable problem for the current Home location workflow.
    private(set) var homeLocationError: String?
    /// Invalidates stale writes from overlapping location work.
    @ObservationIgnored private var homeRefreshGeneration = 0
    /// Prevents tab reconstruction from repeating an identical completed search.
    @ObservationIgnored private var lastCompletedSearchKey: NearestSunnySearchKey?
    /// Small transient cache scope for the last candidate walk.
    @ObservationIgnored private var retainedSearchPlaceIDs: Set<City.ID> = []
    /// Results that have been surfaced remain routable for the life of the app
    /// session, even if a later radius or date search replaces the Home card.
    @ObservationIgnored
    private var surfacedTransientCitiesByID: [City.ID: City] = [:]
    /// A strict ceiling for candidate WeatherKit calls in one search.
    private static let maximumNearbySunnyCityWeatherQueries = 25
    /// Home’s nearby-sun discovery always uses this fixed local scope.
    private static let nearbySunnySearchRadiusKilometers = 100.0
    /// Avoids querying the dataset row that effectively represents the device's
    /// own coordinate after current-location weather has already been loaded.
    private static let minimumCandidateDistanceKilometers = 1.0

    /// Creates the root model from its independent domain stores.
    init(
        placesStore: PlacesStore,
        weatherStore: PlaceWeatherStore,
        locationProvider: LocationProvider,
        worldCitiesCatalog: WorldCitiesCatalog = .shared
    ) {
        self.placesStore = placesStore
        self.weatherStore = weatherStore
        self.locationProvider = locationProvider
        self.worldCitiesCatalog = worldCitiesCatalog
    }

    /// Live convenience that creates Core Location on the owning main actor.
    convenience init(
        placesStore: PlacesStore,
        weatherStore: PlaceWeatherStore
    ) {
        self.init(
            placesStore: placesStore,
            weatherStore: weatherStore,
            locationProvider: LocationProvider()
        )
    }

    /// Forecast snapshots corresponding to the complete saved library.
    var savedWeather: [CityWeather] {
        placesStore.allPlaces.compactMap {
            weatherStore.weather(for: $0.id)
        }
    }

    /// Loads saved forecasts without requesting or reading current location.
    func loadSavedWeather(
        forceRefresh: Bool = false,
        locale: Locale = .autoupdatingCurrent
    ) async {
        await weatherStore.load(
            cities: placesStore.allPlaces.map(\.city),
            forceRefresh: forceRefresh,
            locale: locale
        )
    }

    /// Loads one current-location forecast and a bounded nearby-city forecast
    /// set. Date changes deliberately do not call this method: both cards read
    /// the already loaded forecasts for their newly selected literal date.
    func refreshHomeWeather(
        forceRefresh: Bool = false,
        locale: Locale = .autoupdatingCurrent
    ) async {
        guard let coordinate = locationProvider.coordinate,
              CLLocationCoordinate2DIsValid(coordinate) else {
            clearHomeLocationResults()
            return
        }

        let key = nearestSunnySearchKey(
            coordinate: coordinate
        )
        if !forceRefresh, key == lastCompletedSearchKey {
            return
        }

        homeRefreshGeneration &+= 1
        let generation = homeRefreshGeneration
        isRefreshingHomeWeather = true
        hasCompletedNearestSunnySearch = false
        homeLocationError = nil

        defer {
            if homeRefreshGeneration == generation {
                isRefreshingHomeWeather = false
            }
        }

        let currentCity = makeCurrentLocationCity(
            coordinate: coordinate,
            locale: locale
        )
        currentLocationCity = currentCity
        let currentWeather = await weatherStore.lookup(
            city: currentCity,
            forceRefresh: forceRefresh,
            locale: locale
        )
        guard isCurrentHomeRefresh(generation) else { return }
        currentLocationWeather = currentWeather
        lastHomeRefreshDate = .now

        do {
            let candidates = try await worldCitiesCatalog.mostPopulousCities(
                centeredAt: coordinate,
                withinKilometers: Self.nearbySunnySearchRadiusKilometers,
                fartherThanKilometers: Self.minimumCandidateDistanceKilometers,
                limit: Self.maximumNearbySunnyCityWeatherQueries
            )
            guard isCurrentHomeRefresh(generation) else { return }

            var retainedIDs: Set<City.ID> = []
            var failedLookupCount = 0
            var loadedCandidates: [NearbySunnyCityCandidate] = []
            loadedCandidates.reserveCapacity(candidates.count)

            for candidate in candidates {
                guard isCurrentHomeRefresh(generation) else {
                    break
                }

                let city = resolvedCatalogCity(from: candidate.city)
                let weather = await weatherStore.lookup(
                    city: city,
                    forceRefresh: forceRefresh,
                    retriesOnFailure: false,
                    locale: locale
                )
                guard isCurrentHomeRefresh(generation) else { return }

                retainedIDs.insert(city.id)
                guard weather != nil else {
                    failedLookupCount += 1
                    continue
                }
                loadedCandidates.append(
                    NearbySunnyCityCandidate(
                        city: city,
                        distanceKilometers: candidate.distanceKilometers
                    )
                )
                if placesStore.place(id: city.id) == nil {
                    surfacedTransientCitiesByID[city.id] = city
                }
            }

            guard isCurrentHomeRefresh(generation) else { return }
            retainedSearchPlaceIDs = retainedIDs
            nearbySunnyCityCandidates = loadedCandidates
            hasCompletedNearestSunnySearch = true
            if failedLookupCount > 0 {
                homeLocationError = localizedString(
                    "Some nearby city forecasts were unavailable.",
                    locale: locale
                )
            }
            lastCompletedSearchKey = key
            reconcileRetainedWeather()
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentHomeRefresh(generation) else { return }
            retainedSearchPlaceIDs = []
            nearbySunnyCityCandidates = []
            hasCompletedNearestSunnySearch = true
            homeLocationError = localizedString(
                "Nearby city forecasts are temporarily unavailable.",
                locale: locale
            )
            lastCompletedSearchKey = key
            reconcileRetainedWeather()
        }
    }

    /// Ranks every sunny nearby city from the stable preloaded candidate set
    /// with the exact scoring used by Best Sunny Places. This is local
    /// filtering only—no network request occurs when the date switcher changes.
    func nearbySunnyRecommendations(
        on selectedDate: Date
    ) -> [NearestSunnyPlaceResult] {
        let candidates = nearbySunnyCityCandidates.compactMap {
            candidate -> NearestSunnyPlaceResult? in
            guard let weather = weatherStore.weather(for: candidate.city.id),
                  let recommendation = RecommendationEngine.recommendation(
                    for: weather,
                    on: selectedDate,
                    selectionCalendar: forecastCalendar
                  ),
                  recommendation.condition == .clear
                    || recommendation.condition == .partlySunny else {
                return nil
            }
            return NearestSunnyPlaceResult(
                recommendation: recommendation,
                distanceKilometers: candidate.distanceKilometers
            )
        }
        let candidatesByID = Dictionary(
            uniqueKeysWithValues: candidates.map { ($0.id, $0) }
        )
        return RecommendationEngine.ranked(candidates.map(\.recommendation))
            .compactMap { candidatesByID[$0.id] }
    }

    /// Whether the current location is shown as sunny in the app's condition
    /// vocabulary. The nearby card is unnecessary once this is already true.
    func currentLocationIsSunny(on date: Date) -> Bool {
        guard let weather = currentLocationWeather,
              let forecast = weather.forecastIfAvailable(
                on: date,
                selectionCalendar: forecastCalendar
              ) else {
            return false
        }
        return forecast.condition?.isSunny == true
    }

    /// Saved-place recommendations ranked for one literal calendar date.
    func savedRecommendations(on date: Date) -> [PlaceRecommendation] {
        RecommendationEngine.ranked(
            savedWeather.compactMap {
                RecommendationEngine.recommendation(
                    for: $0,
                    on: date,
                    selectionCalendar: forecastCalendar
                )
            }
        )
    }

    /// Creates the current location's recommendation using the same scoring
    /// rules as Saved Places, without adding it to the persisted library.
    func currentLocationRecommendation(on date: Date) -> PlaceRecommendation? {
        guard let currentLocationWeather else { return nil }
        return RecommendationEngine.recommendation(
            for: currentLocationWeather,
            on: date,
            selectionCalendar: forecastCalendar
        )
    }

    /// Resolves a detail route from either the library or a preloaded nearby
    /// candidate surfaced by Home.
    func city(for placeID: City.ID) -> City? {
        if let savedCity = placesStore.place(id: placeID)?.city {
            return savedCity
        }
        if let transientCity = surfacedTransientCitiesByID[placeID] {
            return transientCity
        }
        return nil
    }

    /// Keeps a selected search result available to Detail until it is either
    /// explicitly saved or the app session ends.
    func registerTransientSearchCity(_ city: City) {
        surfacedTransientCitiesByID[city.id] = city
        reconcileRetainedWeather()
    }

    /// Resolves the bundled, curated first-run overview into saved-city values.
    func starterCities() async throws -> [City] {
        try await worldCitiesCatalog.starterCities().map(makeCatalogCity)
    }

    /// Saves a recommendation directly into Saved Places.
    @discardableResult
    func saveRecommendation(
        _ recommendation: NearestSunnyPlaceResult
    ) throws -> SavedPlace.ID {
        try placesStore.savePlace(recommendation.cityWeather.city)
    }

    /// Keeps the disposable forecast cache aligned with saved places and the
    /// compact transient Home search scope.
    func reconcileRetainedWeather() {
        var retainedIDs = Set(placesStore.allPlaces.map(\.id))
        if let currentLocationCity {
            retainedIDs.insert(currentLocationCity.id)
        }
        retainedIDs.formUnion(retainedSearchPlaceIDs)
        retainedIDs.formUnion(surfacedTransientCitiesByID.keys)
        weatherStore.retainWeather(for: retainedIDs)
    }

    /// Invalidates the completed key when an explicit app reset occurs.
    func resetHomeWeatherState() {
        homeRefreshGeneration &+= 1
        currentLocationCity = nil
        currentLocationWeather = nil
        lastHomeRefreshDate = nil
        nearbySunnyCityCandidates = []
        isRefreshingHomeWeather = false
        hasCompletedNearestSunnySearch = false
        homeLocationError = nil
        retainedSearchPlaceIDs = []
        surfacedTransientCitiesByID = [:]
        lastCompletedSearchKey = nil
    }

    /// Publishes Saved Places to the widget extension.
    func publishWidgetCatalog(locale: Locale) {
        WidgetDataStore.save(
            WidgetDataCatalog(
                cities: placesStore.allPlaces.map { widgetCity(for: $0) },
                appLanguageIdentifier: locale.identifier
            )
        )
    }

    private func clearHomeLocationResults() {
        homeRefreshGeneration &+= 1
        currentLocationCity = nil
        currentLocationWeather = nil
        nearbySunnyCityCandidates = []
        isRefreshingHomeWeather = false
        hasCompletedNearestSunnySearch = false
        homeLocationError = nil
        retainedSearchPlaceIDs = []
        lastCompletedSearchKey = nil
        reconcileRetainedWeather()
    }

    private func isCurrentHomeRefresh(_ generation: Int) -> Bool {
        !Task.isCancelled && homeRefreshGeneration == generation
    }

    private func nearestSunnySearchKey(
        coordinate: CLLocationCoordinate2D
    ) -> NearestSunnySearchKey {
        return NearestSunnySearchKey(
            roundedLatitude: (coordinate.latitude * 1_000).rounded() / 1_000,
            roundedLongitude: (coordinate.longitude * 1_000).rounded() / 1_000
        )
    }

    private func makeCurrentLocationCity(
        coordinate: CLLocationCoordinate2D,
        locale: Locale
    ) -> City {
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
            name: metadata?.displayName
                ?? localizedString("Current Location", locale: locale),
            country: metadata?.countryName ?? "",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timeZoneIdentifier: metadata?.timeZoneIdentifier
        )
    }

    private func makeCatalogCity(from record: WorldCityRecord) -> City {
        City(
            id: Self.stableCityID(namespace: "world-city", value: record.id),
            name: record.name,
            country: record.countryName,
            latitude: record.latitude,
            longitude: record.longitude,
            catalogIdentifier: record.id
        )
    }

    /// Reuses a durable saved identity for a catalog city whenever Search has
    /// already added it to Saved Places.
    private func resolvedCatalogCity(from record: WorldCityRecord) -> City {
        let catalogCity = makeCatalogCity(from: record)
        guard let savedID = placesStore.savedPlaceID(matching: catalogCity),
              let savedCity = placesStore.place(id: savedID)?.city else {
            return catalogCity
        }
        return savedCity
    }

    /// Creates the lightweight identity contract whose weather remains owned by
    /// the widget extension.
    private func widgetCity(for place: SavedPlace) -> WidgetDataCity {
        let city = place.city
        let resolvedTimeZoneIdentifier = weatherStore.weather(for: place.id)?
            .timeZone.identifier
            ?? city.timeZoneIdentifier
        return WidgetDataCity(
            id: WidgetDataStore.cityIdentifier(
                country: city.country,
                latitude: city.latitude,
                longitude: city.longitude
            ),
            cityName: place.customName
                ?? city.displayName,
            timeZoneIdentifier: resolvedTimeZoneIdentifier,
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
        var bytes = Array(
            SHA256.hash(
                data: Data("weather-atlas-\(namespace):\(value)".utf8)
            ).prefix(16)
        )
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
