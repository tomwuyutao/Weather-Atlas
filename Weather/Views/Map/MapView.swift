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

/// Lightweight data for Map's native error alert.
struct MapUIError: Identifiable {
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

/// A value-type snapshot of MapKit's visible region. Storing plain numbers
/// makes it Equatable, so SwiftUI can cheaply notice a meaningful camera move.
struct MapViewport: Equatable {
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
struct MapSunCameraRequest: Equatable {
    enum Kind: Equatable {
        case nearMe
        case nearPlace
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

/// The fully specified request passed from the Find Sun sheet or a contextual
/// map card to the map. Region scopes carry their selection while a city-based
/// request carries the exact city coordinate that anchors its shared local
/// candidate pool.
enum MapSunQueryScope: Equatable {
    case area
    /// Near Me deliberately shares the fixed 200 km policy used by Your
    /// Location, so no caller can supply a conflicting radius.
    case nearMe
    /// The Your Location card's CTA carries its strict comparison semantics to
    /// Map: candidates must have more selected-day sunny hours than the current
    /// location, rather than merely more than zero.
    case nearbySunnier
    case nearPlace(City)
    case country(CountryPlacesOption)
    case continent(ContinentPlacesOption)

    func summary(locale: Locale) -> String {
        switch self {
        case .area:
            localizedString("sunny places in this map area", locale: locale)
        case .nearMe:
            String(
                format: localizedString(
                    "sunny places within %@ km",
                    locale: locale
                ),
                locale: locale,
                NearbySunSearchPolicy.radiusKilometers.formatted(
                    .number.locale(locale)
                )
            )
        case .nearbySunnier:
            localizedString("Nearby Sunnier Places", locale: locale)
        case .nearPlace(let city):
            String(
                format: localizedString(
                    "sunny places near %@",
                    locale: locale
                ),
                locale: locale,
                city.displayName
            )
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

    /// Context shown while the selected scope is being evaluated. Naming the
    /// scope keeps the compact progress surface useful after its sheet closes.
    func loadingTitle(locale: Locale) -> String {
        switch self {
        case .area:
            localizedString(
                "Finding sunny places in this area",
                locale: locale
            )
        case .nearMe:
            localizedString(
                "Finding sunny places near you",
                locale: locale
            )
        case .nearbySunnier:
            localizedString("Loading nearby sunnier places…", locale: locale)
        case .nearPlace(let city):
            String(
                format: localizedString(
                    "Finding sunny places near %@",
                    locale: locale
                ),
                locale: locale,
                city.displayName
            )
        case .country(let country):
            String(
                format: localizedString(
                    "Finding sunny places in %@",
                    locale: locale
                ),
                locale: locale,
                country.localizedName(locale: locale)
            )
        case .continent(let continent):
            String(
                format: localizedString(
                    "Finding sunny places in %@",
                    locale: locale
                ),
                locale: locale,
                continent.localizedName(locale: locale)
            )
        }
    }

    /// Short scope name used by the Find Sun result summary and ranking sheet.
    /// Country and continent results should identify the chosen region directly
    /// rather than repeat the action that produced them.
    func resultsTitle(locale: Locale) -> String {
        switch self {
        case .area:
            localizedString("This Area", locale: locale)
        case .nearMe:
            localizedString("Near Me", locale: locale)
        case .nearbySunnier:
            localizedString("Nearby Sunnier Places", locale: locale)
        case .nearPlace(let city):
            String(
                format: localizedString("Near %@", locale: locale),
                locale: locale,
                city.displayName
            )
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
}

/// One place-scoped source issue used when Map consolidates missing values into
/// a single native alert instead of silently dropping markers or search rows.
struct MapNamedWeatherIssue: Hashable {
    let cityName: String
    let issue: WeatherDataIssue
}

/// Inputs that make a Map operation impossible before weather is requested.
/// These failures leave the corresponding results empty and name the missing
/// source in a native alert.
enum MapDataAvailabilityError: Error {
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
    @State private var presentedError: MapUIError?
    @State var currentViewport: MapViewport?
    @State var activeSunQuery: MapSunQueryScope?
    /// All valid Find Sun assessments drive Map dots, including places with
    /// zero sunny hours. The ranking sheet receives its sunnier-only subset
    /// separately so its recommendation copy remains truthful.
    @State var sunSearchResults: [MapSunSearchResult] = []
    @State var sunRankingResults: [MapSunSearchResult] = []
    /// Stable spatial candidates for the active query. They define both the
    /// date-independent camera frame and the persistent annotation hosts.
    @State var sunCandidateCities: [City] = []
    @State var sunCameraRequest: MapSunCameraRequest?
    /// Retains the source-to-saved identity after persistence merges a
    /// transient provider result into an equivalent place with another UUID.
    @State var acknowledgedSavedPlaceIDsByResultID:
        [City.ID: SavedPlace.ID] = [:]
    @State var selectedSunID: City.ID?
    @State var selectedPreviewID: City.ID?
    /// A toolbar action is handled by the canvas, which owns MapCameraPosition.
    @State private var locationFocusRequestID = 0
    /// Lets the parent close a child-owned map card before a new transient
    /// search or Search preview takes over the map.
    @State var selectionResetID = 0
    @State var isFindingSun = false
    /// A "This Area" command can arrive before MapKit has delivered its first
    /// viewport. Retain that explicit request until the camera is ready.
    @State var pendingAreaSunSearch = false
    /// Navigation visibility is separate from the active query, so popping the
    /// Find Sun list returns to the Map without clearing its results.
    @State private var isSunRankingPresented = false
    /// Rejects stale asynchronous Find Sun results after a date or scope change.
    @State var sunSearchID = 0
    /// Records the last external Map request already cleared locally. A
    /// dedicated token keeps a new hand-off from inheriting an earlier card,
    /// while allowing the corresponding Find Sun/preview callback to begin
    /// its new work exactly once regardless of SwiftUI callback order.
    @State private var handledMapHandoffToken = 0

    @Environment(\.locale) var locale
    @Environment(MissingDataAlertCenter.self) var missingDataAlerts

    // MARK: Shared stores and derived input

    /// The root model owns persistence and WeatherKit state; these shortcuts
    /// keep the view's derived properties readable without creating new stores.
    var placesStore: SavedPlacesStore {
        model.placesStore
    }

    var weatherStore: SavedPlacesWeatherStore {
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
                    isLoading: weatherStore.isLoading(place.id)
                )
            )
        }
    }

    private var presentations: [PlacesMapPlacePresentation] {
        savedPresentations
    }

    /// The Map is a sunny-place finder, so saved places always use the same
    /// sunny-hours ordering as Find Sun and Saved Places.
    private var sortedPresentations: [PlacesMapPlacePresentation] {
        let orderedRecommendations = PlaceRecommendation.ranked(
            presentations.compactMap(\.recommendation),
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

    /// Direct map taps are transient, so they are not part of the normal saved
    /// presentation array. This lightweight resolver gives their shared card
    /// the same selected-date weather state without creating a fake Saved Place.
    private func mapPlaceCardWeather(
        for city: City
    ) -> MapPlaceWeatherPresentation {
        let weather = weatherStore.weather(for: city.id)
        let hasFailure = weatherStore.failuresByID[city.id] != nil

        return MapPlaceWeatherPresentation(
            recommendation: weather.flatMap {
                model.placeRecommendation(for: $0, on: selectedDate)
            },
            // A freshly resolved map tap starts its preload in the canvas's
            // task. Treat the short pre-task gap as loading too, preventing an
            // unavailable flash before WeatherKit receives the request.
            isLoading: weatherStore.isLoading(city.id)
                || (weather == nil && !hasFailure)
        )
    }

    /// The canvas owns the selected transient city, so it receives a compact
    /// revision token and refreshes that city card when either its cache or the
    /// selected calendar day changes.
    private var mapPlaceCardWeatherRevision: String {
        "\(weatherStore.weatherRevision)-\(selectedDate.timeIntervalSinceReferenceDate)"
    }

    /// Uses the store's semantic matcher as well as exact UUIDs so duplicate
    /// provider results cannot leave a second transient dot after saving.
    private var savedPlaceIDsByTransientResultID: [City.ID: SavedPlace.ID] {
        // A transient result can stay selected while its Detail screen removes
        // the corresponding saved place. Keep only acknowledgements that still
        // resolve in the live store so the Map card returns to Save Place.
        var matches = acknowledgedSavedPlaceIDsByResultID.filter {
            placesStore.place(id: $0.value) != nil
        }
        var results = sunSearchResults
        if let previewCity = router.mapPreviewCity,
           let savedID = placesStore.savedPlaceID(matching: previewCity) {
            matches[previewCity.id] = savedID
        }
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

    /// Re-evaluates only when the visible Map request set or its request state
    /// changes. Metric, daylight, and selected-date changes do not affect a
    /// real request failure and therefore do not need another alert pass.
    private var mapWeatherAlertContextID: String {
        let loadingPlaceIDs = mapCities
            .filter { weatherStore.isLoading($0.id) }
            .map(\.id.uuidString)
            .sorted()
            .joined(separator: ",")
        return [
            weatherLoadID.map(\.uuidString).joined(separator: ","),
            String(weatherStore.weatherRevision),
            loadingPlaceIDs,
            router.mapPreviewCity?.id.uuidString ?? ""
        ].joined(separator: "|")
    }

    private var hasSystemicMapWeatherFailure: Bool {
        let cities = mapCities
        guard !cities.isEmpty else { return false }
        return cities.allSatisfy { weatherStore.failuresByID[$0.id] != nil }
    }

    private func updateVisibleMapWeatherAlert() async {
        let alertKey = "map-visible-weather"
        guard !mapCities.contains(where: { weatherStore.isLoading($0.id) }) else {
            return
        }

        // Ordinary partial forecasts remain visible on the Map. Only a total
        // failure of the visible request set needs an automatic retry/alert.
        guard hasSystemicMapWeatherFailure else {
            missingDataAlerts.resolve(key: alertKey)
            return
        }

        let cities = mapCities
        let namedIssues = cities.compactMap { city -> MapNamedWeatherIssue? in
            guard let failure = weatherStore.failuresByID[city.id] else {
                return nil
            }
            return MapNamedWeatherIssue(
                cityName: city.displayName,
                issue: failure.issue
            )
        }
        guard !namedIssues.isEmpty else {
            missingDataAlerts.resolve(key: alertKey)
            return
        }

        let report = MissingDataAlertReport(
            key: alertKey,
            title: localizedString("Data Missing", locale: locale),
            message: consolidatedMapWeatherMessage(namedIssues)
        )
        await missingDataAlerts.retryThenReport(
            report,
            recoveryKey: "map-visible-systemic-weather",
            retry: {
                await weatherStore.retryMissingData(for: cities)
            },
            isStillMissing: {
                hasSystemicMapWeatherFailure
            }
        )
    }

    func consolidatedMapWeatherMessage(
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
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                mapToolbar
            }
            .navigationDestination(isPresented: $isSunRankingPresented) {
                FindSunListView(
                    results: sunRankingResults,
                    title: activeSunQuery?.resultsTitle(locale: locale)
                        ?? localizedString("Results", locale: locale),
                    candidateCities: sunCandidateCities,
                    model: model,
                    router: router,
                    selectedDate: $selectedDate
                )
            }
            .task(id: weatherLoadID) {
                await weatherStore.load(
                    cities: mapCities
                )
            }
            .task(id: mapWeatherAlertContextID) {
                await updateVisibleMapWeatherAlert()
            }
            .onChange(of: selectedDate) {
                // One WeatherKit response supplies the full forecast horizon.
                // Keep the active Find Sun candidate set and rerank it locally
                // instead of clearing dots and showing the loading capsule.
                rerankSunSearchForSelectedDate()
            }
            .onChange(of: currentViewport) {
                resumePendingAreaSunSearchIfPossible()
            }
            .onChange(of: activeSunQuery) { oldQuery, newQuery in
                // A replacement or explicit clear ends the list presentation.
                // Navigation visibility remains independent from the result
                // data, so returning to Map never clears the active query.
                if oldQuery != newQuery {
                    isSunRankingPresented = false
                }
            }
            .onChange(of: router.mapHandoffToken, initial: true) {
                _, handoffToken in
                prepareForIncomingMapHandoff(token: handoffToken)
            }
            .onChange(of: router.mapPreviewCity?.id, initial: true) { _, previewID in
                // A Search hand-off has no separate query token. Consume its
                // Map session before selecting the new preview, so an older
                // Find Sun card cannot appear above it.
                if previewID != nil {
                    prepareForIncomingMapHandoff(
                        token: router.mapHandoffToken
                    )
                }
                selectedPreviewID = previewID
            }
            .onChange(of: selectedPreviewID) { oldID, newID in
                // Closing a Search preview always ends its transient Map
                // session. If it was saved, the ordinary Saved Places marker
                // remains; otherwise its temporary marker disappears too.
                if newID == nil {
                    if oldID != nil {
                        router.mapPreviewCity = nil
                    }
                }
            }
            .onChange(of: router.mapSunQueryToken, initial: true) {
                _, requestID in
                guard requestID > 0,
                      let scope = router.pendingMapSunQuery else {
                    return
                }
                prepareForIncomingMapHandoff(token: router.mapHandoffToken)
                // Consume the hand-off before starting async work. A later
                // Search selection can therefore replace this scope without
                // a stale Map re-evaluation running it again.
                router.pendingMapSunQuery = nil
                beginSunSearch(scope)
            }
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
    }

    @ToolbarContentBuilder
    private var mapToolbar: some ToolbarContent {
        if UIDevice.current.userInterfaceIdiom == .pad {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "slider.horizontal.3") {
                    router.presentedSheet = .settings
                }
                .labelStyle(.iconOnly)
            }
        }

        // The top bar stays dedicated to date navigation. Camera recentering
        // belongs with the lower Map actions, where it reads as a map command
        // rather than a second, unlabeled date-toolbar control.
        ToolbarItem(placement: .topBarTrailing) {
            dateToolbarItem
        }
    }

    private var dateToolbarItem: some View {
        TopForecastDateSwitcher(
            selection: $selectedDate,
            availableDates: mapDatePickerDates
        )
    }

    /// An active Find Sun session owns Map's date choices: the union is built
    /// from its real candidate forecasts rather than a generic fixed horizon.
    /// Ordinary Map and Search-preview use retain the standard app-wide dates.
    private var mapDatePickerDates: [Date] {
        guard activeSunQuery != nil
            || isFindingSun
            || !sunCandidateCities.isEmpty else {
            // A city Search deliberately selects that city's local Today. If
            // that civil day is still yesterday at the device location, keep
            // it navigable in Map's ordinary shared date picker as well.
            return ForecastDateHorizon.dates(
                in: model.forecastCalendar
            ) + [selectedDate]
        }
        return sunSearchDatePickerDates
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
            locationCoordinate: locationCoordinate,
            locationCity: model.locationCity ?? model.locationWeather?.city,
            locationName: CurrentLocationMetadata.localityName(
                from: model.homeLocation?.localizedDisplayName(locale: locale)
                    ?? model.locationProvider.metadata?.displayName
                    ?? model.locationWeather?.city.localizedDisplayName(
                        locale: locale
                    )
            ) ?? "",
            locationRecommendation: locationRecommendation,
            isLocationWeatherLoading: isLocationWeatherLoading,
            needsLocationWeather: needsCurrentLocationWeather,
            locationFocusRequestID: locationFocusRequestID,
            ensureLocationWeather: {
                await model.ensureCurrentLocationWeather(locale: locale)
            },
            sunSearchResults: sunSearchResults,
            sunCandidateCities: sunCandidateCities,
            isPresentingSunSearch: isFindingSun
                || activeSunQuery != nil
                || !sunSearchResults.isEmpty,
            sunCameraRequest: sunCameraRequest,
            savedPlaceIDsByTransientResultID:
                savedPlaceIDsByTransientResultID,
            selectedSunID: $selectedSunID,
            previewCity: router.mapPreviewCity,
            previewResult: previewResult,
            selectedPreviewID: $selectedPreviewID,
            selectionResetID: selectionResetID,
            sunSearchGeneration: sunSearchID,
            mapHandoffToken: router.mapHandoffToken,
            sunQueryTitle: activeSunQuery?.resultsTitle(locale: locale),
            sunQuerySummary: activeSunQuery?.summary(locale: locale),
            sunLoadingTitle: activeSunQuery?.loadingTitle(locale: locale),
            isFindingSun: isFindingSun,
            viewport: $currentViewport,
            displayName: displayName(for:),
            findSunHere: {
                beginSunSearch(.area)
            },
            findSunNearMe: {
                beginSunSearch(.nearMe)
            },
            findSunInCountry: { country in
                beginSunSearch(.country(country))
            },
            findSunInContinent: { continent in
                beginSunSearch(.continent(continent))
            },
            focusCurrentLocation: {
                locationFocusRequestID &+= 1
            },
            showSunRanking: {
                isSunRankingPresented = true
            },
            mapPlaceCardWeatherRevision: mapPlaceCardWeatherRevision,
            resolveMapPlaceCardWeather: { city in
                mapPlaceCardWeather(for: city)
            },
            isSavedPlace: { city in
                placesStore.savedPlaceID(matching: city) != nil
            },
            preloadTappedPlaceDetails: { city in
                // The regional card is an intentional decision point. Start
                // its detail forecast here so View Details can reuse the
                // store's cache or in-flight request instead of starting late.
                await weatherStore.load(cities: [city])
            },
            viewDetails: openTappedPlace,
            viewCurrentLocationDetails: openCurrentLocationDetails,
            findSunNear: { city in
                beginSunSearch(near: city)
            },
            findSunInRegion: { beginSunSearch($0) },
            clearSunSearch: clearSunSearch,
            saveSunResult: saveSunResult,
            saveSearchPreview: saveSearchPreview,
            saveTappedPlace: saveTappedPlace,
            removeSavedPlace: removeSavedPlace
        )
    }

