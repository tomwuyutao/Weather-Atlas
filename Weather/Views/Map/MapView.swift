//
//  MapView.swift
//  Weather
//
//  Purpose: Presents saved places in one immersive map while preserving
//  Weather Atlas's compact weather-dot language.
//

import CoreLocation
import MapKit
import SwiftUI
import UIKit

// MARK: - Lightweight Types Used by the Map Screen

/// The four user-facing ways to choose the geographic scope of a Find Sun
/// request. `rawValue` is only used to make the picker items identifiable.
private enum SunSearchScope: String, CaseIterable, Identifiable {
    case area
    case nearMe
    case country
    case continent

    var id: Self { self }

    func title(locale: Locale) -> String {
        switch self {
        case .area: localizedString("This Area", locale: locale)
        case .nearMe: localizedString("Near Me", locale: locale)
        case .country: localizedString("Country", locale: locale)
        case .continent: localizedString("Continent", locale: locale)
        }
    }
}

/// Keeps sheet presentation data-driven: adding another map sheet later means
/// adding a case here instead of another Boolean state property.
private enum MapSheetDestination: Identifiable {
    case findSun(initialScope: SunSearchScope)

    var id: String {
        switch self {
        case .findSun(let scope): "find-sun-\(scope.rawValue)"
        }
    }
}

/// A value-type snapshot of MapKit's visible region. Storing plain numbers
/// makes it Equatable, so SwiftUI can cheaply notice a meaningful camera move.
private struct MapViewport: Equatable {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let latitudeDelta: CLLocationDegrees
    let longitudeDelta: CLLocationDegrees

    init(region: MKCoordinateRegion) {
        latitude = region.center.latitude
        longitude = region.center.longitude
        latitudeDelta = region.span.latitudeDelta
        longitudeDelta = region.span.longitudeDelta
    }

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// A completed Find Sun request asks the canvas to frame the search scope.
/// Country and continent requests carry their complete catalog geography, not
/// just today's sunny results, so changing dates only changes dots and rows.
private struct MapSunCameraRequest: Equatable {
    enum Kind: Equatable {
        case area
        case nearMe
        case country
        case continent
    }

    let id: Int
    let kind: Kind
    let cities: [City]
    let originLatitude: CLLocationDegrees?
    let originLongitude: CLLocationDegrees?

    var origin: CLLocationCoordinate2D? {
        guard let originLatitude, let originLongitude else { return nil }
        return CLLocationCoordinate2D(
            latitude: originLatitude,
            longitude: originLongitude
        )
    }
}

/// The fully specified request passed from the Find Sun sheet to the map.
/// Unlike `SunSearchScope`, country and continent cases carry the selection.
enum MapSunQueryScope: Equatable {
    case area
    case nearMe
    case country(CountryPlacesOption)
    case continent(ContinentPlacesOption)

    func summary(locale: Locale) -> String {
        switch self {
        case .area:
            localizedString("sunny places in this map area", locale: locale)
        case .nearMe:
            localizedString("sunny places within 100 km", locale: locale)
        case .country(let country):
            String(
                format: localizedString("sunny places in %@", locale: locale),
                locale: locale,
                country.localizedName(locale: locale)
            )
        case .continent(let continent):
            String(
                format: localizedString("sunny places in %@", locale: locale),
                locale: locale,
                continent.localizedName(locale: locale)
            )
        }
    }

    /// Short scope name used as the heading of the Find Sun result panel.
    /// Country and continent results should identify the chosen region directly
    /// rather than repeat the action that produced them.
    func resultsTitle(locale: Locale) -> String {
        switch self {
        case .area:
            localizedString("This Area", locale: locale)
        case .nearMe:
            localizedString("Near Me", locale: locale)
        case .country(let country):
            country.localizedName(locale: locale)
        case .continent(let continent):
            continent.localizedName(locale: locale)
        }
    }
}

/// A transient result is intentionally separate from a saved place: it can be
/// shown and saved without becoming part of the user's library first.
struct MapSunSearchResult: Identifiable {
    let city: City
    let recommendation: PlaceRecommendation

    var id: City.ID { city.id }
    var forecast: DailyForecast { recommendation.forecast }
}

/// One place-scoped source issue used when Map consolidates missing values into
/// a single native alert instead of silently dropping markers or search rows.
private struct MapNamedWeatherIssue: Hashable {
    let cityName: String
    let issue: WeatherDataIssue
}

/// Inputs that make a Map operation impossible before weather is requested.
/// These failures leave the corresponding results empty and name the missing
/// source in a native alert.
private enum MapDataAvailabilityError: Error {
    case viewport
    case currentLocation
    case countryCatalog

    func message(locale: Locale) -> String {
        switch self {
        case .viewport:
            localizedString("Map area data is missing.", locale: locale)
        case .currentLocation:
            localizedString("Current location data is missing.", locale: locale)
        case .countryCatalog:
            localizedString("Country catalog data is missing.", locale: locale)
        }
    }
}

/// Country and continent resolved from a user-selected map coordinate.
struct MapTapRegionContext: Identifiable {
    /// The coordinate-backed city is kept transient until the person elects
    /// to save it from Detail.
    let city: City
    let locality: String?
    let country: CountryPlacesOption
    let continent: ContinentPlacesOption?

    var id: String { "\(country.id)-\(locality ?? "")" }

    func title(locale: Locale) -> String {
        let countryName = country.localizedName(locale: locale)
        guard let locality,
              !locality.isEmpty,
              locality.localizedCaseInsensitiveCompare(countryName) != .orderedSame else {
            return countryName
        }
        return "\(locality), \(countryName)"
    }
}

/// Partial factual metadata collected from Apple's two reverse geocoders for
/// the exact tapped coordinate. Missing fields are merged; none are inferred
/// from a nearby city or a broader administrative area.
private struct MapTapPlaceMetadata {
    let locality: String?
    let countryName: String?
    let isoCountryCode: String?
    let timeZone: TimeZone?

    static let empty = MapTapPlaceMetadata(
        locality: nil,
        countryName: nil,
        isoCountryCode: nil,
        timeZone: nil
    )

    func fillingMissingFields(
        from other: MapTapPlaceMetadata
    ) -> MapTapPlaceMetadata {
        MapTapPlaceMetadata(
            locality: locality ?? other.locality,
            countryName: countryName ?? other.countryName,
            isoCountryCode: isoCountryCode ?? other.isoCountryCode,
            timeZone: timeZone ?? other.timeZone
        )
    }
}

// MARK: - Map Screen

/// The top-level Map tab. It adapts the shared model into map annotations,
/// controls Find Sun, and hands presentation work to `PlacesMapCanvas`.
struct MapView: View {
    let model: WeatherModel

    @Bindable var router: AppNavigation
    @Binding var selectedDate: Date

    // MARK: View-owned UI state

    /// These values belong to this screen only. `@State` lets SwiftUI retain
    /// them while recomputing the view's body after model changes.
    @State private var sortMode: WeatherMetricMode = .sunny
    @State private var presentedError: MapUIError?
    @State private var presentedMapSheet: MapSheetDestination?
    @State private var currentViewport: MapViewport?
    @State private var activeSunQuery: MapSunQueryScope?
    @State private var sunSearchResults: [MapSunSearchResult] = []
    @State private var sunCameraRequest: MapSunCameraRequest?
    /// Retains the source-to-saved identity after persistence merges a
    /// transient provider result into an equivalent place with another UUID.
    @State private var acknowledgedSavedPlaceIDsByResultID:
        [City.ID: SavedPlace.ID] = [:]
    @State private var selectedSunID: City.ID?
    @State private var selectedPreviewID: City.ID?
    /// Lets the parent close a child-owned map card before a new transient
    /// search or Search preview takes over the map.
    @State private var selectionResetID = 0
    @State private var isFindingSun = false
    /// Rejects stale asynchronous Find Sun results after a date or scope change.
    @State private var sunSearchID = 0
    @AppStorage("showLegend") private var showsLegend = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @Environment(MissingDataAlertCenter.self) private var missingDataAlerts

    // MARK: Shared stores and derived input

    /// The root model owns persistence and WeatherKit state; these shortcuts
    /// keep the view's derived properties readable without creating new stores.
    private var placesStore: PlacesStore {
        model.placesStore
    }

    private var weatherStore: PlaceWeatherStore {
        model.weatherStore
    }

    private var savedPlaces: [SavedPlace] { placesStore.allPlaces }

    /// Joins a saved place with its selected-date weather state. The canvas
    /// receives this presentation model rather than reaching into stores.
    private var savedPresentations: [PlacesMapPlacePresentation] {
        savedPlaces.map { place in
            let weather = weatherStore.weather(for: place.id)
            return PlacesMapPlacePresentation(
                presentation: SavedPlacePresentation(
                    place: place,
                    recommendation: weather.flatMap {
                        model.placeRecommendation(for: $0, on: selectedDate)
                    },
                    isLoading: weatherStore.isLoading(place.id),
                    failureMessage:
                        weatherStore.failuresByID[place.id]?.message
                )
            )
        }
    }

    private var presentations: [PlacesMapPlacePresentation] {
        savedPresentations
    }

    /// Recommendations are ordered by the active metric, while places without
    /// usable weather remain visible at the end in a stable name order.
    private var sortedPresentations: [PlacesMapPlacePresentation] {
        let orderedRecommendations = MapOverlayOrdering.sorted(
            presentations.compactMap(\.recommendation),
            by: sortMode,
            locale: locale
        )
        let presentationsByID = Dictionary(
            uniqueKeysWithValues: presentations.map { ($0.id, $0) }
        )
        let ordered = orderedRecommendations.compactMap {
            presentationsByID[$0.id]
        }
        let unavailable = presentations
            .filter { $0.recommendation == nil }
            .sorted {
                displayName(for: $0.place).localizedStandardCompare(
                    displayName(for: $1.place)
                ) == .orderedAscending
            }
        return ordered + unavailable
    }

    /// A sorted ID list gives `.task(id:)` a stable trigger: it reloads only
    /// when the set of map cities changes, not on every body evaluation.
    private var weatherLoadID: [City.ID] {
        mapCities
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
    }

    /// A Search preview is included temporarily so the map can show and save
    /// it even before it exists in the saved-place library.
    private var mapCities: [City] {
        var cities = savedPlaces.map(\.city)
        if let preview = router.mapPreviewCity,
           !cities.contains(where: { $0.id == preview.id }) {
            cities.append(preview)
        }
        return cities
    }

    private var previewResult: MapSunSearchResult? {
        guard let city = router.mapPreviewCity,
              let weather = weatherStore.weather(for: city.id),
              let recommendation = model.placeRecommendation(
                for: weather,
                on: selectedDate
              ) else {
            return nil
        }
        return MapSunSearchResult(
            city: weather.city,
            recommendation: recommendation
        )
    }

    /// Uses the store's semantic matcher as well as exact UUIDs so duplicate
    /// provider results cannot leave a second transient dot after saving.
    private var savedPlaceIDsByTransientResultID: [City.ID: SavedPlace.ID] {
        var matches = acknowledgedSavedPlaceIDsByResultID
        var results = sunSearchResults
        if let previewResult,
           !results.contains(where: { $0.id == previewResult.id }) {
            results.append(previewResult)
        }
        for result in results {
            if let savedID = placesStore.savedPlaceID(matching: result.city) {
                matches[result.id] = savedID
            }
        }
        return matches
    }

    private var locationRecommendation: PlaceRecommendation? {
        guard model.hasWeatherForCurrentLocation,
              let weather = model.locationWeather else {
            return nil
        }
        return model.placeRecommendation(for: weather, on: selectedDate)
    }

    /// Map owns a direct current-location fetch when its marker is selected.
    /// The repository exposes this loading state immediately, including the
    /// period where a normal Home refresh already owns the same lookup.
    private var isLocationWeatherLoading: Bool {
        model.isRefreshingLocation
            || model.locationCity.map { weatherStore.isLoading($0.id) } == true
    }

    private var needsCurrentLocationWeather: Bool {
        locationCoordinate != nil && !model.hasWeatherForCurrentLocation
    }

    private var navigationTitle: String {
        localizedString("Map", locale: locale)
    }

    /// Re-evaluates only after a source revision, date, layer, preview, or
    /// current-location state changes. The task waits for active loads to finish
    /// before deciding whether this failure episode recovered or needs one alert.
    private var mapWeatherAlertContextID: String {
        let loadingPlaceIDs = mapCities
            .filter { weatherStore.isLoading($0.id) }
            .map(\.id.uuidString)
            .sorted()
            .joined(separator: ",")
        return [
            String(weatherStore.weatherRevision),
            loadingPlaceIDs,
            String(selectedDate.timeIntervalSinceReferenceDate),
            sortMode.rawValue,
            router.mapPreviewCity?.id.uuidString ?? "",
            String(describing: model.locationProvider.status),
            model.isRefreshingLocation ? "loading" : "settled"
        ].joined(separator: "|")
    }

    private var hasSystemicMapWeatherFailure: Bool {
        let cities = mapCities
        guard !cities.isEmpty else { return false }
        return cities.allSatisfy { weatherStore.failuresByID[$0.id] != nil }
    }

