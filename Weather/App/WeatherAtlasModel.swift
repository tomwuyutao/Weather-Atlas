//
//  WeatherAtlasModel.swift
//  Weather
//
//  Purpose: Coordinates the independent places library, place-keyed forecasts,
//  and population-prefiltered nearby discovery for the new two-tab app.
//

import CoreLocation
import CryptoKit
import Foundation
import Observation

/// Root domain model shared by Home and Places.
@MainActor
@Observable
final class WeatherAtlasModel {
    /// Independent saved-place and optional-collection source of truth.
    let placesStore: PlacesStore
    /// Weather snapshots keyed by stable place identity.
    let weatherStore: PlaceWeatherStore
    /// Contextual location provider that never prompts during initialization.
    let locationProvider: LocationProvider
    /// Bundled world-cities catalog used before WeatherKit.
    let worldCitiesCatalog: WorldCitiesCatalog

    /// Persisted nearby radius and country restriction.
    var nearbyPreferences: NearbyDiscoveryPreferences {
        didSet { persistNearbyPreferences() }
    }
    /// Explicit opt-in allowing already-authorized location to refresh once on
    /// later launches without presenting a permission prompt.
    var isNearbyDiscoveryEnabled: Bool {
        didSet {
            defaults.set(
                isNearbyDiscoveryEnabled,
                forKey: PreferenceKey.enabled
            )
            if !isNearbyDiscoveryEnabled {
                clearNearbyResults()
            }
        }
    }
    /// Population-ranked catalog candidates for the current scope.
    private(set) var nearbyCandidates: [NearbyWorldCityCandidate] = []
    /// Stable app cities derived from the current catalog candidates.
    private(set) var nearbyCities: [City] = []
    /// Whether local catalog filtering or candidate weather loading is active.
    private(set) var isRefreshingNearby = false
    /// Stable user-facing nearby discovery problem.
    private(set) var nearbyDiscoveryError: String?

    /// Dataset metadata keyed by the identity used by the forecast repository.
    @ObservationIgnored
    private var nearbyMetadataByPlaceID: [City.ID: NearbyWorldCityCandidate] = [:]
    /// Invalidates stale catalog/weather writes when location or preferences
    /// trigger overlapping refreshes.
    @ObservationIgnored
    private var nearbyRefreshGeneration = 0
    /// User defaults used only for the small nearby preferences.
    @ObservationIgnored
    private let defaults: UserDefaults

    private enum PreferenceKey {
        static let enabled = "nearbyDiscoveryEnabled"
        static let radius = "nearbyDiscoveryRadiusKilometers"
        static let limitToCountry = "nearbyDiscoveryLimitToCurrentCountry"
    }

    /// Creates the root model after PlacesStore has completed legacy import.
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
        isNearbyDiscoveryEnabled = defaults.bool(
            forKey: PreferenceKey.enabled
        )

        let savedRadius = defaults.double(forKey: PreferenceKey.radius)
        let radius = NearbyDiscoveryRadius(rawValue: savedRadius) ?? .kilometers100
        nearbyPreferences = NearbyDiscoveryPreferences(
            radius: radius,
            limitToCurrentCountry: defaults.bool(
                forKey: PreferenceKey.limitToCountry
            )
        )
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

    /// Forecast snapshots corresponding to the current nearby prefilter.
    var nearbyWeather: [CityWeather] {
        nearbyCities.compactMap {
            weatherStore.weather(for: $0.id)
        }
    }

