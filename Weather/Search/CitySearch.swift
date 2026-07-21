//
//  CitySearch.swift
//  Weather
//
//  Purpose: Wraps MapKit city search and the in-app search sheet used by
//  the floating bottom search control.
//

import SwiftUI
import CoreLocation
import MapKit

// MARK: - Presentation State

/// Transient state for the city-search sheet and temporary map result.
struct CitySearchPresentationState {
    var isPresented = false
    var query = ""
    var manager = CitySearchManager()
    var isLoading = false
    var loadingResultID: String?
    var confirmation: String?
    var debounceTask: Task<Void, Never>?
    var isSettled = true
    var targetListID: CityListID?
    var temporaryMapCity: CityWeather?
    var showsListPicker = false
}

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
    let cityName: String
    let country: String
    let coordinate: CLLocationCoordinate2D
    let timeZoneIdentifier: String
}

// MARK: - City Search Manager

@Observable
class CitySearchManager: NSObject, MKLocalSearchCompleterDelegate {
    var searchResults: [CitySearchResult] = []
    var isSearching = false
    var searchErrorMessage: String?
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
            isSearching = false
            searchErrorMessage = nil
            return
        }
        isSearching = true
        searchErrorMessage = nil
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
                cityName: mapItem.placemark.locality
                    ?? mapItem.placemark.subAdministrativeArea
                    ?? mapItem.name
                    ?? result.title,
                country: mapItem.placemark.country
                    ?? mapItem.placemark.isoCountryCode
                    ?? "",
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
        isSearching = false
        searchErrorMessage = nil
        searchResults = completer.results.map { completion in
            CitySearchResult(
                title: completion.title,
                subtitle: completion.subtitle,
                completion: completion
            )
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        isSearching = false
        searchResults = []
        searchErrorMessage = error.localizedDescription
    }
}

extension ContentView {

    // MARK: - Search Presentation