    private func updateVisibleMapWeatherAlert() async {
        let alertKey = "map-visible-weather"
        guard !mapCities.contains(where: { weatherStore.isLoading($0.id) }),
              !model.isRefreshingLocation else {
            return
        }

        let dateExcludedIDs = Set(
            model.savedPlaceDateExclusions(on: selectedDate).map(\.id)
        )
        var namedIssues: [MapNamedWeatherIssue] = []

        for place in savedPlaces {
            if let failure = weatherStore.failuresByID[place.id] {
                namedIssues.append(
                    MapNamedWeatherIssue(
                        cityName: displayName(for: place),
                        issue: failure.issue
                    )
                )
                continue
            }
            guard let weather = weatherStore.weather(for: place.id) else {
                continue
            }
            let assessment = model.placeAssessment(for: weather, on: selectedDate)
            namedIssues.append(contentsOf: assessment.issues.compactMap { issue in
                if issue.kind == .missingForecastData,
                   dateExcludedIDs.contains(place.id) {
                    return nil
                }
                // Search can resolve to a city that is already saved. In that
                // case the router selects the saved marker rather than creating
                // `mapPreviewCity`; still surface the hourly issue that prevents
                // this explicit foreground request from producing a card.
                let explainsExplicitSelection =
                    place.id == router.selectedMapPlaceID
                    && issue.kind == .missingHourlyData
                guard explainsExplicitSelection
                        || isRelevantMapIssue(
                            issue,
                            recommendationAvailable:
                                assessment.recommendation != nil
                        ) else {
                    return nil
                }
                return MapNamedWeatherIssue(
                    cityName: displayName(for: place),
                    issue: issue
                )
            })
        }

        if let previewCity = router.mapPreviewCity {
            if let failure = weatherStore.failuresByID[previewCity.id] {
                namedIssues.append(
                    MapNamedWeatherIssue(
                        cityName: previewCity.displayName,
                        issue: failure.issue
                    )
                )
            } else if let weather = weatherStore.weather(for: previewCity.id) {
                let assessment = model.placeAssessment(for: weather, on: selectedDate)
                namedIssues.append(contentsOf: assessment.issues.compactMap { issue in
                    let explainsExplicitPreview =
                        issue.kind == .missingHourlyData
                    guard explainsExplicitPreview
                            || isRelevantMapIssue(
                                issue,
                                recommendationAvailable:
                                    assessment.recommendation != nil
                            ) else {
                        return nil
                    }
                    return MapNamedWeatherIssue(
                        cityName: weather.city.displayName,
                        issue: issue
                    )
                })
            }
        }

        if let weather = model.locationWeather {
            let assessment = model.placeAssessment(for: weather, on: selectedDate)
            namedIssues.append(contentsOf: assessment.issues.compactMap { issue in
                guard isRelevantMapIssue(
                    issue,
                    recommendationAvailable: assessment.recommendation != nil
                ) else {
                    return nil
                }
                return MapNamedWeatherIssue(
                    cityName: CurrentLocationMetadata.localityName(
                        from: weather.city.displayName
                    ) ?? weather.city.displayName,
                    issue: issue
                )
            })
        } else if let locationCity = model.locationCity,
                  let failure = weatherStore.failuresByID[locationCity.id] {
            namedIssues.append(
                MapNamedWeatherIssue(
                    cityName: CurrentLocationMetadata.localityName(
                        from: locationCity.displayName
                    ) ?? locationCity.displayName,
                    issue: failure.issue
                )
            )
        }

        let deduplicatedIssues = Array(Set(namedIssues))
        guard !deduplicatedIssues.isEmpty else {
            missingDataAlerts.resolve(key: alertKey)
            return
        }

        // A single unavailable marker is represented on the map itself. A
        // full visible-map failure is different: retry the whole real request
        // set once, then surface one diagnostic alert only if every forecast
        // remains unavailable.
        guard hasSystemicMapWeatherFailure else {
            missingDataAlerts.resolve(key: alertKey)
            return
        }

        let report = MissingDataAlertReport(
            key: alertKey,
            title: localizedString("Data Missing", locale: locale),
            message: consolidatedMapWeatherMessage(deduplicatedIssues)
        )
        let cities = mapCities
        await missingDataAlerts.retryThenReport(
            report,
            recoveryKey: "map-visible-systemic-weather",
            retry: {
                await weatherStore.retryMissingData(for: cities, locale: locale)
            },
            isStillMissing: {
                hasSystemicMapWeatherFailure
            }
        )
    }

    /// Map alerts only for data used by the active layer. Missing UV data, for
    /// example, does not interrupt someone viewing sunny hours; selecting UV
    /// blanks those markers and then reports that exact omission.
    private func isRelevantMapIssue(
        _ issue: WeatherDataIssue,
        recommendationAvailable: Bool
    ) -> Bool {
        switch issue.kind {
        case .weatherRequestFailed,
             .unresolvedPlace,
             .missingForecastData,
             .missingTimeZone,
             .missingConditionData,
             .unknownWeatherSymbol,
             .missingCloudCoverData,
             .missingSunriseOrSunset,
             .missingSunriseData,
             .missingSunsetData,
             .invalidWeatherValue:
            return true
        case .missingApparentTemperatureData:
            return recommendationAvailable && sortMode == .feelsLike
        case .missingHourlyData:
            // Background markers stay quiet when their hourly series cannot
            // support a recommendation. The explicit saved-selection and Search-
            // preview branches above promote this issue when it blocks a requested
            // card, so that a foreground action never appears to do nothing.
            return recommendationAvailable
                && (sortMode == .feelsLike || sortMode == .visibility)
        case .missingPrecipitationChanceData:
            return recommendationAvailable && sortMode == .rainChance
        case .missingVisibilityData:
            return recommendationAvailable && sortMode == .visibility
        case .missingUVIndexData:
            return recommendationAvailable && sortMode == .uvIndex
        case .missingTemperatureData:
            // Map's temperature layer uses WeatherKit's daily high, not the
            // independently optional hourly temperature series.
            return false
        }
    }

    private func consolidatedMapWeatherMessage(
        _ namedIssues: [MapNamedWeatherIssue]
    ) -> String {
        Dictionary(grouping: namedIssues, by: { $0.issue.kind })
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { _, issues in
                let names = Array(Set(issues.map(\.cityName))).sorted()
                let formatter = ListFormatter()
                formatter.locale = locale
                let shownNames = Array(names.prefix(3))
                var placeLabel = formatter.string(from: shownNames) ?? ""
                if names.count > shownNames.count {
                    let remaining = names.count - shownNames.count
                    placeLabel += String(
                        format: localizedString(
                            " and %d more places",
                            locale: locale
                        ),
                        locale: locale,
                        remaining
                    )
                }
                return weatherDataIssueMessage(
                    issues[0].issue,
                    cityName: placeLabel,
                    locale: locale
                )
            }
            .joined(separator: "\n")
    }

    // MARK: Navigation and lifecycle

    var body: some View {
        mapBody
            // Use the navigation title rather than a custom toolbar item.
            // The latter is treated as a glass control on iOS 26, which made
            // a plain screen title look like it lived in a circular button.
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    TopForecastDateSwitcher(
                        selection: $selectedDate,
                        availableDates: ForecastDateHorizon.dates(in: model.forecastCalendar)
                    )
                }
            }
            .task(id: weatherLoadID) {
                await weatherStore.load(
                    cities: mapCities,
                    locale: locale
                )
            }
            .task(id: mapWeatherAlertContextID) {
                await updateVisibleMapWeatherAlert()
            }
            .onChange(of: selectedDate) {
                // Find Sun is date-specific. Re-run its active query so dots
                // and the selected-date capsule can never describe different days.
                if let activeSunQuery {
                    beginSunSearch(activeSunQuery)
                }
            }
            .onChange(of: router.mapPreviewCity?.id, initial: true) { _, previewID in
                selectedPreviewID = previewID
                if previewID != nil {
                    activateSunnyHoursLayer()
                    selectionResetID &+= 1
                }
            }
            .onChange(of: selectedPreviewID) { oldID, newID in
                // Keep a saved Search preview selected long enough to show the
                // in-place acknowledgement. Once its card is dismissed, the
                // ordinary saved marker becomes the sole representation.
                guard newID == nil,
                      let oldID,
                      savedPlaceIDsByTransientResultID[oldID] != nil else {
                    return
                }
                router.mapPreviewCity = nil
            }
            .onChange(of: router.nearbyMapToken) { _, requestID in
                guard requestID > 0 else { return }
                showNearbyResults()
            }
            .onChange(of: router.mapSunQueryToken, initial: true) {
                _, requestID in
                guard requestID > 0,
                      let scope = router.pendingMapSunQuery else {
                    return
                }
                // Consume the hand-off before starting async work. A later
                // Search selection can therefore replace this scope without
                // a stale Map re-evaluation running it again.
                router.pendingMapSunQuery = nil
                beginSunSearch(scope)
            }
            .sensoryFeedback(.selection, trigger: sortMode)
            .sensoryFeedback(.selection, trigger: showsLegend)
            .alert(
                presentedError?.title
                    ?? localizedString("Unable to Update Places", locale: locale),
                isPresented: errorIsPresented,
                presenting: presentedError
            ) { _ in
                Button("OK") {
                    presentedError = nil
                }
            } message: { error in
                Text(error.message)
            }
            .sheet(item: $presentedMapSheet) { destination in
                switch destination {
                case .findSun(let initialScope):
                    MapSunSearchSheet(
                        initialScope: initialScope,
                        viewport: currentViewport,
                        canSearchNearMe: locationCoordinate != nil,
                        locale: locale,
                        runSearch: beginSunSearch
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
    }

    /// Separating the large canvas from navigation chrome keeps `body` focused
    /// on screen lifecycle, toolbars, sheets, and alerts.
    @ViewBuilder
    private var mapBody: some View {
        PlacesMapCanvas(
            presentations: sortedPresentations,
            latestCachedWeatherDate: weatherStore.latestCachedWeatherDate,
            loadError: placesStore.loadErrorDescription,
            retryLoading: placesStore.retryLoading,
            selectedPlaceID: $router.selectedMapPlaceID,
            showsLegend: $showsLegend,
            sortMode: $sortMode,
            locationCoordinate: locationCoordinate,
            locationName: CurrentLocationMetadata.localityName(
                from: model.locationProvider.metadata?.displayName
                    ?? model.locationWeather?.city.displayName
            ) ?? "",
            locationRecommendation: locationRecommendation,
            isLocationWeatherLoading: isLocationWeatherLoading,
            needsLocationWeather: needsCurrentLocationWeather,
            ensureLocationWeather: {
                await model.ensureCurrentLocationWeather(locale: locale)
            },
            sunSearchResults: sunSearchResults,
            sunCameraRequest: sunCameraRequest,
            savedPlaceIDsByTransientResultID:
                savedPlaceIDsByTransientResultID,
            selectedSunID: $selectedSunID,
            previewResult: previewResult,
            selectedPreviewID: $selectedPreviewID,
            selectionResetID: selectionResetID,
            sunQueryTitle: activeSunQuery?.resultsTitle(locale: locale),
            sunQuerySummary: activeSunQuery?.summary(locale: locale),
            isFindingSun: isFindingSun,
            viewport: $currentViewport,
            displayName: displayName(for:),
            findSun: {
                presentedMapSheet = .findSun(initialScope: .area)
            },
            preloadTappedPlaceDetails: { city in
                // The regional card is an intentional decision point. Start
                // its detail forecast here so View Details can reuse the
                // store's cache or in-flight request instead of starting late.
                await weatherStore.load(cities: [city], locale: locale)
            },
            viewDetails: openTappedPlace,
            findSunInRegion: beginSunSearch,
            clearSunSearch: clearSunSearch,
            saveSunResult: saveSunResult,
            saveSearchPreview: saveSearchPreview,
            searchPlaces: {
                router.selectedTab = .search
            }
        )
    }

    // MARK: Find Sun and map actions

    /// Find Sun and city previews are always explained through the sunniness
    /// layer, so the dots, legend, and floating cards share one metric.
    private func beginSunSearch(_ scope: MapSunQueryScope) {
        activateSunnyHoursLayer()
        selectionResetID &+= 1
        runSunSearch(scope)
    }

    private func showNearbyResults() {
        // Your Location already fetched and ranked these results. Convert that existing
        // value data to Map's transient annotation model without another
        // WeatherKit request, then clear any incompatible map selection.
        sunSearchID &+= 1
        let generation = sunSearchID
        activeSunQuery = nil
        selectedSunID = nil
        selectedPreviewID = nil
        selectionResetID &+= 1
        let results = router.nearbyMapResults.map {
            MapSunSearchResult(
                city: $0.cityWeather.city,
                recommendation: $0.recommendation
            )
        }
        sunSearchResults = results
        sunCameraRequest = makeSunCameraRequest(
            id: generation,
            scope: .nearMe,
            resultCities: results.map(\.city)
        )
    }

    private func activateSunnyHoursLayer() {
        guard sortMode != .sunny else { return }
        withAnimation(.smooth(duration: 0.2)) {
            sortMode = .sunny
        }
    }

    private var locationCoordinate: CLLocationCoordinate2D? {
        guard let coordinate = model.locationProvider.coordinate,
              CLLocationCoordinate2DIsValid(coordinate) else {
            return nil
        }
        return coordinate
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { presentedError != nil },
            set: { isPresented in
                if !isPresented {
                    presentedError = nil
                }
            }
        )
    }

    private func displayName(for place: SavedPlace) -> String {
        place.customName ?? place.city.displayName
    }

    /// Opens a reverse-geocoded map tap in the existing Detail route without
    /// silently adding it to Saved Places.
    private func openTappedPlace(_ city: City) {
        if let savedPlaceID = placesStore.savedPlaceID(matching: city) {
            router.mapPath.append(.place(id: savedPlaceID))
            return
        }

        model.registerTransientCity(city)
        router.mapPath.append(.place(id: city.id))
    }

    private func present(_ error: Error) {
        presentedError = MapUIError(
            message: localizedPlacesErrorDescription(
                error,
                locale: locale
            )
        )
    }

    /// Runs in an unstructured task because the button action is synchronous.
    /// The monotonically increasing generation makes late network responses
    /// harmless after the user changes date, scope, or clears the search.
    private func runSunSearch(_ scope: MapSunQueryScope) {
        // Freeze the requested calendar day before this async work starts.
        // Otherwise a date change halfway through could rank and label the
        // loaded forecasts using a different day from the initiating action.
        let requestedDate = model.forecastCalendar.startOfDay(for: selectedDate)
        sunSearchID &+= 1
        let generation = sunSearchID
        // A date change reruns the same scope to refresh its results. Its
        // camera must remain untouched: a country or continent has one stable
        // geographic frame, regardless of the changing sunny-city set.
        let shouldFrameSearchScope = activeSunQuery != scope || sunCameraRequest == nil
        missingDataAlerts.resolve(key: "map-find-sun-weather")
        missingDataAlerts.resolve(key: "map-find-sun-source")

        // Establish the compact loading surface before this unstructured task
        // yields. A map-tap card can now collapse directly into "Finding sunny
        // places", rather than briefly passing through the idle Find Sun button.
        withAnimation(MapCardMotion.morph(reduceMotion: reduceMotion)) {
            isFindingSun = true
            selectedSunID = nil
            activeSunQuery = scope
            sunSearchResults = []
        }

        Task {
            defer {
                if generation == sunSearchID {
                    withAnimation(MapCardMotion.morph(reduceMotion: reduceMotion)) {
                        isFindingSun = false
                    }
                }
            }

            do {
                let candidates = try await sunSearchCandidatesAfterOneSourceRetry(
                    for: scope
                )
                guard !Task.isCancelled,
                      generation == sunSearchID else { return }

                await weatherStore.load(cities: candidates, locale: locale)
                guard !Task.isCancelled,
                      generation == sunSearchID else { return }

                var namedIssues: [MapNamedWeatherIssue] = []
                let recommendations: [PlaceRecommendation] = candidates.compactMap { city in
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
                        // A retention/reset operation can cancel a candidate
                        // without producing a service failure. Keep the result
                        // blank, but make that exact omission visible rather
                        // than compact-mapping the city away without explanation.
                        namedIssues.append(
                            MapNamedWeatherIssue(
                                cityName: city.displayName,
                                issue: .missingForecastData(at: requestedDate)
                            )
                        )
                        return nil
                    }
                    let assessment = model.placeAssessment(
                        for: weather,
                        on: requestedDate
                    )
                    namedIssues.append(contentsOf: assessment.issues.compactMap { issue in
                        guard isRelevantMapIssue(
                            issue,
                            recommendationAvailable:
                                assessment.recommendation != nil
                        ) else {
                            return nil
                        }
                        return MapNamedWeatherIssue(
                            cityName: weather.city.displayName,
                            issue: issue
                        )
                    })
                    guard let recommendation = assessment.recommendation,
                          recommendation.condition.isSunnyOrPartlySunny else {
                        return nil
                    }
                    return recommendation
                }
                let results = SunnyPlacesRanking.ranked(
                    recommendations,
                    locale: locale
                ).map { recommendation in
                    MapSunSearchResult(
                        city: recommendation.cityWeather.city,
                        recommendation: recommendation
                    )
                }
                withAnimation(MapCardMotion.morph(reduceMotion: reduceMotion)) {
                    sunSearchResults = results
                    if shouldFrameSearchScope {
                        sunCameraRequest = makeSunCameraRequest(
                            id: generation,
                            scope: scope,
                            resultCities: results.map(\.city)
                        )
                    }
                }

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
            guard let coordinate = locationCoordinate else {
                throw MapDataAvailabilityError.currentLocation
            }
            let records = try await model.citiesCatalog.cities(
                centeredAt: coordinate,
                withinKilometers: 100,
                limit: 25
            )
            cities = records.map { resolveSearchCity(from: $0.city) }
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

    private func clearSunSearch() {
        // Invalidate an in-flight lookup before clearing its visible state.
        sunSearchID &+= 1
        // Keep the compact result capsule and Find Sun control in the same
        // explicit transaction. With their shared glass effect ID, iOS can
        // morph the visible surface back to the Find Sun button on dismissal.
        withAnimation(MapCardMotion.morph(reduceMotion: reduceMotion)) {
            activeSunQuery = nil
            sunSearchResults = []
            selectedSunID = nil
            isFindingSun = false
        }
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

    private func saveSunResult(_ result: MapSunSearchResult) {
        do {
            let savedID = try placesStore.savePlace(result.city)
            acknowledgedSavedPlaceIDsByResultID[result.id] = savedID
            // Saving changes persistence only. The transient result remains
            // selected, its card keeps the same identity, and the map camera
            // remains exactly where the user left it.
            selectedSunID = result.id
        } catch {
            present(error)
        }
    }

    private func saveSearchPreview(_ result: MapSunSearchResult) {
        do {
            let savedID = try placesStore.savePlace(result.city)
            acknowledgedSavedPlaceIDsByResultID[result.id] = savedID
            selectedPreviewID = result.id
        } catch {
            present(error)
        }
    }

    private func makeSunCameraRequest(
        id: Int,
        scope: MapSunQueryScope,
        resultCities: [City]
    ) -> MapSunCameraRequest {
        let kind: MapSunCameraRequest.Kind
        let origin: CLLocationCoordinate2D?
        let cameraCities: [City]
        switch scope {
        case .area:
            kind = .area
            origin = nil
            cameraCities = resultCities
        case .nearMe:
            kind = .nearMe
            origin = locationCoordinate
            cameraCities = resultCities
        case .country(let country):
            kind = .country
            origin = nil
            // Use every bundled city to make the map frame the full country,
            // rather than the variable subset that is sunny today.
            cameraCities = country.cities.map(\.appCity)
        case .continent(let continent):
            kind = .continent
            origin = nil
            // A continent's complete catalog sample is likewise stable across
            // selected dates and Find Sun result counts.
            cameraCities = CountryCityCatalog.cities(for: continent)
        }

        return MapSunCameraRequest(
            id: id,
            kind: kind,
            cities: cameraCities,
            originLatitude: origin?.latitude,
            originLongitude: origin?.longitude
        )
    }
}

// MARK: - Map Quick Controls

/// Groups the active overlay, legend, and location focus into one compact
/// bottom-trailing control. The shared capsule communicates that these are
/// peers and prevents three unrelated floating surfaces from competing with
/// Find Sun.
private struct MapQuickControls: View {
    @Binding var sortMode: WeatherMetricMode
    @Binding var showsLegend: Bool
    let canFocusLocation: Bool
    let focusLocation: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            MapOverlayQuickControl(sortMode: $sortMode)

            MapQuickControlButton(
                title: "Show Legend",
                systemImage: showsLegend
                    ? "list.bullet.rectangle.fill"
                    : "list.bullet.rectangle",
                isActive: showsLegend
            ) {
                showsLegend.toggle()
            }

            MapQuickControlButton(
                title: "Zoom to Current Location",
                systemImage: "location.fill",
                isEnabled: canFocusLocation,
                action: focusLocation
            )
        }
        .padding(4)
        .weatherInteractiveGlass(
            colorScheme: colorScheme,
            in: Capsule()
        )
    }
}

/// A native menu that keeps the active overlay visible through its own SF
/// Symbol, rather than requiring people to infer the selected layer from a
/// generic stack icon in the navigation bar.
private struct MapOverlayQuickControl: View {
    @Binding var sortMode: WeatherMetricMode

    @Environment(\.locale) private var locale

    var body: some View {
        Menu {
            Picker("Overlay", selection: $sortMode) {
                ForEach(Array(WeatherMetricMode.allCases.reversed())) { mode in
                    Label(
                        mode.title(locale: locale),
                        systemImage: mode.icon
                    )
                    .tag(mode)
                }
            }
        } label: {
            Image(systemName: sortMode.icon)
                .font(.title3.weight(.regular))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(
            localizedString(
                "Overlay: \(sortMode.title(locale: locale))",
                locale: locale
            )
        )
        .accessibilityHint(
            localizedString("Choose the map overlay", locale: locale)
        )
    }
}

/// A 44-point, icon-only Map control. The plain style intentionally adds no
/// background or outline, while the `Label` still gives the native button a
/// meaningful title for system presentation and UI testing.
private struct MapQuickControlButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var isActive = false
    var isEnabled = true
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.title3.weight(.regular))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            isActive ? theme.colors.filterSunny : theme.colors.primaryText
        )
        .opacity(isEnabled ? 1 : 0.32)
        .disabled(!isEnabled)
        // Icon-only labels can be visually compact without asking VoiceOver
        // or Voice Control users to identify an SF Symbol by its artwork.
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Find Sun Sheet

/// `alert(item:)` needs an identifiable value. Wrapping a string in this type
/// also makes clearing the error explicit rather than treating empty text as a
/// special case.
private struct MapUIError: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(
        title: String = "Unable to Update Places",
        message: String
    ) {
        self.title = title
        self.message = message
    }
}

