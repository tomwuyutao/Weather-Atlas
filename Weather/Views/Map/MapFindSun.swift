//
//  MapFindSun.swift
//  Weather
//
//  Purpose: Owns Find Sun queries, result ranking, persistence actions, and
//  camera requests while MapView remains responsible for screen navigation.
//

import CoreLocation
import MapKit
import SwiftUI

// MARK: - Find Sun Workflow

extension MapView {

    // MARK: - Search Lifecycle

    /// Find Sun and city previews always use the app's sunny-hours ranking.
    func beginSunSearch(
        _ scope: MapSunQueryScope,
        preservingCandidateContext: Bool = false
    ) {
        selectionResetID &+= 1
        runSunSearch(
            scope,
            preservingCandidateContext: preservingCandidateContext
        )
    }

    /// Starts the same fixed-radius, population-first search used by Near Me,
    /// but centers the candidate pool on a city the person just queried on the
    /// map. Keeping this entry point distinct avoids a UI caller accidentally
    /// substituting the device coordinate for the tapped city's coordinate.
    func beginSunSearch(near city: City) {
        beginSunSearch(.nearPlace(city))
    }

    /// Runs in an unstructured task because the button action is synchronous.
    /// The monotonically increasing generation makes late network responses
    /// harmless after the user changes scope, receives a hand-off, or clears
    /// the search. A selected-date change deliberately keeps this generation:
    /// each completion is reassessed for the current selected date instead.
    private func runSunSearch(
        _ scope: MapSunQueryScope,
        preservingCandidateContext: Bool
    ) {
        sunSearchID &+= 1
        let generation = sunSearchID
        let candidateScopeGeneration = model.currentMapCandidateScopeGeneration
        pendingAreaSunSearch = false
        // A new geographic query replaces its candidate set and camera. Date
        // changes use `rerankSunSearchForSelectedDate()` below, which works
        // entirely from these cached ten-day forecasts.
        let hasStableCandidateContext = preservingCandidateContext
            && activeSunQuery == scope
            && !sunCandidateCities.isEmpty
        let shouldReplaceContext = !hasStableCandidateContext
        let shouldFrameSearchScope = shouldReplaceContext && scope != .area
        missingDataAlerts.resolve(key: "map-find-sun-weather")
        missingDataAlerts.resolve(key: "map-find-sun-source")

        // Establish the compact loading surface before this unstructured task
        // yields. This is reserved for a new geographic query; changing only
        // the selected forecast date reranks cached data without clearing it.
        isFindingSun = true
        selectedSunID = nil
        activeSunQuery = scope
        // Forecast recommendations are date-bound. Clear them even when the
        // geographic candidate context is reusable so pending candidates show
        // neutral hosts rather than values carried over from another day.
        sunSearchResults = []
        if shouldReplaceContext {
            // A different geographic query must not leave the prior scope's
            // candidate hosts or camera frame visible. A date refresh retains
            // both while its date-bound results are rebuilt above.
            setSunCandidateCities([])
            sunCameraRequest = nil
        }

        Task {
            defer {
                if generation == sunSearchID,
                   !pendingAreaSunSearch {
                    isFindingSun = false
                }
            }

            do {
                let candidates = try await sunSearchCandidatesAfterOneSourceRetry(
                    for: scope
                )
                guard !Task.isCancelled,
                      generation == sunSearchID,
                      model.isCurrentMapCandidateScope(
                        candidateScopeGeneration
                      ) else { return }

                // Retain the complete candidate batch before either
                // attribution or WeatherKit work can suspend. Saving a result,
                // opening detail, or refreshing Home during this batch must
                // not cancel its sibling requests.
                setSunCandidateCities(candidates)

                if shouldFrameSearchScope,
                   let cameraRequest = makeSunCameraRequest(
                       id: generation,
                       scope: scope,
                       candidateCities: candidates
                   ) {
                    sunCameraRequest = cameraRequest
                }

                // `SavedPlacesWeatherStore` keeps its four-request concurrency cap,
                // while this task group receives each completion independently.
                // That lets Map reveal a city's dot as soon as its sunny-hour
                // total is available instead of waiting for the whole batch.
                // Rebuild from every candidate on each completion rather than
                // retaining date-bound partial recommendations. This lets a
                // date change during the batch preserve late completions and
                // keeps every published value on the current selected date.
                await weatherStore.loadAttributionIfNeeded()
                guard !Task.isCancelled,
                      generation == sunSearchID,
                      model.isCurrentMapCandidateScope(
                        candidateScopeGeneration
                      ) else { return }
                await withTaskGroup(of: City.ID.self) { group in
                    for city in candidates {
                        group.addTask { @MainActor [weatherStore, city] in
                            // A clear, hand-off, or full reset can happen
                            // between scheduling this child and its first
                            // execution. Do not restart an obsolete request
                            // after the shared cache scope has released it.
                            guard !Task.isCancelled,
                                  generation == sunSearchID,
                                  model.isCurrentMapCandidateScope(
                                    candidateScopeGeneration
                                  ) else {
                                return city.id
                            }
                            await weatherStore.load(cities: [city])
                            return city.id
                        }
                    }

                    for await cityID in group {
                        guard !Task.isCancelled,
                              generation == sunSearchID,
                              model.isCurrentMapCandidateScope(
                                candidateScopeGeneration
                              ) else {
                            group.cancelAll()
                            return
                        }
                        _ = cityID
                        rebuildSunSearchResults(for: selectedSunSearchDate)
                    }
                }
                guard !Task.isCancelled,
                      generation == sunSearchID,
                      model.isCurrentMapCandidateScope(
                        candidateScopeGeneration
                      ) else { return }

                rebuildSunSearchResults(for: selectedSunSearchDate)
                await reportFindSunWeatherFailureIfNeeded(
                    candidates: candidates,
                    generation: generation,
                    scopeGeneration: candidateScopeGeneration
                )
            } catch is CancellationError {
                return
            } catch let error as MapDataAvailabilityError {
                guard generation == sunSearchID,
                      model.isCurrentMapCandidateScope(
                        candidateScopeGeneration
                      ) else { return }
                // A Map canvas can receive the command before MapKit has
                // supplied its first camera snapshot. Keep the requested
                // action visibly pending and retry it exactly when a viewport
                // arrives, rather than silently dropping the tap.
                if case .viewport = error {
                    if currentViewport == nil {
                        pendingAreaSunSearch = true
                    } else {
                        // The viewport can land between the source guard and
                        // this catch. Start immediately so that one missed
                        // `onChange` cannot strand the queued action.
                        runSunSearch(
                            scope,
                            preservingCandidateContext: preservingCandidateContext
                        )
                    }
                    return
                }
                if !preservingCandidateContext {
                    activeSunQuery = nil
                }
                missingDataAlerts.report(
                    key: "map-find-sun-source",
                    title: localizedString("Data Missing", locale: locale),
                    message: error.message(locale: locale)
                )
            } catch is CitiesCatalogError {
                guard generation == sunSearchID,
                      model.isCurrentMapCandidateScope(
                        candidateScopeGeneration
                      ) else { return }
                if !preservingCandidateContext {
                    activeSunQuery = nil
                }
                missingDataAlerts.report(
                    key: "map-find-sun-source",
                    title: localizedString("Data Missing", locale: locale),
                    message: localizedString(
                        "World city catalog data is missing.",
                        locale: locale
                    )
                )
            } catch {
                guard generation == sunSearchID,
                      model.isCurrentMapCandidateScope(
                        candidateScopeGeneration
                      ) else { return }
                if !preservingCandidateContext {
                    activeSunQuery = nil
                }
                present(error)
            }
        }
    }

