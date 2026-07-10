//
//  Search.swift
//  Weather
//
//  Purpose: Wraps MapKit city search and the in-app search sheet used by
//  the floating bottom search control.
//

import SwiftUI
import CoreLocation
import MapKit

// MARK: - Search Result
struct CitySearchResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    fileprivate let completion: MKLocalSearchCompletion?

    init(title: String, subtitle: String, completion: MKLocalSearchCompletion) {
        self.id = "city-\(completion.title)-\(completion.subtitle)"
        self.title = title
        self.subtitle = subtitle
        self.completion = completion
    }

}

struct CitySearchResolvedPlace {
    let coordinate: CLLocationCoordinate2D
    let timeZoneIdentifier: String
}

// MARK: - City Search Manager

@Observable
class CitySearchManager: NSObject, MKLocalSearchCompleterDelegate {
    var searchResults: [CitySearchResult] = []
    private let completer: MKLocalSearchCompleter

    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)
        )
    }

    func search(query: String) {
        if query.isEmpty {
            searchResults = []
            return
        }
        completer.queryFragment = query
    }

    func resolvePlace(for result: CitySearchResult) async -> CitySearchResolvedPlace? {
        guard let completion = result.completion else { return nil }
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            guard let mapItem = response.mapItems.first,
                  let coordinate = mapItem.placemark.location?.coordinate else {
                return nil
            }

            let timeZoneIdentifier: String?
            if let mapKitTimeZone = mapItem.placemark.timeZone?.identifier {
                timeZoneIdentifier = mapKitTimeZone
            } else {
                timeZoneIdentifier = await resolveTimeZoneIdentifier(for: coordinate, result: result)
            }

            guard let timeZoneIdentifier else {
                DeveloperWarningCenter.show(
                    title: "Search Time Zone Missing",
                    message: "Apple location search and reverse geocoding returned no time zone for \(result.title), \(result.subtitle). Contact developer."
                )
                return nil
            }

            return CitySearchResolvedPlace(
                coordinate: coordinate,
                timeZoneIdentifier: timeZoneIdentifier
            )
        } catch {
            return nil
        }
    }

    private func resolveTimeZoneIdentifier(
        for coordinate: CLLocationCoordinate2D,
        result: CitySearchResult
    ) async -> String? {
        do {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            return placemarks.first?.timeZone?.identifier
        } catch {
            DeveloperWarningCenter.show(
                title: "Search Time Zone Lookup Failed",
                message: "Apple reverse geocoding failed while resolving the time zone for \(result.title), \(result.subtitle): \(error.localizedDescription). Contact developer."
            )
            return nil
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        searchResults = completer.results.map { completion in
            CitySearchResult(
                title: completion.title,
                subtitle: completion.subtitle,
                completion: completion
            )
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
    }
}

extension ContentView {

    // MARK: - Search Presentation

    var searchSheet: some View {
        NavigationStack {
            List {
                ForEach(Array(displayedSearchResults.prefix(searchResultLimit)), id: \.id) { result in
                    Button {
                        guard !isLoadingSearchCity else { return }
                        Task {
                            await selectSearchResult(result)
                        }
                    } label: {
                        citySearchSuggestionRow(
                            for: result,
                            isLoading: loadingSearchResultID == result.id
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(theme.colors.background)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(localizedString("Search", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismissNativeCitySearchAndRecenter()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.colors.primaryText)
                    }
                    .accessibilityLabel(localizedString("Cancel", locale: locale))
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(localizedString("Search for a city", locale: locale))
            )
            .onSubmit(of: .search) {
                confirmSearchSelection()
            }
        }
        .background(theme.colors.background.ignoresSafeArea())
        .onAppear {
            searchFieldPresented = true
            Task { @MainActor in
                await Task.yield()
                searchFieldFocused = true
            }
        }
    }

    private var searchResultLimit: Int { 8 }

    // MARK: - Search Styling

    private var searchSuggestionTitleColor: Color {
        colorScheme == .dark ? .white.opacity(0.92) : .black
    }

    private var searchSuggestionSubtitleColor: Color {
        colorScheme == .dark ? .white.opacity(0.68) : .black
    }

    // MARK: - Search Result Rows

    private func citySearchSuggestionRow(for result: CitySearchResult, isLoading: Bool) -> some View {
        let existingListName = searchIsSettled ? existingCityListName(for: result) : nil
        let titleColor = isLoading ? searchSuggestionTitleColor.opacity(0.45) : searchSuggestionTitleColor
        let subtitleColor = isLoading ? searchSuggestionSubtitleColor.opacity(0.45) : searchSuggestionSubtitleColor
        let rowSpacing: CGFloat = 10
        let titleFont: Font = .avenir(.body, weight: .medium)
        let subtitleFont: Font = .avenir(.caption, weight: .regular)
        let statusFont: Font = .avenir(.caption2, weight: .medium)
        let statusBoldFont: Font = .avenir(.caption2, weight: .bold)
        let rowVerticalPadding: CGFloat = 8
        let rowHorizontalPadding: CGFloat = 2

        return HStack(spacing: rowSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(titleFont)
                    .foregroundStyle(titleColor)
                    .lineLimit(1)

                Text(result.subtitle)
                    .font(subtitleFont)
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let existingListName {
                HStack(spacing: 6) {
                    (Text(localizedString("In list", locale: locale) + " ")
                        .font(statusFont)
                    + Text(existingListName)
                        .font(statusBoldFont))
                        .foregroundStyle(subtitleColor)
                        .lineLimit(1)

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(subtitleColor)
                }
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, rowVerticalPadding)
        .padding(.horizontal, rowHorizontalPadding)
        .frame(minHeight: 46)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - Result Identity and Sorting

    private func searchCityIdentity(for result: CitySearchResult) -> (name: String, country: String) {
        let name = result.title.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? result.title
        let country = result.subtitle.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? result.subtitle
        return (name, country)
    }

    func existingCityListName(for result: CitySearchResult) -> String? {
        let identity = searchCityIdentity(for: result)
        if let targetListID = searchAddTargetListID {
            let cities = weatherService.cityListCoordinates(for: targetListID)
            if cities.contains(where: { $0.name == identity.name && $0.country == identity.country }) {
                return targetListID.localizedDisplayName(locale: locale)
            }
            return nil
        }

        return weatherService.listContainingCity(named: identity.name, country: identity.country)?.localizedDisplayName(locale: locale)
    }

    func isExistingSearchCity(_ result: CitySearchResult) -> Bool {
        existingCityListName(for: result) != nil
    }

    var sortedSearchResults: [CitySearchResult] {
        citySearchManager.searchResults
            .sorted { a, b in
                let aExists = isExistingSearchCity(a)
                let bExists = isExistingSearchCity(b)
                if aExists != bExists { return aExists }
                return false
            }
    }

    var displayedSearchResults: [CitySearchResult] {
        searchIsSettled ? sortedSearchResults : citySearchManager.searchResults
    }

    // MARK: - Search Lifecycle

    func scheduleCitySearch(for query: String) {
        searchDebounceTask?.cancel()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            searchIsSettled = true
            citySearchManager.search(query: "")
            return
        }

        searchIsSettled = false
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            citySearchManager.search(query: trimmedQuery)
            searchIsSettled = true
        }
    }

    func activateSearch() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingMapExpandedCard = false
            tappedCity = nil
            showingSearchSheet = true
        }
        Task { @MainActor in
            await Task.yield()
            searchFieldPresented = true
            searchFieldFocused = true
        }
    }

    func resetNativeCitySearch() {
        searchText = ""
        citySearchManager.search(query: "")
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        searchIsSettled = true
        searchAddTargetListID = nil
        loadingSearchResultID = nil
    }

    func dismissNativeCitySearchAndRecenter() {
        let shouldRecenter = showingSearchSheet
            || searchFieldPresented
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !citySearchManager.searchResults.isEmpty
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingSearchSheet = false
            searchFieldPresented = false
            searchFieldFocused = false
        }
        resetNativeCitySearch()
        guard shouldRecenter else { return }
        Task { @MainActor in
            await Task.yield()
            centerMapOnDots(useListCoordinates: true)
        }
    }

    func confirmSearchSelection() {
        guard let result = displayedSearchResults.prefix(searchResultLimit).first, !isLoadingSearchCity else { return }
        Task {
            await selectSearchResult(result)
        }
    }

    // MARK: - Search Selection

    func selectSearchResult(_ result: CitySearchResult) async {
        isLoadingSearchCity = true
        loadingSearchResultID = result.id
        defer {
            isLoadingSearchCity = false
            loadingSearchResultID = nil
        }

        let cityName = result.title.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? result.title
        let country = result.subtitle.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? result.subtitle

        let targetListID = searchAddTargetListID
        let targetData = targetListID.map { weatherService.weatherData(for: $0) } ?? weatherService.cityWeatherData

        if let existingCity = targetData.first(where: { $0.city.name == cityName && $0.city.country == country }) {
            if let targetListID {
                searchAddTargetListID = nil
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showingSearchSheet = false
                    searchFieldPresented = false
                    searchText = ""
                }
                revealCityOnMap(existingCity, in: targetListID)
                return
            }
            handleSearchCitySelected(existingCity, canAdd: false)
            return
        }

        guard let resolvedPlace = await citySearchManager.resolvePlace(for: result) else {
            return
        }

        let tempCity = City(
            name: cityName,
            country: country,
            latitude: resolvedPlace.coordinate.latitude,
            longitude: resolvedPlace.coordinate.longitude,
            timeZoneIdentifier: resolvedPlace.timeZoneIdentifier
        )
        guard let tempCityWeather = await weatherService.fetchWeatherForCity(tempCity) else {
            return
        }

        if let targetListID {
            await weatherService.addCityToList(tempCityWeather.city, listID: targetListID)
            searchAddTargetListID = nil
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showingSearchSheet = false
                searchFieldPresented = false
                searchText = ""
            }
            revealCityOnMap(tempCityWeather, in: targetListID)
        } else {
            handleSearchCitySelected(tempCityWeather, canAdd: true)
        }
    }

    private func handleSearchCitySelected(_ cityWeather: CityWeather, canAdd: Bool) {
        if isMapRoute {
            temporaryMapSearchCity = canAdd ? cityWeather : nil
            addCityDetailCity = canAdd ? cityWeather : nil
            tappedCity = cityWeather
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showingSearchSheet = false
                searchFieldPresented = false
                searchText = ""
            }
            Task { @MainActor in
                await Task.yield()
                centerOnCityTrigger = cityWeather
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showingMapExpandedCard = true
                }
            }
        } else if canAdd {
            addCityDetailCity = cityWeather
            temporaryMapSearchCity = nil
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showingSearchSheet = false
                searchFieldPresented = false
                searchText = ""
            }
            Task { @MainActor in
                await Task.yield()
                pushRoute(.addCityDetail)
            }
        } else {
            temporaryMapSearchCity = nil
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showingSearchSheet = false
                searchFieldPresented = false
                searchText = ""
            }
            Task { @MainActor in
                await Task.yield()
                presentDetail(for: cityWeather)
            }
        }
    }
}