/// A compact native sheet for choosing the spatial source of a sunny-place
/// search. Country selection stays inside this sheet's navigation stack.
private struct MapSunSearchSheet: View {
    let viewport: MapViewport?
    let canSearchNearMe: Bool
    let locale: Locale
    let runSearch: (MapSunQueryScope) -> Void

    /// These selections are local draft state. Only `submit()` turns them into
    /// a complete query and hands it back to the parent Map view.
    @State private var scope: SunSearchScope
    @State private var selectedCountry: CountryPlacesOption?
    @State private var selectedContinent: ContinentPlacesOption?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(
        initialScope: SunSearchScope,
        viewport: MapViewport?,
        canSearchNearMe: Bool,
        locale: Locale,
        runSearch: @escaping (MapSunQueryScope) -> Void
    ) {
        self.viewport = viewport
        self.canSearchNearMe = canSearchNearMe
        self.locale = locale
        self.runSearch = runSearch
        _scope = State(initialValue: initialScope)
    }

    private var canRunSearch: Bool {
        // Each scope has a different required input; this prevents a search
        // whose geographic meaning would otherwise be ambiguous.
        switch scope {
        case .area: viewport != nil
        case .nearMe: canSearchNearMe
        case .country: selectedCountry != nil && !hasFatalCatalogIssue
        case .continent: selectedContinent != nil && !hasFatalCatalogIssue
        }
    }

    private var hasFatalCatalogIssue: Bool {
        CountryCityCatalog.dataIssues.contains { issue in
            switch issue {
            case .resourceMissing, .unreadableResource, .noValidCities:
                true
            case .invalidRows:
                false
            }
        }
    }

    private var searchButtonTitle: LocalizedStringKey {
        switch scope {
        case .area: "Search in This Area"
        case .nearMe:
            canSearchNearMe ? "Search Nearby Places" : "Enable Location Access"
        case .country: "Search in This Country"
        case .continent: "Search in This Continent"
        }
    }

