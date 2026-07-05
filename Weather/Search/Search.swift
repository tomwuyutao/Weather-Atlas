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
        VStack(spacing: 16) {
            searchBar

            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !sortedSearchResults.isEmpty {
                searchSuggestionPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.colors.background.ignoresSafeArea())
        .onAppear {
            searchFieldPresented = true
            Task { @MainActor in
                await Task.yield()
                searchFieldFocused = true
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.colors.secondaryText)

            TextField(localizedString("Search for a city", locale: locale), text: $searchText)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .focused($searchFieldFocused)
                .submitLabel(.search)
                .onSubmit {
                    confirmSearchSelection()
                }

            Button {
                dismissNativeCitySearchAndRecenter()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(searchSuggestionBackground, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.38), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 18, y: 8)
        .onAppear {
            searchFieldPresented = true
            searchFieldFocused = true
        }
    }

    // MARK: - Search Suggestions

    private var searchSuggestionPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sortedSearchResults.prefix(searchResultLimit).enumerated()), id: \.element.id) { index, result in
                Button {
                    guard !isLoadingSearchCity else { return }
                    Task {
                        await selectSearchResult(result)
                    }
                } label: {
                    citySearchSuggestionRow(for: result, isSelected: index == searchSelectionIndex)
                }
                .disabled(isLoadingSearchCity)
                .buttonStyle(.plain)

                if index < min(sortedSearchResults.count, searchResultLimit) - 1 {
                    Divider()
                        .padding(.leading, 2)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: 430)
        .background(searchSuggestionBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.38), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.14), radius: 20, y: 8)
    }

    private var searchResultLimit: Int { 8 }

    // MARK: - Search Styling

    private var searchSuggestionBackground: Color {
        theme.colors.background
    }

    private var searchSuggestionSelectedBackground: Color {
        theme.colors.listCardFill.opacity(0.92)
    }

    private var searchSuggestionTitleColor: Color {
        colorScheme == .dark ? .white.opacity(0.92) : .black
    }

    private var searchSuggestionSubtitleColor: Color {
        colorScheme == .dark ? .white.opacity(0.68) : .black
    }

    // MARK: - Search Result Rows

    private func citySearchSuggestionRow(for result: CitySearchResult, isSelected: Bool) -> some View {
        let existingListName = existingCityListName(for: result)
        let titleColor = searchSuggestionTitleColor
        let subtitleColor = searchSuggestionSubtitleColor
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
            } else if loadingSearchResultID == result.id {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, rowVerticalPadding)
        .padding(.horizontal, rowHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Search Lifecycle

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
        searchAddTargetListID = nil
        loadingSearchResultID = nil
        searchSelectionIndex = 0
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
        let results = Array(sortedSearchResults.prefix(searchResultLimit))
        guard results.indices.contains(searchSelectionIndex), !isLoadingSearchCity else { return }
        let result = results[searchSelectionIndex]
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
            handleSearchCitySelected(existingCity)
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
            handleSearchCitySelected(tempCityWeather)
        }
    }

    private func handleSearchCitySelected(_ cityWeather: CityWeather) {
        if isMapRoute {
            temporaryMapSearchCity = cityWeather
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
        } else {
            addCityDetailCity = cityWeather
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showingSearchSheet = false
                searchFieldPresented = false
                searchText = ""
            }
            Task { @MainActor in
                await Task.yield()
                pushRoute(.addCityDetail)
            }
        }
    }
}
