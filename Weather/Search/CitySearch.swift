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
                    // Accessibility: Treat each styled result as one control and announce its
                    // location, saved-list status, and loading state together.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(result.title)
                    .accessibilityValue(
                        citySearchAccessibilityValue(
                            for: result,
                            isLoading: citySearchState.loadingResultID == result.id
                        )
                    )
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
        // Accessibility: Make the standard escape gesture a reliable way out of the
        // modal search flow even while the keyboard or results list has focus.
        .accessibilityAction(.escape) {
            dismissNativeCitySearchAndRecenter()
        }
        .onAppear {
            searchFieldFocused = true
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
        let existingListName = citySearchState.isSettled ? existingCityListName(for: result) : nil
        let titleColor = isLoading ? searchSuggestionTitleColor.opacity(0.45) : searchSuggestionTitleColor
        let subtitleColor = isLoading ? searchSuggestionSubtitleColor.opacity(0.45) : searchSuggestionSubtitleColor
        let rowSpacing: CGFloat = 10
        let titleFont: Font = .body.weight(.medium)
        let subtitleFont: Font = .caption
        let statusFont: Font = .caption2.weight(.medium)
        let statusBoldFont: Font = .caption2.weight(.bold)
        let rowVerticalPadding: CGFloat = 8
        let rowHorizontalPadding: CGFloat = 2
        // Accessibility: Stack result metadata when accessibility Dynamic Type would crowd it.
        let rowLayout: AnyLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: rowSpacing))

        return rowLayout {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(titleFont)
                    .foregroundStyle(titleColor)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

                Text(result.subtitle)
                    .font(subtitleFont)
                    .foregroundStyle(subtitleColor)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }

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
                        .accessibilityHidden(true)
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

    // MARK: - Accessibility - Result Descriptions

    private func citySearchAccessibilityValue(for result: CitySearchResult, isLoading: Bool) -> String {
        var parts = [result.subtitle].filter { !$0.isEmpty }
        if let existingListName = citySearchState.isSettled ? existingCityListName(for: result) : nil {
            parts.append("\(localizedString("In list", locale: locale)) \(existingListName)")
        }
        if isLoading {
            parts.append(localizedString("Loading Weather", locale: locale))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Result Identity and Sorting

    private func searchCityDisplayHint(for result: CitySearchResult) -> (name: String, country: String) {
        let name = result.title.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? result.title
        let country = result.subtitle.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? result.subtitle
        return (name, country)
    }

    func existingCityListName(for result: CitySearchResult) -> String? {
        // Completion strings are only a display hint. Selection resolves a
        // structured MapKit placemark and uses coordinates for identity.
        let identity = searchCityDisplayHint(for: result)
        if let targetListID = citySearchState.targetListID {
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
        citySearchState.manager.searchResults
            .sorted { a, b in
                let aExists = isExistingSearchCity(a)
                let bExists = isExistingSearchCity(b)
                if aExists != bExists { return aExists }
                return false
            }
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
        let targetData = targetListID.map { weatherService.weatherData(for: $0) } ?? weatherService.cityWeatherData

        if let existingCity = targetData.first(where: { weatherService.citiesMatch($0.city, tempCity) }) {
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
            await weatherService.addCityToList(tempCityWeather.city, listID: targetListID)
            citySearchState.targetListID = nil
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                citySearchState.isPresented = false
                citySearchState.query = ""
            }
            revealCityOnMap(tempCityWeather, in: targetListID)
            showCityAddedConfirmation("\(localizedCityName(for: tempCityWeather.city)) was added to \(targetListID.localizedDisplayName(locale: locale)).")
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
