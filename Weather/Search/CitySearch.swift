//
//  CitySearch.swift
//  Weather
//
//  Purpose: Combines Apple and Open-Meteo place search with the in-app search
//  sheet used by the floating bottom search control.
//

import CoreLocation
import Foundation
import MapKit
import SwiftUI

// MARK: - Presentation State

/// Transient state for the city-search sheet and temporary map result.
struct CitySearchPresentationState {
    /// Whether the native search sheet is presented.
    var isPresented = false
    /// Current user-entered query fragment.
    var query = ""
    /// Observable Apple and Open-Meteo search manager.
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
/// Stable presentation wrapper around an Apple or Open-Meteo place suggestion.
struct CitySearchResult: Identifiable {
    /// Deterministic provider-scoped identity.
    let id: String
    /// Primary provider-supplied place name.
    let title: String
    /// Secondary administrative and country context.
    let subtitle: String
    /// Apple completion needed to resolve a concrete map item.
    fileprivate let completion: MKLocalSearchCompletion?
    /// Metadata already supplied by Open-Meteo, avoiding a second geocoding request.
    fileprivate let resolvedPlace: CitySearchResolvedPlace?

    /// Creates a display result while retaining its MapKit resolution token.
    init(title: String, subtitle: String, completion: MKLocalSearchCompletion) {
        self.id = "city-\(completion.title)-\(completion.subtitle)"
        self.title = title
        self.subtitle = subtitle
        self.completion = completion
        self.resolvedPlace = nil
    }

    /// Creates an immediately resolvable Open-Meteo suggestion.
    init(
        openMeteoID: Int,
        title: String,
        subtitle: String,
        country: String,
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String
    ) {
        self.id = "open-meteo-\(openMeteoID)"
        self.title = title
        self.subtitle = subtitle
        self.completion = nil
        self.resolvedPlace = CitySearchResolvedPlace(
            cityName: title,
            country: country,
            coordinate: CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            ),
            timeZoneIdentifier: timeZoneIdentifier
        )
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

/// Decodable subset of Open-Meteo's GeoNames-backed geocoding response.
private struct OpenMeteoGeocodingResponse: Decodable {
    /// Relevance-ranked matches; absent when no place matches the query.
    let results: [OpenMeteoGeocodingResult]?
}

/// Location metadata needed to display and save one Open-Meteo result.
private struct OpenMeteoGeocodingResult: Decodable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let countryCode: String?
    let admin1: String?
    let admin2: String?
    let admin3: String?
    let admin4: String?
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, country, admin1, admin2, admin3, admin4, timezone
        case countryCode = "country_code"
    }
}

// MARK: - City Search Manager

