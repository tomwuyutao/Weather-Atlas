//
//  AddCitySearchView.swift
//  Weather
//

import SwiftUI
import MapKit

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

            Text(searchText.isEmpty ? "Search for a city or place" : "No results")
                .font(.avenir(.title3, weight: .medium))

            if !searchText.isEmpty {
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
