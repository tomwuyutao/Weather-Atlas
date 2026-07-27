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
    /// Whether the native search sheet is presented.
    var isPresented = false
    /// Current user-entered query fragment.
    var query = ""
    /// Observable MapKit completion manager.
    var manager = CitySearchManager()
    /// Whether a selected completion is resolving and fetching weather.
    var isLoading = false
    /// Completion identity whose row displays progress.
    var loadingResultID: String?
    /// Optional transient search confirmation copy.
    var confirmation: String?
    /// Cancellable debounce between typing and MapKit updates.
    var debounceTask: Task<Void, Never>?
    /// Whether the current query has completed its debounce interval.
    var isSettled = true
    /// Destination list chosen for the searched city.
    var targetListID: CityListID?
    /// Unsaved weather result displayed temporarily on the full map.
    var temporaryMapCity: CityWeather?
}

// MARK: - Search Result
/// Stable presentation wrapper around a MapKit completion.
struct CitySearchResult: Identifiable {
    /// Deterministic identity derived from completion title and subtitle.
    let id: String
    /// Primary MapKit completion text.
    let title: String
    /// Secondary MapKit completion context.
    let subtitle: String
    /// Source completion needed to resolve a concrete map item.
    fileprivate let completion: MKLocalSearchCompletion?

    /// Creates a display result while retaining its MapKit resolution token.
    init(title: String, subtitle: String, completion: MKLocalSearchCompletion) {
        self.id = "city-\(completion.title)-\(completion.subtitle)"
        self.title = title
        self.subtitle = subtitle
        self.completion = completion
    }

}

/// Fully resolved place metadata required before requesting weather.
struct CitySearchResolvedPlace {
    /// Exact visible completion title selected by the user.
    let cityName: String
    /// Country or ISO region supplied by MapKit.
    let country: String
    /// Geographic coordinate used by WeatherKit.
    let coordinate: CLLocationCoordinate2D
    /// Required real timezone identifier.
    let timeZoneIdentifier: String
}

// MARK: - City Search Manager

/// Wraps `MKLocalSearchCompleter` callbacks in observable search state.
@Observable
class CitySearchManager: NSObject, MKLocalSearchCompleterDelegate {
    /// Current place completions exposed to SwiftUI.
    var searchResults: [CitySearchResult] = []
    /// Whether MapKit is processing a nonempty query.
    var isSearching = false
    /// Most recent completer failure description.
    var searchErrorMessage: String?
    /// Configured global MapKit place completer.
    private let completer: MKLocalSearchCompleter

    /// Configures an unrestricted global completer and installs this manager as delegate.
    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = [
            .address,
            .pointOfInterest,
            .physicalFeature,
            .query
        ]
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)
        )
    }

    /// Clears state for an empty query or submits a new completion fragment.
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

    /// Resolves one completion into coordinate, canonical labels, and timezone.
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
                // The visible selected result owns the display name. MapKit
                // resolution supplies metadata without renaming the place.
                cityName: result.title,
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

    /// Uses reverse geocoding only when the MapKit item omitted timezone metadata.
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

    /// Publishes the latest successful MapKit completion batch.
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

    /// Clears stale completions and exposes a MapKit completion failure.
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        isSearching = false
        searchResults = []
        searchErrorMessage = error.localizedDescription
    }
}

extension ContentView {

    // MARK: - Search Presentation

