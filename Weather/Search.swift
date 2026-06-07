//
//  Search.swift
//  Weather
//
//  Native city search and MapKit search plumbing.
//

import SwiftUI
import CoreLocation
import MapKit

// MARK: - Search Result

struct CitySearchResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    fileprivate let completion: MKLocalSearchCompletion
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

    func resolveCoordinate(for result: CitySearchResult) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request(completion: result.completion)
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            return response.mapItems.first?.placemark.location?.coordinate
        } catch {
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

    // MARK: - Native City Search

    var nativeCitySearchScreen: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: inlineSearchText.isEmpty ? "magnifyingglass" : "map")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(theme.colors.secondaryText.opacity(0.7))

            if !inlineSearchText.isEmpty {
                Text(localizedString("No results", locale: locale))
                    .font(.avenir(.title3, weight: .medium))
                    .foregroundStyle(theme.colors.primaryText)

                Text(localizedString("Try a different search term", locale: locale))
                    .font(.avenir(.body, weight: .regular))
                    .foregroundStyle(theme.colors.secondaryText)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background.ignoresSafeArea())
    }

    @ViewBuilder
    func nativeCitySearch<Content: View>(
        _ content: Content,
        placement: SearchFieldPlacement = .automatic
    ) -> some View {
        content
            .searchable(
                text: $inlineSearchText,
                isPresented: $inlineSearchFieldPresented,
                placement: placement,
                prompt: Text(localizedString("Search for a city", locale: locale))
            )
            .searchSuggestions {
                if showingInlineSearch || inlineSearchFieldPresented {
                    nativeCitySearchSuggestions
                }
            }
            .onChange(of: inlineSearchText) { _, newValue in
                inlineSearchManager.search(query: newValue)
                inlineSearchSelectionIndex = 0
            }
            .onChange(of: inlineSearchFieldPresented) { _, isPresented in
                if !isPresented {
                    showingInlineSearch = false
                    resetNativeCitySearch()
                }
            }
            .onSubmit(of: .search) {
                confirmInlineSearchSelection()
            }
    }

    @ViewBuilder
    var nativeCitySearchSuggestions: some View {
        ForEach(Array(inlineSortedSearchResults.prefix(8))) { result in
            Button {
                guard !inlineIsLoadingCity else { return }
                Task {
                    await inlineSelectSearchResult(result)
                }
            } label: {
                nativeCitySearchSuggestionRow(for: result)
            }
            .disabled(inlineIsLoadingCity)
        }
    }

    private func nativeCitySearchSuggestionRow(for result: CitySearchResult) -> some View {
        let existingListName = inlineExistingCityListName(for: result)

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.avenir(.body, weight: .medium))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)

                Text(result.subtitle)
                    .font(.avenir(.caption, weight: .regular))
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let existingListName {
                HStack(spacing: 6) {
                    (Text(localizedString("In list", locale: locale) + " ")
                        .font(.avenir(.caption2, weight: .medium))
                    + Text(existingListName)
                        .font(.avenir(.caption2, weight: .bold)))
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.colors.secondaryText)
                }
            } else if inlineIsLoadingCity {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 3)
    }

    private func inlineCityIdentity(for result: CitySearchResult) -> (name: String, country: String) {
        let name = result.title.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? result.title
        let country = result.subtitle.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? result.subtitle
        return (name, country)
    }

    func inlineExistingCityListName(for result: CitySearchResult) -> String? {
        let identity = inlineCityIdentity(for: result)
        if let targetListID = inlineAddTargetListID {
            let cities = weatherService.cityListCoordinates(for: targetListID)
            if cities.contains(where: { $0.name == identity.name && $0.country == identity.country }) {
                return targetListID.localizedDisplayName(locale: locale)
            }
            return nil
        }

        return weatherService.listContainingCity(named: identity.name, country: identity.country)?.localizedDisplayName(locale: locale)
    }

    func inlineIsExistingCity(_ result: CitySearchResult) -> Bool {
        inlineExistingCityListName(for: result) != nil
    }

    var inlineSortedSearchResults: [CitySearchResult] {
        inlineSearchManager.searchResults.sorted { a, b in
            let aExists = inlineIsExistingCity(a)
            let bExists = inlineIsExistingCity(b)
            if aExists != bExists { return aExists }
            return false
        }
    }

    func activateInlineSearch() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingMapExpandedCard = false
            tappedCity = nil
            showingInlineSearch = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            inlineSearchFieldPresented = true
        }
    }

    func dismissInlineSearch() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingInlineSearch = false
            inlineSearchFieldPresented = false
        }
        resetNativeCitySearch()
    }

    func resetNativeCitySearch() {
        inlineSearchText = ""
        inlineSearchManager.search(query: "")
        inlineAddTargetListID = nil
        inlineSearchSelectionIndex = 0
    }

    func moveInlineSearchSelection(_ delta: Int) {
        let count = min(6, inlineSortedSearchResults.count)
        guard count > 0 else { return }
        inlineSearchSelectionIndex = (inlineSearchSelectionIndex + delta + count) % count
    }

    func confirmInlineSearchSelection() {
        let results = Array(inlineSortedSearchResults.prefix(6))
        guard results.indices.contains(inlineSearchSelectionIndex), !inlineIsLoadingCity else { return }
        let result = results[inlineSearchSelectionIndex]
        Task {
            await inlineSelectSearchResult(result)
        }
    }

    func inlineSelectSearchResult(_ result: CitySearchResult) async {
        inlineIsLoadingCity = true
        defer { inlineIsLoadingCity = false }

        let cityName = result.title.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? result.title
        let country = result.subtitle.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? result.subtitle

        let targetListID = inlineAddTargetListID
        let targetData = targetListID.map { weatherService.weatherData(for: $0) } ?? weatherService.cityWeatherData

        if let existingCity = targetData.first(where: { $0.city.name == cityName && $0.city.country == country }) {
            if let targetListID {
                inlineAddTargetListID = nil
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showingInlineSearch = false
                    inlineSearchFieldPresented = false
                    inlineSearchText = ""
                }
                revealCityOnMap(existingCity, in: targetListID)
                return
            }
            handleInlineSearchCitySelected(existingCity)
            return
        }

        guard let coordinate = await inlineSearchManager.resolveCoordinate(for: result) else {
            return
        }

        let tempCity = City(name: cityName, country: country, latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let tempCityWeather = await weatherService.fetchWeatherForCity(tempCity) else {
            return
        }

        if let targetListID {
            await weatherService.addCityToList(tempCityWeather.city, listID: targetListID)
            inlineAddTargetListID = nil
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showingInlineSearch = false
                inlineSearchFieldPresented = false
                inlineSearchText = ""
            }
            revealCityOnMap(tempCityWeather, in: targetListID)
        } else {
            handleInlineSearchCitySelected(tempCityWeather)
        }
    }

    private func handleInlineSearchCitySelected(_ cityWeather: CityWeather) {
        if selectedTab == 1 {
            previewCity = cityWeather
            previewSearchText = cityWeather.city.name
            tappedCity = cityWeather
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showingInlineSearch = false
                inlineSearchFieldPresented = false
                inlineSearchText = ""
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                centerOnCityTrigger = cityWeather
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showingMapExpandedCard = true
                }
            }
        } else {
            addCityDetailCity = cityWeather
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showingInlineSearch = false
                inlineSearchFieldPresented = false
                inlineSearchText = ""
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showingAddCityDetail = true
                pushIPhoneRoute(.addCityDetail)
            }
        }
    }
}