    // MARK: - Forecast Ranking

    /// Evaluates one completed candidate. Every available forecast remains on
    /// the Map, including zero-sun days; only the result-card subset filters to
    /// positive sunny-hour totals. A short forecast horizon simply leaves a
    /// city out for dates it does not contain.
    private func sunSearchRecommendation(
        for city: City,
        on requestedDate: Date
    ) -> PlaceRecommendation? {
        guard weatherStore.failuresByID[city.id] == nil else { return nil }
        guard let weather = weatherStore.weather(for: city.id) else { return nil }
        return model.placeRecommendation(for: weather, on: requestedDate)
    }

    private func mapSunSearchResults(
        from recommendations: [PlaceRecommendation]
    ) -> [MapSunSearchResult] {
        PlaceRecommendation.ranked(recommendations, locale: locale).map {
            MapSunSearchResult(recommendation: $0)
        }
    }

    private var selectedSunSearchDate: Date {
        model.forecastCalendar.startOfDay(for: selectedDate)
    }

    /// Every literal selector day represented by at least one cached Find Sun
    /// candidate forecast. A city can start its forecast on a different local
    /// day, so convert each daily value through that city's time zone instead
    /// of assuming a fixed ten-day horizon in the device calendar.
    var sunSearchCandidateForecastDates: [Date] {
        let forecastCalendar = model.forecastCalendar
        let dates = sunCandidateCities.flatMap { city -> [Date] in
            guard let weather = weatherStore.weather(for: city.id) else {
                return []
            }
            return weather.dailyForecasts.map { forecast in
                weather.selectionDate(
                    for: forecast,
                    selectionCalendar: forecastCalendar
                ) ?? forecastCalendar.startOfDay(for: forecast.date)
            }
        }
        return Array(Set(dates)).sorted()
    }