    private var searchButtonSymbol: String {
        scope == .nearMe && !canSearchNearMe
            ? "location.fill"
            : "magnifyingglass"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Search in", selection: $scope) {
                        ForEach(SunSearchScope.allCases) { scope in
                            Text(scope.title(locale: locale)).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                switch scope {
                case .area:
                    areaControls
                case .nearMe:
                    nearMeControls
                case .country:
                    countryControls
                case .continent:
                    continentControls
                }

                Section {
                    Button(action: submitOrOpenLocationSettings) {
                        Label(searchButtonTitle, systemImage: searchButtonSymbol)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!canRunSearch && scope != .nearMe)
                }
            }
            .navigationTitle("Find Sun")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
        }
    }

    private var areaControls: some View {
        Section {
            Text("Checks the 25 largest cities in the visible map area for sunny conditions.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var nearMeControls: some View {
        Section {
            Text("Checks the 25 largest cities within 100 km of your current location for sunny conditions.")
                .font(.body)
                .foregroundStyle(.secondary)
            if !canSearchNearMe {
                Text("Allow location access in Settings to search nearby.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var countryControls: some View {
        Section {
            NavigationLink {
                MapSunCountryPicker(
                    selectedCountry: $selectedCountry,
                    locale: locale
                )
            } label: {
                Label(
                    selectedCountry?.localizedName(locale: locale)
                        ?? localizedString("Pick a Country", locale: locale),
                    systemImage: "flag.fill"
                )
            }
            .disabled(hasFatalCatalogIssue)
        }
    }

    private var continentControls: some View {
        Section {
            ForEach(ContinentPlacesOption.allCases) { continent in
                Button {
                    selectedContinent = continent
                } label: {
                    HStack {
                        Text(continent.localizedName(locale: locale))
                        Spacer()
                        if selectedContinent == continent {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .accessibilityAddTraits(
                    selectedContinent == continent ? .isSelected : []
                )
            }
        }
    }

    private func submit() {
        // Translate presentation-state cases into the richer enum that carries
        // the selected country or continent when one is required.
        let query: MapSunQueryScope?
        switch scope {
        case .area:
            query = .area
        case .nearMe:
            query = .nearMe
        case .country:
            query = selectedCountry.map(MapSunQueryScope.country)
        case .continent:
            query = selectedContinent.map(MapSunQueryScope.continent)
        }
        guard let query else { return }
        runSearch(query)
        dismiss()
    }

    private func submitOrOpenLocationSettings() {
        guard scope == .nearMe, !canSearchNearMe else {
            submit()
            return
        }
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        openURL(settingsURL)
    }
}

/// Country choice is a pushed searchable screen, keeping Find Sun's scope
/// sheet compact while still supporting the full country catalog.
private struct MapSunCountryPicker: View {
    @Binding var selectedCountry: CountryPlacesOption?
    let locale: Locale

    @State private var query = ""
    @FocusState private var isSearchFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var countries: [CountryPlacesOption] {
        // Search both localized and canonical English names so a saved app
        // language never makes a country impossible to find by a familiar name.
        let allCountries = CountryCityCatalog.countries(locale: locale)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return allCountries }
        return allCountries.filter {
            $0.localizedName(locale: locale).localizedCaseInsensitiveContains(trimmedQuery)
                || $0.englishName.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    var body: some View {
        List(countries) { country in
            Button {
                selectedCountry = country
                dismiss()
            } label: {
                HStack {
                    Text(country.localizedName(locale: locale))
                    Spacer()
                    if selectedCountry == country {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
            }
            .accessibilityAddTraits(
                selectedCountry == country ? .isSelected : []
            )
        }
        .navigationTitle(localizedString("Pick a Country", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search countries")
        // Set focus after this pushed screen appears, rather than trying to
        // focus a search field that does not yet exist in the hierarchy.
        .searchFocused($isSearchFocused)
        .defaultFocus($isSearchFocused, true)
    }
}

// MARK: - MapKit Canvas and Interaction

/// The rendering layer below the navigation bar. It owns transient MapKit
/// camera/selection state while its parent supplies domain data and actions.
private struct PlacesMapCanvas: View {
    // MARK: Parent-Supplied Presentation Contract

    /// The parent converts model/store data into presentation values first.
    /// This rendering layer owns only MapKit interaction state; bindings are
    /// limited to controls and selections the child is allowed to mutate.
    let presentations: [PlacesMapPlacePresentation]
    /// Latest cache timestamp used by the offline replacement for Find Sun.
    let latestCachedWeatherDate: Date?
    let loadError: String?
    let retryLoading: () -> Void
    @Binding var selectedPlaceID: City.ID?
    @Binding var showsLegend: Bool
    @Binding var sortMode: WeatherMetricMode
    let locationCoordinate: CLLocationCoordinate2D?
    let locationName: String
    let locationRecommendation: PlaceRecommendation?
    let isLocationWeatherLoading: Bool
    let needsLocationWeather: Bool
    let ensureLocationWeather: () async -> Void
    let sunSearchResults: [MapSunSearchResult]
    let sunCameraRequest: MapSunCameraRequest?
    let savedPlaceIDsByTransientResultID: [City.ID: SavedPlace.ID]
    @Binding var selectedSunID: City.ID?
    let previewResult: MapSunSearchResult?
    @Binding var selectedPreviewID: City.ID?
    let selectionResetID: Int
    let sunQueryTitle: String?
    let sunQuerySummary: String?
    let isFindingSun: Bool
    @Binding var viewport: MapViewport?
    let displayName: (SavedPlace) -> String
    let findSun: () -> Void
    /// Begins the normal cached WeatherKit load while a bare-map region card is
    /// visible. The card never waits for it; Detail coalesces with this work.
    let preloadTappedPlaceDetails: (City) async -> Void
    let viewDetails: (City) -> Void
    let findSunInRegion: (MapSunQueryScope) -> Void
    let clearSunSearch: () -> Void
    let saveSunResult: (MapSunSearchResult) -> Void
    let saveSearchPreview: (MapSunSearchResult) -> Void
    let searchPlaces: () -> Void

    // MARK: Map-local state and environment

    /// `MapCameraPosition` is deliberately local: moving the map should not
    /// invalidate the app's weather model or overwrite another screen's state.
    @State private var position: MapCameraPosition = .automatic
    @State private var hasInitializedCamera = false
    @State private var labelPlacements:
        [City.ID: PlacesMapLabelPlacement] = [:]
    @State private var tappedRegionContext: MapTapRegionContext?
    @State private var regionLookupID = 0
    @State private var isLocationSelected = false
    @State private var isRequestingLocationWeather = false
    /// iOS 26 uses this shared namespace to interpolate the physical glass
    /// surface from the 44-point Find Sun control into a selection/result card.
    @Namespace private var bottomSurfaceNamespace
    /// The compact control and its expanded card are two states of one physical
    /// surface, so Liquid Glass needs the same identity for a matched morph
    /// between their capsule and rounded-rectangle shapes.
    private enum BottomSurfaceGlassID {
        static let surface = "map-bottom.surface"
    }
    /// Before iOS 26, the same two surfaces use SwiftUI's conventional matched
    /// geometry effect instead of Liquid Glass, which does require one shared
    /// identity.
    private static let bottomSurfaceFallbackGeometryID = "map-bottom.surface"
    /// Quick controls use the actual rendered bottom-surface height instead of
    /// guessing separately for every card, banner, and Dynamic Type size.
    @State private var bottomSurfaceHeight: CGFloat = 0
    /// The compact card's material can be much narrower than its expanded
    /// layout container. Its actual trailing edge tells us when a localized
    /// status message would collide with the trailing control stack.
    @State private var bottomSurfaceTrailingEdge: CGFloat = 0
    /// This tracks only the stack's horizontal leading edge, so lifting it
    /// vertically never feeds a geometry change back into its own layout.
    @State private var quickControlsLeadingEdge: CGFloat = .infinity

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(MissingDataAlertCenter.self) private var missingDataAlerts
    @Environment(NetworkConnectivity.self) private var networkConnectivity
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit")
    private var distanceUnitRaw = DistanceUnit.defaultRawValue

    /// Use one initial span for both the initial location map and the
    /// explicit recenter action. Recentring should change the centre only,
    /// never make the map feel as though it has jumped to a different zoom.
    private static let initialLocationSpan = MKCoordinateSpan(
        latitudeDelta: 3,
        longitudeDelta: 3
    )

    // MARK: Derived annotation data

    /// A metric may require data that is unavailable (for example UV index),
    /// so filter these presentations before producing visible annotations.
    private var layerPresentations: [PlacesMapPlacePresentation] {
        presentations.filter(hasValidActiveLayerData)
    }

    private var visiblePresentations: [PlacesMapPlacePresentation] {
        mapMarkers.map(\.presentation)
    }

    private var mapMarkers: [PlacesMapMarkerPresentation] {
        layerPresentations.compactMap { presentation in
            // While a just-saved transient result is still selected, retain
            // its original annotation identity. The ordinary saved marker
            // takes over as soon as the acknowledgement card is dismissed.
            if preservedSavedPlaceSelectionIDs.contains(presentation.id) {
                return nil
            }
            guard let color = markerColor(for: presentation) else {
                return nil
            }
            return PlacesMapMarkerPresentation(
                presentation: presentation,
                color: color
            )
        }
    }

    private var selectedPresentation: PlacesMapPlacePresentation? {
        guard let selectedPlaceID else { return nil }
        return visiblePresentations.first { $0.id == selectedPlaceID }
    }

    private var selectedSunResult: MapSunSearchResult? {
        guard let selectedSunID else { return nil }
        return sunSearchResults.first { $0.id == selectedSunID }
    }

    private var selectedPreview: MapSunSearchResult? {
        guard let selectedPreviewID,
              previewResult?.id == selectedPreviewID else {
            return nil
        }
        return previewResult
    }

    /// A saved city already has its normal map dot and floating card. Avoid a
    /// duplicate transient dot when Find Sun happens to return that same city.
    private var transientSunResults: [MapSunSearchResult] {
        return sunSearchResults.filter {
            savedPlaceIDsByTransientResultID[$0.id] == nil
                || $0.id == selectedSunID
        }
    }

    private var preservedSavedPlaceSelectionIDs: Set<SavedPlace.ID> {
        var ids: Set<SavedPlace.ID> = []
        if let selectedSunID,
           sunSearchResults.contains(where: { $0.id == selectedSunID }),
           let savedID = savedPlaceIDsByTransientResultID[selectedSunID] {
            ids.insert(savedID)
        }
        if let selectedPreviewID,
           previewResult?.id == selectedPreviewID,
           let savedID = savedPlaceIDsByTransientResultID[selectedPreviewID] {
            ids.insert(savedID)
        }
        return ids
    }

    private func isSaved(_ result: MapSunSearchResult) -> Bool {
        savedPlaceIDsByTransientResultID[result.id] != nil
    }

    private var visiblePlaceIDs: [City.ID] {
        visiblePresentations
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
    }

    private var labelLayoutInputs: [PlacesMapLabelLayoutInput] {
        let savedInputs = mapMarkers.enumerated().map { index, marker in
            PlacesMapLabelLayoutInput(
                id: marker.id,
                name: displayName(marker.presentation.place),
                coordinate: CLLocationCoordinate2D(
                    latitude: marker.presentation.place.city.latitude,
                    longitude: marker.presentation.place.city.longitude
                ),
                priority: selectedPlaceID == marker.id
                    ? 10_000
                    : 1_000 - index,
                isSelected: selectedPlaceID == marker.id
            )
        }
        let foundInputs = transientSunResults.enumerated().map {
            index,
            result in
            PlacesMapLabelLayoutInput(
                id: result.id,
                name: result.city.displayName,
                coordinate: CLLocationCoordinate2D(
                    latitude: result.city.latitude,
                    longitude: result.city.longitude
                ),
                priority: selectedSunID == result.id
                    ? 10_000
                    : 3_000 - index,
                isSelected: selectedSunID == result.id
            )
        }
        let previewInputs = previewResult.map { result in
            [
                PlacesMapLabelLayoutInput(
                    id: result.id,
                    name: result.city.displayName,
                    coordinate: CLLocationCoordinate2D(
                        latitude: result.city.latitude,
                        longitude: result.city.longitude
                    ),
                    priority: selectedPreviewID == result.id
                        ? 10_000
                        : 4_000,
                    isSelected: selectedPreviewID == result.id
                )
            ]
        } ?? []
        let locationInput = locationCoordinate.map { coordinate in
            [
                PlacesMapLabelLayoutInput(
                    id: Self.locationLabelID,
                    name: locationLabel,
                    coordinate: coordinate,
                    priority: isLocationSelected ? 10_000 : 2_000,
                    isSelected: isLocationSelected
                )
            ]
        } ?? []
        return savedInputs + foundInputs + previewInputs + locationInput
    }

    private static let locationLabelID = UUID()

    private var locationLabel: String {
        localizedString("Current Location", locale: locale)
    }

    private var hasFloatingCard: Bool {
        // The bottom Find Sun control needs extra clearance only while one
        // mutually exclusive floating card occupies the same lower region.
        selectedPresentation != nil
            || selectedSunResult != nil
            || selectedPreview != nil
            || isLocationSelected
            || tappedRegionContext != nil
    }

    private var showsSunResultsPanel: Bool {
        !isFindingSun && !sunSearchResults.isEmpty && !hasFloatingCard
    }

    private var hasEmptyMapContentState: Bool {
        visiblePresentations.isEmpty
            && transientSunResults.isEmpty
            && previewResult == nil
    }

    private var sunResultsTitle: String {
        // Cached results handed off by Your Location do not create a query
        // scope, but they still represent the same near-me result category.
        sunQueryTitle ?? localizedString("Near Me", locale: locale)
    }

    private var largeSurfaceHorizontalPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 12 : 18
    }

    /// A short compact capsule can share the bottom edge with the utility
    /// controls. Fix for long localized status capsules: when their visible
    /// material reaches the control stack, lift the entire stack above it.
    private var compactSurfaceOverlapsQuickControls: Bool {
        guard !usesLargeBottomSurface,
              bottomSurfaceTrailingEdge > 0,
              quickControlsLeadingEdge.isFinite else {
            return false
        }

        return bottomSurfaceTrailingEdge + MapCardLayout.surfaceSpacing
            > quickControlsLeadingEdge
    }

    private var mapUtilityBottomInset: CGFloat {
        guard usesLargeBottomSurface || compactSurfaceOverlapsQuickControls
        else {
            return MapCardLayout.bottomPadding
        }
        return bottomSurfaceHeight + MapCardLayout.surfaceSpacing
    }

    private func updateBottomSurfaceTrailingEdge(_ newTrailingEdge: CGFloat) {
        // Geometry can emit fractional animation steps; ignore visual no-ops
        // so a material resize does not repeatedly invalidate the map canvas.
        guard abs(newTrailingEdge - bottomSurfaceTrailingEdge) > 0.5 else {
            return
        }
        bottomSurfaceTrailingEdge = newTrailingEdge
    }

    private func updateQuickControlsLeadingEdge(_ newLeadingEdge: CGFloat) {
        guard abs(newLeadingEdge - quickControlsLeadingEdge) > 0.5 else {
            return
        }
        quickControlsLeadingEdge = newLeadingEdge
    }

    // MARK: Floating-card selection

    /// Only one selection card is produced at a time. The `if` order is also
    /// the precedence rule when a saved city and a transient result overlap.
    @ViewBuilder
    private var activeFloatingCard: some View {
        if let selectedPresentation {
            MapPlaceSelectionCard(
                presentation: selectedPresentation,
                displayName: displayName(selectedPresentation.place),
                sortMode: sortMode,
                clearSelection: clearCards
            )
        } else if let selectedSunResult {
            MapSunResultCard(
                result: selectedSunResult,
                isSaved: isSaved(selectedSunResult),
                viewDetails: {
                    clearCards()
                    viewDetails(selectedSunResult.city)
                },
                save: { saveSunResult(selectedSunResult) },
                clearSelection: clearCards
            )
        } else if let selectedPreview {
            MapSunResultCard(
                result: selectedPreview,
                isSaved: isSaved(selectedPreview),
                viewDetails: {
                    clearCards()
                    viewDetails(selectedPreview.city)
                },
                save: { saveSearchPreview(selectedPreview) },
                clearSelection: clearCards
            )
        } else if isLocationSelected {
            MapCurrentLocationCard(
                name: locationName,
                recommendation: locationRecommendation,
                isLoading: isLocationWeatherLoading
                    || isRequestingLocationWeather,
                clearSelection: clearCards
            )
        } else if let tappedRegionContext {
            MapRegionContextCard(
                context: tappedRegionContext,
                viewDetails: { city in
                    clearCards()
                    viewDetails(city)
                },
                findSun: { scope in
                    findSunInRegion(scope)
                    // Starting the parent-owned loading state first lets this
                    // same animation transaction morph the regional card into
                    // the compact Find Sun progress capsule.
                    clearCards()
                },
                clearSelection: clearCards
            )
        } else {
            EmptyView()
        }
    }

    /// Exactly one lower surface is rendered at a time. A selected marker has
    /// priority over the result list; otherwise the relevant compact status or
    /// recovery banner replaces the ordinary Find Sun action. The two physical
    /// sizes are separate views so iOS can animate the disappearance and
    /// insertion of their glass effects as one native morph.
    @ViewBuilder
    private var activeBottomSurface: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: MapCardLayout.surfaceSpacing) {
                bottomSurface
            }
            .animation(
                MapCardMotion.morph(reduceMotion: reduceMotion),
                value: bottomSurfacePresentationID
            )
        } else {
            bottomSurface
                .animation(
                    MapCardMotion.morph(reduceMotion: reduceMotion),
                    value: bottomSurfacePresentationID
                )
        }
    }

    @ViewBuilder
    private var bottomSurface: some View {
        if usesLargeBottomSurface {
            MapCard(
                size: .large(horizontalPadding: largeSurfaceHorizontalPadding),
                colorScheme: colorScheme,
                maximumWidth: cardMaximumWidth,
                glassEffectID: Self.BottomSurfaceGlassID.surface,
                fallbackGeometryID: Self.bottomSurfaceFallbackGeometryID,
                glassNamespace: bottomSurfaceNamespace,
                onSurfaceTrailingEdgeChange: updateBottomSurfaceTrailingEdge
            ) {
                largeBottomSurfaceContent
            }
        } else {
            MapCard(
                size: networkConnectivity.isOffline ? .offline : .small,
                colorScheme: colorScheme,
                maximumWidth: cardMaximumWidth,
                glassEffectID: Self.BottomSurfaceGlassID.surface,
                fallbackGeometryID: Self.bottomSurfaceFallbackGeometryID,
                glassNamespace: bottomSurfaceNamespace,
                onSurfaceTrailingEdgeChange: updateBottomSurfaceTrailingEdge
            ) {
                compactBottomSurface
            }
        }
    }

    @ViewBuilder
    private var largeBottomSurfaceContent: some View {
        if hasFloatingCard {
            activeFloatingCard
        } else {
            MapSunResultsPanel(
                results: sunSearchResults,
                title: sunResultsTitle,
                select: selectListedSunResult,
                clear: clearSunSearch
            )
        }
    }

    private var usesLargeBottomSurface: Bool {
        hasFloatingCard || showsSunResultsPanel
    }

    private var bottomSurfacePresentationID: String {
        if let selectedPresentation {
            return "saved-place-\(selectedPresentation.id.uuidString)"
        }
        if let selectedSunResult {
            return "found-place-\(selectedSunResult.id.uuidString)"
        }
        if let selectedPreview {
            return "search-preview-\(selectedPreview.id.uuidString)"
        }
        if isLocationSelected {
            return "current-location"
        }
        if let tappedRegionContext {
            return "region-\(tappedRegionContext.id)"
        }
        if showsSunResultsPanel {
            let resultIDs = sunSearchResults
                .map(\.id.uuidString)
                .joined(separator: ",")
            return "sun-results-\(resultIDs)"
        }
        if isFindingSun {
            return "finding-sun"
        }
        if sunQuerySummary != nil, sunSearchResults.isEmpty {
            // Distinct presentation state gives the shared compact glass an
            // animation trigger when Clear Results returns to Find Sun.
            return "empty-sun-results"
        }
        if hasEmptyMapContentState {
            if loadError != nil {
                return "places-unavailable"
            }
            if presentations.isEmpty {
                return "no-saved-places"
            }
            if presentations.contains(where: \.isLoading),
               layerPresentations.isEmpty {
                return "loading-forecasts"
            }
            return "forecast-unavailable"
        }
        return "find-sun"
    }

    /// Every compact state uses the same component and the same one-line text
    /// treatment. Recovery actions stay available as 44-point icon buttons.
    @ViewBuilder
    private var compactBottomSurface: some View {
        if networkConnectivity.isOffline,
           !networkConnectivity.isOfflineBannerDismissed {
            // This occupies the exact Find Sun lane, rather than becoming a
            // second bottom overlay that could compete with map controls.
            OfflineBannerContent(
                lastUpdated: latestCachedWeatherDate,
                dismiss: networkConnectivity.dismissOfflineBanner
            )
            .padding(.horizontal, MapCardLayout.compactHorizontalPadding)
        } else if isFindingSun {
            MapCardSmallContent {
                ProgressView()
                    .controlSize(.small)
                Text("Finding sunny places")
            }
        } else if let sunQuerySummary,
                  sunSearchResults.isEmpty {
            MapCardSmallContent {
                Text(
                    "Found \(sunSearchResults.count) \(sunQuerySummary)"
                )
                MapCardIconButton(
                    title: "Clear Results",
                    systemImage: "xmark",
                    layoutWidth: 32,
                    action: clearSunSearch
                )
            }
        } else if hasEmptyMapContentState {
            emptyMapBanner
        } else {
            findSunBanner
        }
    }

    private var findSunBanner: some View {
        MapCardSmallContent {
            Button(action: findSun) {
                Label("Find Sun", systemImage: "magnifyingglass")
            }
            .buttonStyle(.plain)
        }
    }

    /// Empty, loading, and error states are compact peers of Find Sun instead
    /// of unrelated full-height panels. The old recovery actions are retained,
    /// and Find Sun remains reachable from every state.
    @ViewBuilder
    private var emptyMapBanner: some View {
        if loadError != nil {
            MapCardSmallContent {
                Label(
                    "Places Unavailable",
                    systemImage: "exclamationmark.triangle"
                )
                MapCardIconButton(
                    title: "Try Again",
                    systemImage: "arrow.clockwise",
                    action: retryLoading
                )
                MapCardIconButton(
                    title: "Find Sun",
                    systemImage: "sun.max",
                    action: findSun
                )
            }
        } else if presentations.isEmpty {
            findSunBanner
        } else if presentations.contains(where: \.isLoading),
                  layerPresentations.isEmpty {
            // Forecast loading is status, not a second Find Sun action. Keep
            // it as one compact text-and-spinner capsule.
            MapCardSmallContent(horizontalPadding: 12) {
                Text("Loading Forecasts")
                ProgressView()
                    .controlSize(.small)
            }
        } else {
            MapCardSmallContent {
                Label(
                    "Forecast Unavailable",
                    systemImage: "cloud.slash"
                )
                MapCardIconButton(
                    title: "Find Sun",
                    systemImage: "sun.max",
                    action: findSun
                )
            }
        }
    }

    // MARK: SwiftUI composition

    var body: some View {
        ZStack(alignment: .bottom) {
            mapContent

            activeBottomSurface
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    // Geometry may report tiny fractional changes while glass
                    // animates; ignore those to avoid an update feedback loop.
                    guard abs(newHeight - bottomSurfaceHeight) > 0.5 else {
                        return
                    }
                    bottomSurfaceHeight = newHeight
                }
                .zIndex(3)
        }
        .onChange(of: visiblePlaceIDs, initial: true) { _, newIDs in
            // Clear an invalid selection after visible-data changes. Camera
            // initialization happens once, so later list refreshes never fight
            // the person's pan and zoom gestures.
            if let selectedPlaceID, !newIDs.contains(selectedPlaceID) {
                self.selectedPlaceID = nil
            }

            if !hasInitializedCamera {
                initializeCamera()
                hasInitializedCamera = true
            }
        }
        .onChange(of: selectionResetID) {
            clearCards()
        }
        .onChange(of: previewResult?.id, initial: true) { _, previewID in
            // A new Search preview is intentionally selected and centered as
            // soon as Map receives it, making the save decision obvious.
            guard let previewID,
                  let preview = previewResult,
                  preview.id == previewID else {
                return
            }
            selectSearchPreview(previewID)
            focus(on: preview.city)
        }
        .task(id: tappedRegionContext?.city.id) {
            // Reverse geocoding has supplied an exact city by this point and
            // the region card is visible. Warm that same city ID before any
            // View Details tap; PlaceWeatherStore coalesces duplicate loads.
            guard let city = tappedRegionContext?.city else { return }
            await preloadTappedPlaceDetails(city)
        }
        .onChange(of: selectedPlaceID) {
            if selectedPlaceID != nil {
                selectedSunID = nil
                selectedPreviewID = nil
                isLocationSelected = false
                clearTappedRegionContext()
            }
        }
        .sensoryFeedback(.selection, trigger: selectedPlaceID)
        .sensoryFeedback(.selection, trigger: isLocationSelected)
    }

    /// `MapReader` converts between screen coordinates and geographic points;
    /// `GeometryReader` supplies the canvas size for collision-aware labels.
    private var mapContent: some View {
        MapReader { mapProxy in
            GeometryReader { geometry in
                // Annotation buttons own both saved-place and Find Sun
                // selection. Avoid Map's separate selection binding, which
                // can write `nil` after a transient-result tap and dismiss
                // the floating card immediately.
                Map(position: $position) {
                    // MapKit's muted standard style removes most visual
                    // competition; this light semantic wash further subdues
                    // the tiles while annotations remain above the overlay.
                    MapPolygon(points: baseMapWashPoints)
                        .foregroundStyle(
                            theme.colors.background.opacity(0.22)
                        )
                        .stroke(.clear, lineWidth: 0)

                    ForEach(mapMarkers) { marker in
                        Annotation(
                            "",
                            coordinate: CLLocationCoordinate2D(
                                latitude:
                                    marker.presentation.place.city.latitude,
                                longitude:
                                    marker.presentation.place.city.longitude
                            ),
                            anchor: .center
                        ) {
                            PlacesWeatherMapAnnotation(
                                markerID: marker.id,
                                name: displayName(
                                    marker.presentation.place
                                ),
                                accessibilityName:
                                    savedMarkerAccessibilityName(
                                        marker.presentation.place
                                    ),
                                color: marker.color,
                                isSelected: selectedPlaceID == marker.id,
                                labelPlacement:
                                    labelPlacements[marker.id] ?? .below,
                                differentiatingText:
                                    markerDifferentiatingText(
                                        for: marker.presentation
                                    ),
                                differentiatingSymbol:
                                    markerDifferentiatingSymbol(
                                        for: marker.presentation
                                    ),
                                accessibilityValue:
                                    markerAccessibilityValue(
                                        for: marker.presentation
                                    ),
                                showsMetricText: sortMode == .sunny,
                                select: {
                                    selectPlace(marker.id)
                                }
                            )
                        }
                        .tag(marker.id)
                    }

                    ForEach(transientSunResults) { result in
                        Annotation(
                            "",
                            coordinate: CLLocationCoordinate2D(
                                latitude: result.city.latitude,
                                longitude: result.city.longitude
                            ),
                            anchor: .center
                        ) {
                            PlacesWeatherMapAnnotation(
                                markerID: result.id,
                                name: result.city.displayName,
                                accessibilityName: result.city.displayName,
                                color: result.recommendation.condition
                                    .dotColor(for: theme.colors),
                                isSelected: selectedSunID == result.id,
                                labelPlacement:
                                    labelPlacements[result.id] ?? .below,
                                differentiatingText: nil,
                                differentiatingSymbol: nil,
                                accessibilityValue: markerAccessibilityValue(
                                    for: result.recommendation
                                ),
                                showsMetricText: false,
                                select: {
                                    selectSunResult(result.id)
                                }
                            )
                        }
                    }

                    if let previewResult {
                        Annotation(
                            "",
                            coordinate: CLLocationCoordinate2D(
                                latitude: previewResult.city.latitude,
                                longitude: previewResult.city.longitude
                            ),
                            anchor: .center
                        ) {
                            PlacesWeatherMapAnnotation(
                                markerID: previewResult.id,
                                name: previewResult.city.displayName,
                                accessibilityName:
                                    previewResult.city.displayName,
                                color: previewResult.recommendation.condition
                                    .dotColor(for: theme.colors),
                                isSelected:
                                    selectedPreviewID == previewResult.id,
                                labelPlacement:
                                    labelPlacements[previewResult.id] ?? .below,
                                differentiatingText: nil,
                                differentiatingSymbol: nil,
                                accessibilityValue: markerAccessibilityValue(
                                    for: previewResult.recommendation
                                ),
                                showsMetricText: false,
                                select: {
                                    selectSearchPreview(previewResult.id)
                                }
                            )
                        }
                    }

                    if let locationCoordinate {
                        // This is intentionally separate from saved-place
                        // weather dots, making the location-focus action
                        // unambiguous.
                        Annotation(
                            "",
                            coordinate: locationCoordinate,
                            anchor: .center
                        ) {
                            CurrentLocationMapAnnotation(
                                markerID: Self.locationLabelID,
                                name: locationLabel,
                                color: locationColor,
                                isSelected: isLocationSelected,
                                labelPlacement:
                                    labelPlacements[Self.locationLabelID]
                                    ?? .below,
                                accessibilityValue:
                                    locationRecommendation.map(
                                        markerAccessibilityValue(for:)
                                    ),
                                select: selectCurrentLocation
                            )
                        }
                    }
                }
                .mapStyle(
                    // "Muted" is MapKit's subtle standard-map emphasis.
                    .standard(
                        elevation: .flat,
                        emphasis: .muted,
                        pointsOfInterest: .excludingAll,
                        showsTraffic: false
                    )
                )
                // Keep the bare-map query gesture on the Map itself. Placing it
                // before Map controls and custom overlays means their buttons own
                // their taps instead of simultaneously reverse-geocoding the map
                // coordinate underneath them. Annotation taps still reach this
                // gesture and are rejected by `isTapOnAnnotation` below.
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        handleMapTap(
                            at: value.location,
                            using: mapProxy
                        )
                    }
                )
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .overlay(alignment: .topLeading) {
                    if showsLegend,
                       !visiblePresentations.isEmpty {
                        PlacesMapLegend(sortMode: sortMode)
                        .padding(.horizontal, 16)
                        .padding(.top, legendTopPadding)
                        .transition(legendTransition)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    MapQuickControls(
                        sortMode: $sortMode,
                        showsLegend: $showsLegend,
                        canFocusLocation: locationCoordinate != nil,
                        focusLocation: focusLocation
                    )
                    .padding(.trailing, 12)
                    .padding(.bottom, mapUtilityBottomInset)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.frame(in: .global).minX
                    } action: { newLeadingEdge in
                        updateQuickControlsLeadingEdge(newLeadingEdge)
                    }
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    viewport = MapViewport(region: context.region)
                    updateLabelPlacements(
                        using: mapProxy,
                        viewportSize: geometry.size
                    )
                }
                .onChange(of: labelLayoutInputs, initial: true) {
                    _,
                    _ in
                    updateLabelPlacements(
                        using: mapProxy,
                        viewportSize: geometry.size
                    )
                }
                .onChange(of: geometry.size, initial: true) {
                    _,
                    newSize in
                    updateLabelPlacements(
                        using: mapProxy,
                        viewportSize: newSize
                    )
                }
                .onChange(of: sunCameraRequest?.id, initial: true) {
                    _,
                    _ in
                    guard let sunCameraRequest else { return }
                    fitSunSearchRequest(
                        sunCameraRequest,
                        viewportSize: geometry.size
                    )
                }
                .animation(
                    reduceMotion ? nil : .smooth(duration: 0.22),
                    value: showsLegend
                )
            }
        }
    }

    // MARK: Map tapping and reverse-geocoding

    /// A bare map tap opens a regional Find Sun affordance. Taps near pins are
    /// ignored here so the annotation button remains the single owner of pin
    /// selection.
    private func handleMapTap(
        at location: CGPoint,
        using mapProxy: MapProxy
    ) {
        // A blank-map tap gives any large lower surface dismissal priority.
        // This keeps the Map interaction predictable: query a location only
        // when no card or results panel is open; otherwise close that surface
        // with a single tap elsewhere.
        guard !isTapOnAnnotation(at: location, using: mapProxy) else {
            return
        }

        let hadCard = hasFloatingCard
        let hadResultsPanel = showsSunResultsPanel
        clearCards()

        if hadResultsPanel {
            clearSunSearch()
        }

        guard !hadCard, !hadResultsPanel else {
            return
        }

        guard let coordinate = mapProxy.convert(location, from: .local),
              CLLocationCoordinate2DIsValid(coordinate) else {
            return
        }

        resolveTappedRegion(at: coordinate)
    }

    private func isTapOnAnnotation(
        at location: CGPoint,
        using mapProxy: MapProxy
    ) -> Bool {
        let savedCoordinates = mapMarkers.map {
            CLLocationCoordinate2D(
                latitude: $0.presentation.place.city.latitude,
                longitude: $0.presentation.place.city.longitude
            )
        }
        let foundCoordinates = transientSunResults.map {
            CLLocationCoordinate2D(
                latitude: $0.city.latitude,
                longitude: $0.city.longitude
            )
        }
        let previewCoordinates = previewResult.map {
            [
                CLLocationCoordinate2D(
                    latitude: $0.city.latitude,
                    longitude: $0.city.longitude
                )
            ]
        } ?? []
        let locationPoints = locationCoordinate.map { [$0] } ?? []
        let coordinates = savedCoordinates
            + foundCoordinates
            + previewCoordinates
            + locationPoints

        return coordinates.contains { coordinate in
            guard let point = mapProxy.convert(coordinate, to: .local) else {
                return false
            }
            return hypot(point.x - location.x, point.y - location.y) < 36
        }
    }

    /// Reverse geocoding is asynchronous. Its ID discards an older lookup if
    /// the user immediately taps a different region of the map.
    private func resolveTappedRegion(at coordinate: CLLocationCoordinate2D) {
        regionLookupID &+= 1
        let resolutionID = regionLookupID
        tappedRegionContext = nil
        missingDataAlerts.resolve(key: "map-tap-place")

        Task {
            let location = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            var metadata = await mapTapMetadata(for: location)
            guard !Task.isCancelled,
                  resolutionID == regionLookupID else {
                return
            }

            // Both reverse-geocoder sources have now had one pass. If their
            // factual metadata is incomplete, ask them once more before the
            // map leaves the card blank and presents its missing-data alert.
            if metadata.locality == nil
                || metadata.isoCountryCode == nil
                || metadata.timeZone == nil {
                metadata = await mapTapMetadata(for: location)
            }

            guard !Task.isCancelled,
                  resolutionID == regionLookupID else {
                return
            }

            var missingFields: [String] = []
            if metadata.locality == nil {
                missingFields.append(
                    localizedString("city name", locale: locale)
                )
            }
            if metadata.isoCountryCode == nil {
                missingFields.append(
                    localizedString("country", locale: locale)
                )
            }
            if metadata.timeZone == nil {
                missingFields.append(
                    localizedString("time zone", locale: locale)
                )
            }

            let mappedCountry = metadata.isoCountryCode.flatMap {
                CountryCityCatalog.country(iso2: $0)
            }
            if metadata.isoCountryCode != nil, mappedCountry == nil {
                missingFields.append(
                    localizedString("country catalog", locale: locale)
                )
            }

            guard missingFields.isEmpty,
                  let locality = metadata.locality,
                  let countryCode = metadata.isoCountryCode,
                  let country = mappedCountry,
                  let timeZone = metadata.timeZone else {
                let formatter = ListFormatter()
                formatter.locale = locale
                let formattedFields = formatter.string(from: missingFields)
                let fieldList = formattedFields?.isEmpty == false
                    ? formattedFields!
                    : localizedString("place", locale: locale)
                missingDataAlerts.report(
                    key: "map-tap-place",
                    title: localizedString("Data Missing", locale: locale),
                    message: String(
                        format: localizedString(
                            "%@ data is missing for this map location.",
                            locale: locale
                        ),
                        locale: locale,
                        fieldList
                    )
                )
                return
            }

            let countryName = cleanMapTapValue(metadata.countryName)
                ?? locale.localizedString(forRegionCode: countryCode)
                ?? country.englishName
            let city = City(
                name: locality,
                country: countryName,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                timeZoneIdentifier: timeZone.identifier
            )

            withAnimation(MapCardMotion.morph(reduceMotion: reduceMotion)) {
                tappedRegionContext = MapTapRegionContext(
                    city: city,
                    locality: locality,
                    country: country,
                    continent: CountryCityCatalog.continent(for: country)
                )
            }
        }
    }

    /// Collects exact-coordinate metadata from MapKit, then Core Location only
    /// for fields MapKit omitted. It never turns region text into a city name.
    private func mapTapMetadata(for location: CLLocation) async -> MapTapPlaceMetadata {
        var metadata = MapTapPlaceMetadata.empty

        if #available(iOS 26.0, *),
           let request = MKReverseGeocodingRequest(location: location) {
            request.preferredLocale = locale
            do {
                if let item = try await request.mapItems.first {
                    metadata = metadata.fillingMissingFields(
                        from: mapTapMetadata(from: item)
                    )
                }
            } catch is CancellationError {
                return metadata
            } catch {
                DeveloperDiagnostics.show(
                    title: "Map Tap Reverse Geocoding Failed",
                    message: error.localizedDescription
                )
            }
        }

        if metadata.locality == nil
            || metadata.isoCountryCode == nil
            || metadata.timeZone == nil {
            do {
                if let placemark = try await CLGeocoder()
                    .reverseGeocodeLocation(
                        location,
                        preferredLocale: locale
                    )
                    .first {
                    metadata = metadata.fillingMissingFields(
                        from: mapTapMetadata(from: placemark)
                    )
                }
            } catch is CancellationError {
                return metadata
            } catch {
                DeveloperDiagnostics.show(
                    title: "Map Tap Reverse Geocoding Failed",
                    message: error.localizedDescription
                )
            }
        }

        return metadata
    }

    @available(iOS 26.0, *)
    private func mapTapMetadata(from item: MKMapItem) -> MapTapPlaceMetadata {
        MapTapPlaceMetadata(
            locality: cleanMapTapValue(
                item.addressRepresentations?.cityName
                    ?? item.placemark.locality
            ),
            countryName: cleanMapTapValue(item.placemark.country),
            isoCountryCode: cleanMapTapValue(
                item.placemark.isoCountryCode
            )?.uppercased(),
            timeZone: item.timeZone ?? item.placemark.timeZone
        )
    }

    private func mapTapMetadata(
        from placemark: CLPlacemark
    ) -> MapTapPlaceMetadata {
        MapTapPlaceMetadata(
            locality: cleanMapTapValue(placemark.locality),
            countryName: cleanMapTapValue(placemark.country),
            isoCountryCode: cleanMapTapValue(
                placemark.isoCountryCode
            )?.uppercased(),
            timeZone: placemark.timeZone
        )
    }

    private func cleanMapTapValue(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func clearTappedRegionContext() {
        regionLookupID &+= 1
        tappedRegionContext = nil
    }

    private func clearCards() {
        // Keep selection mutually exclusive by resetting every possible card
        // source in the same animated transaction.
        withAnimation(MapCardMotion.morph(reduceMotion: reduceMotion)) {
            selectedPlaceID = nil
            selectedSunID = nil
            selectedPreviewID = nil
            isLocationSelected = false
            clearTappedRegionContext()
        }
    }

    private func selectPlace(_ id: City.ID) {
        withAnimation(MapCardMotion.morph(reduceMotion: reduceMotion)) {
            selectedPlaceID = id
            selectedSunID = nil
            selectedPreviewID = nil
            isLocationSelected = false
            clearTappedRegionContext()
        }
    }

    private func selectSunResult(_ id: City.ID) {
        withAnimation(MapCardMotion.morph(reduceMotion: reduceMotion)) {
            selectedPlaceID = nil
            selectedSunID = id
            selectedPreviewID = nil
            isLocationSelected = false
            clearTappedRegionContext()
        }
    }

    private func selectListedSunResult(_ result: MapSunSearchResult) {
        selectSunResult(result.id)
        focus(on: result.city)
    }

    private func selectSearchPreview(_ id: City.ID) {
        withAnimation(MapCardMotion.morph(reduceMotion: reduceMotion)) {
            selectedPlaceID = nil
            selectedSunID = nil
            selectedPreviewID = id
            isLocationSelected = false
            clearTappedRegionContext()
        }
    }

    private func selectCurrentLocation() {
        let shouldLoadWeather = needsLocationWeather
            && !isLocationWeatherLoading
            && !isRequestingLocationWeather
        withAnimation(MapCardMotion.morph(reduceMotion: reduceMotion)) {
            selectedPlaceID = nil
            selectedSunID = nil
            selectedPreviewID = nil
            clearTappedRegionContext()
            isLocationSelected = true
        }
        guard shouldLoadWeather else { return }

        // Set local loading state before awaiting so the card never flashes its
        // data-less fallback while the current-location lookup starts.
        isRequestingLocationWeather = true
        Task { @MainActor in
            await ensureLocationWeather()
            isRequestingLocationWeather = false
        }
    }

    // MARK: Label collision avoidance

    /// Projects every annotation label onto the screen, then greedily tries
    /// below, above, and finally hidden in that exact order. Selected markers
    /// and ranked results reserve space before lower-priority saved labels.
    private func updateLabelPlacements(
        using mapProxy: MapProxy,
        viewportSize: CGSize
    ) {
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return
        }

        let projectedLabels: [PlacesMapProjectedLabel] = labelLayoutInputs
            .compactMap {
                input -> PlacesMapProjectedLabel? in
                guard let point = mapProxy.convert(
                    input.coordinate,
                    to: .local
                ) else {
                    return nil
                }

                return PlacesMapProjectedLabel(
                    input: input,
                    point: point,
                    size: estimatedLabelSize(for: input.name)
                )
            }
            .sorted {
                (lhs: PlacesMapProjectedLabel,
                 rhs: PlacesMapProjectedLabel) -> Bool in
                if lhs.input.priority != rhs.input.priority {
                    return lhs.input.priority > rhs.input.priority
                }
                if lhs.point.y != rhs.point.y {
                    return lhs.point.y < rhs.point.y
                }
                if lhs.point.x != rhs.point.x {
                    return lhs.point.x < rhs.point.x
                }
                return lhs.input.id.uuidString
                    < rhs.input.id.uuidString
            }

        let viewportBounds = CGRect(
            origin: .zero,
            size: viewportSize
        )
        .insetBy(dx: 4, dy: 4)
        let markerObstacles = projectedLabels.map { projectedLabel in
            (
                id: projectedLabel.input.id,
                rect: CGRect(
                    x: projectedLabel.point.x - 22,
                    y: projectedLabel.point.y - 14,
                    width: 44,
                    height: 28
                )
            )
        }

        var occupiedLabelRects: [CGRect] = []
        var newPlacements: [City.ID: PlacesMapLabelPlacement] = [:]
        var hidesLowerPriorities = false

        for projectedLabel in projectedLabels {
            guard !hidesLowerPriorities else {
                newPlacements[projectedLabel.input.id] = .hidden
                continue
            }

            let belowRect = projectedLabel.rect(
                for: PlacesMapLabelPlacement.below
            )
            let aboveRect = projectedLabel.rect(
                for: PlacesMapLabelPlacement.above
            )
            let placement: PlacesMapLabelPlacement
            let placedRect: CGRect?
            if canPlaceLabel(
                for: belowRect,
                labelID: projectedLabel.input.id,
                occupiedLabelRects: occupiedLabelRects,
                markerObstacles: markerObstacles,
                viewportBounds: viewportBounds
            ) {
                placement = .below
                placedRect = belowRect
            } else if canPlaceLabel(
                for: aboveRect,
                labelID: projectedLabel.input.id,
                occupiedLabelRects: occupiedLabelRects,
                markerObstacles: markerObstacles,
                viewportBounds: viewportBounds
            ) {
                placement = .above
                placedRect = aboveRect
            } else {
                placement = .hidden
                placedRect = nil
                if projectedLabel.input.isSelected,
                   viewportBounds.contains(projectedLabel.point) {
                    // Never leave ordinary labels visible while the selected
                    // destination's label was the one sacrificed.
                    hidesLowerPriorities = true
                    occupiedLabelRects.removeAll()
                    for id in Array(newPlacements.keys) {
                        newPlacements[id] = .hidden
                    }
                }
            }

            newPlacements[projectedLabel.input.id] = placement
            if let placedRect {
                occupiedLabelRects.append(placedRect.insetBy(dx: -2, dy: -2))
            }
        }

        guard newPlacements != labelPlacements else { return }
        labelPlacements = newPlacements
    }

    private func estimatedLabelSize(for name: String) -> CGSize {
        let preferredFont = UIFont.preferredFont(forTextStyle: .caption2)
        let font = UIFont.systemFont(
            ofSize: preferredFont.pointSize,
            weight: .semibold
        )
        let measuredSize = (name as NSString).size(
            withAttributes: [.font: font]
        )

        return CGSize(
            width: min(104, max(18, ceil(measuredSize.width))) + 4,
            height: ceil(font.lineHeight) + 2
        )
    }

    private func savedMarkerAccessibilityName(_ place: SavedPlace) -> String {
        // A custom name is the place's sole user-facing name, including in
        // VoiceOver. Do not reveal the underlying city as a second label.
        displayName(place)
    }

    private func canPlaceLabel(
        for rect: CGRect,
        labelID: City.ID,
        occupiedLabelRects: [CGRect],
        markerObstacles: [(id: City.ID, rect: CGRect)],
        viewportBounds: CGRect
    ) -> Bool {
        let collisionRect = rect.insetBy(dx: -2, dy: -2)
        guard viewportBounds.contains(collisionRect),
              !occupiedLabelRects.contains(where: {
                  $0.intersects(collisionRect)
              }) else {
            return false
        }

        return !markerObstacles.contains { obstacle in
            obstacle.id != labelID
                && obstacle.rect.intersects(collisionRect)
        }
    }

    // MARK: Camera fitting and marker semantics

    /// Chooses a useful initial frame without fighting the user's later manual
    /// map gestures. A selected city takes precedence over location and list.
    private func initializeCamera() {
        if let selectedPlaceID,
           let selected = visiblePresentations.first(where: {
               $0.id == selectedPlaceID
           }) {
            position = .region(
                PlacesMapRegionFitting.region(
                    centeredOn: selected.place.city,
                    span: 0.35
                )
            )
        } else if let locationCoordinate {
            position = .region(
                MKCoordinateRegion(
                    center: locationCoordinate,
                    span: Self.initialLocationSpan
                )
            )
        } else {
            guard !visiblePresentations.isEmpty else {
                position = .automatic
                return
            }
            position = .region(
                PlacesMapRegionFitting.region(
                    for: visiblePresentations.map(\.place.city)
                )
            )
        }
    }

    /// Centers on the real location marker at the same zoom used
    /// when Map first opens, instead of fitting saved cities or zooming in.
    private func focusLocation() {
        guard let locationCoordinate else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
            position = .region(
                MKCoordinateRegion(
                    center: locationCoordinate,
                    span: Self.initialLocationSpan
                )
            )
        }
    }

    /// A city chosen in Search enters Map as an explicit preview rather than a
    /// detail route, so the pin and save decision are visible immediately.
    private func focus(on city: City) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
            position = .region(
                PlacesMapRegionFitting.region(centeredOn: city, span: 0.5)
            )
        }
    }

    /// Adapts the original zoom-to-fit implementation to Find Sun. Near Me
    /// includes the physical search origin; broader scopes fit their returned
    /// dots. Asymmetric padding reserves the legend, utility capsule, result
    /// panel, and floating navigation areas rather than hiding edge markers.
    private func fitSunSearchRequest(
        _ request: MapSunCameraRequest,
        viewportSize: CGSize
    ) {
        var coordinates = request.cities.map {
            CLLocationCoordinate2D(
                latitude: $0.latitude,
                longitude: $0.longitude
            )
        }
        if request.kind == .nearMe,
           let origin = request.origin,
           !coordinates.contains(where: {
               abs($0.latitude - origin.latitude) < 0.000_001
                   && abs($0.longitude - origin.longitude) < 0.000_001
           }) {
            coordinates.append(origin)
        }
        guard !coordinates.isEmpty else { return }

        let resultPanelClearance: CGFloat = request.cities.isEmpty
            ? 72
            : MapSunResultsPanel.height(for: dynamicTypeSize) + 52
        let padding = EdgeInsets(
            top: showsLegend ? 150 : 28,
            leading: showsLegend ? 76 : 28,
            bottom: resultPanelClearance,
            trailing: 76
        )
        let region = PlacesMapRegionFitting.region(
            for: coordinates,
            viewportSize: viewportSize,
            edgePadding: padding
        )

        withAnimation(reduceMotion ? nil : .smooth(duration: 0.42)) {
            position = .region(region)
        }
    }

    /// Different metrics have different required forecast fields. Returning
    /// false keeps a partially populated marker from implying false precision.
    private func hasValidActiveLayerData(
        _ presentation: PlacesMapPlacePresentation
    ) -> Bool {
        guard let recommendation = presentation.recommendation else {
            return false
        }

        switch sortMode {
        case .sunny, .temperature, .cloud:
            return true
        case .feelsLike:
            return recommendation.maximumFeelsLike != nil
        case .rainChance:
            return recommendation.precipitationChance != nil
        case .visibility:
            return recommendation.maximumVisibilityKilometers != nil
        case .uvIndex:
            return recommendation.forecast.uvIndex != nil
        }
    }

    private func markerColor(
        for presentation: PlacesMapPlacePresentation
    ) -> Color? {
        // These are continuous color ramps for numeric layers. `nil` means the
        // active metric is missing, so the marker is excluded upstream.
        guard let recommendation = presentation.recommendation else { return nil }
        return markerColor(for: recommendation)
    }

    private var locationColor: Color {
        locationRecommendation.flatMap(markerColor(for:))
            ?? theme.colors.secondaryText
    }

    private func markerColor(
        for recommendation: PlaceRecommendation
    ) -> Color? {
        switch sortMode {
        case .sunny:
            return recommendation.condition.dotColor(for: theme.colors)
        case .temperature:
            return temperatureColor(for: recommendation.forecast.dailyHigh)
        case .feelsLike:
            guard let value = recommendation.maximumFeelsLike else {
                return nil
            }
            return temperatureColor(for: value)
        case .cloud:
            guard let value = recommendation.cloudCover else {
                return nil
            }
            return theme.colors.dotRain.interpolated(
                with: theme.colors.dotCloudy,
                by: clamped(value)
            )
        case .rainChance:
            guard let value = recommendation.precipitationChance else {
                return nil
            }
            return theme.colors.dotCloudy.interpolated(
                with: theme.colors.dotDrizzle,
                by: clamped(value)
            )
        case .visibility:
            guard let value = recommendation.maximumVisibilityKilometers else {
                return nil
            }
            return theme.colors.dotRain.interpolated(
                with: theme.colors.dotSun,
                by: clamped(value / 30)
            )
        case .uvIndex:
            guard let value = recommendation.forecast.uvIndex else {
                return nil
            }
            return theme.colors.dotCloudy.interpolated(
                with: theme.colors.destructive,
                by: clamped(Double(value) / 11)
            )
        }
    }

    private var cardMaximumWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 390 : 580
    }

    private var legendTopPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 24 : 12
    }

    private var legendTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .scale(scale: 0.92, anchor: .topLeading)
            .combined(with: .opacity)
    }

    // MARK: Marker labels, colors, and animation support

    /// Non-sunny map layers encode the selected numeric metric inside the pin
    /// capsule; the sunny layer instead uses a condition symbol.
    private func markerDifferentiatingText(
        for presentation: PlacesMapPlacePresentation
    ) -> String? {
        guard let recommendation = presentation.recommendation else {
            return nil
        }

        switch sortMode {
        case .sunny:
            return nil
        case .temperature:
            return temperatureUnit.display(
                recommendation.forecast.dailyHigh
            )
        case .feelsLike:
            return recommendation.maximumFeelsLike.map(
                temperatureUnit.display
            )
        case .cloud:
            return recommendation.cloudCover.map(percentage)
        case .rainChance:
            return recommendation.precipitationChance.map(percentage)
        case .visibility:
            return recommendation.maximumVisibilityKilometers.map(
                distanceUnit.display
            )
        case .uvIndex:
            return recommendation.forecast.uvIndex.map(String.init)
        }
    }

    /// Spoken marker values mirror the active map layer, so a colored dot does
    /// not leave VoiceOver users to infer a forecast value from its appearance.
    private func markerAccessibilityValue(
        for presentation: PlacesMapPlacePresentation
    ) -> String {
        guard let recommendation = presentation.recommendation else {
            return localizedString("Forecast unavailable", locale: locale)
        }
        return markerAccessibilityValue(for: recommendation)
    }

    private func markerAccessibilityValue(
        for recommendation: PlaceRecommendation
    ) -> String {
        let value: String
        switch sortMode {
        case .sunny:
            value = mapCardSunnyHoursText(for: recommendation, locale: locale)
        case .temperature:
            value = temperatureUnit.display(recommendation.forecast.dailyHigh)
        case .feelsLike:
            value = recommendation.maximumFeelsLike.map(temperatureUnit.display)
                ?? localizedString("Forecast unavailable", locale: locale)
        case .cloud:
            value = recommendation.cloudCover.map(percentage)
                ?? localizedString("Forecast unavailable", locale: locale)
        case .rainChance:
            value = recommendation.precipitationChance.map(percentage)
                ?? localizedString("Forecast unavailable", locale: locale)
        case .visibility:
            value = recommendation.maximumVisibilityKilometers.map(distanceUnit.display)
                ?? localizedString("Forecast unavailable", locale: locale)
        case .uvIndex:
            value = recommendation.forecast.uvIndex.map(String.init)
                ?? localizedString("Forecast unavailable", locale: locale)
        }
        return String(
            format: localizedString("%@: %@", locale: locale),
            locale: locale,
            sortMode.title(locale: locale),
            value
        )
    }

    private func markerDifferentiatingSymbol(
        for presentation: PlacesMapPlacePresentation
    ) -> String? {
        guard sortMode == .sunny else { return nil }
        return presentation.recommendation?.condition.displayIcon
            ?? "exclamationmark"
    }

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .systemDefault
    }

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    private func percentage(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func temperatureColor(for celsius: Double) -> Color {
        // Interpolate across deliberately broad temperature bands. The exact
        // color is a visual comparison aid, not a separate weather value.
        let colors = theme.colors
        let partlySunny = colors.dotPartlyCloudy.interpolated(
            with: colors.filterSunny,
            by: 0.18
        )

        if celsius <= 0 {
            return colors.dotRain.interpolated(
                with: colors.dotDrizzle,
                by: clamped((celsius + 20) / 20)
            )
        }
        if celsius <= 10 {
            return colors.dotDrizzle.interpolated(
                with: colors.dotCloudy,
                by: clamped(celsius / 10)
            )
        }
        if celsius <= 20 {
            return colors.dotCloudy.interpolated(
                with: partlySunny,
                by: clamped((celsius - 10) / 10)
            )
        }
        return partlySunny.interpolated(
            with: colors.destructive,
            by: clamped((celsius - 20) / 20)
        )
    }

    private func clamped(_ value: Double) -> Double {
        max(0, min(1, value))
    }

    /// A native MapKit overlay spanning the complete projected world map.
    private var baseMapWashPoints: [MKMapPoint] {
        let world = MKMapRect.world
        return [
            MKMapPoint(x: world.minX, y: world.minY),
            MKMapPoint(x: world.maxX, y: world.minY),
            MKMapPoint(x: world.maxX, y: world.maxY),
            MKMapPoint(x: world.minX, y: world.maxY)
        ]
    }
}

