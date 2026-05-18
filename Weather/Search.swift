//
//  Search.swift
//  Weather
//
//  Native city search, add-city search, and MapKit search plumbing.
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
            return response.mapItems.first?.location.coordinate
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

// MARK: - Add City Search View

struct AddCitySearchView: View {
    let cities: [CityWeather]
    @State var citySearchManager: CitySearchManager
    let weatherService: WeatherService
    let onCitySelected: (CityWeather) -> Void

    @State private var searchText: String = ""
    @State private var isSearchPresented = true
    @State private var isLoadingCity = false
    @Environment(\.dismiss) private var dismiss

    private func isExistingCity(_ result: CitySearchResult) -> Bool {
        let name = result.title.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? result.title
        let country = result.subtitle.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? result.subtitle
        return cities.contains(where: { $0.city.name == name && $0.city.country == country })
    }

    private var sortedSearchResults: [CitySearchResult] {
        citySearchManager.searchResults.sorted { a, b in
            let aExists = isExistingCity(a)
            let bExists = isExistingCity(b)
            if aExists != bExists { return aExists }
            return false
        }
    }

    var body: some View {
        searchContent
            .navigationTitle("Add City")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .searchable(
                text: $searchText,
                isPresented: $isSearchPresented,
                prompt: Text("Search for a city or place")
            )
            .searchSuggestions {
                nativeSearchSuggestions
            }
            .onChange(of: searchText) { _, newValue in
                citySearchManager.search(query: newValue)
            }
            .onAppear {
                isSearchPresented = true
            }
    }

    private var searchContent: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: searchText.isEmpty ? "magnifyingglass" : "map")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            if !searchText.isEmpty {
                Text("No results")
                    .font(.avenir(.title3, weight: .medium))

                Text("Try a different search term")
                    .font(.avenir(.body))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.shared.colors.background.ignoresSafeArea())
    }

    @ViewBuilder
    private var nativeSearchSuggestions: some View {
        ForEach(sortedSearchResults) { result in
            Button {
                guard !isLoadingCity else { return }
                Task {
                    await selectSearchResult(result)
                }
            } label: {
                nativeSearchSuggestionRow(for: result)
            }
            .disabled(isLoadingCity)
        }
    }

    private func nativeSearchSuggestionRow(for result: CitySearchResult) -> some View {
        let existing = isExistingCity(result)

        return HStack(spacing: 10) {
            Image(systemName: existing ? "checkmark.circle.fill" : "magnifyingglass")
                .foregroundStyle(existing ? Color.secondary : Color.primary.opacity(0.7))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.avenir(.body, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(result.subtitle)
                    .font(.avenir(.caption, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if existing {
                Text("Added")
                    .font(.avenir(.caption2, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if isLoadingCity {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 3)
    }

    private func selectSearchResult(_ result: CitySearchResult) async {
        isLoadingCity = true
        defer { isLoadingCity = false }

        let cityName = result.title.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? result.title
        let country = result.subtitle.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? result.subtitle

        if let existingCity = cities.first(where: { $0.city.name == cityName && $0.city.country == country }) {
            onCitySelected(existingCity)
            return
        }

        guard let coordinate = await citySearchManager.resolveCoordinate(for: result) else {
            return
        }

        let tempCity = City(name: cityName, country: country, latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let tempCityWeather = await weatherService.fetchWeatherForCity(tempCity) else {
            return
        }

        onCitySelected(tempCityWeather)
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
                isPresented: $showingInlineSearch,
                placement: placement,
                prompt: Text(localizedString("Search for a city", locale: locale))
            )
            .searchSuggestions {
                if showingInlineSearch {
                    nativeCitySearchSuggestions
                }
            }
            .onChange(of: inlineSearchText) { _, newValue in
                inlineSearchManager.search(query: newValue)
                inlineSearchSelectionIndex = 0
            }
            .onChange(of: showingInlineSearch) { _, isPresented in
                if !isPresented {
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
        let existing = inlineIsExistingCity(result)

        return HStack(spacing: 10) {
            Image(systemName: existing ? "checkmark.circle.fill" : "magnifyingglass")
                .foregroundStyle(existing ? theme.colors.secondaryText : theme.colors.primaryText.opacity(0.7))
                .frame(width: 20)

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

            if existing {
                Text(localizedString("Added", locale: locale))
                    .font(.avenir(.caption2, weight: .medium))
                    .foregroundStyle(theme.colors.secondaryText)
            } else if inlineIsLoadingCity {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 3)
    }

    func inlineIsExistingCity(_ result: CitySearchResult) -> Bool {
        let name = result.title.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? result.title
        let country = result.subtitle.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? result.subtitle
        let data = inlineAddTargetListID.map { weatherService.weatherData(for: $0) } ?? weatherService.cityWeatherData
        return data.contains(where: { $0.city.name == name && $0.city.country == country })
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
    }

    func dismissInlineSearch() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingInlineSearch = false
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
                inlineSearchText = ""
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showingAddCityDetail = true
                pushIPhoneRoute(.addCityDetail)
            }
        }
    }
}

#Preview("Add City Search") {
    NavigationStack {
        AddCitySearchView(
            cities: [],
            citySearchManager: CitySearchManager(),
            weatherService: WeatherService(),
            onCitySelected: { _ in }
        )
    }
}