/// Coordinates Apple autocomplete with Open-Meteo's global place-name search.
@Observable
class CitySearchManager: NSObject, MKLocalSearchCompleterDelegate {
    /// Current Apple place completions exposed to SwiftUI.
    var searchResults: [CitySearchResult] = []
    /// Current Open-Meteo place-name results exposed to SwiftUI.
    var openMeteoSearchResults: [CitySearchResult] = []
    /// Whether MapKit is processing a nonempty query.
    var isSearching = false
    /// Whether the Open-Meteo request for the current query is in flight.
    var isOpenMeteoSearching = false
    /// Most recent completer failure description.
    var searchErrorMessage: String?
    /// Most recent Open-Meteo request failure description.
    var openMeteoErrorMessage: String?
    /// Configured global MapKit place completer.
    private let completer: MKLocalSearchCompleter
    /// Query owning the current Open-Meteo response, used to reject stale requests.
    private var currentOpenMeteoQuery = ""

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
            openMeteoSearchResults = []
            isSearching = false
            isOpenMeteoSearching = false
            searchErrorMessage = nil
            openMeteoErrorMessage = nil
            currentOpenMeteoQuery = ""
            completer.queryFragment = ""
            return
        }
        isSearching = true
        searchErrorMessage = nil
        openMeteoSearchResults = []
        openMeteoErrorMessage = nil
        currentOpenMeteoQuery = query
        isOpenMeteoSearching = query.count >= 2
        completer.queryFragment = query
    }

    /// Fetches up to five global place-name matches from Open-Meteo.
    func searchOpenMeteo(query: String, locale: Locale) async {
        guard query.count >= 2 else {
            if currentOpenMeteoQuery == query {
                openMeteoSearchResults = []
                isOpenMeteoSearching = false
            }
            return
        }

        var components = URLComponents(
            string: "https://geocoding-api.open-meteo.com/v1/search"
        )
        components?.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "5"),
            URLQueryItem(
                name: "language",
                value: locale.language.languageCode?.identifier ?? "en"
            ),
            URLQueryItem(name: "format", value: "json")
        ]

        guard let url = components?.url else {
            if currentOpenMeteoQuery == query {
                openMeteoSearchResults = []
                isOpenMeteoSearching = false
                openMeteoErrorMessage = URLError(.badURL).localizedDescription
            }
            return
        }

        do {
            // Open-Meteo's public endpoint is suitable for the app's current
            // noncommercial use; a commercial release requires its customer endpoint.
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled, currentOpenMeteoQuery == query else { return }
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                throw URLError(.badServerResponse)
            }

            let decoded = try JSONDecoder().decode(OpenMeteoGeocodingResponse.self, from: data)
            openMeteoSearchResults = (decoded.results ?? []).compactMap { result in
                guard let timeZoneIdentifier = result.timezone,
                      TimeZone(identifier: timeZoneIdentifier) != nil else {
                    return nil
                }

                var subtitleParts: [String] = []
                for part in [result.admin4, result.admin3, result.admin2, result.admin1, result.country] {
                    guard let part,
                          !part.isEmpty,
                          !subtitleParts.contains(where: {
                              $0.localizedCaseInsensitiveCompare(part) == .orderedSame
                          }),
                          part.localizedCaseInsensitiveCompare(result.name) != .orderedSame else {
                        continue
                    }
                    subtitleParts.append(part)
                }

                return CitySearchResult(
                    openMeteoID: result.id,
                    title: result.name,
                    subtitle: subtitleParts.joined(separator: ", "),
                    country: result.country ?? result.countryCode ?? "",
                    latitude: result.latitude,
                    longitude: result.longitude,
                    timeZoneIdentifier: timeZoneIdentifier
                )
            }
            .prefix(5)
            .map { $0 }
            openMeteoErrorMessage = nil
            isOpenMeteoSearching = false
        } catch is CancellationError {
            return
        } catch {
            guard currentOpenMeteoQuery == query else { return }
            openMeteoSearchResults = []
            openMeteoErrorMessage = error.localizedDescription
            isOpenMeteoSearching = false
        }
    }

    /// Resolves one completion into coordinate, canonical labels, and timezone.
    func resolvePlace(for result: CitySearchResult) async -> CitySearchResolvedPlace? {
        if let resolvedPlace = result.resolvedPlace {
            return resolvedPlace
        }
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
        searchResults = completer.results.prefix(5).map { completion in
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
                // Apple remains first for rich local places; Open-Meteo follows
                // with globally available cities and administrative areas.
                if !citySearchState.manager.searchResults.isEmpty {
                    citySearchSuggestionSection(
                        sourceName: "Apple Maps",
                        results: Array(citySearchState.manager.searchResults.prefix(5))
                    )
                }

                if !citySearchState.manager.openMeteoSearchResults.isEmpty {
                    citySearchSuggestionSection(
                        sourceName: "Open-Meteo",
                        results: Array(citySearchState.manager.openMeteoSearchResults.prefix(5))
                    )
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
            .defaultFocus($searchFieldFocused, true)
            .onSubmit(of: .search) {
                // Confirm the first resolved result when search is idle.
                guard let result = displayedSearchResults.first,
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

    /// Destination selected before search opens, defaulting to the active list for direct entry points.
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
            if citySearchState.manager.isSearching
                || citySearchState.manager.isOpenMeteoSearching
                || !citySearchState.isSettled {
                ProgressView()
                    .controlSize(.large)
            } else if citySearchState.manager.searchErrorMessage != nil,
                      citySearchState.manager.openMeteoErrorMessage != nil {
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

    /// Builds one provider-labelled group capped at five suggestions.
    private func citySearchSuggestionSection(
        sourceName: String,
        results: [CitySearchResult]
    ) -> some View {
        Section {
            ForEach(results.prefix(5)) { result in
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
        } header: {
            Text(verbatim: sourceName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme.colors.secondaryText)
                .textCase(nil)
        }
    }

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

    /// Current suggestions in provider order for keyboard submission and empty states.
    var displayedSearchResults: [CitySearchResult] {
        Array(citySearchState.manager.searchResults.prefix(5))
            + Array(citySearchState.manager.openMeteoSearchResults.prefix(5))
    }

    // MARK: - Search Lifecycle

    /// Opens Add City search targeting the currently active list.
    func presentAddCitySearch() {
        citySearchState.targetListID = weatherService.activeListID
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isMapCardPresented = false
            selectedMapCity = nil
            citySearchState.isPresented = true
        }
        searchFieldFocused = true
    }

    /// Debounces query changes before updating both search providers.
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
            await citySearchState.manager.searchOpenMeteo(
                query: trimmedQuery,
                locale: locale
            )
            guard !Task.isCancelled,
                  citySearchState.query.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedQuery else {
                return
            }
            citySearchState.isSettled = true
        }
    }

    /// Closes search and restores the active list's map framing.
    func dismissNativeCitySearchAndRecenter() {
        let shouldRecenter = citySearchState.isPresented
            || !citySearchState.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !citySearchState.manager.searchResults.isEmpty
            || !citySearchState.manager.openMeteoSearchResults.isEmpty
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