// MARK: - Annotation Building Blocks

/// Adds the map-specific color to the shared saved-place presentation model.
private struct PlacesMapMarkerPresentation: Identifiable {
    let presentation: PlacesMapPlacePresentation
    let color: Color

    var id: City.ID { presentation.id }
}

/// Equatable, coordinate-only input for the collision algorithm. Keeping it
/// small lets `.onChange` avoid recomputing labels for unrelated view state.
private struct PlacesMapLabelLayoutInput: Equatable {
    let id: City.ID
    let name: String
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let priority: Int
    let isSelected: Bool

    init(
        id: City.ID,
        name: String,
        coordinate: CLLocationCoordinate2D,
        priority: Int,
        isSelected: Bool
    ) {
        self.id = id
        self.name = name
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        self.priority = priority
        self.isSelected = isSelected
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }
}

/// A geographic label after MapKit has projected it into canvas coordinates.
private struct PlacesMapProjectedLabel {
    let input: PlacesMapLabelLayoutInput
    let point: CGPoint
    let size: CGSize

    func rect(for placement: PlacesMapLabelPlacement) -> CGRect {
        CGRect(
            x: point.x - size.width / 2,
            y: point.y + placement.verticalOffset - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

/// The two candidate positions plus an explicit collision-hidden state.
private enum PlacesMapLabelPlacement: Equatable {
    case above
    case below
    case hidden

    var verticalOffset: CGFloat {
        switch self {
        case .above:
            -25
        case .below:
            25
        case .hidden:
            0
        }
    }

    var isVisible: Bool { self != .hidden }
}

/// A distinct marker for the device coordinate, independent of the
/// saved-place weather layer.
private struct CurrentLocationMapAnnotation: View {
    let markerID: UUID
    let name: String
    let color: Color
    let isSelected: Bool
    let labelPlacement: PlacesMapLabelPlacement
    let accessibilityValue: String?
    let select: () -> Void

    @Environment(\.accessibilityDifferentiateWithoutColor)
    private var differentiateWithoutColor

    var body: some View {
        Button(action: select) {
            ZStack {
                if isSelected && !differentiateWithoutColor {
                    PlacesMapSelectedPulseRing(
                        markerID: markerID,
                        color: color,
                        diameter: 30,
                        expandedScale: 1.28
                    )
                }

                Image(systemName: "location.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
                    .shadow(color: color.opacity(0.32), radius: 3, y: 1)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .overlay {
            PlacesMapMarkerLabel(name: name, placement: labelPlacement)
        }
        .accessibilityLabel(name)
        .accessibilityValue(accessibilityValue ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A 44-point tap target surrounding the compact visual weather marker.
private struct PlacesWeatherMapAnnotation: View {
    let markerID: UUID
    let name: String
    let accessibilityName: String
    let color: Color
    let isSelected: Bool
    let labelPlacement: PlacesMapLabelPlacement
    let differentiatingText: String?
    let differentiatingSymbol: String?
    let accessibilityValue: String
    let showsMetricText: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            PlacesWeatherMapDot(
                markerID: markerID,
                color: color,
                isSelected: isSelected,
                differentiatingText: differentiatingText,
                differentiatingSymbol: differentiatingSymbol,
                showsMetricText: showsMetricText
            )
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .overlay {
            PlacesMapMarkerLabel(name: name, placement: labelPlacement)
        }
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One label treatment shared by weather dots, Find Sun results, and location.
private struct PlacesMapMarkerLabel: View {
    let name: String
    let placement: PlacesMapLabelPlacement

    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(name)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(theme.colors.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: 104)
            .fixedSize(horizontal: true, vertical: false)
            .offset(y: placement.verticalOffset)
            .opacity(placement.isVisible ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Draws both the ordinary color dot and accessible/high-contrast alternatives
/// without making the MapKit annotation itself responsible for those details.
private struct PlacesWeatherMapDot: View {
    let markerID: UUID
    let color: Color
    let isSelected: Bool
    let differentiatingText: String?
    let differentiatingSymbol: String?
    let showsMetricText: Bool

    @Environment(\.accessibilityDifferentiateWithoutColor)
    private var differentiateWithoutColor
    @Environment(\.appTheme) private var theme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var markerScale: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 1.25 : 1
    }

    var body: some View {
        ZStack {
            // Keep the ordinary weather-dot halo static. Selection feedback is
            // deliberately supplied only by the shared centered ring below,
            // matching the Current Location annotation exactly.
            Circle()
                .fill(color.opacity(0.22))
                .frame(width: 18, height: 18)
                .blur(radius: 5)

            if isSelected && !differentiateWithoutColor {
                PlacesMapSelectedPulseRing(
                    markerID: markerID,
                    color: color,
                    diameter: 22,
                    expandedScale: 1.28
                )
            }

            if differentiateWithoutColor
                || (showsMetricText && differentiatingText != nil) {
                // A bordered text/symbol capsule supplies a second channel of
                // meaning when color alone is insufficient or a numeric layer
                // needs its actual value printed inside the marker.
                differentiatingContent
                    .frame(minWidth: 26, maxWidth: 44, minHeight: 24)
                    .background {
                        if colorSchemeContrast == .increased {
                            Capsule().fill(theme.colors.glassFill)
                        } else {
                            Capsule().fill(.regularMaterial)
                        }
                    }
                    .overlay {
                        Capsule()
                            .stroke(
                                colorSchemeContrast == .increased
                                    ? theme.colors.primaryText
                                    : color,
                                lineWidth: isSelected ? 3 : 2
                            )
                    }
            } else if colorSchemeContrast == .increased {
                Circle()
                    .fill(theme.colors.glassFill)
                    .frame(
                        width: isSelected ? 24 : 20,
                        height: isSelected ? 24 : 20
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                theme.colors.primaryText,
                                lineWidth: isSelected ? 2.5 : 2
                            )
                    }

                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                    .shadow(color: color.opacity(0.42), radius: 3)
            }
        }
        .scaleEffect(markerScale)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }

    @ViewBuilder
    private var differentiatingContent: some View {
        if let differentiatingText {
            Text(differentiatingText)
                .font(.caption2.weight(.bold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 5)
        } else if let differentiatingSymbol {
            Image(systemName: differentiatingSymbol)
                .font(.caption2.weight(.bold))
                // Keep the accessibility weather symbol in the same semantic
                // color as the marker it describes.
                .foregroundStyle(color)
                .padding(5)
        }
    }
}

/// A reusable selection treatment. It reacts to Reduce Motion rather than
/// starting an animation the user has explicitly asked to avoid.
private struct PlacesMapSelectedPulseRing: View {
    /// A marker-specific identity prevents MapKit annotation recycling from
    /// carrying the previous dot's pulse geometry to a new selection.
    let markerID: UUID
    let color: Color
    var diameter: CGFloat = 22
    var expandedScale: CGFloat = 1.22

    /// Separates the centred appearance from the repeating pulse so a newly
    /// selected marker never starts its first pulse partway through the ring.
    @State private var hasEntered = false
    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scale: CGFloat {
        guard hasEntered else { return 0.01 }
        return isPulsing ? expandedScale : 1
    }

    private var opacity: Double {
        guard hasEntered else { return 0 }
        return isPulsing ? 0.28 : 0.8
    }

    var body: some View {
        Circle()
            .stroke(
                color.opacity(opacity),
                lineWidth: isPulsing ? 1.5 : 2.5
            )
            .frame(width: diameter, height: diameter)
            // The visual starts at the marker's exact centre, grows to its
            // resting ring, then begins the outward pulse from that position.
            .scaleEffect(scale, anchor: .center)
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: 0.22),
                value: hasEntered
            )
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 1.05)
                        .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear(perform: startPulseSequence)
            .onChange(of: reduceMotion) { _, shouldReduceMotion in
                if shouldReduceMotion {
                    hasEntered = true
                    isPulsing = false
                } else {
                    startPulseSequence()
                }
            }
            .frame(width: 44, height: 44)
            // Selection also morphs the bottom card. Do not let that outer
            // transaction animate this annotation between two map positions;
            // the ring owns its own centred entry animation below.
            .transaction { transaction in
                transaction.animation = nil
            }
            .id(markerID)
            // The ring owns its entry state, rather than inheriting an
            // annotation transition that could choose an off-centre origin.
            .transition(.identity)
    }

    private func startPulseSequence() {
        guard !reduceMotion else {
            hasEntered = true
            isPulsing = false
            return
        }

        hasEntered = false
        isPulsing = false
        withAnimation(.easeOut(duration: 0.22)) {
            hasEntered = true
        } completion: {
            guard !reduceMotion else { return }
            isPulsing = true
        }
    }
}

// MARK: - Map Legend and Camera Geometry

/// Explains the colors for whichever metric the map is currently displaying.
private struct PlacesMapLegend: View {
    let sortMode: WeatherMetricMode

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit")
    private var distanceUnitRaw = DistanceUnit.defaultRawValue

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.vertical) {
                    legendContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.visible)
                .frame(maxHeight: 220)
            } else {
                legendContent
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(
            width: legendWidth,
            alignment: .leading
        )
        .detailTranslucentCard(
            colorScheme: colorScheme,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .fixedSize(
            horizontal: !dynamicTypeSize.isAccessibilitySize,
            vertical: false
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(sortMode.title(locale: locale))
    }

    @ViewBuilder
    private var legendContent: some View {
        metricLegendContent
    }

    @ViewBuilder
    private var metricLegendContent: some View {
        switch sortMode {
        case .sunny:
            VStack(alignment: .leading, spacing: 11) {
                legendEntry(
                    localizedString("Clear", locale: locale),
                    color: theme.colors.dotSun
                )
                legendEntry(
                    localizedString("Partly Sunny", locale: locale),
                    color: theme.colors.dotPartlyCloudy
                )
                legendEntry(
                    localizedString("Rain", locale: locale),
                    color: theme.colors.dotRain
                )
                legendEntry(
                    localizedString("Drizzle", locale: locale),
                    color: theme.colors.dotDrizzle
                )
                legendEntry(
                    cloudyTitle,
                    color: theme.colors.dotCloudy
                )
            }
        case .temperature, .feelsLike:
            verticalGradientLegend(
                colors: [
                    temperatureColor(for: 40),
                    temperatureColor(for: 20),
                    temperatureColor(for: 10),
                    temperatureColor(for: 0),
                    temperatureColor(for: -20)
                ],
                labels: temperatureUnit == .fahrenheit
                    ? ["104°F", "68°F", "50°F", "32°F", "-4°F"]
                    : ["40°C", "20°C", "10°C", "0°C", "-20°C"]
            )
        case .cloud:
            verticalGradientLegend(
                colors: [
                    cloudColor(1),
                    cloudColor(0.66),
                    cloudColor(0.33),
                    cloudColor(0)
                ],
                labels: ["100%", "75%", "50%", "25%", "0%"]
            )
        case .rainChance:
            verticalGradientLegend(
                colors: [
                    rainColor(1),
                    rainColor(0.66),
                    rainColor(0.33),
                    rainColor(0)
                ],
                labels: ["100%", "75%", "50%", "25%", "0%"]
            )
        case .visibility:
            verticalGradientLegend(
                colors: [
                    theme.colors.dotSun,
                    theme.colors.dotPartlyCloudy,
                    theme.colors.dotCloudy,
                    theme.colors.dotRain
                ],
                labels: [
                    distanceUnit.display(30),
                    distanceUnit.display(20),
                    distanceUnit.display(10),
                    distanceUnit.display(0)
                ]
            )
        case .uvIndex:
            verticalGradientLegend(
                colors: [
                    uvColor(1),
                    uvColor(0.82),
                    uvColor(0.55),
                    uvColor(0.27),
                    uvColor(0)
                ],
                labels: ["11+", "9", "6", "3", "0"]
            )
        }
    }

    private func legendEntry(
        _ title: String,
        color: Color
    ) -> some View {
        let isWrapped = title.contains("\n")

        return HStack(
            alignment: isWrapped ? .top : .center,
            spacing: 12
        ) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.5), radius: 2)
                .padding(.top, isWrapped ? 5 : 0)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(
                    horizontal: !dynamicTypeSize.isAccessibilitySize,
                    vertical: true
                )
        }
    }

    private var cloudyTitle: String {
        let title = localizedString(
            "Cloudy, Windy, Snowy, Foggy",
            locale: locale
        )
        let separator = title.contains("、") ? "、" : ","
        let conditions = title
            .components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard conditions.count == 4 else { return title }

        let joiner = separator == "、" ? separator : "\(separator) "
        let firstLine = conditions.prefix(2).joined(separator: joiner)
        let secondLine = conditions.suffix(2).joined(separator: joiner)
        return "\(firstLine)\(separator)\n\(secondLine)"
    }

    private func verticalGradientLegend(
        colors: [Color],
        labels: [String]
    ) -> some View {
        // A gradient's labels describe its endpoints and intermediate values;
        // they are intentionally one more than some of the color stop arrays.
        HStack(alignment: .center, spacing: 10) {
            LinearGradient(
                colors: colors,
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 10, height: gradientHeight)
            .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.element) {
                    index,
                    label in
                    Text(label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(theme.colors.secondaryText)
                    if index < labels.count - 1 {
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(height: gradientHeight)
        }
    }

    private var legendWidth: CGFloat? {
        if dynamicTypeSize.isAccessibilitySize {
            return 260
        }
        return sortMode == .sunny ? nil : 172
    }

    private var gradientHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 200 : 132
    }

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .systemDefault
    }

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    private func temperatureColor(for celsius: Double) -> Color {
        let colors = theme.colors
        let partlySunny = colors.dotPartlyCloudy.interpolated(
            with: colors.filterSunny,
            by: 0.18
        )
        if celsius <= 0 {
            return colors.dotRain.interpolated(
                with: colors.dotDrizzle,
                by: clamped((celsius + 20) / 20)
            )
        }
        if celsius <= 10 {
            return colors.dotDrizzle.interpolated(
                with: colors.dotCloudy,
                by: clamped(celsius / 10)
            )
        }
        if celsius <= 20 {
            return colors.dotCloudy.interpolated(
                with: partlySunny,
                by: clamped((celsius - 10) / 10)
            )
        }
        return partlySunny.interpolated(
            with: colors.destructive,
            by: clamped((celsius - 20) / 20)
        )
    }

    private func cloudColor(_ value: Double) -> Color {
        theme.colors.dotRain.interpolated(
            with: theme.colors.dotCloudy,
            by: clamped(value)
        )
    }

    private func rainColor(_ value: Double) -> Color {
        theme.colors.dotCloudy.interpolated(
            with: theme.colors.dotDrizzle,
            by: clamped(value)
        )
    }

    private func uvColor(_ value: Double) -> Color {
        theme.colors.dotCloudy.interpolated(
            with: theme.colors.destructive,
            by: clamped(value)
        )
    }

    private func clamped(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}

/// Computes a camera region that includes a set of cities, including sets that
/// cross the International Date Line (where a naive min/max longitude fails).
private enum PlacesMapRegionFitting {
    static func region(
        centeredOn city: City,
        span: CLLocationDegrees
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: city.latitude,
                longitude: city.longitude
            ),
            span: MKCoordinateSpan(
                latitudeDelta: span,
                longitudeDelta: span
            )
        )
    }

    static func region(for cities: [City]) -> MKCoordinateRegion {
        region(
            for: cities.map {
                CLLocationCoordinate2D(
                    latitude: $0.latitude,
                    longitude: $0.longitude
                )
            }
        )
    }

    static func region(
        for coordinates: [CLLocationCoordinate2D]
    ) -> MKCoordinateRegion {
        precondition(!coordinates.isEmpty)

        var minimumLatitude = coordinates[0].latitude
        var maximumLatitude = coordinates[0].latitude
        for coordinate in coordinates.dropFirst() {
            minimumLatitude = min(minimumLatitude, coordinate.latitude)
            maximumLatitude = max(maximumLatitude, coordinate.latitude)
        }

        let longitudeArc = minimumLongitudeArc(
            for: coordinates.map(\.longitude)
        )
        return paddedRegion(
            minimumLatitude: minimumLatitude,
            maximumLatitude: maximumLatitude,
            centerLongitude: longitudeArc.center,
            longitudeSpan: longitudeArc.span
        )
    }

    /// Expands and offsets the historical geographic fitter so all coordinates
    /// land inside the unobscured rectangle left by SwiftUI map overlays.
    static func region(
        for coordinates: [CLLocationCoordinate2D],
        viewportSize: CGSize,
        edgePadding: EdgeInsets
    ) -> MKCoordinateRegion {
        let base = region(for: coordinates)
        let width = max(1, Double(viewportSize.width))
        let height = max(1, Double(viewportSize.height))
        let leading = max(0, Double(edgePadding.leading))
        let trailing = max(0, Double(edgePadding.trailing))
        let top = max(0, Double(edgePadding.top))
        let bottom = max(0, Double(edgePadding.bottom))
        let availableWidth = max(1, width - leading - trailing)
        let availableHeight = max(1, height - top - bottom)

        let longitudeDelta = min(
            340,
            base.span.longitudeDelta * width / availableWidth
        )
        let latitudeDelta = min(
            160,
            base.span.latitudeDelta * height / availableHeight
        )
        let longitudeShift = (trailing - leading)
            * longitudeDelta / (2 * width)
        let latitudeShift = (top - bottom)
            * latitudeDelta / (2 * height)

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: max(
                    -85,
                    min(85, base.center.latitude + latitudeShift)
                ),
                longitude: normalizedLongitude(
                    base.center.longitude + longitudeShift
                )
            ),
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta,
                longitudeDelta: longitudeDelta
            )
        )
    }

    /// Finds the smallest longitude arc by removing the largest gap between
    /// sorted longitudes on a circular 0…360-degree scale.
    private static func minimumLongitudeArc(
        for longitudes: [CLLocationDegrees]
    ) -> (center: CLLocationDegrees, span: CLLocationDegrees) {
        guard longitudes.count > 1 else {
            return (longitudes.first ?? 0, 0)
        }

        let normalized = longitudes
            .map { $0 >= 0 ? $0 : $0 + 360 }
            .sorted()
        var largestGap = -CLLocationDegrees.infinity
        var arcStart = normalized[0]

        for index in normalized.indices {
            let current = normalized[index]
            let next = index == normalized.index(before: normalized.endIndex)
                ? normalized[0] + 360
                : normalized[index + 1]
            let gap = next - current
            if gap > largestGap {
                largestGap = gap
                arcStart = next.truncatingRemainder(dividingBy: 360)
            }
        }

        let span = 360 - largestGap
        let normalizedCenter = (arcStart + span / 2)
            .truncatingRemainder(dividingBy: 360)
        let center = normalizedCenter > 180
            ? normalizedCenter - 360
            : normalizedCenter
        return (center, span)
    }

    private static func normalizedLongitude(
        _ longitude: CLLocationDegrees
    ) -> CLLocationDegrees {
        var normalized = longitude.truncatingRemainder(dividingBy: 360)
        if normalized > 180 { normalized -= 360 }
        if normalized < -180 { normalized += 360 }
        return normalized
    }

    private static func paddedRegion(
        minimumLatitude: CLLocationDegrees,
        maximumLatitude: CLLocationDegrees,
        centerLongitude: CLLocationDegrees,
        longitudeSpan: CLLocationDegrees
    ) -> MKCoordinateRegion {
        // Add breathing room and cap world-scale spans. The lower bounds avoid
        // a single city creating an unusably tight, street-level camera.
        let latitudeDelta = max(
            1.2,
            (maximumLatitude - minimumLatitude) * 1.25
        )
        let longitudeDelta = max(1.2, longitudeSpan * 1.25)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minimumLatitude + maximumLatitude) / 2,
                longitude: centerLongitude
            ),
            span: MKCoordinateSpan(
                latitudeDelta: min(160, latitudeDelta),
                longitudeDelta: min(340, longitudeDelta)
            )
        )
    }
}