    /// Keep a currently selected literal date navigable while a batch is still
    /// loading or its previous forecast has disappeared. It is a preservation
    /// fallback only; every additional offered date comes from a candidate's
    /// real cached forecast above.
    var sunSearchDatePickerDates: [Date] {
        Array(
            Set(sunSearchCandidateForecastDates + [selectedSunSearchDate])
        )
        .sorted()
    }

    /// The cached response holds every currently returned forecast row. Moving
    /// the shared date only needs a synchronous reassessment of those rows; it
    /// must not clear dots or repeat the city search.
    func rerankSunSearchForSelectedDate() {
        guard let activeSunQuery else { return }

        // Nearby Sunnier Places is defined relative to the current-location
        // total as well as the selected date. Re-derive its already-cached
        // eligible set rather than reusing the previous date's membership or
        // falling back to generic >0 Near Me results.
        if activeSunQuery == .nearbySunnier {
            beginSunSearch(.nearbySunnier)
            return
        }

        // A brand-new search may still be resolving its source candidates. Do
        // not invalidate that batch: every later completion rebuilds against
        // `selectedSunSearchDate`, so it naturally joins this date instead of
        // being permanently discarded by a newer generation.
        guard !sunCandidateCities.isEmpty else {
            return
        }

        rebuildSunSearchResults(for: selectedSunSearchDate)

        // A running batch will make a final missing-data decision only after
        // all of its candidate loads have completed. For a completed query,
        // however, reranking can newly reveal a missing selected-day forecast,
        // so report that no-results condition now.
        guard !isFindingSun else { return }
        let generation = sunSearchID
        let scopeGeneration = model.currentMapCandidateScopeGeneration
        let candidates = sunCandidateCities
        Task { @MainActor in
            await reportFindSunWeatherFailureIfNeeded(
                candidates: candidates,
                generation: generation,
                scopeGeneration: scopeGeneration
            )
        }
    }

    /// Rebuilds marker and ranking values from the already retained candidate
    /// forecasts. Candidates without a cached forecast remain absent rather
    /// than requesting data during a date switch.
    private func rebuildSunSearchResults(
        for requestedDate: Date
    ) {
        let recommendations = sunCandidateCities.compactMap {
            sunSearchRecommendation(
                for: $0,
                on: requestedDate
            )
        }
        let results = mapSunSearchResults(from: recommendations)
        sunSearchResults = results

        if let selectedSunID,
           !results.contains(where: { $0.id == selectedSunID }) {
            self.selectedSunID = nil
        }

    }