    /// Builds the native search sheet, suggestions, progress, and empty states.
    var searchSheet: some View {
        NavigationStack {
            List {
                Section {
                    Menu {
                        ForEach(managedLists) { listID in
                            Button {
                                citySearchState.targetListID = listID
                            } label: {
                                HStack {
                                    Text(listID.localizedDisplayName(locale: locale))
                                    if listID.rawValue == citySearchDestinationListID.rawValue {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "list.bullet")
                                .foregroundStyle(theme.colors.accent)

                            Text(localizedString("Add to List", locale: locale))
                                .foregroundStyle(theme.colors.primaryText)

                            Spacer(minLength: 12)

                            Text(citySearchDestinationListID.localizedDisplayName(locale: locale))
                                .foregroundStyle(theme.colors.secondaryText)
                                .lineLimit(1)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(theme.colors.secondaryText)
                        }
                        .contentShape(Rectangle())
                    }
                    .menuOrder(.fixed)
                    .tint(theme.colors.accent)
                }
                .listRowBackground(theme.colors.settingsRowFill)

                // Keep a broad but bounded, naturally scrollable suggestion list.
                Section {
                    ForEach(Array(displayedSearchResults.prefix(20)), id: \.id) { result in
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
            }
            .overlay {
                citySearchStatusOverlay
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(localizedString("Add City", locale: locale))
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
                prompt: Text(localizedString("Search for a place", locale: locale))
            )
            .searchFocused($searchFieldFocused)
            .onSubmit(of: .search) {
                // Confirm the first resolved result when search is idle.
                guard let result = displayedSearchResults.prefix(20).first,
                      !citySearchState.isLoading else { return }
                Task {
                    await selectSearchResult(result)
                }
            }
        }
        .background(theme.colors.background.ignoresSafeArea())
        .onAppear {
            searchFieldFocused = true
        }
    }

    /// Destination selected by the search context row, defaulting to the active list.
    var citySearchDestinationListID: CityListID {
        guard let targetListID = citySearchState.targetListID,
              managedLists.contains(where: { $0.rawValue == targetListID.rawValue }) else {
            return weatherService.activeListID
        }
        return targetListID
    }

    @ViewBuilder
    /// Selects loading, error, prompt, and no-results overlays for search state.
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

    // MARK: - Search Result Rows

    /// Builds one completion row with per-result resolution progress.
    private func citySearchSuggestionRow(for result: CitySearchResult, isLoading: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(
                        isLoading ? theme.colors.primaryText.opacity(0.45) : theme.colors.primaryText
                    )
                    .lineLimit(1)

                Text(result.subtitle)
                    .font(.caption)
                    .foregroundStyle(
                        isLoading ? theme.colors.secondaryText.opacity(0.45) : theme.colors.secondaryText
                    )
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        .frame(minHeight: 46)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Current MapKit completions in relevance order.
    var displayedSearchResults: [CitySearchResult] {
        citySearchState.manager.searchResults
    }

    // MARK: - Search Lifecycle

    /// Opens Add City search with an explicit list destination.
    func presentAddCitySearch(to listID: CityListID? = nil) {
        citySearchState.targetListID = listID ?? weatherService.activeListID
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isMapCardPresented = false
            selectedMapCity = nil
            citySearchState.isPresented = true
        }
        searchFieldFocused = true
    }

    /// Debounces query changes before updating the MapKit completer.
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

    /// Closes search and restores the active list's map framing.
    func dismissNativeCitySearchAndRecenter() {
        let shouldRecenter = citySearchState.isPresented
            || !citySearchState.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !citySearchState.manager.searchResults.isEmpty
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            citySearchState.isPresented = false
            searchFieldFocused = false
        }
        // Cancel debounce work and clear all transient search state.
        citySearchState.query = ""
        citySearchState.manager.search(query: "")
        citySearchState.debounceTask?.cancel()
        citySearchState.debounceTask = nil
        citySearchState.isSettled = true
        citySearchState.targetListID = nil
        citySearchState.loadingResultID = nil
        guard shouldRecenter else { return }
        centerMapOnDots()
    }

    // MARK: - Search Selection

    /// Resolves a completion and saves it directly to the selected list.
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

        let targetListID = citySearchDestinationListID

        if weatherService.cityListCoordinates(for: targetListID)
            .contains(where: { weatherService.citiesMatch($0, tempCity) }) {
            citySearchState.targetListID = nil
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                citySearchState.isPresented = false
                citySearchState.query = ""
            }
            await switchToList(targetListID)
            return
        }

        guard let tempCityWeather = await weatherService.fetchWeatherForCity(tempCity) else {
            return
        }

        let didAdd = weatherService.addCityToList(tempCityWeather, listID: targetListID)
        citySearchState.targetListID = nil
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            citySearchState.isPresented = false
            citySearchState.query = ""
        }
        await switchToList(targetListID)
        if didAdd {
            showCityAddedConfirmation(
                cityAddedConfirmationMessage(
                    cityName: localizedCityName(for: tempCityWeather.city),
                    listName: targetListID.localizedDisplayName(locale: locale)
                )
            )
        }
    }

}