    var searchSheet: some View {
        NavigationStack {
            List {
                ForEach(Array(displayedSearchResults.prefix(searchResultLimit)), id: \.id) { result in
                    Button {
                        guard !citySearchState.isLoading else { return }
                        Task {
                            await selectSearchResult(result)
                        }
                    } label: {
                        citySearchSuggestionRow(
                            for: result,
                            isLoading: citySearchState.loadingResultID == result.id
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(citySearchState.isLoading)
                    .listRowBackground(theme.colors.background)
                }
            }
            .overlay {
                citySearchStatusOverlay
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
                }
            }
            .searchable(
                text: $citySearchState.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(localizedString("Search for a city", locale: locale))
            )
            .searchFocused($searchFieldFocused)
            .onSubmit(of: .search) {
                confirmSearchSelection()
            }
        }
        .background(theme.colors.background.ignoresSafeArea())
        .onAppear {
            searchFieldFocused = true
        }
    }

    private var searchResultLimit: Int { 8 }

    @ViewBuilder
    private var citySearchStatusOverlay: some View {
        let trimmedQuery = citySearchState.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty, displayedSearchResults.isEmpty {
            if citySearchState.manager.isSearching || !citySearchState.isSettled {
                ProgressView()
                    .controlSize(.large)
            } else if citySearchState.manager.searchErrorMessage != nil {
                ContentUnavailableView(
                    localizedString("Search Unavailable", locale: locale),
                    systemImage: "wifi.exclamationmark",
                    description: Text(localizedString("Check your connection and try again.", locale: locale))
                )
            } else {
                ContentUnavailableView.search(text: trimmedQuery)
            }
        }
    }

    // MARK: - Search Styling

    private var searchSuggestionTitleColor: Color {
        theme.colors.primaryText
    }

    private var searchSuggestionSubtitleColor: Color {
        theme.colors.secondaryText
    }

    // MARK: - Search Result Rows

    private func citySearchSuggestionRow(for result: CitySearchResult, isLoading: Bool) -> some View {
        let titleColor = isLoading ? searchSuggestionTitleColor.opacity(0.45) : searchSuggestionTitleColor
        let subtitleColor = isLoading ? searchSuggestionSubtitleColor.opacity(0.45) : searchSuggestionSubtitleColor
        let rowSpacing: CGFloat = 10
        let titleFont: Font = .body.weight(.medium)
        let subtitleFont: Font = .caption
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

            if isLoading {
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

    var sortedSearchResults: [CitySearchResult] {
        citySearchState.manager.searchResults
    }

    var displayedSearchResults: [CitySearchResult] {
        citySearchState.isSettled ? sortedSearchResults : citySearchState.manager.searchResults
    }

    // MARK: - Search Lifecycle

    func scheduleCitySearch(for query: String) {
        citySearchState.debounceTask?.cancel()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            citySearchState.isSettled = true
            citySearchState.manager.search(query: "")
            return
        }

        citySearchState.isSettled = false
        citySearchState.debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            citySearchState.manager.search(query: trimmedQuery)
            citySearchState.isSettled = true
        }
    }

    func activateSearch() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingMapExpandedCard = false
            selectedMapCity = nil
            citySearchState.isPresented = true
        }
        searchFieldFocused = true
    }

    func resetNativeCitySearch() {
        citySearchState.query = ""
        citySearchState.manager.search(query: "")
        citySearchState.debounceTask?.cancel()
        citySearchState.debounceTask = nil
        citySearchState.isSettled = true
        citySearchState.targetListID = nil
        citySearchState.loadingResultID = nil
    }

    func dismissNativeCitySearchAndRecenter() {
        let shouldRecenter = citySearchState.isPresented
            || !citySearchState.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !citySearchState.manager.searchResults.isEmpty
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            citySearchState.isPresented = false
            searchFieldFocused = false
        }
        resetNativeCitySearch()
        guard shouldRecenter else { return }
        centerMapOnDots(useListCoordinates: true)
    }

    func confirmSearchSelection() {
        guard let result = displayedSearchResults.prefix(searchResultLimit).first, !citySearchState.isLoading else { return }
        Task {
            await selectSearchResult(result)
        }
    }

    // MARK: - Search Selection

    func selectSearchResult(_ result: CitySearchResult) async {
        citySearchState.isLoading = true
        citySearchState.loadingResultID = result.id
        defer {
            citySearchState.isLoading = false
            citySearchState.loadingResultID = nil
        }

        guard let resolvedPlace = await citySearchState.manager.resolvePlace(for: result) else {
            return
        }

        let cityName = resolvedPlace.cityName
        let country = resolvedPlace.country
        let tempCity = City(
            name: cityName,
            country: country,
            latitude: resolvedPlace.coordinate.latitude,
            longitude: resolvedPlace.coordinate.longitude,
            timeZoneIdentifier: resolvedPlace.timeZoneIdentifier
        )

        let targetListID = citySearchState.targetListID
        let targetList = targetListID ?? weatherService.activeListID
        let targetData = targetListID.map { weatherService.weatherData(for: $0) } ?? weatherService.cityWeatherData

        if let savedCity = weatherService.cityListCoordinates(for: targetList)
            .first(where: { weatherService.citiesMatch($0, tempCity) }) {
            let existingCity: CityWeather?
            if let loadedCity = targetData.first(where: {
                weatherService.citiesMatch($0.city, savedCity)
            }) {
                existingCity = loadedCity
            } else {
                existingCity = await weatherService.switchList(
                    to: targetList,
                    prioritizing: savedCity
                )
            }
            guard let existingCity else { return }

            if let targetListID {
                citySearchState.targetListID = nil
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    citySearchState.isPresented = false
                    citySearchState.query = ""
                }
                revealCityOnMap(existingCity, in: targetListID)
                return
            }
            handleSearchCitySelected(existingCity, canAdd: false)
            return
        }

        guard let tempCityWeather = await weatherService.fetchWeatherForCity(tempCity) else {
            return
        }

        if let targetListID {
            let didAdd = weatherService.addCityToList(tempCityWeather, listID: targetListID)
            citySearchState.targetListID = nil
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                citySearchState.isPresented = false
                citySearchState.query = ""
            }
            revealCityOnMap(tempCityWeather, in: targetListID)
            if didAdd {
                showCityAddedConfirmation(
                    cityAddedConfirmationMessage(
                        cityName: localizedCityName(for: tempCityWeather.city),
                        listName: targetListID.localizedDisplayName(locale: locale)
                    )
                )
            }
        } else {
            handleSearchCitySelected(tempCityWeather, canAdd: true)
        }
    }

    private func handleSearchCitySelected(_ cityWeather: CityWeather, canAdd: Bool) {
        citySearchState.temporaryMapCity = isMapRoute && canAdd ? cityWeather : nil
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            citySearchState.isPresented = false
            citySearchState.query = ""
        }

        if isMapRoute {
            centerMap(on: cityWeather)
            selectedMapCity = cityWeather
        } else if canAdd {
            pushRoute(.addCityDetail(cityWeather))
        } else {
            presentDetail(for: cityWeather)
        }
    }

}