    /// Keeps Find Sun's best-effort behavior: valid zero-sun forecasts remain
    /// ordinary results. A retry/alert is reserved for a total request failure,
    /// not a partial forecast horizon or a date absent from some candidates.
    private func reportFindSunWeatherFailureIfNeeded(
        candidates: [City],
        generation: Int,
        scopeGeneration: Int
    ) async {
        guard generation == sunSearchID,
              model.isCurrentMapCandidateScope(scopeGeneration),
              activeSunQuery != nil else {
            return
        }

        guard !candidates.isEmpty,
              candidates.allSatisfy({ candidate in
                  weatherStore.failuresByID[candidate.id] != nil
              }) else {
            missingDataAlerts.resolve(key: "map-find-sun-weather")
            return
        }

        let namedIssues = candidates.compactMap { city -> MapNamedWeatherIssue? in
            guard let failure = weatherStore.failuresByID[city.id] else {
                return nil
            }
            return MapNamedWeatherIssue(
                cityName: city.displayName,
                issue: failure.issue
            )
        }
        guard !namedIssues.isEmpty else {
            missingDataAlerts.resolve(key: "map-find-sun-weather")
            return
        }

        let report = MissingDataAlertReport(
            key: "map-find-sun-weather",
            title: localizedString("Data Missing", locale: locale),
            message: consolidatedMapWeatherMessage(namedIssues)
        )

        // Every candidate ended in a request failure. Retry this explicit
        // batch once before showing one systemic-failure alert. Rebuild after
        // recovery so a repaired forecast is published immediately.
        await missingDataAlerts.retryThenReport(
            report,
            recoveryKey: "map-find-sun-systemic-weather:\(generation)",
            retry: {
                guard generation == sunSearchID,
                      model.isCurrentMapCandidateScope(scopeGeneration) else {
                    return
                }
                await weatherStore.retryMissingData(for: candidates)
                guard generation == sunSearchID,
                      model.isCurrentMapCandidateScope(scopeGeneration) else {
                    return
                }
                rebuildSunSearchResults(for: selectedSunSearchDate)
            },
            isStillMissing: {
                generation == sunSearchID
                    && model.isCurrentMapCandidateScope(scopeGeneration)
                    && activeSunQuery != nil
                    && sunSearchResults.isEmpty
                    && candidates.allSatisfy { candidate in
                        weatherStore.failuresByID[candidate.id] != nil
                    }
            }
        )
    }

    // MARK: - Candidate Selection

    /// Selects up to 25 geographically distinct candidate cities before
    /// WeatherKit is asked for their forecasts. A larger population-ranked
    /// source pool backfills boroughs and other nearby locality duplicates.
    private func sunSearchCandidates(
        for scope: MapSunQueryScope
    ) async throws -> [City] {
        let cities: [City]
        switch scope {
        case .area:
            // `currentViewport` is the most recent completed camera move. It
            // keeps “This Area” tied to what the person can actually see.
            guard let viewport = currentViewport else {
                throw MapDataAvailabilityError.viewport
            }
            let records = try await model.citiesCatalog.spatiallyDistinctCities(
                visibleIn: MKCoordinateRegion(
                    center: viewport.center,
                    span: MKCoordinateSpan(
                        latitudeDelta: viewport.latitudeDelta,
                        longitudeDelta: viewport.longitudeDelta
                    )
                ),
                resultLimit: FindSunCitySamplingPolicy.resultLimit,
                sourceCandidateLimit: FindSunCitySamplingPolicy.sourceCandidateLimit,
                clusterRadiusKilometers: FindSunCitySamplingPolicy.clusterRadiusKilometers
            )
            cities = records.map(resolveSearchCity)
        case .nearMe:
            // Near Me uses the physical coordinate, not the map's center, so
            // manually panning the map does not silently change its meaning.
            // Its fixed 200 km population-first pool matches the Your
            // Location search policy; only the Map's result presentation is
            // different.
            guard let coordinate = locationCoordinate else {
                throw MapDataAvailabilityError.currentLocation
            }
            cities = try await sharedNearbySunCandidates(centeredAt: coordinate)
        case .nearbySunnier:
            // The Your Location CTA has already loaded this shared local pool.
            // Derive its strict current-location comparison from the cached
            // recommendations so Map shows the same eligible cities, not every
            // nearby place with nonzero sunny hours.
            cities = model.nearbyRecommendations(
                on: selectedSunSearchDate,
                locale: locale
            ).map(\.recommendation.cityWeather.city)
        case .nearPlace(let city):
            // A contextual map-card query keeps the same 200 km / 25-city
            // contract as Near Me. Only the center changes: it is the exact
            // city the person selected, never the device location or the
            // potentially moved map viewport.
            cities = try await sharedNearbySunCandidates(
                centeredAt: CLLocationCoordinate2D(
                    latitude: city.latitude,
                    longitude: city.longitude
                )
            )
        case .country(let country):
            // Country and continent catalogs provide a larger population-ranked
            // source pool, collapsed to 25 metro representatives before only
            // those candidates incur WeatherKit requests below.
            guard !hasFatalCountryCatalogIssue else {
                throw MapDataAvailabilityError.countryCatalog
            }
            cities = CountryCityCatalog.spatiallyDistinctTopCities(
                for: country,
                resultLimit: FindSunCitySamplingPolicy.resultLimit,
                sourceCandidateLimit: FindSunCitySamplingPolicy.sourceCandidateLimit,
                clusterRadiusKilometers: FindSunCitySamplingPolicy.clusterRadiusKilometers
            ).map(resolveSearchCity)
        case .continent(let continent):
            guard !hasFatalCountryCatalogIssue else {
                throw MapDataAvailabilityError.countryCatalog
            }
            cities = CountryCityCatalog.spatiallyDistinctTopCities(
                for: continent,
                resultLimit: FindSunCitySamplingPolicy.resultLimit,
                sourceCandidateLimit: FindSunCitySamplingPolicy.sourceCandidateLimit,
                clusterRadiusKilometers: FindSunCitySamplingPolicy.clusterRadiusKilometers
            ).map(resolveSearchCity)
        }

        var seenIDs: Set<City.ID> = []
        return cities.filter { seenIDs.insert($0.id).inserted }
    }