    var locationCoordinate: CLLocationCoordinate2D? {
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

    /// Consumes one external Map request before its specific marker, preview,
    /// or Find Sun action is applied. Advancing the generation makes any late
    /// result from the previous session harmless, while the canvas receives a
    /// matching token to dismiss child-owned map-tap state without clearing a
    /// newly requested saved-place marker.
    func prepareForIncomingMapHandoff(token: Int) {
        guard token > handledMapHandoffToken else { return }
        handledMapHandoffToken = token

        isSunRankingPresented = false
        sunSearchID &+= 1
        activeSunQuery = nil
        isFindingSun = false
        pendingAreaSunSearch = false
        sunSearchResults = []
        sunRankingResults = []
        sunCandidateCities = []
        sunCameraRequest = nil
        selectedSunID = nil
        selectedPreviewID = nil
        acknowledgedSavedPlaceIDsByResultID = [:]
        presentedError = nil
        // Repeating a Search selection for the same city does not change the
        // optional city's identity, but it does advance the hand-off token.
        // Restore that requested preview here so a repeat cannot leave Map at
        // its bare root after the old session is cleared.
        if let preview = router.mapPreviewCity {
            selectedPreviewID = preview.id
        }
        missingDataAlerts.resolve(key: "map-find-sun-weather")
        missingDataAlerts.resolve(key: "map-find-sun-source")
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

    /// Current Location already has its own full report at the root of the
    /// Your Location tab. The Map card uses the same View Details affordance
    /// as every other marker, but routes there instead of manufacturing a
    /// saved-place detail destination for the transient device coordinate.
    private func openCurrentLocationDetails() {
        router.yourLocationPath = []
        router.selectedTab = .yourLocation
    }

    func present(_ error: Error) {
        presentedError = MapUIError(
            message: localizedPlacesErrorDescription(error)
        )
    }

}

// MARK: - Floating Map Actions

/// A dedicated recenter control lives near the Map's lower action surface
/// without becoming part of that surface's Find Sun semantics.
private struct MapFloatingLocationButton: View {
    let isEnabled: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if #available(iOS 26.0, *) {
            button
                .glassEffect(
                    isEnabled ? .regular.interactive() : .regular,
                    in: Circle()
                )
        } else {
            button
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(
                            theme.colors.primaryText.opacity(0.16),
                            lineWidth: 0.6
                        )
                }
        }
    }