    /// Union used by the shared forecast-date control.
    var availableForecastDates: [Date] {
        RecommendationEngine.availableDates(
            in: deduplicatedWeather(savedWeather + nearbyWeather)
        )
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

    /// Refreshes the dataset candidates and all weather required by Home.
    ///
    /// The query order is a product invariant: radius/country filter, top ten
    /// by population, then WeatherKit and sunniness ranking.
    func refreshNearbyRecommendations(
        forceRefresh: Bool = false,
        locale: Locale = .autoupdatingCurrent
    ) async {
        nearbyRefreshGeneration &+= 1
        let generation = nearbyRefreshGeneration

        guard isNearbyDiscoveryEnabled else {
            clearNearbyResults()
            return
        }

        guard let coordinate = locationProvider.coordinate,
              CLLocationCoordinate2DIsValid(coordinate) else {
            clearNearbyResults()
            return
        }

        let countryCode: String?
        if nearbyPreferences.limitToCurrentCountry {
            guard let resolvedCode = locationProvider.country?.isoCountryCode else {
                clearNearbyResults()
                nearbyDiscoveryError = localizedString(
                    "Current country is still being resolved.",
                    locale: locale
                )
                return
            }
            countryCode = resolvedCode
        } else {
            countryCode = nil
        }

        isRefreshingNearby = true
        nearbyDiscoveryError = nil
        defer {
            if nearbyRefreshGeneration == generation {
                isRefreshingNearby = false
            }
        }

        do {
            let candidates = try await worldCitiesCatalog.nearbyCities(
                centeredAt: coordinate,
                radiusKilometers: nearbyPreferences.radius.kilometers,
                limitingToISOCountryCode: countryCode,
                limit: WorldCitiesCatalog.maximumCandidateCount
            )
            guard !Task.isCancelled,
                  nearbyRefreshGeneration == generation else {
                return
            }

            let converted = convertedCities(from: candidates)
            nearbyCandidates = candidates
            nearbyCities = converted.cities
            nearbyMetadataByPlaceID = converted.metadata
            reconcileRetainedWeather()

            let citiesToLoad = deduplicatedCities(
                placesStore.allPlaces.map(\.city) + converted.cities
            )
            await weatherStore.load(
                cities: citiesToLoad,
                forceRefresh: forceRefresh,
                locale: locale
            )
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled,
                  nearbyRefreshGeneration == generation else {
                return
            }
            clearNearbyResults()
            nearbyDiscoveryError = localizedString(
                "Nearby city discovery is temporarily unavailable.",
                locale: locale
            )
        }
    }

    /// Saved-place recommendations ranked for one literal calendar date.
    func savedRecommendations(on date: Date) -> [PlaceRecommendation] {
        RecommendationEngine.ranked(
            savedWeather.compactMap {
                RecommendationEngine.recommendation(
                    for: $0,
                    on: date,
                    source: .saved
                )
            }
        )
    }

    /// Nearby population candidates ranked by their fetched sunny conditions.
    func nearbyRecommendations(on date: Date) -> [PlaceRecommendation] {
        RecommendationEngine.ranked(
            nearbyWeather.compactMap { weather in
                let metadata = nearbyMetadataByPlaceID[weather.id]
                return RecommendationEngine.recommendation(
                    for: weather,
                    on: date,
                    source: placesStore.place(id: weather.id) == nil
                        ? .nearby
                        : .saved,
                    distanceKilometers: metadata?.distanceKilometers,
                    population: metadata?.city.population
                )
            }
        )
    }

    /// Combined Home ranking, deduplicated when a nearby candidate is saved.
    func homeRecommendations(on date: Date) -> [PlaceRecommendation] {
        let all = savedRecommendations(on: date)
            + nearbyRecommendations(on: date)
        var seen: Set<City.ID> = []
        return RecommendationEngine.ranked(
            all.filter { seen.insert($0.id).inserted }
        )
    }

    /// Saves a discovered place directly into All Places, optionally tagging it
    /// with one collection, then retains its stable forecast identity.
    @discardableResult
    func saveRecommendation(
        _ recommendation: PlaceRecommendation,
        in collectionID: PlaceCollection.ID? = nil
    ) throws -> SavedPlace.ID {
        try placesStore.savePlace(
            recommendation.cityWeather.city,
            in: collectionID
        )
    }

    /// Clears the transient nearby error after native alert or retry handling.
    func clearNearbyDiscoveryError() {
        nearbyDiscoveryError = nil
    }

    /// Keeps the disposable forecast cache aligned with the current saved and
    /// discovery scopes.
    func reconcileRetainedWeather() {
        weatherStore.retainWeather(
            for: Set(
                placesStore.allPlaces.map(\.id)
                    + nearbyCities.map(\.id)
            )
        )
    }

    /// Removes transient discovery state while retaining the user's settings.
    private func clearNearbyResults() {
        nearbyCandidates = []
        nearbyCities = []
        nearbyMetadataByPlaceID = [:]
        nearbyDiscoveryError = nil
        isRefreshingNearby = false
        reconcileRetainedWeather()
    }

    /// Publishes All Places and optional collections to the existing widget
    /// contract. Migrated collection IDs remain unchanged so installed widget
    /// configurations can continue resolving their former list selection.
    func publishWidgetCatalog(locale: Locale) {
        let allPlaces = WidgetDataList(
            id: "all-places",
            displayName: localizedString("All Places", locale: locale),
            cities: placesStore.allPlaces.map {
                widgetCity(for: $0, scopeID: "all-places", locale: locale)
            }
        )
        let collections = placesStore.collections.map { collection in
            WidgetDataList(
                id: collection.id,
                displayName: collection.name,
                cities: placesStore.places(in: collection.id).map {
                    widgetCity(
                        for: $0,
                        scopeID: collection.id,
                        locale: locale
                    )
                }
            )
        }
        WidgetDataStore.save(
            WidgetDataCatalog(
                lists: [allPlaces] + collections,
                appLanguageIdentifier: locale.identifier
            )
        )
    }

    /// Converts catalog rows to deterministic City identities. A matching saved
    /// coordinate reuses its persisted identity so Home never duplicates it.
    private func convertedCities(
        from candidates: [NearbyWorldCityCandidate]
    ) -> (
        cities: [City],
        metadata: [City.ID: NearbyWorldCityCandidate]
    ) {
        var cities: [City] = []
        var metadata: [City.ID: NearbyWorldCityCandidate] = [:]

        for candidate in candidates {
            let catalogCity = City(
                id: Self.stableCityID(for: candidate.city.id),
                name: candidate.city.name,
                country: candidate.city.countryName,
                latitude: candidate.city.latitude,
                longitude: candidate.city.longitude,
                timeZoneIdentifier: nil,
                catalogIdentifier: candidate.city.id
            )

            let city: City
            if let savedID = placesStore.savedPlaceID(matching: catalogCity),
               let savedPlace = placesStore.place(id: savedID) {
                city = savedPlace.city
            } else {
                city = catalogCity
            }

            guard metadata[city.id] == nil else { continue }
            cities.append(city)
            metadata[city.id] = candidate
        }
        return (cities, metadata)
    }

    /// Persists only the choices explicitly exposed by the native nearby sheet.
    private func persistNearbyPreferences() {
        defaults.set(
            nearbyPreferences.radius.rawValue,
            forKey: PreferenceKey.radius
        )
        defaults.set(
            nearbyPreferences.limitToCurrentCountry,
            forKey: PreferenceKey.limitToCountry
        )
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
                listID: scopeID
            ),
            cityName: place.customName
                ?? localizedCityDisplayName(for: city, locale: locale),
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

    private func deduplicatedCities(_ cities: [City]) -> [City] {
        var seen: Set<City.ID> = []
        return cities.filter { seen.insert($0.id).inserted }
    }

    private func deduplicatedWeather(_ weather: [CityWeather]) -> [CityWeather] {
        var seen: Set<City.ID> = []
        return weather.filter { seen.insert($0.id).inserted }
    }

    /// Derives a reproducible UUID from the world-cities dataset identity.
    nonisolated private static func stableCityID(for worldCityID: String) -> UUID {
        var bytes = Array(
            SHA256.hash(
                data: Data("weather-atlas-world-city:\(worldCityID)".utf8)
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
