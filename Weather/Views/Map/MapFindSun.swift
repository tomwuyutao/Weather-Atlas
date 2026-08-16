//
//  MapFindSun.swift
//  Weather
//
//  Owns the Find Sun workflow and its presentation bridge. MapView remains
//  responsible for screen navigation and PlacesMapCanvas for MapKit rendering.
//

import CoreLocation
import MapKit
import SwiftUI

extension MapView {


    /// Keeps the phone's bottom-sheet workflow while using iPad's native page
    /// sheet, which is a larger presentation centered over the Map.
    @ViewBuilder
    func findSunSearchSheet(initialScope: SunSearchScope) -> some View {
        let sheet = MapSunSearchSheet(
            initialScope: initialScope,
            viewport: currentViewport,
            currentLocationCoordinate: locationCoordinate,
            canSearchNearMe: locationCoordinate != nil,
            locale: locale,
            runSearch: { beginSunSearch($0) }
        )

        if horizontalSizeClass == .regular {
            if #available(iOS 18.0, *) {
                sheet
                    .presentationSizing(.page)
                    .presentationDragIndicator(.visible)
            } else {
                sheet
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        } else {
            sheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Find Sun and map actions

    /// Find Sun and city previews always use the app's sunny-hours ranking.
    func beginSunSearch(
        _ scope: MapSunQueryScope,
        preservingCandidateContext: Bool = false
    ) {
        let normalizedScope = scope.normalizedForMapSearch
        selectionResetID &+= 1
        runSunSearch(
            normalizedScope,
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

    func showNearbyResults() {
        // Your Location already fetched and ranked these results. Convert that existing
        // value data to Map's transient annotation model without another
        // WeatherKit request, then clear any incompatible map selection.
        sunSearchID &+= 1
        let generation = sunSearchID
        // Keep the logical Near Me scope active even though these first dots
        // came from Your Location's cache. A later Map date change can then
        // run the full shared 200 km / 25-city query instead of leaving the
        // hand-off's old selected-day hours on screen.
        activeSunQuery = .nearMe(
            kilometers: MapSunQueryScope.nearMeRadiusKilometers
        )
        selectedSunID = nil
        selectedPreviewID = nil
        sunResultsPanelSize = .compact
        selectionResetID &+= 1
        // The hand-off can contain more places than the compact card displays.
        // Reapply the shared sunny-hours ranking here so Map's markers and
        // result panel never inherit a distance, weather-window, or view-order
        // sort.
        let results = SunnyPlacesRanking.ranked(
            router.nearbyMapResults.map(\.recommendation),
            locale: locale
        ).map {
            MapSunSearchResult(
                city: $0.cityWeather.city,
                recommendation: $0
            )
        }
        sunSearchResults = results
        // The hand-off intentionally contains only the compact Home card's
        // visible results. Do not mistake those for the complete candidate
        // context: keeping this empty makes the next date change rebuild the
        // standard 25-city population-first pool within 200 km.
        sunCandidateCities = []
        sunCameraRequest = makeSunCameraRequest(
            id: generation,
            scope: .nearMe(
                kilometers: MapSunQueryScope.nearMeRadiusKilometers
            ),
            candidateCities: results.map(\.city)
        )
    }

    /// Runs in an unstructured task because the button action is synchronous.
    /// The monotonically increasing generation makes late network responses
    /// harmless after the user changes date, scope, or clears the search.
    private func runSunSearch(
        _ scope: MapSunQueryScope,
        preservingCandidateContext: Bool
    ) {
        // Freeze the requested calendar day before this async work starts.
        // Otherwise a date change halfway through could rank and label the
        // loaded forecasts using a different day from the initiating action.
        let requestedDate = model.forecastCalendar.startOfDay(for: selectedDate)
        sunSearchID &+= 1
        let generation = sunSearchID
        // A date change reruns the same scope to refresh its results. Its
        // camera must remain untouched: a country or continent has one stable
        // geographic frame, regardless of the changing sunny-city set.
        let hasStableCandidateContext = preservingCandidateContext
            && activeSunQuery == scope
            && !sunCandidateCities.isEmpty
        let shouldReplaceContext = !hasStableCandidateContext
        let shouldFrameSearchScope = shouldReplaceContext && scope != .area
        missingDataAlerts.resolve(key: "map-find-sun-weather")
        missingDataAlerts.resolve(key: "map-find-sun-source")

        // Establish the compact loading surface before this unstructured task
        // yields. The bottom surface owns its morph animation; keeping this
        // mutation unanimated prevents MapKit from animating annotation hosts.
        isFindingSun = true
        sunResultsPanelSize = .compact
        selectedSunID = nil
        activeSunQuery = scope
        if shouldReplaceContext {
            // A different geographic query must not leave the prior scope's
            // markers visible. A date refresh of the same scope intentionally
            // keeps its current results until replacements arrive, preserving
            // annotations whose cities remain sunny on both dates.
            sunSearchResults = []
            sunCandidateCities = []
            sunCameraRequest = nil
        }

        Task {
            defer {
                if generation == sunSearchID {
                    isFindingSun = false
                }
            }

            do {
                let candidates = try await sunSearchCandidatesAfterOneSourceRetry(
                    for: scope
                )
                guard !Task.isCancelled,
                      generation == sunSearchID else { return }

                sunCandidateCities = candidates

                if shouldFrameSearchScope,
                   let cameraRequest = makeSunCameraRequest(
                       id: generation,
                       scope: scope,
                       candidateCities: candidates
                   ) {
                    sunCameraRequest = cameraRequest
                }

                var namedIssues: [MapNamedWeatherIssue] = []
                let candidatesByID = Dictionary(
                    uniqueKeysWithValues: candidates.map { ($0.id, $0) }
                )
                // During a date refresh, retain each existing marker until
                // that exact city has been re-evaluated. A fresh query starts
                // empty and adds dots only as their forecasts arrive.
                var recommendationsByID = hasStableCandidateContext
                    ? Dictionary(
                        uniqueKeysWithValues: sunSearchResults.map {
                            ($0.id, $0.recommendation)
                        }
                    )
                    : [:]

                // `PlaceWeatherStore` keeps its four-request concurrency cap,
                // while this task group receives each completion independently.
                // That lets Map reveal a city's dot as soon as its sunny-hour
                // total is available instead of waiting for the whole batch.
                await weatherStore.loadAttributionIfNeeded()
                await withTaskGroup(of: City.ID.self) { group in
                    for city in candidates {
                        group.addTask { [weatherStore, locale, city] in
                            await weatherStore.load(cities: [city], locale: locale)
                            return city.id
                        }
                    }

                    for await cityID in group {
                        guard !Task.isCancelled,
                              generation == sunSearchID else {
                            group.cancelAll()
                            return
                        }
                        guard let city = candidatesByID[cityID] else { continue }

                        recommendationsByID.removeValue(forKey: cityID)
                        if let recommendation = sunSearchRecommendation(
                            for: city,
                            on: requestedDate,
                            namedIssues: &namedIssues
                        ) {
                            recommendationsByID[cityID] = recommendation
                        }
                        sunSearchResults = mapSunSearchResults(
                            from: Array(recommendationsByID.values)
                        )
                    }
                }
                guard !Task.isCancelled,
                      generation == sunSearchID else { return }

                let results = sunSearchResults

                let uniqueIssues = Array(Set(namedIssues))
                // Find Sun is a best-effort batch query. Once it has produced
                // useful sunny results, an unavailable candidate must not cover
                // those results with a blocking alert. Preserve the alert only
                // when missing weather data leaves the search with nothing useful
                // to present; explicit single-city previews use their own path.
                if uniqueIssues.isEmpty || !results.isEmpty {
                    missingDataAlerts.resolve(key: "map-find-sun-weather")
                } else if candidates.allSatisfy({ candidate in
                    weatherStore.failuresByID[candidate.id] != nil
                }) {
                    // Every candidate failed after its regular two-attempt
                    // WeatherKit episode. Retry this explicit Find Sun batch
                    // once more before showing one systemic-failure alert.
                    let report = MissingDataAlertReport(
                        key: "map-find-sun-weather",
                        title: localizedString("Data Missing", locale: locale),
                        message: consolidatedMapWeatherMessage(uniqueIssues)
                    )
                    await missingDataAlerts.retryThenReport(
                        report,
                        recoveryKey: "map-find-sun-systemic-weather:\(generation)",
                        retry: {
                            await weatherStore.retryMissingData(
                                for: candidates,
                                locale: locale
                            )
                        },
                        isStillMissing: {
                            candidates.allSatisfy { candidate in
                                weatherStore.failuresByID[candidate.id] != nil
                            }
                        }
                    )
                }
            } catch is CancellationError {
                return
            } catch let error as MapDataAvailabilityError {
                guard generation == sunSearchID else { return }
                activeSunQuery = nil
                // The map can briefly be visible before SwiftUI has delivered
                // its first camera snapshot. That is a normal readiness state,
                // not missing user-facing data, so it must not raise an alert.
                if case .viewport = error {
                    return
                }
                missingDataAlerts.report(
                    key: "map-find-sun-source",
                    title: localizedString("Data Missing", locale: locale),
                    message: error.message(locale: locale)
                )
            } catch is CitiesCatalogError {
                guard generation == sunSearchID else { return }
                activeSunQuery = nil
                missingDataAlerts.report(
                    key: "map-find-sun-source",
                    title: localizedString("Data Missing", locale: locale),
                    message: localizedString(
                        "World city catalog data is missing.",
                        locale: locale
                    )
                )
            } catch {
                guard generation == sunSearchID else { return }
                activeSunQuery = nil
                present(error)
            }
        }
    }

    /// Evaluates one completed candidate. The Find Sun eligibility rule is the
    /// measured daylight sunny-hour total; the daily condition remains card
    /// presentation data and must not exclude a city from the query.
    private func sunSearchRecommendation(
        for city: City,
        on requestedDate: Date,
        namedIssues: inout [MapNamedWeatherIssue]
    ) -> PlaceRecommendation? {
        if let failure = weatherStore.failuresByID[city.id] {
            namedIssues.append(
                MapNamedWeatherIssue(
                    cityName: city.displayName,
                    issue: failure.issue
                )
            )
            return nil
        }
        guard let weather = weatherStore.weather(for: city.id) else {
            namedIssues.append(
                MapNamedWeatherIssue(
                    cityName: city.displayName,
                    issue: .missingForecastData(at: requestedDate)
                )
            )
            return nil
        }

        let assessment = model.placeAssessment(for: weather, on: requestedDate)
        namedIssues.append(contentsOf: assessment.issues.compactMap { issue in
            guard isRelevantMapIssue(
                issue,
                recommendationAvailable: assessment.recommendation != nil
            ) else {
                return nil
            }
            return MapNamedWeatherIssue(cityName: weather.city.displayName, issue: issue)
        })
        guard let recommendation = assessment.recommendation,
              recommendation.sunnyHourCount > 0 else {
            return nil
        }
        return recommendation
    }

    private func mapSunSearchResults(
        from recommendations: [PlaceRecommendation]
    ) -> [MapSunSearchResult] {
        SunnyPlacesRanking.ranked(recommendations, locale: locale).map {
            MapSunSearchResult(city: $0.cityWeather.city, recommendation: $0)
        }
    }

    /// Selects at most 25 candidate cities for the chosen spatial scope before
    /// WeatherKit is asked for their forecasts. Deduplication protects against
    /// catalog rows that resolve to the same stable city identifier.
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
            let records = try await model.citiesCatalog.cities(
                visibleIn: MKCoordinateRegion(
                    center: viewport.center,
                    span: MKCoordinateSpan(
                        latitudeDelta: viewport.latitudeDelta,
                        longitudeDelta: viewport.longitudeDelta
                    )
                ),
                limit: 25
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
            // Country and continent catalogs supply a bounded populous sample;
            // only those candidates incur weather requests below.
            guard !hasFatalCountryCatalogIssue else {
                throw MapDataAvailabilityError.countryCatalog
            }
            cities = CountryCityCatalog.topCities(for: country, limit: 25)
                .map(resolveSearchCity)
        case .continent(let continent):
            guard !hasFatalCountryCatalogIssue else {
                throw MapDataAvailabilityError.countryCatalog
            }
            cities = CountryCityCatalog.topCities(for: continent, limit: 25)
                .map(resolveSearchCity)
        }

        var seenIDs: Set<City.ID> = []
        return cities.filter { seenIDs.insert($0.id).inserted }
    }

    /// Resolves the one shared local candidate policy used by both city-origin
    /// Map searches. `CitiesCatalog` performs the exact Haversine-radius
    /// filter, then population-first ordering before WeatherKit is asked for
    /// any forecast, keeping the local search cheap and predictable.
    private func sharedNearbySunCandidates(
        centeredAt coordinate: CLLocationCoordinate2D
    ) async throws -> [City] {
        let records = try await model.citiesCatalog.mostPopulousCities(
            centeredAt: coordinate,
            withinKilometers: Double(
                NearbySunSearchPolicy.radiusKilometers
            ),
            limit: NearbySunSearchPolicy.candidateLimit
        )
        return records.map { resolveSearchCity(from: $0.city) }
    }

    /// A world-catalog parse can fail transiently while the app is launching.
    /// Retry the complete candidate-source operation once before the Find Sun
    /// workflow turns that absence into a native alert. This intentionally does
    /// not retry weather here: `PlaceWeatherStore.load` owns its one exact
    /// weather-response repair for every returned candidate.
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
        // The world-city source does not carry timezone data. Reuse the
        // country catalog only when its complete validated country sample has
        // exactly one IANA zone; otherwise leave this blank so Apple's exact
        // coordinate resolver can supply it without a geographic guess.
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

    func clearSunSearch() {
        // Invalidate an in-flight lookup before clearing its visible state.
        sunSearchID &+= 1
        // The bottom surface owns its morph animation. These plain mutations
        // must not start a transaction on MapKit's annotation hierarchy.
        activeSunQuery = nil
        sunResultsPanelSize = .compact
        sunSearchResults = []
        sunCandidateCities = []
        sunCameraRequest = nil
        selectedSunID = nil
        isFindingSun = false
        missingDataAlerts.resolve(key: "map-find-sun-weather")
        missingDataAlerts.resolve(key: "map-find-sun-source")
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
    func saveSearchPreview(_ result: MapSunSearchResult) -> Bool {
        do {
            let savedID = try placesStore.savePlace(result.city)
            acknowledgedSavedPlaceIDsByResultID[result.id] = savedID
            selectedPreviewID = result.id
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
        case .nearMe:
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