    private var button: some View {
        Button("Zoom to Current Location", systemImage: "location.fill") {
            action()
        }
        .labelStyle(.iconOnly)
        .font(.body.weight(.semibold))
        .foregroundStyle(theme.colors.primaryText)
        .frame(width: compactSurfaceHeight, height: compactSurfaceHeight)
        .contentShape(Circle())
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var compactSurfaceHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 60 : MapCardLayout.compactHeight
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
    let locationCoordinate: CLLocationCoordinate2D?
    /// The model's stable current-location cache identity when it is already
    /// resolved. A short-lived coordinate fallback below covers the initial
    /// loading frame before WeatherKit has populated this value.
    let locationCity: City?
    let locationName: String
    let locationRecommendation: PlaceRecommendation?
    let isLocationWeatherLoading: Bool
    let needsLocationWeather: Bool
    let locationFocusRequestID: Int
    let ensureLocationWeather: () async -> Void
    let sunSearchResults: [MapSunSearchResult]
    let sunCandidateCities: [City]
    let isPresentingSunSearch: Bool
    let sunCameraRequest: MapSunCameraRequest?
    let savedPlaceIDsByTransientResultID: [City.ID: SavedPlace.ID]
    @Binding var selectedSunID: City.ID?
    /// Search immediately supplies the city. Its forecast result may arrive
    /// later, but the temporary selected marker and card must not wait for it.
    let previewCity: City?
    let previewResult: MapSunSearchResult?
    @Binding var selectedPreviewID: City.ID?
    let selectionResetID: Int
    /// A delayed Find Sun menu selection must not outlive a newer clear,
    /// query, or external Map hand-off.
    let sunSearchGeneration: Int
    /// An external request clears only child-owned Map selection state. The
    /// parent still controls the saved-place selection binding, so a hand-off
    /// to a saved marker remains selected rather than being immediately reset.
    let mapHandoffToken: Int
    let sunQueryTitle: String?
    let sunQuerySummary: String?
    let sunLoadingTitle: String?
    let isFindingSun: Bool
    @Binding var viewport: MapViewport?
    let displayName: (SavedPlace) -> String
    /// The primary Find Sun action uses the visible Map region immediately.
    let findSunHere: () -> Void
    let findSunNearMe: () -> Void
    let findSunInCountry: (CountryPlacesOption) -> Void
    let findSunInContinent: (ContinentPlacesOption) -> Void
    /// Recenters the Map without changing the active Find Sun query.
    let focusCurrentLocation: () -> Void
    let showSunRanking: () -> Void
    /// A parent-owned weather resolver gives a reverse-geocoded map tap the
    /// same selected-date presentation as saved and transient places.
    let mapPlaceCardWeatherRevision: String
    let resolveMapPlaceCardWeather: (City) -> MapPlaceWeatherPresentation
    /// Saving remains parent-owned so the canvas does not reach into the
    /// library store. This semantic matcher also lets a direct-tap bookmark
    /// become filled as soon as persistence succeeds.
    let isSavedPlace: (City) -> Bool
    /// Begins the normal cached WeatherKit load while a bare-map region card is
    /// visible. The card never waits for it; Detail coalesces with this work.
    let preloadTappedPlaceDetails: (City) async -> Void
    let viewDetails: (City) -> Void
    /// Device location does not become a Saved Place. Its Details action
    /// returns to the existing Your Location report instead.
    let viewCurrentLocationDetails: () -> Void
    /// Starts the fixed-radius Find Sun query using a tapped map city as its
    /// origin rather than the device's current location.
    let findSunNear: (City) -> Void
    let findSunInRegion: (MapSunQueryScope) -> Void
    let clearSunSearch: () -> Void
    let saveSunResult: (MapSunSearchResult) -> Bool
    let saveSearchPreview: (City) -> Bool
    let saveTappedPlace: (City) -> Bool
    let removeSavedPlace: (City) -> Bool

    // MARK: Map-local state and environment

    /// `MapCameraPosition` is deliberately local: moving the map should not
    /// invalidate the app's weather model or overwrite another screen's state.
    @State private var position: MapCameraPosition = .automatic
    @State private var hasInitializedCamera = false
    /// A targeted saved-place hand-off may arrive before its presentation has
    /// loaded. Retain just that one camera request until its city is available.
    @State private var pendingSavedPlaceFocusID: City.ID?
    @State private var labelPlacements:
        [City.ID: PlacesMapLabelPlacement] = [:]
    /// The coordinate is recorded immediately so a direct map tap gets visual
    /// confirmation while its reverse-geocoded place details are loading.
    @State private var tappedRegionCoordinate: CLLocationCoordinate2D?
    @State private var tappedRegionContext: MapTapRegionContext?
    /// A map tap is not in Saved Places, so retain its parent-resolved weather
    /// presentation locally while the preloading task is in flight.
    @State private var tappedRegionWeather: MapPlaceWeatherPresentation?
    /// A bare-map tap receives a large card immediately. Reverse geocoding
    /// then replaces its loading content in place, rather than withholding
    /// confirmation until MapKit and Core Location both return metadata.
    @State private var isResolvingTappedRegion = false
    @State private var regionLookupID = 0
    @State private var isLocationSelected = false
    @State private var isRequestingLocationWeather = false
    /// The expanded key remains a user preference; closing it restores the
    /// plain icon beneath Map's date switcher on future visits.
    @AppStorage("showsMapSunnyHoursLegend")
    private var showsSunnyHoursLegend = true
    /// iOS 26 uses this shared namespace to interpolate the physical glass
    /// surface from the 44-point Find Sun control into a selection/result card.
    @Namespace private var bottomSurfaceNamespace
    /// The compact control and its expanded card are two states of one physical
    /// surface, so Liquid Glass needs the same identity for a matched morph
    /// between their capsule and rounded-rectangle shapes.
    private enum BottomSurfaceGlassID {
        static let surface = "map-bottom.surface"
        static let offlineBanner = "map-bottom.offline-banner"
    }
    /// Before iOS 26, the same two surfaces use SwiftUI's conventional matched
    /// geometry effect instead of Liquid Glass, which does require one shared
    /// identity.
    private static let bottomSurfaceFallbackGeometryID = "map-bottom.surface"
    private static let offlineBannerFallbackGeometryID = "map-bottom.offline-banner"
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(MissingDataAlertCenter.self) private var missingDataAlerts
    @Environment(NetworkConnectivity.self) private var networkConnectivity

    /// Use one initial span for both the initial location map and the
    /// explicit recenter action. Recentring should change the centre only,
    /// never make the map feel as though it has jumped to a different zoom.
    private static let initialLocationSpan = MKCoordinateSpan(
        latitudeDelta: 3,
        longitudeDelta: 3
    )

    // MARK: Derived annotation data

    /// Every Map marker represents a real selected-date sunny-hours assessment.
    private var layerPresentations: [PlacesMapPlacePresentation] {
        presentations.filter { $0.recommendation != nil }
    }

    private var visiblePresentations: [PlacesMapPlacePresentation] {
        mapMarkers.map(\.presentation)
    }

    private var mapMarkers: [PlacesMapMarkerPresentation] {
        guard !isPresentingSunSearch else { return [] }
        return layerPresentations.compactMap { presentation in
            // While a just-saved transient result is still selected, retain
            // its original annotation identity. The ordinary saved marker
            // takes over as soon as the acknowledgement card is dismissed.
            if preservedSavedPlaceSelectionIDs.contains(presentation.id) {
                return nil
            }
            guard let recommendation = presentation.recommendation else {
                return nil
            }
            return PlacesMapMarkerPresentation(
                presentation: presentation,
                color: sunnyHoursMarkerColor(for: recommendation)
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

    private var selectedPreviewCity: City? {
        guard let selectedPreviewID,
              previewCity?.id == selectedPreviewID else {
            return nil
        }
        return previewCity
    }

    /// A saved city already has its normal map dot and floating card. Avoid a
    /// duplicate transient dot when Find Sun happens to return that same city.
    private var transientSunResults: [MapSunSearchResult] {
        if isPresentingSunSearch {
            return sunSearchResults
        }
        return sunSearchResults.filter {
            savedPlaceIDsByTransientResultID[$0.id] == nil
                || $0.id == selectedSunID
        }
    }

    /// Candidate annotations retain their identity across date changes. Every
    /// searched city keeps a visible host; available forecast data upgrades
    /// its neutral dot into the corresponding sunny-hours color.
    private var sunCandidatePresentations: [MapSunCandidatePresentation] {
        var resultsByID: [City.ID: MapSunSearchResult] = [:]
        for result in transientSunResults {
            resultsByID[result.id] = result
        }
        let candidates = sunCandidateCities.isEmpty
            ? transientSunResults.map(\.city)
            : sunCandidateCities
        return candidates.map {
            MapSunCandidatePresentation(
                city: $0,
                result: resultsByID[$0.id]
            )
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
           let savedID = savedPlaceIDsByTransientResultID[selectedPreviewID] {
            ids.insert(savedID)
        }
        return ids
    }

    private func isSaved(_ result: MapSunSearchResult) -> Bool {
        savedPlaceIDsByTransientResultID[result.id] != nil
    }

    // Keep marker selection visuals in lockstep with the floating-card source.
    // A pending or stale selection ID alone must not show a ring.
    private func isShowingPlaceCard(_ id: City.ID) -> Bool {
        selectedPresentation?.id == id
    }

    private func isShowingSunResultCard(_ id: City.ID) -> Bool {
        selectedSunResult?.id == id
    }

    private func isShowingSearchPreviewCard(_ id: City.ID) -> Bool {
        selectedPreviewCity?.id == id
    }

    private var isShowingCurrentLocationCard: Bool {
        isLocationSelected
            && selectedPresentation == nil
            && selectedSunResult == nil
            && selectedPreviewCity == nil
    }

    /// A direct-map marker exists only for the active, unsaved query. Once it
    /// is saved, the normal Saved Places marker takes over; clearing the card
    /// drops this transient marker entirely.
    private var showsTappedRegionMarker: Bool {
        guard tappedRegionCoordinate != nil else { return false }
        guard let tappedRegionContext else { return true }
        return !isSavedPlace(tappedRegionContext.city)
    }

    private var tappedRegionMarkerColor: Color {
        tappedRegionWeather?.recommendation.map(sunnyHoursMarkerColor(for:))
            ?? theme.colors.secondaryText
    }

    private var visiblePlaceIDs: [City.ID] {
        visiblePresentations
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
    }

    /// Unlike visible marker IDs, this remains present while a saved place's
    /// forecast is loading or unavailable. It is therefore the correct source
    /// of truth for a targeted saved-place Map hand-off.
    private var presentationIDs: [City.ID] {
        presentations
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
                priority: isShowingPlaceCard(marker.id)
                    ? 10_000
                    : 1_000 - index,
                isSelected: isShowingPlaceCard(marker.id)
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
                priority: isShowingSunResultCard(result.id)
                    ? 10_000
                    : 3_000 - index,
                isSelected: isShowingSunResultCard(result.id)
            )
        }
        let previewInputs = previewCity.map { city in
            [
                PlacesMapLabelLayoutInput(
                    id: city.id,
                    name: city.displayName,
                    coordinate: CLLocationCoordinate2D(
                        latitude: city.latitude,
                        longitude: city.longitude
                    ),
                    priority: isShowingSearchPreviewCard(city.id)
                        ? 10_000
                        : 4_000,
                    isSelected: isShowingSearchPreviewCard(city.id)
                )
            ]
        } ?? []
        let locationInput = locationCoordinate.map { coordinate in
            [
                PlacesMapLabelLayoutInput(
                    id: Self.locationLabelID,
                    name: locationLabel,
                    coordinate: coordinate,
                    priority: isShowingCurrentLocationCard ? 10_000 : 2_000,
                    isSelected: isShowingCurrentLocationCard
                )
            ]
        } ?? []
        let tappedRegionInput = showsTappedRegionMarker
            ? tappedRegionContext.map { context in
            [
                PlacesMapLabelLayoutInput(
                    id: context.city.id,
                    name: context.city.displayName,
                    coordinate: CLLocationCoordinate2D(
                        latitude: context.city.latitude,
                        longitude: context.city.longitude
                    ),
                    priority: 10_000,
                    isSelected: true
                )
            ]
        } ?? []
            : []
        return savedInputs + foundInputs + previewInputs + locationInput
            + tappedRegionInput
    }

    private static let locationLabelID = UUID()
    /// Reverse geocoding has not supplied a stable city UUID during the short
    /// loading phase, so its selected temporary dot uses this private MapKit
    /// tag until a factual city identity is available.
    private var locationLabel: String {
        localizedString("Current Location", locale: locale)
    }

    /// The current-location marker may be visible one render before its
    /// WeatherKit lookup establishes the model's stable city. Use the exact
    /// current coordinate as a temporary context in that short interval so
    /// the shared place card can still offer Find Near Me and View Details.
    private var currentLocationCardCity: City? {
        guard let coordinate = locationCoordinate else { return nil }

        if let locationCity,
           coordinatesMatch(locationCity, coordinate) {
            return locationCity
        }

        if let recommendation = locationRecommendation,
           coordinatesMatch(recommendation.cityWeather.city, coordinate) {
            return recommendation.cityWeather.city
        }

        return City(
            id: Self.currentLocationFallbackID,
            name: locationName,
            country: "",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    private static let currentLocationFallbackID = UUID(
        uuidString: "88A7A357-AB00-4CDD-83C7-3B0D8DF9403E"
    )!

    private func coordinatesMatch(
        _ city: City,
        _ coordinate: CLLocationCoordinate2D
    ) -> Bool {
        abs(city.latitude - coordinate.latitude) < 0.0001
            && abs(city.longitude - coordinate.longitude) < 0.0001
    }

    private var hasFloatingCard: Bool {
        // The bottom Find Sun control needs extra clearance only while one
        // mutually exclusive floating card occupies the same lower region.
        selectedPresentation != nil
            || selectedSunResult != nil
            || selectedPreviewCity != nil
            // Without a resolved coordinate there is no city card to show.
            // Keep the persistent compact Map capsule visible instead of
            // replacing it with an empty expanded surface.
            || (isLocationSelected && currentLocationCardCity != nil)
            || tappedRegionContext != nil
            || isResolvingTappedRegion
    }

    private var showsSunResultsSummary: Bool {
        !isFindingSun && sunQuerySummary != nil && !hasFloatingCard
    }

    private var hasEmptyMapContentState: Bool {
        visiblePresentations.isEmpty
            && transientSunResults.isEmpty
            && previewCity == nil
    }

    /// Forecast refreshes can briefly leave the selected-date marker layer
    /// empty. This is a compact Map-surface state, not an absence of UI.
    private var isLoadingMapWeatherData: Bool {
        presentations.contains(where: \.isLoading)
            && layerPresentations.isEmpty
    }

    private var sunResultsTitle: String {
        // Cached results handed off by Your Location do not create a query
        // scope, but they still represent the same near-me result category.
        sunQueryTitle ?? localizedString("Near Me", locale: locale)
    }

    private var largeSurfaceHorizontalPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 12 : 18
    }

    /// iPad has no bottom tab bar beneath the Map canvas, so the compact Map
    /// controls can sit closer to the safe-area edge. Keep the established
    /// spacing on iPhone, where the native tab bar occupies that lower lane.
    private var compactSurfaceBottomPadding: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad
            ? 8
            : MapCardLayout.bottomPadding
    }

    /// Only iPad separates the trailing recenter action from the centred
    /// surface across the full canvas. Preserve the established compact iPhone
    /// cluster by leaving its overlay at its intrinsic width.
    private var compactSurfaceOverlayMaximumWidth: CGFloat? {
        UIDevice.current.userInterfaceIdiom == .pad ? .infinity : nil
    }

    // MARK: Floating-card selection

    /// Only one selection card is produced at a time. The `if` order is also
    /// the precedence rule when a saved city and a transient result overlap.
    @ViewBuilder
    private var activeFloatingCard: some View {
        if let selectedPresentation {
            mapPlaceContextCard(
                city: selectedPresentation.place.city,
                // Only the Map information card may use a richer
                // reverse-geocoded locality-and-area title. Labels, pins, and
                // saved-place rows retain the concise locality.
                displayName: selectedPresentation.place.customName
                    ?? selectedPresentation.place.city.titleDisplayName,
                weather: MapPlaceWeatherPresentation(
                    recommendation: selectedPresentation.recommendation,
                    isLoading: selectedPresentation.isLoading
                ),
                save: nil,
                removeSavedPlace: nil,
                // A saved marker keeps the shared card's filled bookmark as a
                // state indicator, even though it has no duplicate save action.
                isSaved: true
            )
        } else if let selectedSunResult {
            mapPlaceContextCard(
                city: selectedSunResult.city,
                displayName: selectedSunResult.city.titleDisplayName,
                weather: MapPlaceWeatherPresentation(
                    recommendation: selectedSunResult.recommendation,
                    isLoading: false
                ),
                save: {
                    return saveSunResult(selectedSunResult)
                },
                removeSavedPlace: {
                    removeSavedPlace(selectedSunResult.city)
                },
                isSaved: isSaved(selectedSunResult),
            )
        } else if let selectedPreviewCity {
            mapPlaceContextCard(
                city: selectedPreviewCity,
                displayName: selectedPreviewCity.titleDisplayName,
                weather: resolveMapPlaceCardWeather(selectedPreviewCity),
                save: {
                    return saveSearchPreview(selectedPreviewCity)
                },
                removeSavedPlace: {
                    removeSavedPlace(selectedPreviewCity)
                },
                isSaved: savedPlaceIDsByTransientResultID[
                    selectedPreviewCity.id
                ] != nil,
            )
        } else if isLocationSelected,
                  let currentLocationCardCity {
            // Current Location intentionally shares the exact same card shell
            // and Find Sun disclosure as every other selected Map marker. It
            // omits only persistence, then routes View Details back to the
            // existing Your Location report.
            mapPlaceContextCard(
                city: currentLocationCardCity,
                displayName: locationName.isEmpty
                    ? localizedString("Current Location", locale: locale)
                    : locationName,
                weather: MapPlaceWeatherPresentation(
                    recommendation: locationRecommendation,
                    isLoading: isLocationWeatherLoading
                        || isRequestingLocationWeather
                ),
                save: nil,
                removeSavedPlace: nil,
                isSaved: false,
                viewDetailsAction: viewCurrentLocationDetails
            )
        } else if isResolvingTappedRegion {
            // The tap itself is enough to acknowledge immediately. The
            // reverse-geocoded city card replaces this loading state as soon
            // as factual place metadata becomes available.
            MapLocationLoadingCard(clearSelection: clearCards)
        } else if let tappedRegionContext {
            MapRegionContextCard(
                context: tappedRegionContext,
                weather: tappedRegionWeather ?? MapPlaceWeatherPresentation(
                    recommendation: nil,
                    isLoading: true
                ),
                save: {
                    // Do not clear or replace the tapped-region context here:
                    // its stable outer MapCard identity is what lets the
                    // bookmark fill in place after the parent persists it.
                    return saveTappedPlace(tappedRegionContext.city)
                },
                removeSavedPlace: {
                    removeSavedPlace(tappedRegionContext.city)
                },
                isSaved: isSavedPlace(tappedRegionContext.city),
                viewDetails: { city in
                    // Keep the selected card alive while Detail is pushed.
                    // `NavigationStack` preserves this Map view underneath the
                    // destination, so native Back returns to the same place
                    // context rather than an empty map.
                    viewDetails(city)
                },
                findSunNear: { city in
                    // Start the parent-owned loading state first so this
                    // contextual card can morph into the compact Find Sun
                    // progress surface without leaving an extra card behind.
                    findSunNear(city)
                    clearCards()
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

    /// Builds the one shared place-card contract for saved, Find Sun, and
    /// Search-preview markers. The action closures start the parent-owned Map
    /// search before dismissing the card, so only one lower Map surface is
    /// visible throughout the existing glass morph.
    private func mapPlaceContextCard(
        city: City,
        displayName: String,
        weather: MapPlaceWeatherPresentation,
        save: (() -> Bool)?,
        removeSavedPlace: (() -> Bool)?,
        isSaved: Bool,
        viewDetailsAction: (() -> Void)? = nil
    ) -> MapPlaceContextCard {
        let regions = mapFindSunRegions(for: city)
        return MapPlaceContextCard(
            city: city,
            displayName: displayName,
            weather: weather,
            country: regions.country,
            continent: regions.continent,
            save: save,
            removeSavedPlace: removeSavedPlace,
            isSaved: isSaved,
            viewDetails: {
                // Do not treat navigation as a dismissal. The selected marker
                // remains the current Map context until the person closes it,
                // selects something else, or starts a new Find Sun request.
                if let viewDetailsAction {
                    viewDetailsAction()
                } else {
                    viewDetails(city)
                }
            },
            findSunNear: { origin in
                findSunNear(origin)
                clearCards()
            },
            findSun: { scope in
                findSunInRegion(scope)
                clearCards()
            },
            clearSelection: clearCards
        )
    }

    /// Resolves the factual catalog regions that can be searched from a city.
    /// Catalog identity is authoritative; city-country text is only a fallback
    /// for saved and provider-derived places that predate the bundled catalog.
    private func mapFindSunRegions(
        for city: City
    ) -> (
        country: CountryPlacesOption?,
        continent: ContinentPlacesOption?
    ) {
        guard let country = countryCatalogOption(for: city) else {
            return (nil, nil)
        }
        return (country, CountryCityCatalog.continent(for: country))
    }

    private func countryCatalogOption(
        for city: City
    ) -> CountryPlacesOption? {
        let countries = CountryCityCatalog.countries(locale: locale)

        if let catalogIdentifier = city.catalogIdentifier,
           let catalogCountry = countries.first(where: { country in
               country.cities.contains {
                   $0.catalogIdentifier == catalogIdentifier
               }
           }) {
            return catalogCountry
        }

        let normalizedCityCountry = normalizedCountryName(city.country)
        guard !normalizedCityCountry.isEmpty else { return nil }

        return countries.first { country in
            normalizedCountryName(country.englishName)
                == normalizedCityCountry
                || normalizedCountryName(country.localizedName(locale: locale))
                == normalizedCityCountry
        }
    }

    private func normalizedCountryName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                    .widthInsensitive
                ],
                locale: locale
            )
    }

    /// Exactly one lower surface is rendered at a time. A selected marker has
    /// priority over the result summary; otherwise the relevant compact status or
    /// recovery banner replaces the ordinary Find Sun action. The two physical
    /// sizes are separate views so iOS can animate the disappearance and
    /// insertion of their glass effects as one native morph.
    @ViewBuilder
    private var activeBottomSurface: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack(alignment: .bottom) {
                if #available(iOS 26.0, *) {
                    GlassEffectContainer(spacing: MapCardLayout.surfaceSpacing) {
                        bottomSurface
                    }
                    .animation(
                        MapCardMotion.morph(),
                        value: bottomSurfacePresentationID
                    )
                } else {
                    bottomSurface
                        .animation(
                            MapCardMotion.morph(),
                            value: bottomSurfacePresentationID
                        )
                }

                if showsMapOfflineBanner {
                    mapOfflineBanner
                        // MapCard owns its bottom safe-area inset. Offset this
                        // second surface by only the capsule height and gap so
                        // its visible material lands immediately above it.
                        .padding(
                            .bottom,
                            compactMapSurfaceHeight + MapCardLayout.surfaceSpacing
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            // The centred Find Sun surface must not define this overlay's
            // width. Fill the Map so the location action is truly trailing on
            // iPad instead of trailing relative to the compact capsule.
            .frame(
                maxWidth: compactSurfaceOverlayMaximumWidth,
                alignment: .bottom
            )

            // Recenter is a standalone Map action, not part of the centred
            // Find Sun capsule. It remains on the capsule's baseline and uses
            // the same compact height at the trailing edge.
            if !usesLargeBottomSurface {
                MapFloatingLocationButton(
                    isEnabled: locationCoordinate != nil,
                    action: focusCurrentLocation
                )
                .padding(.trailing, 16)
                .padding(.bottom, compactSurfaceBottomPadding)
            }
        }
        .frame(
            maxWidth: compactSurfaceOverlayMaximumWidth,
            alignment: .bottomTrailing
        )
    }

    /// Offline status supplements the Map controls instead of replacing them:
    /// Find Sun stays available and the recenter action remains on its baseline.
    private var showsMapOfflineBanner: Bool {
        networkConnectivity.isOffline
            && !networkConnectivity.isOfflineBannerDismissed
            && !usesLargeBottomSurface
    }

    private var compactMapSurfaceHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 60 : MapCardLayout.compactHeight
    }

    private var mapOfflineBanner: some View {
        MapCard(
            size: .offline,
            colorScheme: colorScheme,
            maximumWidth: cardMaximumWidth,
            bottomPadding: compactSurfaceBottomPadding,
            glassEffectID: Self.BottomSurfaceGlassID.offlineBanner,
            fallbackGeometryID: Self.offlineBannerFallbackGeometryID,
            glassNamespace: bottomSurfaceNamespace
        ) {
            OfflineBannerContent(
                lastUpdated: latestCachedWeatherDate,
                dismiss: networkConnectivity.dismissOfflineBanner
            )
            .padding(.horizontal, MapCardLayout.compactHorizontalPadding)
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
                glassNamespace: bottomSurfaceNamespace
            ) {
                largeBottomSurfaceContent
            }
        } else {
            MapCard(
                size: .small,
                colorScheme: colorScheme,
                maximumWidth: cardMaximumWidth,
                bottomPadding: compactSurfaceBottomPadding,
                glassEffectID: Self.BottomSurfaceGlassID.surface,
                fallbackGeometryID: Self.bottomSurfaceFallbackGeometryID,
                glassNamespace: bottomSurfaceNamespace
            ) {
                compactBottomSurface
            }
        }
    }

    @ViewBuilder
    private var largeBottomSurfaceContent: some View {
        activeFloatingCard
    }

    private var usesLargeBottomSurface: Bool {
        hasFloatingCard
    }

    private var bottomSurfacePresentationID: String {
        if let selectedPresentation {
            return "saved-place-\(selectedPresentation.id.uuidString)"
        }
        if let selectedSunResult {
            return "found-place-\(selectedSunResult.id.uuidString)"
        }
        if let selectedPreviewCity {
            return "search-preview-\(selectedPreviewCity.id.uuidString)"
        }
        if isLocationSelected,
           currentLocationCardCity != nil {
            return "current-location"
        }
        if let tappedRegionContext {
            return "region-\(tappedRegionContext.id)"
        }
        if isResolvingTappedRegion {
            return "region-loading-\(regionLookupID)"
        }
        if showsSunResultsSummary {
            // Result membership changes with the selected date, but the compact
            // scope summary remains the same surface throughout the search.
            return "sun-results-summary"
        }
        if isFindingSun {
            return "finding-sun"
        }
        if isLoadingMapWeatherData {
            return "loading-weather-data"
        }
        if hasEmptyMapContentState {
            if loadError != nil {
                return "places-unavailable"
            }
            if presentations.isEmpty {
                return "no-saved-places"
            }
            return "forecast-unavailable"
        }
        return "find-sun"
    }

    /// Every compact state uses the same component and the same one-line text
    /// treatment. Recovery actions stay available as 44-point icon buttons.
    @ViewBuilder
    private var compactBottomSurface: some View {
        if isFindingSun {
            MapSunSearchCapsule(
                state: .finding(
                    title: sunLoadingTitle
                        ?? localizedString(
                            "Finding sunny places",
                            locale: locale
                        )
                )
            )
        } else if isLoadingMapWeatherData {
            loadingWeatherDataBanner
        } else if showsSunResultsSummary {
            sunResultsSummary
        } else {
            findSunBanner
        }
    }

    /// A finished query retains the same compact surface as its loading state.
    /// The list button presents the complete ranking without covering the Map
    /// until the person explicitly asks for it.
    private var sunResultsSummary: some View {
        MapSunSearchCapsule(
            state: .results(
                title: sunResultsTitle,
                showResults: showSunRanking,
                clearResults: clearSunSearch
            )
        )
    }

    private var findSunBanner: some View {
        MapCapsule {
            FindSunButton(
                currentLocationCoordinate: locationCoordinate,
                locale: locale,
                sessionGeneration: sunSearchGeneration,
                findSunHere: findSunHere,
                findSunNearMe: findSunNearMe,
                findSunInCountry: findSunInCountry,
                findSunInContinent: findSunInContinent
            )
        }
    }

    /// Loading keeps the same compact lower surface in place until forecasts
    /// yield selected-date recommendations or settle unavailable.
    private var loadingWeatherDataBanner: some View {
        MapCapsule(horizontalPadding: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Loading weather data")
        }
    }

    // MARK: SwiftUI composition

    var body: some View {
        ZStack(alignment: .bottom) {
            mapContent

            activeBottomSurface
                .zIndex(3)
        }
        .onChange(of: visiblePlaceIDs, initial: true) { _, _ in
            // Camera initialization happens once, so later list refreshes
            // never fight the person's pan and zoom gestures.

            if !hasInitializedCamera {
                initializeCamera()
                hasInitializedCamera = true
            }
        }
        .onChange(of: presentationIDs, initial: true) { _, newIDs in
            // A saved place can be selected before its forecast makes a
            // marker visible. Validate against the saved presentation itself,
            // not marker visibility, so the target remains selected and can
            // receive its pending camera focus once loading settles.
            if let selectedPlaceID, !newIDs.contains(selectedPlaceID) {
                self.selectedPlaceID = nil
                pendingSavedPlaceFocusID = nil
            }
            focusPendingSavedPlaceIfPossible()
        }
        .onChange(of: selectionResetID) {
            clearCards()
        }
        .onChange(of: mapHandoffToken, initial: true) { _, token in
            guard token > 0 else { return }
            clearForIncomingMapHandoff()
            if let previewCity {
                revealSearchPreview(previewCity)
            } else {
                requestFocusForIncomingSavedPlace()
            }
        }
        .onChange(of: locationFocusRequestID) {
            focusLocation()
        }
        .onChange(of: mapPlaceCardWeatherRevision) {
            // A direct map tap is outside the saved-place array. Refresh its
            // local presentation when WeatherKit completes or the date changes.
            refreshTappedRegionWeather()
        }
        .task(id: tappedRegionContext?.city.id) {
            // Reverse geocoding has supplied an exact city by this point and
            // the region card is visible. Warm that same city ID before any
            // View Details tap; SavedPlacesWeatherStore coalesces duplicate loads.
            guard let city = tappedRegionContext?.city else { return }
            let cityID = city.id
            tappedRegionWeather = resolveMapPlaceCardWeather(city)
            await preloadTappedPlaceDetails(city)
            guard tappedRegionContext?.city.id == cityID else { return }
            tappedRegionWeather = resolveMapPlaceCardWeather(city)
        }
        .onChange(of: selectedPlaceID) { _, newID in
            if newID != pendingSavedPlaceFocusID {
                pendingSavedPlaceFocusID = nil
            }
            if newID != nil {
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
                // Pin selection is resolved by the simultaneous map-level tap
                // below. This keeps the native map's pan and pinch recognizers
                // in charge while avoiding MapKit's delayed annotation
                // selection confirmation.
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
                                name: displayName(
                                    marker.presentation.place
                                ),
                                color: marker.color,
                                isSelected: isShowingPlaceCard(marker.id),
                                labelPlacement:
                                    labelPlacements[marker.id] ?? .below
                            )
                        }
                    }

                    ForEach(sunCandidatePresentations) { candidate in
                        Annotation(
                            "",
                            coordinate: CLLocationCoordinate2D(
                                latitude: candidate.city.latitude,
                                longitude: candidate.city.longitude
                            ),
                            anchor: .center
                        ) {
                            MapSunCandidateAnnotation(
                                city: candidate.city,
                                result: candidate.result,
                                color: candidate.result.map {
                                    sunnyHoursMarkerColor(
                                        for: $0.recommendation
                                    )
                                } ?? theme.colors.secondaryText,
                                isSelected: candidate.result.map {
                                    isShowingSunResultCard($0.id)
                                } ?? false,
                                labelPlacement: candidate.result == nil
                                    ? .hidden
                                    : labelPlacements[candidate.id] ?? .below
                            )
                        }
                    }

                    if let previewCity {
                        Annotation(
                            "",
                            coordinate: CLLocationCoordinate2D(
                                latitude: previewCity.latitude,
                                longitude: previewCity.longitude
                            ),
                            anchor: .center
                        ) {
                            PlacesWeatherMapAnnotation(
                                name: previewCity.displayName,
                                color: previewResult.map {
                                    sunnyHoursMarkerColor(for: $0.recommendation)
                                } ?? theme.colors.secondaryText,
                                isSelected:
                                    isShowingSearchPreviewCard(previewCity.id),
                                labelPlacement:
                                    labelPlacements[previewCity.id] ?? .below
                            )
                        }
                    }

                    if let tappedRegionCoordinate,
                       showsTappedRegionMarker {
                        Annotation(
                            "",
                            coordinate: tappedRegionCoordinate,
                            anchor: .center
                        ) {
                            TappedMapLocationAnnotation(
                                name: tappedRegionContext?.city.displayName,
                                color: tappedRegionMarkerColor,
                                labelPlacement: tappedRegionContext.map {
                                    labelPlacements[$0.city.id] ?? .below
                                } ?? .hidden
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
                                name: locationLabel,
                                color: locationColor,
                                isSelected: isShowingCurrentLocationCard,
                                labelPlacement:
                                    labelPlacements[Self.locationLabelID]
                                    ?? .below
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
                // Resolve pin taps and bare-map queries from one simultaneous
                // gesture. A `SpatialTapGesture` fails for map movement and
                // multi-touch navigation, so a pinch that starts near a pin is
                // never mistaken for a selection.
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
                .overlay(alignment: .topTrailing) {
                    MapSunnyHoursLegend(isExpanded: $showsSunnyHoursLegend)
                        .padding(.trailing, 16)
                }
                .animation(
                    .snappy(duration: 0.2),
                    value: showsSunnyHoursLegend
                )
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
            }
        }
    }

    // MARK: Map tapping and reverse-geocoding

    /// A single map-level tap resolves an explicitly touched marker first; a
    /// bare-map tap then opens a regional Find Sun affordance. Keeping this as
    /// a simultaneous gesture lets MapKit cancel it cleanly for pan and pinch
    /// navigation, including when a finger begins near a marker.
    private func handleMapTap(
        at location: CGPoint,
        using mapProxy: MapProxy
    ) {
        if let target = mapAnnotationTapTarget(
            at: location,
            using: mapProxy
        ) {
            selectMapAnnotation(target)
            return
        }

        // A blank-map tap may close a temporary place card, revealing the
        // active search summary beneath it. It never clears or replaces a Find
        // Sun session; only the summary's explicit close button does that.
        if hasFloatingCard {
            clearCards()
            return
        }

        guard !isPresentingSunSearch else { return }

        guard let coordinate = mapProxy.convert(location, from: .local),
              CLLocationCoordinate2DIsValid(coordinate) else {
            return
        }

        resolveTappedRegion(at: coordinate)
    }

    private enum MapAnnotationTapTarget {
        case currentLocation
        case tappedRegion
        case searchPreview(City.ID)
        case sunResult(City.ID)
        case savedPlace(City.ID)
    }

    /// The marker layers are tested in their visual stacking order. This
    /// preserves the behaviour of MapKit's old native selection while keeping
    /// the hit target deliberately limited to the actual dot, not its label.
    private func mapAnnotationTapTarget(
        at location: CGPoint,
        using mapProxy: MapProxy
    ) -> MapAnnotationTapTarget? {
        var targets: [(coordinate: CLLocationCoordinate2D,
                       target: MapAnnotationTapTarget)] = []

        // Later Map annotations sit above earlier ones. Keep this list in the
        // same top-to-bottom order so an overlap activates the visible marker.
        if let locationCoordinate {
            targets.append((locationCoordinate, .currentLocation))
        }
        if showsTappedRegionMarker, let tappedRegionCoordinate {
            targets.append((tappedRegionCoordinate, .tappedRegion))
        }
        if let previewCity {
            targets.append((
                CLLocationCoordinate2D(
                    latitude: previewCity.latitude,
                    longitude: previewCity.longitude
                ),
                .searchPreview(previewCity.id)
            ))
        }
        targets += sunCandidatePresentations.compactMap { candidate in
            guard candidate.result != nil else { return nil }
            return (
                CLLocationCoordinate2D(
                    latitude: candidate.city.latitude,
                    longitude: candidate.city.longitude
                ),
                .sunResult(candidate.id)
            )
        }
        targets += mapMarkers.map { marker in
            (
                CLLocationCoordinate2D(
                    latitude: marker.presentation.place.city.latitude,
                    longitude: marker.presentation.place.city.longitude
                ),
                .savedPlace(marker.id)
            )
        }

        return targets.first { candidate in
            let coordinate = candidate.coordinate
            guard let point = mapProxy.convert(coordinate, to: .local) else {
                return false
            }
            return hypot(point.x - location.x, point.y - location.y)
                < MapMarkerInteraction.tapRadius
        }?.target
    }

    private func selectMapAnnotation(_ target: MapAnnotationTapTarget) {
        switch target {
        case .currentLocation:
            selectCurrentLocation()
        case .tappedRegion:
            selectTappedRegion()
        case .searchPreview(let id):
            selectSearchPreview(id)
        case .sunResult(let id):
            selectSunResult(id)
        case .savedPlace(let id):
            selectPlace(id)
        }
    }

    /// Reverse geocoding is asynchronous. Its ID discards an older lookup if
    /// the user immediately taps a different region of the map.
    private func resolveTappedRegion(at coordinate: CLLocationCoordinate2D) {
        regionLookupID &+= 1
        let resolutionID = regionLookupID
        tappedRegionCoordinate = coordinate
        tappedRegionContext = nil
        tappedRegionWeather = nil
        isResolvingTappedRegion = true
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
                DeveloperDiagnostics.show(
                    title: "Map Tap Metadata Incomplete",
                    message: "Attempt 1 for \(mapTapCoordinateDescription(coordinate)) returned \(mapTapMetadataDescription(metadata)). Retrying once."
                )
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
                DeveloperDiagnostics.show(
                    title: "Map Tap Missing Data",
                    message: "Attempt 2 for \(mapTapCoordinateDescription(coordinate)) could not create a queryable place. Missing: \(missingFields.joined(separator: ", ")). Metadata: \(mapTapMetadataDescription(metadata)). Catalog match: \(mappedCountry?.id ?? "none")."
                )
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
                tappedRegionCoordinate = nil
                isResolvingTappedRegion = false
                return
            }

            let countryName = cleanMapTapValue(metadata.countryName)
                ?? locale.localizedString(forRegionCode: countryCode)
                ?? country.englishName
            let shortLocality = CurrentLocationMetadata.localityName(
                from: locality
            ) ?? locality
            let city = City(
                name: shortLocality,
                titleName: locality,
                country: countryName,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                timeZoneIdentifier: timeZone.identifier
            )

            tappedRegionContext = MapTapRegionContext(
                city: city,
                locality: locality,
                country: country,
                continent: CountryCityCatalog.continent(for: country)
            )
            isResolvingTappedRegion = false
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
                let items = try await request.mapItems
                if let item = items.first {
                    metadata = metadata.fillingMissingFields(
                        from: mapTapMetadata(from: item)
                    )
                } else {
                    DeveloperDiagnostics.show(
                        title: "Map Tap Reverse Geocoding Empty",
                        message: "MapKit returned no map items for \(mapTapCoordinateDescription(location.coordinate))."
                    )
                }
            } catch is CancellationError {
                return metadata
            } catch {
                DeveloperDiagnostics.show(
                    title: "Map Tap Reverse Geocoding Failed",
                    message: "MapKit failed for \(mapTapCoordinateDescription(location.coordinate)): \(error.localizedDescription)"
                )
            }
        } else {
            DeveloperDiagnostics.show(
                title: "Map Tap Reverse Geocoding Fallback",
                message: "MapKit reverse geocoding is unavailable for \(mapTapCoordinateDescription(location.coordinate)); using CLGeocoder."
            )
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
                } else {
                    DeveloperDiagnostics.show(
                        title: "Map Tap Reverse Geocoding Empty",
                        message: "CLGeocoder returned no placemarks for \(mapTapCoordinateDescription(location.coordinate))."
                    )
                }
            } catch is CancellationError {
                return metadata
            } catch {
                DeveloperDiagnostics.show(
                    title: "Map Tap Reverse Geocoding Failed",
                    message: "CLGeocoder failed for \(mapTapCoordinateDescription(location.coordinate)): \(error.localizedDescription)"
                )
            }
        }

