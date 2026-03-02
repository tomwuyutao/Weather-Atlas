//
//  DesktopSidebar.swift
//  Weather
//

import SwiftUI
import MapKit

// MARK: - City Row

struct CityRow: View {
    let cityWeather: CityWeather
    let dayOffset: Int
    let showCloudCover: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var forecast: DailyForecast {
        cityWeather.forecast(for: dayOffset)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Weather icon - always shown
            Image(systemName: forecast.weatherIcon)
                .font(.title3)
                .symbolRenderingMode(.multicolor)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                .frame(width: 32, height: 28)
            
            // City name
            Text(cityWeather.city.name)
                .font(.body)
            
            Spacer()
            
            // Temperature or cloud cover
            Text(showCloudCover ? "\(forecast.cloudCoverPercent)%" : "\(Int(forecast.daytimeHigh))°")
                .font(.headline)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.3), value: showCloudCover)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Desktop Sidebar (macOS & iPadOS)

struct DesktopSidebar: View {
    let cities: [CityWeather]
    @Binding var selectedCity: CityWeather?
    @Binding var selectedDayOffset: Int
    @Binding var isEditMode: Bool
    @Binding var searchText: String
    @Binding var showingCityDetail: Bool
    @Binding var tappedCity: CityWeather?
    @State var citySearchManager: CitySearchManager
    let weatherService: WeatherService
    let showCloudCover: Bool
    let onCitySelected: (CityWeather) -> Void
    let onDeleteCity: (CityWeather) -> Void
    let onMoveCity: (IndexSet, Int) -> Void
    let onRefresh: () async -> Void
    let lastFetchDate: Date?
    let isRefreshing: Bool
    
    @State private var isLoadingSearchedCity = false
    @State private var showingAddCityView = false
    
    private var filteredCities: [CityWeather] {
        if searchText.isEmpty {
            return cities
        } else {
            return cities.filter { cityWeather in
                cityWeather.city.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    private var shouldShowSearchResults: Bool {
        !searchText.isEmpty && !citySearchManager.searchResults.isEmpty
    }
    
    private var cacheStatusText: String {
        guard let lastFetch = lastFetchDate else {
            return "Loading…"
        }
        
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFetch)
        let minutes = Int(elapsed / 60)
        
        if minutes < 1 {
            return "Now"
        } else if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            return "\(hours)h"
        }
    }
    
    @ViewBuilder
    private var cityListContent: some View {
        ForEach(filteredCities) { cityWeather in
            CityRow(
                cityWeather: cityWeather,
                dayOffset: selectedDayOffset,
                showCloudCover: showCloudCover
            )
                .tag(cityWeather)
                .contentShape(Rectangle())
                .onTapGesture {
                    tappedCity = cityWeather
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        showingCityDetail = true
                    }
                    onCitySelected(cityWeather)
                }
                .contextMenu {
                    Button {
                        tappedCity = cityWeather
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            showingCityDetail = true
                        }
                        onCitySelected(cityWeather)
                    } label: {
                        Label("View Details", systemImage: "info.circle")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        onDeleteCity(cityWeather)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        }
        .onDelete { indexSet in
            for index in indexSet {
                let cityToDelete = filteredCities[index]
                onDeleteCity(cityToDelete)
            }
        }
        .onMove { source, destination in
            onMoveCity(source, destination)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            List {
                // Show search results if searching
                if shouldShowSearchResults {
                    Section {
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
                                    
                                    if isLoadingSearchedCity {
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
                            .disabled(isLoadingSearchedCity)
                        }
                    }
                }
                
                // Show existing cities
                if !filteredCities.isEmpty {
                    if shouldShowSearchResults {
                        Section("My Cities") {
                            cityListContent
                        }
                    } else {
                        cityListContent
                    }
                } else if cities.isEmpty && isRefreshing {
                    // First launch loading state
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "cloud.sun.fill")
                                .font(.system(size: 36))
                                .symbolRenderingMode(.multicolor)
                            Text("Loading Weather…")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            ProgressView()
                                .controlSize(.small)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
            }
            #if os(macOS)
            .listStyle(.sidebar)
            #else
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            #endif
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
            .onChange(of: searchText) { oldValue, newValue in
                citySearchManager.search(query: newValue)
            }
            
            // Cache status footer
            if !isEditMode {
                HStack {
                    Text("Updated: \(cacheStatusText)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button {
                        Task {
                            await onRefresh()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if isRefreshing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isRefreshing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
        }
        .navigationTitle("My Cities")
        
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        #endif
    }
    
    private func selectSearchResult(_ result: MKLocalSearchCompletion) async {
        isLoadingSearchedCity = true
        defer { isLoadingSearchedCity = false }
        
        let searchRequest = MKLocalSearch.Request(completion: result)
        let search = MKLocalSearch(request: searchRequest)
        
        do {
            let response = try await search.start()
            if let mapItem = response.mapItems.first {
                let coordinate = mapItem.location.coordinate
                let cityName = result.title
                
                if let existingCity = cities.first(where: { $0.city.name == cityName }) {
                    tappedCity = existingCity
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        showingCityDetail = true
                    }
                    onCitySelected(existingCity)
                    searchText = ""
                    return
                }
                
                let tempCity = City(name: cityName, latitude: coordinate.latitude, longitude: coordinate.longitude)
                guard let tempCityWeather = await weatherService.fetchWeatherForCity(tempCity) else {
                    print("⚠️ Could not fetch weather for \(cityName)")
                    return
                }
                
                tappedCity = tempCityWeather
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    showingCityDetail = true
                }
                onCitySelected(tempCityWeather)
                
                searchText = ""
            }
        } catch {
            print("Error searching for location: \(error.localizedDescription)")
        }
    }
}
