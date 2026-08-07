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

private enum MapSheetDestination: Identifiable {
    case findSun(initialScope: SunSearchScope)

    var id: String {
        switch self {
        case .findSun(let scope): "find-sun-\(scope.rawValue)"
        }
    }
}

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

private enum MapSunQueryScope {
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
            localizedString("sunny places in \(country.localizedName(locale: locale))", locale: locale)
        case .continent(let continent):
            localizedString("sunny places in \(continent.localizedName(locale: locale))", locale: locale)
        }
    }
}

private struct MapSunSearchResult: Identifiable {
    let city: City
    let forecast: DailyForecast

    var id: City.ID { city.id }
}

/// Country and continent resolved from a user-selected map coordinate.
private struct MapTapRegionContext: Identifiable {
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

struct MapView: View {
    let model: WeatherAtlasModel

    @Bindable var router: AppRouter
    @Binding var selectedDate: Date

    @State private var sortMode: WeatherMetricMode = .sunny
    @State private var filtersToSunnyPlaces = false
    /// Drives the explicit current-location focus without re-fitting saved dots.
    @State private var currentLocationFocusRequestID = 0
    @State private var presentedError: MapUIError?
    @State private var presentedMapSheet: MapSheetDestination?
    @State private var currentViewport: MapViewport?
    @State private var activeSunQuery: MapSunQueryScope?
    @State private var sunSearchResults: [MapSunSearchResult] = []
    @State private var selectedSunResultID: City.ID?
    @State private var selectedSearchPreviewID: City.ID?
    @State private var isSearchingForSun = false
    /// Rejects stale asynchronous Find Sun results after a date or scope change.
    @State private var sunSearchGeneration = 0
    @AppStorage("showLegend") private var showsLegend = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    private var placesStore: PlacesStore {
        model.placesStore
    }

    private var weatherStore: PlaceWeatherStore {
        model.weatherStore
    }

    private var savedPlaces: [SavedPlace] { placesStore.allPlaces }

    private var savedPresentations: [PlacesMapPlacePresentation] {
        savedPlaces.map { place in
            let weather = weatherStore.weather(for: place.id)
            return PlacesMapPlacePresentation(
                presentation: SavedPlacePresentation(
                    place: place,
                    recommendation: weather.flatMap {
                        RecommendationEngine.recommendation(
                            for: $0,
                            on: selectedDate,
                            selectionCalendar: model.forecastCalendar
                        )
                    },
                    isLoading: weatherStore.isLoading(place.id),
                    failureMessage:
                        weatherStore.failuresByPlaceID[place.id]?.message
                )
            )
        }
    }

    private var presentations: [PlacesMapPlacePresentation] {
        savedPresentations
    }