    /// Resolves the one shared local candidate policy used by both city-origin
    /// Map searches. `CitiesCatalog` performs the exact Haversine-radius
    /// filter, then retains population-leading metro representatives before
    /// WeatherKit is asked for any forecast, keeping the local search cheap.
    private func sharedNearbySunCandidates(
        centeredAt coordinate: CLLocationCoordinate2D
    ) async throws -> [City] {
        let records = try await model.citiesCatalog
            .mostPopulousSpatiallyDistinctCities(
            centeredAt: coordinate,
            withinKilometers: Double(
                NearbySunSearchPolicy.radiusKilometers
            ),
            resultLimit: NearbySunSearchPolicy.candidateLimit,
            sourceCandidateLimit: FindSunCitySamplingPolicy.sourceCandidateLimit,
            clusterRadiusKilometers: FindSunCitySamplingPolicy.clusterRadiusKilometers
        )
        return records.map { resolveSearchCity(from: $0.city) }
    }

    /// A world-catalog parse can fail transiently while the app is launching.
    /// Retry the complete candidate-source operation once before the Find Sun
    /// workflow turns that absence into a native alert. Weather requests use
    /// their own bounded transient-network retry in `WeatherService`.
    private func sunSearchCandidatesAfterOneSourceRetry(
        for scope: MapSunQueryScope
    ) async throws -> [City] {
        do {
            return try await sunSearchCandidates(for: scope)
        } catch is CitiesCatalogError {
            await model.citiesCatalog.reload()
            return try await sunSearchCandidates(for: scope)
        }
    }

    /// Converts catalog data into the app's `City` value, then prefers the
    /// saved copy when it exists so map identity remains consistent everywhere.
    private func resolveSearchCity(from record: CatalogCity) -> City {
        // The world-city source has no timezone column. A single-zone country
        // is still an authoritative source fact; multi-zone countries fall
        // through to the local coordinate time-zone lookup in WeatherService.
        let timeZoneIdentifier = CountryCityCatalog
            .unambiguousTimeZoneIdentifier(forISO2: record.isoCountryCode)
        let city = City(
            name: record.name,
            country: record.countryName,
            latitude: record.latitude,
            longitude: record.longitude,
            timeZoneIdentifier: timeZoneIdentifier,
            catalogIdentifier: record.id
        )
        return resolveSearchCity(city)
    }

    private func resolveSearchCity(_ city: City) -> City {
        // Prefer the persisted `City` value for an already saved result. Its
        // stable ID then matches the existing marker, cache, and detail route.
        guard let savedID = placesStore.savedPlaceID(matching: city),
              let savedCity = placesStore.place(id: savedID)?.city else {
            return city
        }
        return savedCity
    }