        return metadata
    }

    /// Keeps every Debug-only missing-data report comparable across the two
    /// reverse-geocoder providers without exposing diagnostics to people using
    /// a release build.
    private func mapTapMetadataDescription(
        _ metadata: MapTapPlaceMetadata
    ) -> String {
        "locality=\(metadata.locality ?? "nil"), country=\(metadata.countryName ?? "nil"), ISO=\(metadata.isoCountryCode ?? "nil"), timeZone=\(metadata.timeZone?.identifier ?? "nil")"
    }

    private func mapTapCoordinateDescription(
        _ coordinate: CLLocationCoordinate2D
    ) -> String {
        String(
            format: "%.6f, %.6f",
            coordinate.latitude,
            coordinate.longitude
        )
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
        tappedRegionCoordinate = nil
        tappedRegionContext = nil
        tappedRegionWeather = nil
        isResolvingTappedRegion = false
    }

    /// Keeps the reverse-geocoded city reactive even though it does not live in
    /// the parent Map view's saved-place presentation array.
    private func refreshTappedRegionWeather() {
        guard let city = tappedRegionContext?.city else {
            tappedRegionWeather = nil
            return
        }
        tappedRegionWeather = resolveMapPlaceCardWeather(city)
    }

    private func clearCards() {
        // The bottom surface animates itself. Never wrap marker selection in a
        // broad animation transaction: MapKit can otherwise interpolate a
        // recycled annotation host from the previous marker's coordinate.
        selectedPlaceID = nil
        selectedSunID = nil
        selectedPreviewID = nil
        isLocationSelected = false
        pendingSavedPlaceFocusID = nil
        clearTappedRegionContext()
    }

