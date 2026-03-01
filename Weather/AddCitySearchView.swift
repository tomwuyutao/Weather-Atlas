//
//  AddCitySearchView.swift
//  Weather
//

import SwiftUI
import MapKit

#if !os(macOS)
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
                        .font(.system(size: 17))
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
                .background(
                    Capsule()
                        .fill(.regularMaterial)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
                
                // Dismiss keyboard button (appears when focused)
                if searchFieldFocus {
                    Button {
                        searchFieldFocus = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44)
                            .frame(height: 44)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: searchFieldFocus)
            
            // Search results
            if shouldShowSearchResults {
                List {
                    ForEach(citySearchManager.searchResults, id: \.title) { result in
                        Button {
                            Task {
                                await selectSearchResult(result)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Text(result.title)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                if isLoadingCity {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text(result.subtitle)
                                        .font(.headline)
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
                        .font(.title3)
                        .fontWeight(.medium)
                    
                    Spacer()
                }
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    
                    Image(systemName: "map")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    
                    Text("No results")
                        .font(.title3)
                        .fontWeight(.medium)
                    
                    Text("Try a different search term")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
            }
        }
        .navigationTitle("Add City")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .onChange(of: searchText) { oldValue, newValue in
            citySearchManager.search(query: newValue)
        }
        .onChange(of: searchFieldFocus) { oldValue, newValue in
            isSearchFieldFocused = newValue
        }
    }
    
    private func selectSearchResult(_ result: MKLocalSearchCompletion) async {
        isLoadingCity = true
        defer { isLoadingCity = false }
        
        let searchRequest = MKLocalSearch.Request(completion: result)
        let search = MKLocalSearch(request: searchRequest)
        
        do {
            let response = try await search.start()
            if let mapItem = response.mapItems.first {
                let coordinate = mapItem.location.coordinate
                let cityName = result.title
                
                // Check if city already exists
                if let existingCity = cities.first(where: { $0.city.name == cityName }) {
                    print("City \(cityName) already exists")
                    onCitySelected(existingCity)
                    return
                }
                
                // Create and fetch weather for new city
                let tempCity = City(name: cityName, latitude: coordinate.latitude, longitude: coordinate.longitude)
                guard let tempCityWeather = await weatherService.fetchWeatherForCity(tempCity) else {
                    print("⚠️ Could not fetch weather for \(cityName)")
                    return
                }
                
                onCitySelected(tempCityWeather)
            }
        } catch {
            print("Error searching for location: \(error.localizedDescription)")
        }
    }
}
#endif
