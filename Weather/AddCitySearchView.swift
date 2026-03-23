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
    @State private var isLoadingCity = false
    @State private var isSearchFieldFocused = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFieldFocus: Bool
    
    private var shouldShowSearchResults: Bool {
        !searchText.isEmpty && !citySearchManager.searchResults.isEmpty
    }
    
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
        VStack(spacing: 0) {
            // Search bar with dismiss button
            HStack(spacing: 12) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 16, weight: .medium))
                    
                    TextField("Search for a city", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.avenir(.body))
                        .autocorrectionDisabled()
                        .focused($searchFieldFocus)
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                                .font(.system(size: 16, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .themedGlass(in: .circle)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: searchText.isEmpty)
            
            // Search results
            if shouldShowSearchResults {
                List {
                    ForEach(sortedSearchResults) { result in
                        let existing = isExistingCity(result)
                        Button {
                            Task {
                                await selectSearchResult(result)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Text(result.title)
                                    .font(.avenir(.body, weight: existing ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                                
                                if existing {
                                    Text("Added")
                                        .font(.avenir(.caption2, weight: .medium))
                                        .foregroundStyle(AppTheme.shared.colors.accent)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppTheme.shared.colors.accent.opacity(0.12), in: Capsule())
                                }
                                
                                Spacer()
                                
                                if isLoadingCity {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text(result.subtitle)
                                        .font(.avenir(.headline, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoadingCity)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.visible)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            } else if searchText.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    
                    Text("Search for a city")
                        .font(.avenir(.title3, weight: .medium))
                    
                    Spacer()
                }
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    
                    Image(systemName: "map")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    
                    Text("No results")
                        .font(.avenir(.title3, weight: .medium))
                    
                    Text("Try a different search term")
                        .font(.avenir(.body))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
            }
        }
        .navigationBarHidden(true)
        .onChange(of: searchText) { oldValue, newValue in
            citySearchManager.search(query: newValue)
        }
        .onChange(of: searchFieldFocus) { oldValue, newValue in
            isSearchFieldFocused = newValue
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                searchFieldFocus = true
            }
        }
    }
    
    private func selectSearchResult(_ result: CitySearchResult) async {
        isLoadingCity = true
        defer { isLoadingCity = false }
        
        let cityName = result.title.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? result.title
        let country = result.subtitle.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? result.subtitle
        
        // Check if city already exists (match by name + country)
        if let existingCity = cities.first(where: { $0.city.name == cityName && $0.city.country == country }) {
            onCitySelected(existingCity)
            return
        }
        
        // Resolve coordinates
        guard let coordinate = await citySearchManager.resolveCoordinate(for: result) else {
            return
        }
        
        // Create and fetch weather for new city
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