    /// Clears the card state the canvas owns locally when another tab hands a
    /// fresh request to Map. Keep `selectedPlaceID` intact: it is a parent
    /// binding and may already hold the saved marker that the new request
    /// specifically asked Map to show.
    private func clearForIncomingMapHandoff() {
        selectedSunID = nil
        isLocationSelected = false
        isRequestingLocationWeather = false
        pendingSavedPlaceFocusID = nil
        clearTappedRegionContext()
    }

    private func selectPlace(_ id: City.ID) {
        selectedPlaceID = id
        selectedSunID = nil
        selectedPreviewID = nil
        isLocationSelected = false
        pendingSavedPlaceFocusID = nil
        clearTappedRegionContext()
    }

    private func selectSunResult(_ id: City.ID) {
        selectedPlaceID = nil
        selectedSunID = id
        selectedPreviewID = nil
        isLocationSelected = false
        pendingSavedPlaceFocusID = nil
        clearTappedRegionContext()
    }

    private func selectSearchPreview(_ id: City.ID) {
        selectedPlaceID = nil
        selectedSunID = nil
        selectedPreviewID = id
        isLocationSelected = false
        pendingSavedPlaceFocusID = nil
        clearTappedRegionContext()
    }

    /// A Search hand-off must be visible before WeatherKit has populated the
    /// selected-date recommendation. Selecting this city drives the existing
    /// marker ring animation and opens the shared place card immediately.
    private func revealSearchPreview(_ city: City) {
        selectSearchPreview(city.id)
        focus(on: city)
    }