    private var sortedPresentations: [PlacesMapPlacePresentation] {
        let orderedRecommendations = RecommendationEngine.sorted(
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

    private var weatherLoadID: [City.ID] {
        mapCities
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
    }

    private var mapCities: [City] {
        var cities = savedPlaces.map(\.city)
        if let preview = router.mapPreviewCity,
           !cities.contains(where: { $0.id == preview.id }) {
            cities.append(preview)
        }
        return cities
    }

    private var searchPreviewResult: MapSunSearchResult? {
        guard let city = router.mapPreviewCity,
              let weather = weatherStore.weather(for: city.id),
              let forecast = weather.forecastIfAvailable(
                on: selectedDate,
                selectionCalendar: model.forecastCalendar
              ) else {
            return nil
        }
        return MapSunSearchResult(city: city, forecast: forecast)
    }

    private var navigationTitle: String {
        localizedString("Map", locale: locale)
    }

    var body: some View {
        mapBody
            .toolbarVisibility(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 4) {
                    Text(navigationTitle)
                        .font(.largeTitle.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    .layoutPriority(1)

                    Spacer(minLength: 4)

                    if currentLocationCoordinate != nil {
                        Button(action: {
                            currentLocationFocusRequestID &+= 1
                        }) {
                            Label(
                                "Center on Current Location",
                                systemImage: "location.fill"
                            )
                            .labelStyle(.iconOnly)
                        }
                        .accessibilityHint(
                            "Centers the map on your current location and highlights it."
                        )
                        .frame(minWidth: 36, minHeight: 44)
                    }

                    moreMenu
                        .frame(minWidth: 36, minHeight: 44)

                    TopForecastDateSwitcher(
                        selection: $selectedDate,
                        availableDates: ForecastDateHorizon.dates(in: model.forecastCalendar)
                    )
                }
                .font(.title3)
                .buttonStyle(.plain)
                .foregroundStyle(theme.colors.primaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .task(id: weatherLoadID) {
                await weatherStore.load(
                    cities: mapCities,
                    locale: locale
                )
            }
            .onChange(of: selectedDate) {
                // Find Sun is date-specific. Re-run its active query so dots
                // and the selected-date capsule can never describe different days.
                if let activeSunQuery {
                    runSunSearch(activeSunQuery)
                }
            }
            .onChange(of: router.mapPreviewCity?.id, initial: true) { _, previewID in
                selectedSearchPreviewID = previewID
            }
            .sensoryFeedback(
                .selection,
                trigger: filtersToSunnyPlaces
            )
            .sensoryFeedback(.selection, trigger: showsLegend)
            .alert(
                "Unable to Update Places",
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
                        canSearchNearMe: currentLocationCoordinate != nil,
                        locale: locale,
                        runSearch: runSunSearch
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
    }

    @ViewBuilder
    private var mapBody: some View {
        if let loadErrorDescription = placesStore.loadErrorDescription {
            ContentUnavailableView {
                Label("Places Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadErrorDescription)
            } actions: {
            Button("Try Again", action: placesStore.retryLoading)
                .buttonStyle(.borderedProminent)
            }
            .weatherAtlasScreenBackground()
        } else {
            PlacesMapCanvas(
                presentations: sortedPresentations,
                selectedPlaceID: $router.selectedMapPlaceID,
                showsLegend: $showsLegend,
                filtersToSunnyPlaces: $filtersToSunnyPlaces,
                sortMode: sortMode,
                currentLocationCoordinate: currentLocationCoordinate,
                currentLocationName: model.locationProvider.metadata?.displayName
                    ?? model.currentLocationWeather?.city.displayName
                    ?? localizedString("Current Location", locale: locale),
                currentLocationFocusRequestID: currentLocationFocusRequestID,
                sunSearchResults: sunSearchResults,
                selectedSunResultID: $selectedSunResultID,
                searchPreviewResult: searchPreviewResult,
                selectedSearchPreviewID: $selectedSearchPreviewID,
                activeSunQuerySummary: activeSunQuery?.summary(locale: locale),
                isSearchingForSun: isSearchingForSun,
                viewport: $currentViewport,
                displayName: displayName(for:),
                findSun: {
                    presentedMapSheet = .findSun(initialScope: .area)
                },
                findSunInRegion: runSunSearch,
                clearSunSearch: clearSunSearch,
                saveSunResult: saveSunResult,
                saveSearchPreview: saveSearchPreview,
                searchPlaces: {
                    router.selectedTab = .search
                }
            )
        }
    }

    private var moreMenu: some View {
        Menu {
            Picker("Map Data", selection: $sortMode) {
                ForEach(WeatherMetricMode.allCases) { mode in
                    Label(
                        mode.title(locale: locale),
                        systemImage: mode.icon
                    )
                    .tag(mode)
                }
            }

            Button {
                Task {
                    await weatherStore.load(
                        cities: mapCities,
                        forceRefresh: true,
                        locale: locale
                    )
                }
            } label: {
                Label("Refresh Forecasts", systemImage: "arrow.clockwise")
            }

            Divider()

            Toggle(isOn: $filtersToSunnyPlaces) {
                Label("Sunny Places Only", systemImage: "sun.max")
            }

            Toggle(isOn: $showsLegend) {
                Label("Show Legend", systemImage: "list.bullet.rectangle")
            }
        } label: {
            Label("More", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
        }
    }

    private var currentLocationCoordinate: CLLocationCoordinate2D? {
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

    private func present(_ error: Error) {
        presentedError = MapUIError(
            message: localizedPlacesErrorDescription(
                error,
                locale: locale
            )
        )
    }

    private func runSunSearch(_ scope: MapSunQueryScope) {
        let requestedDate = Calendar.current.startOfDay(for: selectedDate)
        sunSearchGeneration &+= 1
        let generation = sunSearchGeneration

        Task {
            isSearchingForSun = true
            selectedSunResultID = nil
            activeSunQuery = scope
            sunSearchResults = []

            defer {
                if generation == sunSearchGeneration {
                    isSearchingForSun = false
                }
            }

            do {
                let candidates = try await sunSearchCandidates(for: scope)
                guard !Task.isCancelled,
                      generation == sunSearchGeneration else { return }

                await weatherStore.load(cities: candidates, locale: locale)
                guard !Task.isCancelled,
                      generation == sunSearchGeneration else { return }

                sunSearchResults = candidates.compactMap { city in
                    guard let weather = weatherStore.weather(for: city.id),
                          let forecast = weather.forecastIfAvailable(
                            on: requestedDate,
                            selectionCalendar: model.forecastCalendar
                          ),
                          forecast.condition?.isSunny == true else {
                        return nil
                    }
                    return MapSunSearchResult(city: city, forecast: forecast)
                }
                .sorted { lhs, rhs in
                    let lhsCloudCover = lhs.forecast.cloudCover ?? 1
                    let rhsCloudCover = rhs.forecast.cloudCover ?? 1
                    if lhsCloudCover != rhsCloudCover {
                        return lhsCloudCover < rhsCloudCover
                    }
                    return lhs.forecast.dailyHigh > rhs.forecast.dailyHigh
                }
            } catch is CancellationError {
                return
            } catch {
                guard generation == sunSearchGeneration else { return }
                activeSunQuery = nil
                present(error)
            }
        }
    }

    private func sunSearchCandidates(
        for scope: MapSunQueryScope
    ) async throws -> [City] {
        let cities: [City]
        switch scope {
        case .area:
            guard let viewport = currentViewport else { return [] }
            let records = try await model.worldCitiesCatalog.cities(
                visibleIn: MKCoordinateRegion(
                    center: viewport.center,
                    span: MKCoordinateSpan(
                        latitudeDelta: viewport.latitudeDelta,
                        longitudeDelta: viewport.longitudeDelta
                    )
                ),
                limit: 25
            )
            cities = records.map(resolvedMapSearchCity)
        case .nearMe:
            guard let coordinate = currentLocationCoordinate else { return [] }
            let records = try await model.worldCitiesCatalog.cities(
                centeredAt: coordinate,
                withinKilometers: 100,
                limit: 25
            )
            cities = records.map { resolvedMapSearchCity(from: $0.city) }
        case .country(let country):
            cities = CountryCityCatalog.topCities(for: country, limit: 25)
                .map(resolvedMapSearchCity)
        case .continent(let continent):
            cities = CountryCityCatalog.topCities(for: continent, limit: 25)
                .map(resolvedMapSearchCity)
        }

        return Array(Dictionary(uniqueKeysWithValues: cities.map {
            ($0.id, $0)
        }).values)
    }

    private func resolvedMapSearchCity(from record: WorldCityRecord) -> City {
        let city = City(
            name: record.name,
            country: record.countryName,
            latitude: record.latitude,
            longitude: record.longitude,
            timeZoneIdentifier: CountryCityCatalog.nearestTimeZoneIdentifier(
                to: record.coordinate
            ),
            catalogIdentifier: record.id
        )
        return resolvedMapSearchCity(city)
    }

    private func resolvedMapSearchCity(_ city: City) -> City {
        guard let savedID = placesStore.savedPlaceID(matching: city),
              let savedCity = placesStore.place(id: savedID)?.city else {
            return city
        }
        return savedCity
    }

    private func clearSunSearch() {
        // Invalidate an in-flight lookup before clearing its visible state.
        sunSearchGeneration &+= 1
        activeSunQuery = nil
        sunSearchResults = []
        selectedSunResultID = nil
        isSearchingForSun = false
    }

    private func saveSunResult(_ result: MapSunSearchResult) {
        do {
            let savedPlaceID = try placesStore.savePlace(result.city)
            selectedSunResultID = nil
            router.selectedMapPlaceID = savedPlaceID
        } catch {
            present(error)
        }
    }

    private func saveSearchPreview(_ result: MapSunSearchResult) {
        do {
            let savedPlaceID = try placesStore.savePlace(result.city)
            router.mapPreviewCity = nil
            selectedSearchPreviewID = nil
            router.selectedMapPlaceID = savedPlaceID
        } catch {
            present(error)
        }
    }
}

private struct MapUIError: Identifiable {
    let id = UUID()
    let message: String
}

/// A compact native sheet for choosing the spatial source of a sunny-place
/// search. Country selection stays inside this sheet's navigation stack.
private struct MapSunSearchSheet: View {
    let viewport: MapViewport?
    let canSearchNearMe: Bool
    let locale: Locale
    let runSearch: (MapSunQueryScope) -> Void

    @State private var scope: SunSearchScope
    @State private var selectedCountry: CountryPlacesOption?
    @State private var selectedContinent: ContinentPlacesOption?

    @Environment(\.dismiss) private var dismiss

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
        switch scope {
        case .area: viewport != nil
        case .nearMe: canSearchNearMe
        case .country: selectedCountry != nil
        case .continent: selectedContinent != nil
        }
    }

    private var searchButtonTitle: LocalizedStringKey {
        switch scope {
        case .area: "Search in This Area"
        case .nearMe: "Search Near Me"
        case .country: "Search in This Country"
        case .continent: "Search in This Continent"
        }
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
                    Button(action: submit) {
                        Label(searchButtonTitle, systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!canRunSearch)
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
                Label("Current location is unavailable.", systemImage: "location.slash")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var countryControls: some View {
        Section {
            if let selectedCountry {
                Label(selectedCountry.localizedName(locale: locale), systemImage: "checkmark")
                    .foregroundStyle(.tint)
            }

            NavigationLink {
                MapSunCountryPicker(
                    selectedCountry: $selectedCountry,
                    locale: locale
                )
            } label: {
                Label("Search a Country", systemImage: "magnifyingglass")
            }
        } header: {
            Text("Country")
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
                        }
                    }
                }
            }
        } header: {
            Text("Continent")
        }
    }

    private func submit() {
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
}

/// Country choice is a pushed searchable screen, keeping Find Sun's scope
/// sheet compact while still supporting the full country catalog.
private struct MapSunCountryPicker: View {
    @Binding var selectedCountry: CountryPlacesOption?
    let locale: Locale

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var countries: [CountryPlacesOption] {
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
                    }
                }
            }
        }
        .navigationTitle("Search a Country")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search countries")
    }
}

/// Uses the same floating-card material and hierarchy as a saved-place card;
/// the top-right action differs because this transient result can be saved.
private struct MapSunResultCard: View {
    let result: MapSunSearchResult
    let save: () -> Void
    let clearSelection: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .systemDefault
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            cardContent
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .frame(minHeight: cardHeight)

            Button("Close", systemImage: "xmark", action: clearSelection)
                .labelStyle(.iconOnly)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
                .accessibilityHint("Closes this place preview.")
        }
        .weatherAtlasInteractiveGlass(
            colorScheme: colorScheme,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    private var cardHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 150 : 128
    }

    private var cardContent: some View {
        HStack(alignment: .center, spacing: 16) {
            let icon = result.forecast.condition?.displayIcon ?? "sun.max.fill"
            Image(systemName: icon)
                .font(.system(size: 40, weight: .medium))
                .weatherIconStyle(for: icon)
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(temperatureUnit.display(result.forecast.dailyHigh))
                    .font(.system(size: 32, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                Text(
                    "\(result.city.displayName) · \(result.forecast.condition?.localizedDisplayName(locale: locale) ?? localizedString("Sunny", locale: locale))"
                )
                .font(.headline.weight(.regular))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 4)

            Button("Save", systemImage: "plus", action: save)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Saves this found sunny place to Saved Places.")
        }
    }
}

/// Contextual regional search shown only after the user taps the map itself.
private struct MapRegionContextCard: View {
    let context: MapTapRegionContext
    let findSun: (MapSunQueryScope) -> Void
    let clearSelection: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(context.title(locale: locale))
                    .font(.headline)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)

                Button("Close", systemImage: "xmark", action: clearSelection)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
                    .accessibilityHint("Closes regional search options.")
            }

