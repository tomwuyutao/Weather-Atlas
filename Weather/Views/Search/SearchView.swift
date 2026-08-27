//
//  SearchView.swift
//  Weather
//
//  Purpose: Presents Apple Maps and translated Open-Meteo city results, then
//  opens an unsaved city in Map preview for an explicit save decision.
//

import CoreLocation
import SwiftUI
import UIKit

// MARK: - Search Scope

/// The Search tab keeps city lookup separate from the two geographic Find Sun
/// scopes. City remains the default because it is the only provider-backed
/// lookup that resolves an individual place for saving.
private enum PlaceSearchScope: String, CaseIterable, Identifiable {
    case city
    case country
    case continent

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .city: "City"
        case .country: "Country"
        case .continent: "Continent"
        }
    }
}

// MARK: - Search Tab

/// The user-facing search screen. It debounces typing, presents two providers,
/// then resolves the selected result before handing it to the Map preview flow.
struct PlaceSearchView: View {
    let model: WeatherModel
    @Bindable var router: AppNavigation
    /// Search is the one entry point that deliberately resets the shared
    /// forecast day: a newly selected city always opens on its own local
    /// calendar day, rather than inheriting a non-today date from another tab.
    @Binding var selectedDate: Date

    // MARK: - Search State

    /// The manager is observable but owned by this view, so `@State` preserves
    /// one instance for the screen's lifetime rather than recreating it in body.
    @State private var searchManager = CitySearchManager()
    @State private var searchScope: PlaceSearchScope = .city
    @State private var query = ""
    /// Stays false during the debounce interval so an empty list can show a
    /// searching state before either provider has begun returning suggestions.
    @State private var isSettled = true
    /// Disables competing result taps while one selected provider result is
    /// resolving into a coordinate, time zone, and concrete `City`.
    @State private var loadingID: CitySearchResult.ID?
    /// Keeping the task lets a newer selection cancel resolution of an older
    /// result rather than racing to change the Map preview.
    @State private var selectionTask: Task<Void, Never>?
    /// A cancellation alone is not enough: a provider can finish just as a
    /// query changes. Each invalidation gets a new generation so stale work
    /// cannot update navigation or row state after that race.
    @State private var selectionGeneration = 0
    @State private var selectionError: (key: String, message: String)?
    @State private var allCountries: [CountryPlacesOption] = []
    @State private var hasLoadedCountries = false
    /// The highest-population cities in the active current/home country. This
    /// intentionally preserves the catalog's literal rank; it does not apply
    /// the spatial clustering used by nearby-destination workflows.
    @State private var countryCitySuggestions: [City] = []
    @FocusState private var isSearchFocused: Bool

    @Environment(\.locale) private var locale
    @Environment(\.appTheme) private var theme

    private var missingDataReport: MissingDataAlertReport? {
        guard searchScope == .city else { return nil }

        if let selectionError {
            return MissingDataAlertReport(
                key: "search-selection:\(selectionError.key)",
                title: localizedString("Search Data Missing", locale: locale),
                message: selectionError.message
            )
        }

        let messages = [
            searchManager.appleErrorMessage,
            searchManager.openMeteoErrorMessage
        ].compactMap { $0 }
        // Each provider already owns an inline unavailable row. Do not cover a
        // usable provider's results with a blocking alert just because its
        // sibling failed; reserve that alert for a complete provider outage.
        guard !messages.isEmpty,
              !isSearchInProgress,
              hasNoResults else {
            return nil
        }
        return MissingDataAlertReport(
            key: "search-providers:\(normalizedQuery):\(messages.joined(separator: "|"))",
            title: localizedString("Search Data Missing", locale: locale),
            message: localizedString(
                "This provider could not return results. Try again.",
                locale: locale
            )
        )
    }

    // MARK: - Lifecycle and Search Field