    /// Tapping the transient marker keeps its contextual card active instead
    /// of letting the bare-map gesture dismiss this still-active query.
    private func selectTappedRegion() {
        guard tappedRegionContext != nil else { return }
        selectedPlaceID = nil
        selectedSunID = nil
        selectedPreviewID = nil
        isLocationSelected = false
    }

    private func selectCurrentLocation() {
        let shouldLoadWeather = needsLocationWeather
            && !isLocationWeatherLoading
            && !isRequestingLocationWeather
        selectedPlaceID = nil
        selectedSunID = nil
        selectedPreviewID = nil
        clearTappedRegionContext()
        isLocationSelected = true
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
        var pendingLabels = projectedLabels
        var newPlacements: [City.ID: PlacesMapLabelPlacement] = [:]

        // Choose the least-flexible label next rather than letting the first
        // high-ranked dot reserve its preferred side unconditionally. This
        // small constraint pass produces more visible labels in dense rows:
        // one dot can use its spare above position while a neighbour keeps the
        // only below position it can actually occupy.
        while !pendingLabels.isEmpty {
            let candidatesByIndex = Dictionary(
                uniqueKeysWithValues: pendingLabels.indices.map { index in
                    (
                        index,
                        labelPlacementCandidates(
                            for: pendingLabels[index],
                            occupiedLabelRects: occupiedLabelRects,
                            markerObstacles: markerObstacles,
                            viewportBounds: viewportBounds
                        )
                    )
                }
            )

            guard let nextIndex = pendingLabels.indices.min(by: { lhs, rhs in
                let left = pendingLabels[lhs]
                let right = pendingLabels[rhs]
                // An actively selected place still wins over every ordinary
                // marker, even if it has two legal sides.
                if left.input.isSelected != right.input.isSelected {
                    return left.input.isSelected
                }

                let leftCount = candidatesByIndex[lhs]?.count ?? 0
                let rightCount = candidatesByIndex[rhs]?.count ?? 0
                if leftCount != rightCount {
                    return leftCount < rightCount
                }
                if left.input.priority != right.input.priority {
                    return left.input.priority > right.input.priority
                }
                return left.input.id.uuidString < right.input.id.uuidString
            }) else {
                break
            }

            let projectedLabel = pendingLabels.remove(at: nextIndex)
            let candidates = candidatesByIndex[nextIndex] ?? []

            guard !candidates.isEmpty else {
                newPlacements[projectedLabel.input.id] = .hidden
                if projectedLabel.input.isSelected,
                   viewportBounds.contains(projectedLabel.point) {
                    // A selected marker must never lose its label while lower
                    // priority labels remain visible.
                    for placedID in Array(newPlacements.keys) {
                        newPlacements[placedID] = .hidden
                    }
                    for remainingLabel in pendingLabels {
                        newPlacements[remainingLabel.input.id] = .hidden
                    }
                    break
                }
                continue
            }

            let remainingCandidates = candidatesByIndex
                .filter { $0.key != nextIndex }
                .flatMap(\.value)
            let chosenCandidate = candidates.min { lhs, rhs in
                let leftConflicts = remainingCandidates.filter {
                    $0.collisionRect.intersects(lhs.collisionRect)
                }.count
                let rightConflicts = remainingCandidates.filter {
                    $0.collisionRect.intersects(rhs.collisionRect)
                }.count
                if leftConflicts != rightConflicts {
                    return leftConflicts < rightConflicts
                }
                // Preserve the former visual default when both positions are
                // equally good: names appear below their dots first.
                return lhs.placement == .below
                    && rhs.placement != .below
            }!

            newPlacements[projectedLabel.input.id] = chosenCandidate.placement
            occupiedLabelRects.append(chosenCandidate.collisionRect)
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

    private func labelPlacementCandidates(
        for projectedLabel: PlacesMapProjectedLabel,
        occupiedLabelRects: [CGRect],
        markerObstacles: [(id: City.ID, rect: CGRect)],
        viewportBounds: CGRect
    ) -> [PlacesMapLabelCandidate] {
        [PlacesMapLabelPlacement.below, .above].compactMap { placement in
            let rect = projectedLabel.rect(for: placement)
            guard canPlaceLabel(
                for: rect,
                labelID: projectedLabel.input.id,
                occupiedLabelRects: occupiedLabelRects,
                markerObstacles: markerObstacles,
                viewportBounds: viewportBounds
            ) else {
                return nil
            }
            return PlacesMapLabelCandidate(
                placement: placement,
                collisionRect: rect.insetBy(dx: -2, dy: -2)
            )
        }
    }

    // MARK: Camera fitting and marker semantics

    /// Chooses a useful initial frame without fighting the user's later manual
    /// map gestures. A Search preview takes precedence over every default.
    private func initializeCamera() {
        if let previewCity {
            position = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: previewCity.latitude,
                        longitude: previewCity.longitude
                    ),
                    span: Self.initialLocationSpan
                )
            )
        } else if let selectedPlaceID,
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

