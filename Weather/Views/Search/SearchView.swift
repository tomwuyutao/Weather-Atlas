//
//  SearchView.swift
//  Weather
//
//  Purpose: Presents Apple Maps and translated Open-Meteo city results, then
//  opens an unsaved city in Map preview for an explicit save decision.
//

import CoreLocation
import SwiftUI

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

    // MARK: Search-local state

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
    @State private var selectionError: (key: String, message: String)?
    @State private var allCountries: [CountryPlacesOption] = []
    @State private var recommendedCountries: [CountryPlacesOption] = []
    @State private var countryResults: [CountryPlacesOption] = []
    @State private var hasLoadedCountries = false
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
        guard !messages.isEmpty, !isSearchInProgress else { return nil }
        return MissingDataAlertReport(
            key: "search-providers:\(normalizedQuery):\(messages.joined(separator: "|"))",
            title: localizedString("Search Data Missing", locale: locale),
            message: Array(Set(messages)).sorted().joined(separator: "\n")
        )
    }

    // MARK: Lifecycle and presentation

    var body: some View {
        searchableScopeContent
            // Keep one native search-field host mounted across every scope.
            // Reattaching `.searchable` inside each switch branch made its
            // navigation-bar placement jump when the segmented control changed.
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: searchPrompt
            )
            .searchFocused($isSearchFocused)
            .safeAreaInset(edge: .top, spacing: 0) {
                scopePicker
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(theme.colors.background)
            }
            .weatherScreenBackground()
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
            .onChange(of: query) {
                guard searchScope == .country else { return }
                updateCountrySearchResults()
            }
            .onDisappear {
                // A resolved place should not navigate away from a search tab
                // the person has already left.
                selectionTask?.cancel()
                isSearchFocused = false
            }
            .reportingMissingData(missingDataReport)
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
        .accessibilityLabel(Text("Search Scope"))
    }

    // MARK: Result states and rows

    /// Empty, loading, no-result, and populated results are mutually exclusive
    /// states derived from the normalized query and both provider states.
    @ViewBuilder
    private var citySearchContent: some View {
        if normalizedQuery.isEmpty {
            ContentUnavailableView(
                "Search for a City",
                systemImage: "building.2",
                description: Text("Search for a city to view its weather conditions.")
            )
        } else if hasNoResults && isSearchInProgress && !hasProviderError {
            VStack(spacing: 12) {
                ProgressView()
                    .accessibilityHidden(true)
                Text("Searching…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else if hasNoResults && !hasProviderError {
            ContentUnavailableView.search(text: normalizedQuery)
        } else {
            resultsList
        }
    }

    @ViewBuilder
    private var countrySearchContent: some View {
        if !hasLoadedCountries {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text("Loading countries"))
        } else if countryResults.isEmpty {
            if normalizedQuery.isEmpty {
                ContentUnavailableView(
                    "Search countries",
                    systemImage: "flag.fill"
                )
            } else {
                ContentUnavailableView.search(text: normalizedQuery)
            }
        } else {
            List {
                Section {
                    ForEach(countryResults) { country in
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
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .weatherScrollableBackground()
        }
    }

    private var continentSearchContent: some View {
        List {
            Section {
                ForEach(ContinentPlacesOption.allCases) { continent in
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
        }
        .listStyle(.insetGrouped)
        .weatherScrollableBackground()
    }

    private func geographicQueryButton(
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(Text("Find sunny places in this region"))
    }

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
                            .accessibilityHidden(true)
                        Text("Searching…")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                } else if errorMessage != nil {
                    Color.clear
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func resultButton(_ result: CitySearchResult) -> some View {
        Button {
            select(result)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .foregroundStyle(.primary)

                    if !result.subtitle.isEmpty {
                        Text(result.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if loadingID == result.id {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Open place preview"))
        // This also prevents a second button from cancelling and replacing the
        // in-flight resolution while its row's progress indicator is visible.
        .disabled(loadingID != nil)
    }

    // MARK: Search timing and selection

    /// Whitespace-only queries behave like no query and never hit a provider.
    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var citySearchTaskID: String {
        "\(searchScope.rawValue)|\(normalizedQuery)|\(locale.identifier)"
    }

    private var countryRecommendationTaskID: String {
        "\(searchScope.rawValue)|\(locationIdentifier)|\(locale.identifier)"
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
            .font(.body)
            .foregroundStyle(.primary)
            .textCase(nil)
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

    @MainActor
    private func handleScopeChange(to scope: PlaceSearchScope) {
        selectionTask?.cancel()
        loadingID = nil
        selectionError = nil
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

    /// Country data is bundled with the app, so suggestions arrive without a
    /// network request. A fresh location coordinate re-ranks only the compact
    /// six-item starter list; typing still searches the complete catalog.
    @MainActor
    private func refreshCountryOptions() {
        let countries = CountryCityCatalog.countries(locale: locale)
        allCountries = countries
        recommendedCountries = CountryCityCatalog.recommendedCountries(
            near: currentLocationCoordinate,
            locale: locale,
            limit: 6
        )
        hasLoadedCountries = true
        updateCountrySearchResults()
    }

    @MainActor
    private func updateCountrySearchResults() {
        let trimmedQuery = normalizedQuery
        guard !trimmedQuery.isEmpty else {
            countryResults = recommendedCountries
            return
        }

        countryResults = allCountries.filter { country in
            country.localizedName(locale: locale)
                .localizedCaseInsensitiveContains(trimmedQuery)
                || country.englishName.localizedCaseInsensitiveContains(
                    trimmedQuery
                )
        }
    }

    @MainActor
    private func openFindSun(in scope: MapSunQueryScope) {
        selectionTask?.cancel()
        selectionError = nil
        isSearchFocused = false
        router.showMap(findingSunIn: scope)
    }

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

    /// A result first resolves to concrete coordinates/time zone. Existing
    /// saved places open directly; new ones use the map preview as an explicit
    /// opportunity to inspect and save rather than being persisted implicitly.
    @MainActor
    private func select(_ result: CitySearchResult) {
        selectionTask?.cancel()
        selectionTask = Task { @MainActor in
            // `defer` restores the row's enabled state on every exit path,
            // including cancellation and a failed provider resolution.
            loadingID = result.id
            selectionError = nil
            defer {
                loadingID = nil
                selectionTask = nil
            }

            let resolvedPlace: CitySearchResolvedPlace
            do {
                resolvedPlace = try await searchManager.resolvePlace(for: result)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                selectionError = (
                    key: "\(result.id):\(error.localizedDescription)",
                    message: error.localizedDescription
                )
                return
            }
            guard !Task.isCancelled else { return }

            let city = City(
                name: resolvedPlace.cityName,
                country: resolvedPlace.country,
                latitude: resolvedPlace.coordinate.latitude,
                longitude: resolvedPlace.coordinate.longitude,
                timeZoneIdentifier: resolvedPlace.timeZoneIdentifier
            )
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
}