    var body: some View {
        searchFieldHost
            .safeAreaInset(edge: .top, spacing: 0) {
                scopePicker
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(theme.colors.background)
            }
            .weatherContentColumn(standardMaximumWidth: .infinity)
            .weatherScreenBackground()
            .toolbar {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Settings", systemImage: "slider.horizontal.3") {
                            router.presentedSheet = .settings
                        }
                        .labelStyle(.iconOnly)
                    }
                }
            }
            .task(id: citySearchTaskID) {
                // SwiftUI cancels this task when the normalized query changes,
                // which makes the debounce naturally track the latest typing.
                guard searchScope == .city else { return }
                await updateSearch()
            }
            .task(id: countryRecommendationTaskID) {
                guard searchScope == .country else { return }
                refreshCountryOptions()
            }
            .task(id: citySuggestionTaskID) {
                guard searchScope == .city else { return }
                refreshCountryCitySuggestions()
            }
            .task(id: router.selectedTab) {
                // The system search tab may morph into its field after the
                // screen appears, so yield once before requesting focus.
                guard router.selectedTab == .search else { return }
                if searchScope != .city {
                    searchScope = .city
                    await Task.yield()
                }
                await Task.yield()
                guard router.selectedTab == .search,
                      searchScope == .city else {
                    return
                }
                isSearchFocused = true
            }
            .onChange(of: searchScope) { _, newScope in
                handleScopeChange(to: newScope)
            }
            .onChange(of: query) { _, _ in
                invalidateSelection()
            }
            .onDisappear {
                // A resolved place should not navigate away from a search tab
                // the person has already left.
                invalidateSelection()
                isSearchFocused = false
            }
            .reportingMissingData(missingDataReport)
    }

    /// One native search-field host remains mounted across every scope. Keeping
    /// its identity stable prevents the navigation-bar field from disappearing
    /// or shifting while the person changes search modes.
    private var searchFieldHost: some View {
        searchableScopeContent
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: searchPrompt
            )
            .searchFocused($isSearchFocused)
    }

    /// Scope content owns only its results. The enclosing view owns the one
    /// persistent native search field, so it never appears or shifts while a
    /// person changes between City, Country, and Continent.
    @ViewBuilder
    private var searchableScopeContent: some View {
        switch searchScope {
        case .city:
            citySearchContent
        case .country:
            countrySearchContent
        case .continent:
            continentSearchContent
        }
    }

    private var searchPrompt: LocalizedStringKey {
        switch searchScope {
        case .city: "Search cities"
        case .country: "Search countries"
        case .continent: "Search continents"
        }
    }

    private var scopePicker: some View {
        Picker("Search", selection: $searchScope) {
            ForEach(PlaceSearchScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Scope Result States

    /// Empty, loading, no-result, and populated results are mutually exclusive
    /// states derived from the normalized query and both provider states.
    @ViewBuilder
    private var citySearchContent: some View {
        if normalizedQuery.isEmpty {
            if recentCitySuggestions.isEmpty
                && remainingCountryCitySuggestions.isEmpty {
                ContentUnavailableView(
                    "Search for a City",
                    systemImage: "building.2",
                    description: Text(
                        "Search for a city to view its weather conditions."
                    )
                    .font(.body.weight(.bold))
                )
            } else {
                countryCitySuggestionsList
            }
        } else if hasNoResults && isSearchInProgress && !hasProviderError {
            VStack(spacing: 12) {
                ProgressView()

                Text("Searching…")
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if hasNoResults && !hasProviderError {
            ContentUnavailableView.search(text: normalizedQuery)
        } else {
            resultsList
        }
    }

    @ViewBuilder
    private var countrySearchContent: some View {
        if !hasLoadedCountries {
            VStack(spacing: 12) {
                ProgressView()

                Text("Loading countries…")
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !hasCountrySuggestionContent {
            if normalizedQuery.isEmpty {
                ContentUnavailableView(
                    "Search countries",
                    systemImage: "flag"
                )
            } else {
                ContentUnavailableView.search(text: normalizedQuery)
            }
        } else {
            List {
                if normalizedQuery.isEmpty,
                   !recentCountrySuggestions.isEmpty {
                    Section {
                        ForEach(recentCountrySuggestions) { country in
                            geographicQueryButton(
                                title: country.localizedName(locale: locale)
                            ) {
                                openFindSun(in: .country(country))
                            }
                        }
                    } header: {
                        geographicScopeHeader(description: "Recent")
                    }
                    .listRowBackground(theme.colors.settingsRowFill)
                }

                if !countrySuggestionResults.isEmpty {
                    Section {
                        ForEach(countrySuggestionResults) { country in
                            geographicQueryButton(
                                title: country.localizedName(locale: locale)
                            ) {
                                openFindSun(in: .country(country))
                            }
                        }
                    } header: {
                        geographicScopeHeader(
                            description: "Find which cities are sunny in a country."
                        )
                    }
                    .listRowBackground(theme.colors.settingsRowFill)
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .weatherScrollableBackground()
        }
    }

    private var continentSearchContent: some View {
        Group {
            if !hasContinentSuggestionContent {
                ContentUnavailableView.search(text: normalizedQuery)
            } else {
                List {
                    if normalizedQuery.isEmpty,
                       !recentContinentSuggestions.isEmpty {
                        Section {
                            ForEach(recentContinentSuggestions) { continent in
                                geographicQueryButton(
                                    title: continent.localizedName(locale: locale)
                                ) {
                                    openFindSun(in: .continent(continent))
                                }
                            }
                        } header: {
                            geographicScopeHeader(description: "Recent")
                        }
                        .listRowBackground(theme.colors.settingsRowFill)
                    }

                    if !continentSuggestionResults.isEmpty {
                        Section {
                            ForEach(continentSuggestionResults) { continent in
                                geographicQueryButton(
                                    title: continent.localizedName(locale: locale)
                                ) {
                                    openFindSun(in: .continent(continent))
                                }
                            }
                        } header: {
                            geographicScopeHeader(
                                description: "Find which cities are sunny across a continent."
                            )
                        }
                        .listRowBackground(theme.colors.settingsRowFill)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
                .weatherScrollableBackground()
            }
        }
    }

    private func geographicQueryButton(
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body)
                    .foregroundStyle(theme.colors.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.colors.secondaryText.opacity(0.7))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Provider Result Rows

    /// Separate sections preserve each provider's provenance instead of
    /// silently merging heterogeneous geographic results into one list.
    private var resultsList: some View {
        List {
            providerSection(
                "Apple Maps",
                results: searchManager.appleResults,
                isSearching: searchManager.isAppleSearching,
                errorMessage: searchManager.appleErrorMessage
            )

            providerSection(
                "Open-Meteo",
                results: searchManager.openMeteoResults,
                isSearching: searchManager.isOpenMeteoSearching,
                errorMessage: searchManager.openMeteoErrorMessage
            )
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .weatherScrollableBackground()
    }

    private var countryCitySuggestionsList: some View {
        List {
            if !recentCitySuggestions.isEmpty {
                Section {
                    ForEach(recentCitySuggestions) { city in
                        geographicQueryButton(
                            title: city.localizedDisplayName(locale: locale)
                        ) {
                            selectSuggestedCity(city)
                        }
                    }
                } header: {
                    geographicScopeHeader(description: "Recent")
                }
                .listRowBackground(theme.colors.settingsRowFill)
            }

            if !remainingCountryCitySuggestions.isEmpty {
                Section {
                    ForEach(remainingCountryCitySuggestions) { city in
                        geographicQueryButton(
                            title: city.localizedDisplayName(locale: locale)
                        ) {
                            selectSuggestedCity(city)
                        }
                    }
                } header: {
                    geographicScopeHeader(
                        description: "Find when the sun comes out in a city."
                    )
                }
                .listRowBackground(theme.colors.settingsRowFill)
            }
        }
        .listStyle(.insetGrouped)
        .weatherScrollableBackground()
    }

    @ViewBuilder
    private func providerSection(
        _ title: LocalizedStringKey,
        results: [CitySearchResult],
        isSearching: Bool,
        errorMessage: String?
    ) -> some View {
        if !results.isEmpty || isSearching || errorMessage != nil {
            Section(title) {
                ForEach(results) { result in
                    resultButton(result)
                }

                if isSearching {
                    HStack(spacing: 12) {
                        ProgressView()

                        Text("Searching…")
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                } else if errorMessage != nil {
                    providerUnavailableRow
                }
            }
            .listRowBackground(theme.colors.settingsRowFill)
        }
    }

    /// An unavailable provider remains visibly distinct from an empty search.
    /// Retrying repeats the current query immediately rather than requiring a
    /// person to edit the native search field to trigger another request.
    private var providerUnavailableRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Search Unavailable", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(theme.colors.primaryText)

            Text("This provider could not return results. Try again.")
                .font(.subheadline)
                .foregroundStyle(theme.colors.secondaryText)

            Button("Try Again", systemImage: "arrow.clockwise") {
                retryCitySearch()
            }
            .buttonStyle(.bordered)
            .tint(theme.colors.accent)
        }
        .padding(.vertical, 4)
    }

    private func resultButton(_ result: CitySearchResult) -> some View {
        Button {
            select(result)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.body)
                        .foregroundStyle(theme.colors.primaryText)

                    if !result.subtitle.isEmpty {
                        Text(result.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if loadingID == result.id {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)

        // This also prevents a second button from cancelling and replacing the
        // in-flight resolution while its row's progress indicator is visible.
        .disabled(loadingID != nil)
    }

    // MARK: - Query Derivations

    /// Whitespace-only queries behave like no query and never hit a provider.
    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var countryResults: [CountryPlacesOption] {
        guard !normalizedQuery.isEmpty else { return allCountries }
        return allCountries.filter { country in
            country.matchesSearchQuery(normalizedQuery, locale: locale)
        }
    }

    /// Recents are a first section only while the field is empty. Their exact
    /// identities are removed from the ordinary suggestion section so no row
    /// appears twice on the same screen.
    private var recentCitySuggestions: [City] {
        Array(
            model.recentCitySuggestions.prefix(
                RecentSearchStore.maximumSuggestionCount
            )
        )
    }

    private var remainingCountryCitySuggestions: [City] {
        countryCitySuggestions.filter { suggestion in
            !recentCitySuggestions.contains {
                CitySemanticMatcher.matches($0, suggestion)
            }
        }
    }

    private var recentCountrySuggestions: [CountryPlacesOption] {
        model.recentSearches.countryISO2Codes.compactMap {
            CountryCityCatalog.country(iso2: $0)
        }
    }

    private var countrySuggestionResults: [CountryPlacesOption] {
        guard normalizedQuery.isEmpty else { return countryResults }
        let recentIDs = Set(recentCountrySuggestions.map(\.id))
        return countryResults.filter { !recentIDs.contains($0.id) }
    }

    private var hasCountrySuggestionContent: Bool {
        !countrySuggestionResults.isEmpty
            || (normalizedQuery.isEmpty && !recentCountrySuggestions.isEmpty)
    }

    private var citySearchTaskID: String {
        "\(searchScope.rawValue)|\(normalizedQuery)|\(locale.identifier)"
    }

    private var countryRecommendationTaskID: String {
        "\(searchScope.rawValue)|\(locationIdentifier)|\(locale.identifier)"
    }

    private var citySuggestionTaskID: String {
        "\(searchScope.rawValue)|\(locationCountryName ?? "unavailable")|\(locale.identifier)"
    }

    private var locationCountryName: String? {
        model.homeLocation?.country
            ?? model.locationProvider.metadata?.countryName
            ?? model.locationCity?.country
    }

    private var currentLocationCoordinate: CLLocationCoordinate2D? {
        guard let coordinate = model.locationProvider.coordinate,
              CLLocationCoordinate2DIsValid(coordinate) else {
            return nil
        }
        return coordinate
    }

    private var locationIdentifier: String {
        guard let coordinate = currentLocationCoordinate else {
            return "unavailable"
        }
        return "\(coordinate.latitude),\(coordinate.longitude)"
    }

    private func geographicScopeHeader(
        description: LocalizedStringKey
    ) -> some View {
        Text(description)
            .font(.body.weight(.bold))
            .foregroundStyle(theme.colors.primaryText)
            .textCase(nil)
    }

    /// The continent catalog is deliberately tiny, so filtering its six stable
    /// values locally is cheaper and more predictable than introducing another
    /// stored result array or asynchronous task.
    private var continentResults: [ContinentPlacesOption] {
        guard !normalizedQuery.isEmpty else {
            return ContinentPlacesOption.allCases
        }

        return ContinentPlacesOption.allCases.filter { continent in
            let localizedName = continent.localizedName(locale: locale)
            let englishName = continent.localizedName(
                locale: Locale(identifier: "en")
            )
            return localizedName.localizedCaseInsensitiveContains(
                normalizedQuery
            ) || englishName.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    private var recentContinentSuggestions: [ContinentPlacesOption] {
        model.recentSearches.continents
    }

    private var continentSuggestionResults: [ContinentPlacesOption] {
        guard normalizedQuery.isEmpty else { return continentResults }
        let recentIDs = Set(recentContinentSuggestions.map(\.id))
        return continentResults.filter { !recentIDs.contains($0.id) }
    }

    private var hasContinentSuggestionContent: Bool {
        !continentSuggestionResults.isEmpty
            || (normalizedQuery.isEmpty
                && !recentContinentSuggestions.isEmpty)
    }

    private var hasNoResults: Bool {
        searchManager.appleResults.isEmpty && searchManager.openMeteoResults.isEmpty
    }

    private var isSearchInProgress: Bool {
        !isSettled || searchManager.isAppleSearching || searchManager.isOpenMeteoSearching
    }

    private var hasProviderError: Bool {
        searchManager.appleErrorMessage != nil || searchManager.openMeteoErrorMessage != nil
    }

    // MARK: - Scope Changes and Catalog Loading

    @MainActor
    private func handleScopeChange(to scope: PlaceSearchScope) {
        invalidateSelection()
        query = ""
        isSettled = true
        searchManager.search(query: "", locale: locale)

        switch scope {
        case .city:
            Task { @MainActor in
                await Task.yield()
                guard searchScope == scope,
                      router.selectedTab == .search else {
                    return
                }
                isSearchFocused = true
            }
        case .country, .continent:
            isSearchFocused = false
        }
    }

    /// Country data is bundled with the app, so the complete list appears
    /// without a network request. A fresh location coordinate reorders every
    /// country by its nearest catalog city rather than showing a short subset.
    @MainActor
    private func refreshCountryOptions() {
        let countries = CountryCityCatalog.countries(
            near: currentLocationCoordinate,
            locale: locale
        )
        allCountries = countries
        hasLoadedCountries = true
    }

    @MainActor
    private func refreshCountryCitySuggestions() {
        guard let locationCountryName,
              let country = CountryCityCatalog.countries(locale: locale).first(where: {
                  $0.englishName.compare(
                      locationCountryName,
                      options: [.caseInsensitive, .diacriticInsensitive]
                  ) == .orderedSame
        }) else {
            countryCitySuggestions = []
            return
        }
        countryCitySuggestions = CountryCityCatalog.topCities(
            for: country,
            limit: 8
        )
    }

    @MainActor
    private func openFindSun(in scope: MapSunQueryScope) {
        invalidateSelection()
        isSearchFocused = false
        router.showMap(findingSunIn: scope, on: selectedDate)
    }

    // MARK: - Provider Search Timing

    /// A short cancellable debounce means only the final pause in typing starts
    /// a lookup. The second query check prevents an older task from settling a
    /// newer search field value.
    @MainActor
    private func updateSearch() async {
        guard searchScope == .city else { return }
        selectionError = nil
        guard !normalizedQuery.isEmpty else {
            searchManager.search(query: "", locale: locale)
            isSettled = true
            return
        }

        isSettled = false
        do {
            try await Task.sleep(for: .milliseconds(250))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        let submittedQuery = normalizedQuery
        searchManager.search(query: submittedQuery, locale: locale)
        guard !Task.isCancelled, normalizedQuery == submittedQuery else { return }
        isSettled = true
    }

    /// Restarts both providers for the currently visible query after a provider
    /// section reports that it could not return results.
    @MainActor
    private func retryCitySearch() {
        guard searchScope == .city, !normalizedQuery.isEmpty else { return }
        invalidateSelection()
        isSettled = true
        searchManager.search(query: normalizedQuery, locale: locale)
    }

    // MARK: - Selection and Navigation

    @MainActor
    private func invalidateSelection() {
        selectionGeneration &+= 1
        selectionTask?.cancel()
        selectionTask = nil
        loadingID = nil
        selectionError = nil
    }

    /// A result first resolves to concrete coordinates/time zone. Existing
    /// saved places open directly; new ones use the map preview as an explicit
    /// opportunity to inspect and save rather than being persisted implicitly.
    @MainActor
    private func select(_ result: CitySearchResult) {
        invalidateSelection()
        let generation = selectionGeneration
        let submittedQuery = normalizedQuery
        selectionTask = Task { @MainActor in
            // `defer` restores the row's enabled state on every exit path,
            // including cancellation and a failed provider resolution.
            loadingID = result.id
            selectionError = nil
            defer {
                if selectionGeneration == generation {
                    loadingID = nil
                    selectionTask = nil
                }
            }

            let resolvedPlace: CitySearchResolvedPlace
            do {
                resolvedPlace = try await searchManager.resolvePlace(for: result)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      selectionGeneration == generation,
                      normalizedQuery == submittedQuery,
                      searchScope == .city,
                      router.selectedTab == .search else {
                    return
                }
                selectionError = (
                    key: "\(result.id):\(error.localizedDescription)",
                    message: localizedCitySearchResolutionErrorDescription(
                        error,
                        locale: locale
                    )
                )
                return
            }
            guard !Task.isCancelled,
                  selectionGeneration == generation,
                  normalizedQuery == submittedQuery,
                  searchScope == .city,
                  router.selectedTab == .search else {
                return
            }

            let city = City(
                name: resolvedPlace.cityName,
                country: resolvedPlace.country,
                latitude: resolvedPlace.coordinate.latitude,
                longitude: resolvedPlace.coordinate.longitude,
                timeZoneIdentifier: resolvedPlace.timeZoneIdentifier
            )
            // `CityWeather.forecastIfAvailable` compares literal day
            // components using the app's selection calendar. Convert the
            // selected city's local "today" components into that calendar
            // before navigating, so a future/past date selected elsewhere
            // cannot make this freshly searched forecast disappear on Map.
            selectToday(for: resolvedPlace.timeZoneIdentifier)
            model.recordRecentCityAccess(city)
            if let savedPlaceID = model.placesStore.savedPlaceID(matching: city) {
                isSearchFocused = false
                router.showMap(placeID: savedPlaceID)
                return
            }
            model.registerTransientCity(city)
            selectionError = nil
            isSearchFocused = false
            router.showMap(previewing: city)
        }
    }

    @MainActor
    private func selectSuggestedCity(_ city: City) {
        guard loadingID == nil else { return }
        invalidateSelection()
        loadingID = "country-suggestion-\(city.id.uuidString)"
        defer { loadingID = nil }

        selectToday(for: city.timeZoneIdentifier ?? TimeZone.autoupdatingCurrent.identifier)
        model.recordRecentCityAccess(city)
        if let savedPlaceID = model.placesStore.savedPlaceID(matching: city) {
            isSearchFocused = false
            router.showMap(placeID: savedPlaceID)
            return
        }
        model.registerTransientCity(city)
        isSearchFocused = false
        router.showMap(previewing: city)
    }

    /// Produces a shared-selector date whose year/month/day are today's values
    /// in the searched city's IANA time zone. It intentionally does not use
    /// that city's midnight instant directly: the selector is interpreted in
    /// `model.forecastCalendar`, so only matching civil-date components keep
    /// the Map preview aligned with the city forecast.
    @MainActor
    private func selectToday(for timeZoneIdentifier: String) {
        guard let cityTimeZone = TimeZone(identifier: timeZoneIdentifier) else {
            return
        }

        var cityCalendar = model.forecastCalendar
        cityCalendar.timeZone = cityTimeZone
        let cityToday = cityCalendar.dateComponents(
            [.year, .month, .day],
            from: .now
        )

        let selectionCalendar = model.forecastCalendar
        guard let selectionDate = selectionCalendar.date(from: cityToday) else {
            return
        }
        selectedDate = selectionCalendar.startOfDay(for: selectionDate)
    }
}