    /// A router-driven saved-place hand-off must change the camera even when
    /// this Map view already has an initialized position from an earlier
    /// session. If the library is still loading, `presentationIDs` retries it
    /// once the target appears.
    private func requestFocusForIncomingSavedPlace() {
        guard let selectedPlaceID else { return }
        pendingSavedPlaceFocusID = selectedPlaceID
        focusPendingSavedPlaceIfPossible()
    }

    private func focusPendingSavedPlaceIfPossible() {
        guard let pendingSavedPlaceFocusID,
              let presentation = presentations.first(where: {
                  $0.id == pendingSavedPlaceFocusID
              }) else {
            return
        }
        self.pendingSavedPlaceFocusID = nil
        focus(onSavedPlace: presentation.place.city)
    }

    /// Saved-place targets use Map's existing tighter initial-target span,
    /// while location and Search previews retain their broader orientation span.
    private func focus(onSavedPlace city: City) {
        withAnimation(.smooth(duration: 0.35)) {
            position = .region(
                PlacesMapRegionFitting.region(
                    centeredOn: city,
                    span: 0.35
                )
            )
        }
    }

    /// Centers on the real location marker at the same zoom used
    /// when Map first opens, instead of fitting saved cities or zooming in.
    private func focusLocation() {
        guard let locationCoordinate else { return }
        focus(on: locationCoordinate)
    }

    /// Search previews intentionally use the same camera treatment as the
    /// device location: identical region span and animation, with only the
    /// centre changing to the selected city.
    private func focus(on city: City) {
        focus(
            on: CLLocationCoordinate2D(
                latitude: city.latitude,
                longitude: city.longitude
            )
        )
    }