            Button {
                findSun(.country(context.country))
            } label: {
                Label(
                    findSunTitle(
                        for: context.country.localizedName(locale: locale)
                    ),
                    systemImage: "sun.max.magnifyingglass"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if let continent = context.continent {
                Button {
                    findSun(.continent(continent))
                } label: {
                    Label(
                        findSunTitle(
                            for: continent.localizedName(locale: locale)
                        ),
                        systemImage: "globe.europe.africa"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .weatherAtlasInteractiveGlass(
            colorScheme: colorScheme,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    private func findSunTitle(for regionName: String) -> String {
        String(
            format: localizedString("Find Sun in %@", locale: locale),
            locale: locale,
            regionName
        )
    }
}

/// A single stable map item using the saved-place presentation contract shared
/// by cards and weather rows.
private struct PlacesMapPlacePresentation: Identifiable {
    let presentation: SavedPlacePresentation

    var id: City.ID { presentation.id }
    var place: SavedPlace { presentation.place }
    var recommendation: PlaceRecommendation? {
        presentation.recommendation
    }
    var isLoading: Bool { presentation.isLoading }
    var failureMessage: String? { presentation.failureMessage }
}

private struct PlacesMapCanvas: View {
    let presentations: [PlacesMapPlacePresentation]
    @Binding var selectedPlaceID: City.ID?
    @Binding var showsLegend: Bool
    @Binding var filtersToSunnyPlaces: Bool
    let sortMode: WeatherMetricMode
    let currentLocationCoordinate: CLLocationCoordinate2D?
    let currentLocationName: String
    let currentLocationFocusRequestID: Int
    let sunSearchResults: [MapSunSearchResult]
    @Binding var selectedSunResultID: City.ID?
    let searchPreviewResult: MapSunSearchResult?
    @Binding var selectedSearchPreviewID: City.ID?
    let activeSunQuerySummary: String?
    let isSearchingForSun: Bool
    @Binding var viewport: MapViewport?
    let displayName: (SavedPlace) -> String
    let findSun: () -> Void
    let findSunInRegion: (MapSunQueryScope) -> Void
    let clearSunSearch: () -> Void
    let saveSunResult: (MapSunSearchResult) -> Void
    let saveSearchPreview: (MapSunSearchResult) -> Void
    let searchPlaces: () -> Void

    @State private var position: MapCameraPosition = .automatic
    @State private var hasInitializedCamera = false
    @State private var labelPlacements:
        [City.ID: PlacesMapLabelPlacement] = [:]
    @State private var tappedRegionContext: MapTapRegionContext?
    @State private var regionContextResolutionID = 0

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit")
    private var distanceUnitRaw = DistanceUnit.defaultRawValue

    private var layerPresentations: [PlacesMapPlacePresentation] {
        presentations.filter(hasValidActiveLayerData)
    }

    private var visiblePresentations: [PlacesMapPlacePresentation] {
        mapMarkers.map(\.presentation)
    }

    private var mapMarkers: [PlacesMapMarkerPresentation] {
        let candidates = filtersToSunnyPlaces
            ? layerPresentations.filter {
                $0.recommendation?.condition.isSunny == true
            }
            : layerPresentations

        return candidates.compactMap { presentation in
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
        guard let selectedSunResultID else { return nil }
        return transientSunResults.first { $0.id == selectedSunResultID }
    }

    private var selectedSearchPreview: MapSunSearchResult? {
        guard let selectedSearchPreviewID,
              searchPreviewResult?.id == selectedSearchPreviewID else {
            return nil
        }
        return searchPreviewResult
    }

    /// A saved city already has its normal map dot and floating card. Avoid a
    /// duplicate transient dot when Find Sun happens to return that same city.
    private var transientSunResults: [MapSunSearchResult] {
        let savedIDs = Set(presentations.map(\.id))
        return sunSearchResults.filter { !savedIDs.contains($0.id) }
    }

    private var visiblePlaceIDs: [City.ID] {
        visiblePresentations
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
    }

    private var labelLayoutInputs: [PlacesMapLabelLayoutInput] {
        let savedInputs = mapMarkers.map { marker in
            PlacesMapLabelLayoutInput(
                id: marker.id,
                name: displayName(marker.presentation.place),
                coordinate: CLLocationCoordinate2D(
                    latitude: marker.presentation.place.city.latitude,
                    longitude: marker.presentation.place.city.longitude
                )
            )
        }
        let foundInputs = transientSunResults.map { result in
            PlacesMapLabelLayoutInput(
                id: result.id,
                name: result.city.displayName,
                coordinate: CLLocationCoordinate2D(
                    latitude: result.city.latitude,
                    longitude: result.city.longitude
                )
            )
        }
        let previewInputs = searchPreviewResult.map { result in
            [
                PlacesMapLabelLayoutInput(
                    id: result.id,
                    name: result.city.displayName,
                    coordinate: CLLocationCoordinate2D(
                        latitude: result.city.latitude,
                        longitude: result.city.longitude
                    )
                )
            ]
        } ?? []
        return savedInputs + foundInputs + previewInputs
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mapContent

            if visiblePresentations.isEmpty,
               transientSunResults.isEmpty,
               searchPreviewResult == nil {
                emptyMapState
                    .zIndex(1)
            }

            if let selectedPresentation {
                MapPlaceSelectionCard(
                    presentation: selectedPresentation,
                    displayName: displayName(selectedPresentation.place),
                    sortMode: sortMode,
                    clearSelection: clearSelection
                )
                .padding(
                    .horizontal,
                    dynamicTypeSize.isAccessibilitySize ? 12 : 18
                )
                .padding(.bottom, 18)
                .frame(maxWidth: cardMaximumWidth)
                .transition(cardTransition)
                .zIndex(2)
            }

            if let selectedSunResult {
                MapSunResultCard(
                    result: selectedSunResult,
                    save: { saveSunResult(selectedSunResult) },
                    clearSelection: { selectedSunResultID = nil }
                )
                .padding(
                    .horizontal,
                    dynamicTypeSize.isAccessibilitySize ? 12 : 18
                )
                .padding(.bottom, 18)
                .frame(maxWidth: cardMaximumWidth)
                .transition(cardTransition)
                .zIndex(3)
            }

            if let selectedSearchPreview {
                MapSunResultCard(
                    result: selectedSearchPreview,
                    save: { saveSearchPreview(selectedSearchPreview) },
                    clearSelection: { selectedSearchPreviewID = nil }
                )
                .padding(
                    .horizontal,
                    dynamicTypeSize.isAccessibilitySize ? 12 : 18
                )
                .padding(.bottom, 18)
                .frame(maxWidth: cardMaximumWidth)
                .transition(cardTransition)
                .zIndex(4)
            }

            if let tappedRegionContext {
                MapRegionContextCard(
                    context: tappedRegionContext,
                    findSun: { scope in
                        clearTappedRegionContext()
                        findSunInRegion(scope)
                    },
                    clearSelection: clearTappedRegionContext
                )
                .padding(
                    .horizontal,
                    dynamicTypeSize.isAccessibilitySize ? 12 : 18
                )
                .padding(.bottom, 18)
                .frame(maxWidth: cardMaximumWidth)
                .transition(cardTransition)
                .zIndex(5)
            }
        }
        .onChange(of: visiblePlaceIDs, initial: true) { _, newIDs in
            if let selectedPlaceID, !newIDs.contains(selectedPlaceID) {
                self.selectedPlaceID = nil
            }

            if !hasInitializedCamera {
                initializeCamera()
                hasInitializedCamera = true
            }
        }
        .onChange(of: currentLocationFocusRequestID) {
            focusCurrentLocation()
        }
        .onChange(of: searchPreviewResult?.id, initial: true) { _, previewID in
            guard let previewID,
                  let preview = searchPreviewResult,
                  preview.id == previewID else {
                return
            }
            focus(on: preview.city)
        }
        .onChange(of: selectedPlaceID) {
            if selectedPlaceID != nil {
                selectedSunResultID = nil
                selectedSearchPreviewID = nil
            }
        }
        .animation(
            reduceMotion
                ? nil
                : .spring(response: 0.35, dampingFraction: 0.85),
            value: selectedPlaceID
        )
        .sensoryFeedback(.selection, trigger: selectedPlaceID)
    }

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
                    MapPolygon(points: subtleBaseMapOverlayPoints)
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
                                accessibilityValue: markerAccessibilityValue(
                                    for: marker.presentation
                                ),
                                select: {
                                    withAnimation(
                                        reduceMotion
                                            ? nil
                                            : .smooth(duration: 0.22)
                                    ) {
                                        selectedPlaceID = marker.id
                                    }
                                }
                            )
                        }
                        .tag(marker.id)
                    }

                    ForEach(transientSunResults) { result in
                        Annotation(
                            "Sunny result",
                            coordinate: CLLocationCoordinate2D(
                                latitude: result.city.latitude,
                                longitude: result.city.longitude
                            ),
                            anchor: .center
                        ) {
                            PlacesWeatherMapAnnotation(
                                name: result.city.displayName,
                                color: (result.forecast.condition ?? .clear)
                                    .dotColor(for: theme.colors),
                                isSelected: selectedSunResultID == result.id,
                                labelPlacement:
                                    labelPlacements[result.id] ?? .below,
                                differentiatingText: nil,
                                differentiatingSymbol:
                                    result.forecast.condition?.displayIcon,
                                accessibilityValue: localizedString(
                                    "Sunny search result",
                                    locale: locale
                                ),
                                select: {
                                    selectedPlaceID = nil
                                    selectedSunResultID = result.id
                                }
                            )
                        }
                    }

                    if let searchPreviewResult {
                        Annotation(
                            "Search result",
                            coordinate: CLLocationCoordinate2D(
                                latitude: searchPreviewResult.city.latitude,
                                longitude: searchPreviewResult.city.longitude
                            ),
                            anchor: .center
                        ) {
                            PlacesWeatherMapAnnotation(
                                name: searchPreviewResult.city.displayName,
                                color: (searchPreviewResult.forecast.condition ?? .clear)
                                    .dotColor(for: theme.colors),
                                isSelected:
                                    selectedSearchPreviewID == searchPreviewResult.id,
                                labelPlacement:
                                    labelPlacements[searchPreviewResult.id] ?? .below,
                                differentiatingText: nil,
                                differentiatingSymbol:
                                    searchPreviewResult.forecast.condition?.displayIcon,
                                accessibilityValue: localizedString(
                                    "Search result",
                                    locale: locale
                                ),
                                select: {
                                    selectedPlaceID = nil
                                    selectedSunResultID = nil
                                    selectedSearchPreviewID = searchPreviewResult.id
                                }
                            )
                        }
                    }

                    if let currentLocationCoordinate {
                        // This is intentionally separate from saved-place
                        // weather dots: it stays available under all filters
                        // and makes the location-focus action unambiguous.
                        Annotation(
                            "Current Location",
                            coordinate: currentLocationCoordinate,
                            anchor: .center
                        ) {
                            CurrentLocationMapAnnotation(
                                name: currentLocationName
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
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .overlay(alignment: .topLeading) {
                    if showsLegend,
                       !visiblePresentations.isEmpty {
                        PlacesMapLegend(sortMode: sortMode) {
                            withAnimation(
                                reduceMotion
                                    ? nil
                                    : .smooth(duration: 0.2)
                            ) {
                                showsLegend = false
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, legendTopPadding)
                        .transition(legendTransition)
                    }
                }
                .overlay(alignment: .bottom) {
                    Group {
                        if isSearchingForSun {
                            ProgressView("Finding sunny places")
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .weatherAtlasInteractiveGlass(
                                    colorScheme: colorScheme,
                                    in: Capsule()
                                )
                        } else if let activeSunQuerySummary {
                            HStack(spacing: 8) {
                                Text(
                                    "Found \(sunSearchResults.count) \(activeSunQuerySummary)"
                                )
                                .lineLimit(1)
                                Button(
                                    "Clear Find Sun Results",
                                    systemImage: "xmark",
                                    action: clearSunSearch
                                )
                                .labelStyle(.iconOnly)
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .weatherAtlasInteractiveGlass(
                                colorScheme: colorScheme,
                                in: Capsule()
                            )
                            .accessibilityElement(children: .combine)
                        } else {
                            Button(action: findSun) {
                                Label(
                                    "Find Sun",
                                    systemImage: "sun.max.magnifyingglass"
                                )
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                            }
                            .buttonStyle(.plain)
                            .weatherAtlasInteractiveGlass(
                                colorScheme: colorScheme,
                                in: Capsule()
                            )
                            .accessibilityHint(
                                "Search this area, near you, a country, or a continent."
                            )
                        }
                    }
                    .padding(
                        .bottom,
                        selectedPresentation == nil
                            && selectedSunResult == nil
                            && selectedSearchPreview == nil
                            && tappedRegionContext == nil ? 24 : 164
                    )
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
                .animation(
                    reduceMotion ? nil : .smooth(duration: 0.22),
                    value: showsLegend
                )
                .animation(
                    reduceMotion ? nil : .smooth(duration: 0.22),
                    value: selectedPlaceID
                )
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        handleMapTap(
                            at: value.location,
                            using: mapProxy
                        )
                    }
                )
            }
        }
    }

    private func handleMapTap(
        at location: CGPoint,
        using mapProxy: MapProxy
    ) {
        guard !isTapOnAnnotation(at: location, using: mapProxy),
              let coordinate = mapProxy.convert(location, from: .local),
              CLLocationCoordinate2DIsValid(coordinate) else {
            return
        }

        selectedPlaceID = nil
        selectedSunResultID = nil
        selectedSearchPreviewID = nil
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
        let previewCoordinates = searchPreviewResult.map {
            [
                CLLocationCoordinate2D(
                    latitude: $0.city.latitude,
                    longitude: $0.city.longitude
                )
            ]
        } ?? []
        let coordinates = savedCoordinates + foundCoordinates + previewCoordinates

        return coordinates.contains { coordinate in
            guard let point = mapProxy.convert(coordinate, to: .local) else {
                return false
            }
            return hypot(point.x - location.x, point.y - location.y) < 36
        }
    }

    private func resolveTappedRegion(at coordinate: CLLocationCoordinate2D) {
        regionContextResolutionID &+= 1
        let resolutionID = regionContextResolutionID
        tappedRegionContext = nil

        Task {
            let location = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            let placemark = try? await CLGeocoder()
                .reverseGeocodeLocation(location, preferredLocale: locale)
                .first
            guard !Task.isCancelled,
                  resolutionID == regionContextResolutionID,
                  let countryCode = placemark?.isoCountryCode,
                  let country = CountryCityCatalog.country(iso2: countryCode) else {
                return
            }

            tappedRegionContext = MapTapRegionContext(
                locality: placemark?.locality
                    ?? placemark?.subAdministrativeArea
                    ?? placemark?.administrativeArea,
                country: country,
                continent: CountryCityCatalog.continent(for: country)
            )
        }
    }

    private func clearTappedRegionContext() {
        regionContextResolutionID &+= 1
        tappedRegionContext = nil
    }

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
                    x: projectedLabel.point.x - 7,
                    y: projectedLabel.point.y - 7,
                    width: 14,
                    height: 14
                )
            )
        }

        var occupiedLabelRects: [CGRect] = []
        var newPlacements: [City.ID: PlacesMapLabelPlacement] = [:]

        for projectedLabel in projectedLabels {
            let belowRect = projectedLabel.rect(
                for: PlacesMapLabelPlacement.below
            )
            let aboveRect = projectedLabel.rect(
                for: PlacesMapLabelPlacement.above
            )
            let belowScore = labelCollisionScore(
                for: belowRect,
                labelID: projectedLabel.input.id,
                occupiedLabelRects: occupiedLabelRects,
                markerObstacles: markerObstacles,
                viewportBounds: viewportBounds
            )
            let aboveScore = labelCollisionScore(
                for: aboveRect,
                labelID: projectedLabel.input.id,
                occupiedLabelRects: occupiedLabelRects,
                markerObstacles: markerObstacles,
                viewportBounds: viewportBounds
            )
            let placement: PlacesMapLabelPlacement =
                aboveScore < belowScore ? .above : .below

            newPlacements[projectedLabel.input.id] = placement
            occupiedLabelRects.append(projectedLabel.rect(for: placement))
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

    private func labelCollisionScore(
        for rect: CGRect,
        labelID: City.ID,
        occupiedLabelRects: [CGRect],
        markerObstacles: [(id: City.ID, rect: CGRect)],
        viewportBounds: CGRect
    ) -> CGFloat {
        let labelOverlap = occupiedLabelRects.reduce(CGFloat.zero) {
            $0 + intersectionArea(rect, $1)
        }
        let markerOverlap = markerObstacles.reduce(CGFloat.zero) {
            partialResult,
            obstacle in
            guard obstacle.id != labelID else { return partialResult }
            return partialResult + intersectionArea(rect, obstacle.rect)
        }
        let clippedArea = intersectionArea(rect, viewportBounds)
        let offscreenArea = max(0, rect.width * rect.height - clippedArea)

        return labelOverlap * 4 + markerOverlap * 2 + offscreenArea * 6
    }

    private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private func clearSelection() {
        withAnimation(
            reduceMotion
                ? nil
                : .spring(response: 0.35, dampingFraction: 0.85)
        ) {
            selectedPlaceID = nil
        }
    }

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
        } else if let currentLocationCoordinate {
            position = .region(
                MKCoordinateRegion(
                    center: currentLocationCoordinate,
                    span: MKCoordinateSpan(
                        // Start wider than the dedicated focus action so Home
                        // opens as an atlas rather than a street-level map.
                        latitudeDelta: 3,
                        longitudeDelta: 3
                    )
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

    /// Centers on the real location marker instead of changing zoom to include
    /// every saved city. This preserves the user's manual map framing.
    private func focusCurrentLocation() {
        guard let currentLocationCoordinate else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
            position = .region(
                MKCoordinateRegion(
                    center: currentLocationCoordinate,
                    span: MKCoordinateSpan(
                        latitudeDelta: 0.5,
                        longitudeDelta: 0.5
                    )
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
        guard let recommendation = presentation.recommendation else {
            return nil
        }

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
            return theme.colors.dotRain.interpolated(
                with: theme.colors.dotCloudy,
                by: clamped(recommendation.cloudCover)
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

    @ViewBuilder
    private var emptyMapState: some View {
        if presentations.isEmpty {
            ContentUnavailableView {
                Label("No Places to Show", systemImage: "mappin.slash")
            } description: {
                Text(
                    "Save a city to add it to this map."
                )
            } actions: {
                Button(
                    "Search for a Place",
                    systemImage: "magnifyingglass",
                    action: searchPlaces
                )
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
        } else if presentations.contains(where: \.isLoading),
           layerPresentations.isEmpty {
            ProgressView("Loading Forecasts")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial)
        } else if filtersToSunnyPlaces {
            ContentUnavailableView {
                Label("No Sun", systemImage: "sun.max")
            } description: {
                Text("No sunny places for this date.")
            } actions: {
                Button("Show All Cities") {
                    withAnimation(
                        reduceMotion ? nil : .smooth(duration: 0.2)
                    ) {
                        filtersToSunnyPlaces = false
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
        } else {
            ContentUnavailableView {
                Label(
                    "Forecast Unavailable",
                    systemImage: "cloud.slash"
                )
            } description: {
                Text("No forecast for the selected date.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
        }
    }

    private var cardMaximumWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 390 : 580
    }

    private var legendTopPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 24 : 12
    }

    private var cardTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .scale(scale: 0.4, anchor: .bottom)
            .combined(with: .opacity)
            .combined(with: .offset(y: 20))
    }

    private var legendTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .scale(scale: 0.92, anchor: .topLeading)
            .combined(with: .opacity)
    }

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
            return percentage(recommendation.cloudCover)
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

    private func markerDifferentiatingSymbol(
        for presentation: PlacesMapPlacePresentation
    ) -> String? {
        guard sortMode == .sunny else { return nil }
        return presentation.recommendation?.condition.displayIcon
            ?? "exclamationmark"
    }

    private func markerAccessibilityValue(
        for presentation: PlacesMapPlacePresentation
    ) -> String {
        guard let recommendation = presentation.recommendation else {
            return localizedString(
                "Forecast Unavailable",
                locale: locale
            )
        }

        if sortMode == .sunny {
            return recommendation.condition.localizedDisplayName(
                locale: locale
            )
        }

        let value = markerDifferentiatingText(for: presentation) ?? "—"
        return "\(sortMode.title(locale: locale)), \(value)"
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
    private var subtleBaseMapOverlayPoints: [MKMapPoint] {
        let world = MKMapRect.world
        return [
            MKMapPoint(x: world.minX, y: world.minY),
            MKMapPoint(x: world.maxX, y: world.minY),
            MKMapPoint(x: world.maxX, y: world.maxY),
            MKMapPoint(x: world.minX, y: world.maxY)
        ]
    }
}

private struct PlacesMapMarkerPresentation: Identifiable {
    let presentation: PlacesMapPlacePresentation
    let color: Color

    var id: City.ID { presentation.id }
}

private struct PlacesMapLabelLayoutInput: Equatable {
    let id: City.ID
    let name: String
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees

    init(
        id: City.ID,
        name: String,
        coordinate: CLLocationCoordinate2D
    ) {
        self.id = id
        self.name = name
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }
}

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

private enum PlacesMapLabelPlacement: Equatable {
    case above
    case below

    var verticalOffset: CGFloat {
        switch self {
        case .above:
            -15
        case .below:
            15
        }
    }
}

/// A distinct, accessible marker for the device coordinate. It is independent
/// of the saved-place weather layer, so filters never hide the user's anchor.
private struct CurrentLocationMapAnnotation: View {
    let name: String
    @Environment(\.appTheme) private var theme

    var body: some View {
        Image(systemName: "location.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.red)
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .overlay {
            // Match the saved-city label exactly: the location is distinct by
            // its red glyph, not a different label treatment.
            Text(name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 104)
                .fixedSize(horizontal: true, vertical: false)
                .offset(y: PlacesMapLabelPlacement.below.verticalOffset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityLabel("Current Location")
        .accessibilityValue(name)
    }
}

private struct PlacesWeatherMapAnnotation: View {
    let name: String
    let color: Color
    let isSelected: Bool
    let labelPlacement: PlacesMapLabelPlacement
    let differentiatingText: String?
    let differentiatingSymbol: String?
    let accessibilityValue: String
    let select: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: select) {
            PlacesWeatherMapDot(
                color: color,
                isSelected: isSelected,
                differentiatingText: differentiatingText,
                differentiatingSymbol: differentiatingSymbol
            )
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(name)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .overlay {
            Text(name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 104)
                .fixedSize(horizontal: true, vertical: false)
                .offset(y: labelPlacement.verticalOffset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct PlacesWeatherMapDot: View {
    let color: Color
    let isSelected: Bool
    let differentiatingText: String?
    let differentiatingSymbol: String?

    @State private var glowPulse = false
    @Environment(\.accessibilityDifferentiateWithoutColor)
    private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var markerScale: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 1.25 : 1
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(isSelected ? 0.34 : 0.22))
                .frame(
                    width: isSelected ? 28 : 18,
                    height: isSelected ? 28 : 18
                )
                .blur(radius: isSelected ? 8 : 5)
                .scaleEffect(isSelected && glowPulse ? 1.18 : 1)
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: 1.15)
                            .repeatForever(autoreverses: true),
                    value: glowPulse
                )

            if isSelected && !differentiateWithoutColor {
                PlacesMapSelectedPulseRing(color: color)
            }

            if differentiateWithoutColor {
                differentiatingContent
                    .foregroundStyle(theme.colors.primaryText)
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
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.22),
            value: isSelected
        )
        .onAppear {
            glowPulse = isSelected && !reduceMotion
        }
        .onChange(of: isSelected) { _, selected in
            glowPulse = selected && !reduceMotion
        }
        .onChange(of: reduceMotion) { _, shouldReduceMotion in
            glowPulse = isSelected && !shouldReduceMotion
        }
    }

    @ViewBuilder
    private var differentiatingContent: some View {
        if let differentiatingText {
            Text(differentiatingText)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 5)
        } else if let differentiatingSymbol {
            Image(systemName: differentiatingSymbol)
                .font(.caption2.weight(.bold))
                .padding(5)
        }
    }
}

private struct PlacesMapSelectedPulseRing: View {
    let color: Color

    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .stroke(
                color.opacity(isPulsing ? 0.3 : 0.8),
                lineWidth: isPulsing ? 1.5 : 2.5
            )
            .frame(width: 22, height: 22)
            .scaleEffect(isPulsing ? 1.22 : 1)
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 1.2)
                        .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = !reduceMotion
            }
            .onChange(of: reduceMotion) { _, shouldReduceMotion in
                isPulsing = !shouldReduceMotion
            }
    }
}

private struct MapPlaceSelectionCard: View {
    let presentation: PlacesMapPlacePresentation
    let displayName: String
    let sortMode: WeatherMetricMode
    let clearSelection: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit")
    private var distanceUnitRaw = DistanceUnit.defaultRawValue

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: AppRoute.place(id: presentation.id)) {
                cardContent
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: cardHeight)
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: 24,
                            style: .continuous
                        )
                    )
            }
            .buttonStyle(.plain)

            Button("Close", systemImage: "xmark", action: clearSelection)
                .labelStyle(.iconOnly)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
                .zIndex(1)
                .accessibilityHint("Closes this place preview.")
        }
        .weatherAtlasInteractiveGlass(
            colorScheme: colorScheme,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var cardContent: some View {
        if let recommendation = presentation.recommendation {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: recommendation.condition.displayIcon)
                        .font(.title2.weight(.medium))
                        .weatherIconStyle(for: recommendation.condition.displayIcon)
                        .accessibilityHidden(true)

                    Text(metricValue(for: recommendation))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()

                    Text(displayName)
                        .font(.headline)

                    Label(
                        sortMode.title(locale: locale),
                        systemImage: recommendation.condition.displayIcon
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: recommendation.condition.displayIcon)
                        .font(.system(size: 40, weight: .medium))
                        .weatherIconStyle(
                            for: recommendation.condition.displayIcon
                        )
                        .frame(width: 56, height: 48)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(metricValue(for: recommendation))
                            .font(.system(size: 32, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.74)

                        Text(
                            "\(displayName) · \(sortMode.title(locale: locale))"
                        )
                        .font(.headline.weight(.regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    }

                    Spacer(minLength: 8)
                }
            }
        } else {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(displayName)
                        .font(.headline)

                    Text(
                        statusDescription
                    )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cardHeight: CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return 150
        }
        switch dynamicTypeSize {
        case .xSmall, .small, .medium, .large:
            return 128
        case .xLarge:
            return 138
        default:
            return 150
        }
    }

    private var statusDescription: String {
        if presentation.isLoading {
            return localizedString("Loading forecast…", locale: locale)
        }
        return presentation.failureMessage
            ?? localizedString(
                "No forecast for the selected date.",
                locale: locale
            )
    }

    private func metricValue(
        for recommendation: PlaceRecommendation
    ) -> String {
        switch sortMode {
        case .sunny:
            if let range = recommendation.bestSunnyWindow {
                let start = SunninessScoring.compactHourLabel(
                    range.lowerBound,
                    locale: locale
                )
                let end = SunninessScoring.compactHourLabel(
                    range.upperBound + 1,
                    locale: locale
                )
                return "\(start) – \(end)"
            }
            return recommendation.sunnyHourCount == 0
                ? localizedString("No Sun", locale: locale)
                : String(recommendation.sunnyHourCount)
        case .temperature:
            return temperatureUnit.display(
                recommendation.forecast.dailyHigh
            )
        case .feelsLike:
            return recommendation.maximumFeelsLike.map(
                temperatureUnit.display
            ) ?? "—"
        case .cloud:
            return percentage(recommendation.cloudCover)
        case .rainChance:
            return recommendation.precipitationChance.map(percentage) ?? "—"
        case .visibility:
            return recommendation.maximumVisibilityKilometers.map(
                distanceUnit.display
            ) ?? "—"
        case .uvIndex:
            return recommendation.forecast.uvIndex.map(String.init) ?? "—"
        }
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
}

private struct PlacesMapLegend: View {
    let sortMode: WeatherMetricMode
    let close: () -> Void

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
        .padding(.trailing, 20)
        .frame(
            width: legendWidth,
            alignment: .leading
        )
        .detailTranslucentCard(
            colorScheme: colorScheme,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(alignment: .topTrailing) {
            Button("Close", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
        }
        .fixedSize(
            horizontal: !dynamicTypeSize.isAccessibilitySize,
            vertical: false
        )
        .accessibilityElement(children: .contain)
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
                    wrappedCloudyConditionsTitle,
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

    private var wrappedCloudyConditionsTitle: String {
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
        var minimumLatitude = cities[0].latitude
        var maximumLatitude = cities[0].latitude
        for city in cities.dropFirst() {
            minimumLatitude = min(minimumLatitude, city.latitude)
            maximumLatitude = max(maximumLatitude, city.latitude)
        }

        let longitudeArc = minimumLongitudeArc(
            for: cities.map(\.longitude)
        )
        return paddedRegion(
            minimumLatitude: minimumLatitude,
            maximumLatitude: maximumLatitude,
            centerLongitude: longitudeArc.center,
            longitudeSpan: longitudeArc.span
        )
    }

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

    private static func paddedRegion(
        minimumLatitude: CLLocationDegrees,
        maximumLatitude: CLLocationDegrees,
        centerLongitude: CLLocationDegrees,
        longitudeSpan: CLLocationDegrees
    ) -> MKCoordinateRegion {
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
