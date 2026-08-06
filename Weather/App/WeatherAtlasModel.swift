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

/// Distance choices exposed directly on the Nearest Sunny Place card.
nonisolated enum NearestSunnySearchRadius: Double, CaseIterable, Identifiable,
    Sendable {
    case kilometers25 = 25
    case kilometers50 = 50
    case kilometers100 = 100
    case kilometers200 = 200

    var id: Self { self }
    var kilometers: Double { rawValue }

    var measurement: Measurement<UnitLength> {
        Measurement(value: kilometers, unit: .kilometers)
    }
}

/// A strict clear-condition result that does not require optional ranking
/// metrics such as cloud cover to be present.
struct NearestSunnyPlaceResult: Identifiable {
    let cityWeather: CityWeather
    let forecast: DailyForecast
    let distanceKilometers: Double

    var id: City.ID { cityWeather.city.id }
}

/// Stable inputs that make rebuilding Home or changing tabs a no-op.
nonisolated private struct NearestSunnySearchKey: Equatable, Sendable {
    let date: Date
    let radius: NearestSunnySearchRadius
    let roundedLatitude: Double
    let roundedLongitude: Double
    let localeIdentifier: String
    let locationDisplayName: String?
    let locationCountryName: String?
    let locationTimeZoneIdentifier: String?
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

    /// Persisted search radius controlled from the Home card.
    var nearestSunnySearchRadius: NearestSunnySearchRadius {
        didSet {
            defaults.set(
                nearestSunnySearchRadius.rawValue,
                forKey: PreferenceKey.nearestSunnyRadius
            )
        }
    }

    /// Coordinate-backed city used to retain current-location weather safely.
    private(set) var currentLocationCity: City?
    /// Weather rendered by the Home timeline card.
    private(set) var currentLocationWeather: CityWeather?
    /// First distance-ordered catalog city that is fully sunny on the date.
    private(set) var nearestSunnyRecommendation: NearestSunnyPlaceResult?
    /// Loading state shared by the timeline and nearest-sunny cards.
    private(set) var isRefreshingHomeWeather = false
    /// Distinguishes an honest no-match result from an unstarted search.
    private(set) var hasCompletedNearestSunnySearch = false
    /// Recoverable problem for the current Home location workflow.
    private(set) var homeLocationError: String?
    /// Debug-visible count of WeatherKit calls started by the latest search.
    private(set) var lastNearestSunnyWeatherQueryCount = 0
    /// Number of distance-ordered catalog cities inspected by the latest search.
    private(set) var lastNearestSunnyCheckedCityCount = 0

    /// Invalidates stale writes from overlapping date, radius, and location work.
    @ObservationIgnored private var homeRefreshGeneration = 0
    /// Prevents tab reconstruction from repeating an identical completed search.
    @ObservationIgnored private var lastCompletedSearchKey: NearestSunnySearchKey?
    /// Small transient cache scope for the last candidate walk.
    @ObservationIgnored private var retainedSearchPlaceIDs: Set<City.ID> = []
    /// Results that have been surfaced remain routable for the life of the app
    /// session, even if a later radius or date search replaces the Home card.
    @ObservationIgnored
    private var surfacedTransientCitiesByID: [City.ID: City] = [:]
    /// User defaults used only for the compact Home radius preference.
    @ObservationIgnored private let defaults: UserDefaults

    private enum PreferenceKey {
        static let nearestSunnyRadius = "nearestSunnyPlaceRadiusKilometers"
    }

    /// A strict ceiling for candidate WeatherKit calls in one search.
    private static let maximumNearestSunnyWeatherQueries = 10
    /// Avoids querying the dataset row that effectively represents the device's
    /// own coordinate after current-location weather has already been loaded.
    private static let minimumCandidateDistanceKilometers = 1.0

    /// Creates the root model from its independent domain stores.
    init(
        placesStore: PlacesStore,
        weatherStore: PlaceWeatherStore,
        locationProvider: LocationProvider,
        worldCitiesCatalog: WorldCitiesCatalog = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.placesStore = placesStore
        self.weatherStore = weatherStore
        self.locationProvider = locationProvider
        self.worldCitiesCatalog = worldCitiesCatalog
        self.defaults = defaults

        let savedRadius = defaults.double(
            forKey: PreferenceKey.nearestSunnyRadius
        )
        nearestSunnySearchRadius = NearestSunnySearchRadius(
            rawValue: savedRadius
        ) ?? .kilometers100
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

    /// Loads the current-location timeline and then walks nearest catalog cities
    /// sequentially, stopping on the first fully sunny daily condition.
    func refreshHomeWeather(
        on selectedDate: Date,
        forceRefresh: Bool = false,
        locale: Locale = .autoupdatingCurrent
    ) async {
        guard let coordinate = locationProvider.coordinate,
              CLLocationCoordinate2DIsValid(coordinate) else {
            clearHomeLocationResults()
            return
        }

        let key = nearestSunnySearchKey(
            date: selectedDate,
            coordinate: coordinate,
            locale: locale
        )
        if !forceRefresh, key == lastCompletedSearchKey {
            return
        }

        homeRefreshGeneration &+= 1
        let generation = homeRefreshGeneration
        isRefreshingHomeWeather = true
        hasCompletedNearestSunnySearch = false
        homeLocationError = nil
        nearestSunnyRecommendation = nil
        lastNearestSunnyWeatherQueryCount = 0
        lastNearestSunnyCheckedCityCount = 0

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
        let currentLookup = await weatherStore.lookup(
            city: currentCity,
            forceRefresh: forceRefresh,
            locale: locale
        )
        guard isCurrentHomeRefresh(generation) else { return }
        currentLocationWeather = currentLookup.weather

        if currentLocationIsFullySunny(on: selectedDate) {
            retainedSearchPlaceIDs = []
            hasCompletedNearestSunnySearch = true
            lastCompletedSearchKey = key
            reconcileRetainedWeather()
            logNearestSunnySearch(
                radius: nearestSunnySearchRadius,
                matchName: nil,
                hiddenBecauseCurrentLocationIsSunny: true
            )
            return
        }

        do {
            let candidates = try await worldCitiesCatalog.cities(
                centeredAt: coordinate,
                withinKilometers: nearestSunnySearchRadius.kilometers,
                fartherThanKilometers: Self.minimumCandidateDistanceKilometers,
                limit: Self.maximumNearestSunnyWeatherQueries
            )
            guard isCurrentHomeRefresh(generation) else { return }

            var retainedIDs: Set<City.ID> = []
            var queryCount = 0
            var checkedCount = 0
            var failedLookupCount = 0
            var match: NearestSunnyPlaceResult?

            for candidate in candidates {
                guard isCurrentHomeRefresh(generation),
                      queryCount < Self.maximumNearestSunnyWeatherQueries else {
                    break
                }

                let city = resolvedCatalogCity(from: candidate.city)
                let lookup = await weatherStore.lookup(
                    city: city,
                    forceRefresh: forceRefresh,
                    retriesOnFailure: false,
                    locale: locale
                )
                guard isCurrentHomeRefresh(generation) else { return }

                retainedIDs.insert(city.id)
                checkedCount += 1
                if lookup.performedWeatherKitRequest {
                    queryCount += 1
                }

                guard let weather = lookup.weather else {
                    failedLookupCount += 1
                    continue
                }
                guard let forecast = weather.forecastIfAvailable(
                    on: selectedDate
                ), forecast.isFullyClear == true else {
                    continue
                }
                match = NearestSunnyPlaceResult(
                    cityWeather: weather,
                    forecast: forecast,
                    distanceKilometers: candidate.distanceKilometers
                )
                break
            }

            guard isCurrentHomeRefresh(generation) else { return }
            retainedSearchPlaceIDs = retainedIDs
            nearestSunnyRecommendation = match
            if let match,
               placesStore.place(id: match.id) == nil {
                surfacedTransientCitiesByID[match.id] = match.cityWeather.city
            }
            lastNearestSunnyWeatherQueryCount = queryCount
            lastNearestSunnyCheckedCityCount = checkedCount
            hasCompletedNearestSunnySearch = true
            if match == nil, failedLookupCount > 0 {
                homeLocationError = localizedString(
                    "Some candidate forecasts were unavailable, so the nearest sunny place could not be confirmed.",
                    locale: locale
                )
            }
            lastCompletedSearchKey = key
            reconcileRetainedWeather()
            logNearestSunnySearch(
                radius: nearestSunnySearchRadius,
                matchName: match?.cityWeather.city.displayName,
                hiddenBecauseCurrentLocationIsSunny: false
            )
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentHomeRefresh(generation) else { return }
            retainedSearchPlaceIDs = []
            hasCompletedNearestSunnySearch = true
            homeLocationError = localizedString(
                "Nearest sunny place is temporarily unavailable.",
                locale: locale
            )
            lastCompletedSearchKey = key
            reconcileRetainedWeather()
            logNearestSunnySearch(
                radius: nearestSunnySearchRadius,
                matchName: nil,
                hiddenBecauseCurrentLocationIsSunny: false
            )
        }
    }

    /// Whether WeatherKit classified the selected day as exactly clear.
    func currentLocationIsFullySunny(on date: Date) -> Bool {
        guard let weather = currentLocationWeather,
              let forecast = weather.forecastIfAvailable(on: date) else {
            return false
        }
        return forecast.isFullyClear == true
    }

    /// Saved-place recommendations ranked for one literal calendar date.
    func savedRecommendations(on date: Date) -> [PlaceRecommendation] {
        RecommendationEngine.ranked(
            savedWeather.compactMap {
                RecommendationEngine.recommendation(for: $0, on: date)
            }
        )
    }

    /// Resolves a detail route from either the library or the one transient
    /// nearest-sunny result.
    func city(for placeID: City.ID) -> City? {
        if let savedCity = placesStore.place(id: placeID)?.city {
            return savedCity
        }
        if let transientCity = surfacedTransientCitiesByID[placeID] {
            return transientCity
        }
        guard let nearestSunnyRecommendation,
              nearestSunnyRecommendation.id == placeID else {
            return nil
        }
        return nearestSunnyRecommendation.cityWeather.city
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
        nearestSunnyRecommendation = nil
        isRefreshingHomeWeather = false
        hasCompletedNearestSunnySearch = false
        homeLocationError = nil
        lastNearestSunnyWeatherQueryCount = 0
        lastNearestSunnyCheckedCityCount = 0
        retainedSearchPlaceIDs = []
        surfacedTransientCitiesByID = [:]
        lastCompletedSearchKey = nil
    }

    /// Publishes the one Saved Places scope to the widget extension.
    func publishWidgetCatalog(locale: Locale) {
        let allPlaces = WidgetPlaceScope(
            id: "all-places",
            // Keep the stable ID so existing widget configurations continue
            // to resolve after the flat Saved Places migration.
            displayName: localizedString("Saved Places", locale: locale),
            cities: placesStore.allPlaces.map {
                widgetCity(for: $0, scopeID: "all-places", locale: locale)
            }
        )
        WidgetDataStore.save(
            WidgetDataCatalog(
                placeScopes: [allPlaces],
                appLanguageIdentifier: locale.identifier
            )
        )
    }

    private func clearHomeLocationResults() {
        homeRefreshGeneration &+= 1
        currentLocationCity = nil
        currentLocationWeather = nil
        nearestSunnyRecommendation = nil
        isRefreshingHomeWeather = false
        hasCompletedNearestSunnySearch = false
        homeLocationError = nil
        lastNearestSunnyWeatherQueryCount = 0
        lastNearestSunnyCheckedCityCount = 0
        retainedSearchPlaceIDs = []
        lastCompletedSearchKey = nil
        reconcileRetainedWeather()
    }

    private func isCurrentHomeRefresh(_ generation: Int) -> Bool {
        !Task.isCancelled && homeRefreshGeneration == generation
    }

    private func nearestSunnySearchKey(
        date: Date,
        coordinate: CLLocationCoordinate2D,
        locale: Locale
    ) -> NearestSunnySearchKey {
        let metadata = locationProvider.metadata
        return NearestSunnySearchKey(
            date: Calendar.current.startOfDay(for: date),
            radius: nearestSunnySearchRadius,
            roundedLatitude: (coordinate.latitude * 1_000).rounded() / 1_000,
            roundedLongitude: (coordinate.longitude * 1_000).rounded() / 1_000,
            localeIdentifier: locale.identifier,
            locationDisplayName: metadata?.displayName,
            locationCountryName: metadata?.countryName,
            locationTimeZoneIdentifier: metadata?.timeZoneIdentifier
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
    private func widgetCity(
        for place: SavedPlace,
        scopeID: String,
        locale: Locale
    ) -> WidgetDataCity {
        let city = place.city
        let resolvedTimeZoneIdentifier = weatherStore.weather(for: place.id)?
            .timeZone.identifier
            ?? city.timeZoneIdentifier
        return WidgetDataCity(
            id: WidgetDataStore.cityIdentifier(
                country: city.country,
                latitude: city.latitude,
                longitude: city.longitude,
                scopeID: scopeID
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

    private func logNearestSunnySearch(
        radius: NearestSunnySearchRadius,
        matchName: String?,
        hiddenBecauseCurrentLocationIsSunny: Bool
    ) {
        #if DEBUG
        let result = hiddenBecauseCurrentLocationIsSunny
            ? "hidden-current-location-clear"
            : matchName ?? "none"
        print(
            "[NearestSunnyPlace] checked \(lastNearestSunnyCheckedCityCount) cities; "
                + "WeatherKit queries: \(lastNearestSunnyWeatherQueryCount); "
                + "radius: \(Int(radius.kilometers)) km; result: \(result)"
        )
        #endif
    }
}