    private func focus(on coordinate: CLLocationCoordinate2D) {
        withAnimation(.smooth(duration: 0.35)) {
            position = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: Self.initialLocationSpan
                )
            )
        }
    }

    /// Adapts the original zoom-to-fit implementation to Find Sun. Local
    /// city-origin scopes include their search origin; broader scopes fit their
    /// returned dots. Asymmetric padding reserves the legend, utility capsule,
    /// compact results summary, and floating navigation areas rather than
    /// hiding edge markers.
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
        if (request.kind == .nearMe || request.kind == .nearPlace),
           let origin = request.origin,
           !coordinates.contains(where: {
               abs($0.latitude - origin.latitude) < 0.000_001
                   && abs($0.longitude - origin.longitude) < 0.000_001
           }) {
            coordinates.append(origin)
        }
        guard !coordinates.isEmpty else { return }

        let resultSummaryHeight: CGFloat = dynamicTypeSize.isAccessibilitySize
            ? 60
            : MapCardLayout.compactHeight
        let resultSummaryClearance: CGFloat = request.cities.isEmpty
            ? 72
            : resultSummaryHeight + 52
        let padding = EdgeInsets(
            top: 28,
            leading: 28,
            bottom: resultSummaryClearance,
            trailing: 76
        )
        let region = PlacesMapRegionFitting.region(
            for: coordinates,
            viewportSize: viewportSize,
            edgePadding: padding
        )

        withAnimation(.smooth(duration: 0.42)) {
            position = .region(region)
        }
    }

    private var locationColor: Color {
        locationRecommendation.map(sunnyHoursMarkerColor(for:))
            ?? theme.colors.secondaryText
    }

    private var cardMaximumWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 390 : 580
    }

    // MARK: Marker labels, colors, and animation support

    /// Map markers communicate selected-day sunny hours through the same
    /// quiet-to-vivid yellow ramp as Saved Places. The map-specific color is
    /// pre-blended with white so low-sun dots stay fully opaque over terrain.
    private func sunnyHoursMarkerColor(
        for recommendation: PlaceRecommendation
    ) -> Color {
        theme.colors.sunnyHoursMapDotColor(
            for: recommendation.sunnyHourCount
        )
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

/// A stable Map annotation host for one Find Sun candidate. Its optional result
/// changes with the selected date, while its city identity and coordinate do not.
private struct MapSunCandidatePresentation: Identifiable {
    let city: City
    let result: MapSunSearchResult?

    var id: City.ID { city.id }
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

/// One legal above/below result in the collision-placement pass.
private struct PlacesMapLabelCandidate {
    let placement: PlacesMapLabelPlacement
    let collisionRect: CGRect
}

/// The two candidate positions plus an explicit collision-hidden state.
private enum PlacesMapLabelPlacement: Equatable {
    case above
    case below
    case hidden

    var verticalOffset: CGFloat {
        switch self {
        case .above:
            -18
        case .below:
            18
        case .hidden:
            0
        }
    }

    var isVisible: Bool { self != .hidden }
}

/// Custom marker selection uses this small, dot-only hit radius. The
/// map-level tap recognizer fails whenever MapKit starts navigation, so this
/// never claims the first finger of a pinch or pan.
private enum MapMarkerInteraction {
    static let tapDiameter: CGFloat = 28
    static let tapRadius = tapDiameter / 2
}

/// A distinct marker for the device coordinate, independent of the
/// saved-place weather layer.
private struct CurrentLocationMapAnnotation: View {
    let name: String
    let color: Color
    let isSelected: Bool
    let labelPlacement: PlacesMapLabelPlacement

    var body: some View {
        ZStack {
            PlacesMapSelectionRing(
                color: color,
                isVisible: isSelected,
                diameter: 30,
                minimumScale: 0.82,
                expandedScale: 1.28
            )

            Image(systemName: "location.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.32), radius: 3, y: 1)
        }
        .frame(
            width: MapMarkerInteraction.tapDiameter,
            height: MapMarkerInteraction.tapDiameter
        )
        .contentShape(Circle())
        .overlay {
            PlacesMapMarkerLabel(name: name, placement: labelPlacement)
        }
    }
}

/// Keeps every searched MapKit candidate visible while forecast data arrives
/// or its sunny-hour total changes with the selected date.
private struct MapSunCandidateAnnotation: View {
    let city: City
    let result: MapSunSearchResult?
    let color: Color
    let isSelected: Bool
    let labelPlacement: PlacesMapLabelPlacement

    var body: some View {
        PlacesWeatherMapAnnotation(
            name: city.displayName,
            color: color,
            isSelected: isSelected,
            labelPlacement: labelPlacement
        )
        .frame(
            width: MapMarkerInteraction.tapDiameter,
            height: MapMarkerInteraction.tapDiameter
        )
        .allowsHitTesting(result != nil)
        .animation(.easeInOut(duration: 0.2), value: result != nil)
    }
}

/// A compact visual host for the weather marker. The parent Map resolves the
/// deliberately small dot-only selection target from its tap location.
private struct PlacesWeatherMapAnnotation: View {
    let name: String
    let color: Color
    let isSelected: Bool
    let labelPlacement: PlacesMapLabelPlacement

    var body: some View {
        PlacesWeatherMapDot(
            color: color,
            isSelected: isSelected
        )
        .frame(
            width: MapMarkerInteraction.tapDiameter,
            height: MapMarkerInteraction.tapDiameter
        )
        .contentShape(Circle())
        .overlay {
            PlacesMapMarkerLabel(name: name, placement: labelPlacement)
        }
    }
}

/// The short-lived marker for a direct map query. It deliberately reuses the
/// Saved Places dot treatment, but it is retained only while its contextual
/// card is open and has not been saved.
private struct TappedMapLocationAnnotation: View {
    let name: String?
    let color: Color
    let labelPlacement: PlacesMapLabelPlacement

    var body: some View {
        PlacesWeatherMapDot(
            color: color,
            isSelected: true
        )
        .frame(
            width: MapMarkerInteraction.tapDiameter,
            height: MapMarkerInteraction.tapDiameter
        )
        .contentShape(Circle())
        .overlay {
            if let name {
                PlacesMapMarkerLabel(
                    name: name,
                    placement: labelPlacement
                )
            }
        }
        // The direct-tap card remains the selected surface while reverse
        // geocoding is unresolved. Once named, it matches a Saved Place marker.
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

    }
}

/// Draws the ordinary color dot and increased-contrast variant.
private struct PlacesWeatherMapDot: View {
    let color: Color
    let isSelected: Bool

    @Environment(\.appTheme) private var theme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var markerScale: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 1.25 : 1
    }

    var body: some View {
        ZStack {
            // Keep the halo and selection ring permanently attached to this
            // marker. Only their rendered properties change, so MapKit never
            // has an inserted ring it can recycle from another annotation.
            Circle()
                .fill(color.opacity(0.22))
                .frame(width: 18, height: 18)
                .blur(radius: 5)

            PlacesMapSelectionRing(
                color: color,
                isVisible: isSelected,
                diameter: 22,
                minimumScale: 0.78,
                expandedScale: 1.28
            )

            if colorSchemeContrast == .increased {
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
                                lineWidth: isSelected ? 2 : 1.5
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
}

/// A selection ring that permanently belongs to one annotation. Selection
/// changes only local scale and opacity, so both its entry and its pulse expand
/// only from that marker's centre.
private struct PlacesMapSelectionRing: View {
    let color: Color
    let isVisible: Bool
    var diameter: CGFloat = 22
    var minimumScale: CGFloat = 0.8
    var expandedScale: CGFloat = 1.22

    @State private var pulseScale: CGFloat = 0.01
    @State private var pulseOpacity = 0.8

    var body: some View {
        Circle()
            .stroke(color.opacity(pulseOpacity), lineWidth: 1.5)
            .frame(width: diameter, height: diameter)
            .scaleEffect(pulseScale, anchor: .center)
            .opacity(isVisible ? 1 : 0)
        .frame(width: 44, height: 44)
        .task(id: isVisible) {
            guard isVisible else {
                // Cancel the breathing animation before the card closes.
                // The ring stays hidden rather than settling through a second
                // visual state after its floating card has gone away.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    pulseScale = 0.01
                    pulseOpacity = 0.8
                }
                return
            }

            pulseScale = 0.01
            pulseOpacity = 0.8
            await Task.yield()
            guard !Task.isCancelled, isVisible else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                pulseScale = minimumScale
            }
            await Task.yield()
            guard !Task.isCancelled, isVisible else { return }
            withAnimation(
                .easeInOut(duration: 1.05).repeatForever(autoreverses: true)
            ) {
                pulseScale = expandedScale
                // The ring gently recedes as it reaches its widest point.
                pulseOpacity = 0.22
            }
        }
            .allowsHitTesting(false)

    }
}

/// A focused Xcode canvas preview for tuning the centred entry and breathing
/// selection rings without loading MapKit or live forecast data.
private struct MapSelectionPulsePreview: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 56) {
            ZStack {
                PlacesMapSelectionRing(
                    color: theme.colors.dotSun,
                    isVisible: true,
                    diameter: 22,
                    minimumScale: 0.78,
                    expandedScale: 1.28
                )

                Circle()
                    .fill(theme.colors.dotSun)
                    .frame(width: 9, height: 9)
            }

            ZStack {
                PlacesMapSelectionRing(
                    color: theme.colors.dotRain,
                    isVisible: true,
                    diameter: 30,
                    minimumScale: 0.82,
                    expandedScale: 1.28
                )

                Image(systemName: "location.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.colors.dotRain)
            }
        }
        .padding(48)
        .background(theme.colors.background)
    }
}

#Preview("Map Selection Pulse", traits: .sizeThatFitsLayout) {
    MapSelectionPulsePreview()
        .environment(\.appTheme, .shared)
}

/// A canvas-only legend for reviewing the exact sunny-hours colour ramp used
/// by ordinary Map dots. It uses `PlacesWeatherMapDot` rather than a separate
/// swatch so marker size, halo, and colour stay truthful to the live map.
private struct MapSunnyHoursDotScalePreview: View {
    private let hourSteps = [0, 2, 4, 6, 8, 10]

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Map Dot · Sunny Hours")
                .font(.headline)
                .foregroundStyle(theme.colors.primaryText)

            HStack(spacing: 12) {
                ForEach(hourSteps, id: \.self) { hours in
                    VStack(spacing: 4) {
                        PlacesWeatherMapDot(
                            color: theme.colors.sunnyHoursMapDotColor(
                                for: Double(hours)
                            ),
                            isSelected: false
                        )
                        Text(hours == 10 ? "10 h+" : "\(hours) h")
                            .font(.caption2)
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(24)
        .background(theme.colors.background)
    }
}

#Preview("Map Dot Color Scale", traits: .sizeThatFitsLayout) {
    MapSunnyHoursDotScalePreview()
        .environment(\.appTheme, .shared)
}

// MARK: - Camera Geometry

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