    // MARK: - Session and Persistence Actions

    func clearSunSearch() {
        // Invalidate an in-flight lookup before clearing its visible state.
        sunSearchID &+= 1
        // The bottom surface owns its morph animation. These plain mutations
        // must not start a transaction on MapKit's annotation hierarchy.
        activeSunQuery = nil
        sunSearchResults = []
        setSunCandidateCities([])
        sunCameraRequest = nil
        selectedSunID = nil
        isFindingSun = false
        pendingAreaSunSearch = false
        missingDataAlerts.resolve(key: "map-find-sun-weather")
        missingDataAlerts.resolve(key: "map-find-sun-source")
    }

    /// Completes a "This Area" tap that occurred during MapKit's initial
    /// camera setup. The first completed viewport is the authoritative area;
    /// no generic fallback location is substituted for it.
    func resumePendingAreaSunSearchIfPossible() {
        guard pendingAreaSunSearch,
              currentViewport != nil,
              activeSunQuery == .area else {
            return
        }
        pendingAreaSunSearch = false
        runSunSearch(.area, preservingCandidateContext: false)
    }

    private var hasFatalCountryCatalogIssue: Bool {
        CountryCityCatalog.dataIssues.contains { issue in
            switch issue {
            case .resourceMissing, .unreadableResource, .noValidCities:
                true
            case .invalidRows:
                false
            }
        }
    }

    @discardableResult
    func saveSunResult(_ result: MapSunSearchResult) -> Bool {
        do {
            let savedID = try placesStore.savePlace(result.city)
            acknowledgedSavedPlaceIDsByResultID[result.id] = savedID
            // Saving changes persistence only. The transient result remains
            // selected, its card keeps the same identity, and the map camera
            // remains exactly where the user left it.
            selectedSunID = result.id
            return true
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    func saveSearchPreview(_ city: City) -> Bool {
        do {
            let savedID = try placesStore.savePlace(city)
            acknowledgedSavedPlaceIDsByResultID[city.id] = savedID
            selectedPreviewID = city.id
            return true
        } catch {
            present(error)
            return false
        }
    }

    /// Persists a reverse-geocoded map tap without changing the canvas's
    /// selected-context state. The shared card therefore retains its existing
    /// MapCard identity and simply redraws its bookmark as filled.
    @discardableResult
    func saveTappedPlace(_ city: City) -> Bool {
        do {
            _ = try placesStore.savePlace(city)
            return true
        } catch {
            present(error)
            return false
        }
    }

    /// Removes a transient card's corresponding saved row without disturbing
    /// the active Map result, selection, or camera state.
    @discardableResult
    func removeSavedPlace(matching city: City) -> Bool {
        guard let savedID = placesStore.savedPlaceID(matching: city) else {
            return false
        }

        do {
            try placesStore.deletePlace(id: savedID)
            acknowledgedSavedPlaceIDsByResultID =
                acknowledgedSavedPlaceIDsByResultID.filter { $0.value != savedID }
            return true
        } catch {
            present(error)
            return false
        }
    }

    // MARK: - Camera Framing

    private func makeSunCameraRequest(
        id: Int,
        scope: MapSunQueryScope,
        candidateCities: [City]
    ) -> MapSunCameraRequest? {
        let kind: MapSunCameraRequest.Kind
        let origin: CLLocationCoordinate2D?
        switch scope {
        case .area:
            // "This Area" is defined by the current viewport. Refitting it
            // would change the scope after the person submits the search.
            return nil
        case .nearMe, .nearbySunnier:
            kind = .nearMe
            origin = locationCoordinate
        case .nearPlace(let city):
            kind = .nearPlace
            origin = CLLocationCoordinate2D(
                latitude: city.latitude,
                longitude: city.longitude
            )
        case .country:
            kind = .country
            origin = nil
        case .continent:
            kind = .continent
            origin = nil
        }

        return MapSunCameraRequest(
            id: id,
            kind: kind,
            // The candidate set is chosen before weather is evaluated and is
            // therefore stable when the selected forecast date changes.
            cities: candidateCities,
            originLatitude: origin?.latitude,
            originLongitude: origin?.longitude
        )
    }
}
