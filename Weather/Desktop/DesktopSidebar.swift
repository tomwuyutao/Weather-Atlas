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
    var showPrecipitation: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    
    private var tempUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
    }
    
    private var forecast: DailyForecast {
        cityWeather.forecast(for: dayOffset)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Weather icon - always shown
            Image(systemName: forecast.weatherIcon)
                .font(.title3)
                .weatherIconStyle(for: forecast.weatherIcon)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                .frame(width: 32, height: 28)
            
            // City name
            Text(cityWeather.city.localizedName(locale: locale))
                .font(.body)
            
            Spacer()
            
            // Temperature, cloud cover, or precipitation
            Text(showCloudCover ? "\(forecast.cloudCoverPercent)%" : showPrecipitation ? "\(Int(forecast.precipitationChance * 100))%" : tempUnit.display(forecast.daytimeHigh))
                .font(.headline)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.3), value: showCloudCover)
                .animation(.smooth(duration: 0.3), value: showPrecipitation)
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
    var showPrecipitation: Bool = false
    let onCitySelected: (CityWeather) -> Void
    let onDeleteCity: (CityWeather) -> Void
    let onMoveCity: (IndexSet, Int) -> Void
    let onRefresh: () async -> Void
    let onSwitchList: (CityListID) -> Void
    let lastFetchDate: Date?
    let isRefreshing: Bool
    @Binding var detailOpenedFromList: Bool
    
    @Environment(\.locale) private var locale
    @State private var isLoadingSearchedCity = false
    @State private var showingAddCityView = false
    @State private var showingListSwitcher = false
    
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
            return localizedString("Loading…", locale: locale)
        }
        
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFetch)
        let minutes = Int(elapsed / 60)
        
        if minutes < 1 {
            return localizedString("Now", locale: locale)
        } else if minutes < 60 {
            return localizedString("\(minutes) m", locale: locale)
        } else {
            let hours = minutes / 60
            return localizedString("\(hours) h", locale: locale)
        }
    }
    
    @ViewBuilder
    private var cityListContent: some View {
        ForEach(filteredCities) { cityWeather in
            CityRow(
                cityWeather: cityWeather,
                dayOffset: selectedDayOffset,
                showCloudCover: showCloudCover,
                showPrecipitation: showPrecipitation
            )
                .tag(cityWeather)
                .contentShape(Rectangle())
                .onTapGesture {
                    detailOpenedFromList = true
                    tappedCity = cityWeather
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        showingCityDetail = true
                    }
                    onCitySelected(cityWeather)
                }
                .contextMenu {
                    Button {
                        detailOpenedFromList = true
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
                        ForEach(citySearchManager.searchResults) { result in
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
                        Section(weatherService.activeListID.localizedDisplayName(locale: locale)) {
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
                                .weatherIconStyle(for: "cloud.sun.fill")
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
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    showingListSwitcher = true
                } label: {
                    HStack(spacing: 4) {
                        Text(weatherService.activeListID.localizedDisplayName(locale: locale))
                            .font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingListSwitcher) {
                    desktopListSwitcherMenu
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
        
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        #endif
    }
    
    private var desktopListSwitcherMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(CityListID.allLists) { listID in
                Button {
                    showingListSwitcher = false
                    onSwitchList(listID)
                } label: {
                    HStack(spacing: 12) {
                        Text(listID.localizedDisplayName(locale: locale))
                            .font(.body)
                            .fontWeight(listID == weatherService.activeListID ? .bold : .regular)
                            .foregroundStyle(.primary)
                        Spacer()
                        if listID == weatherService.activeListID {
                            Circle()
                                .fill(Color.primary)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 170)
        .presentationBackground(.ultraThinMaterial)
    }
    
    private func selectSearchResult(_ result: CitySearchResult) async {
        isLoadingSearchedCity = true
        defer { isLoadingSearchedCity = false }
        
        let cityName = result.title.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? result.title
        let country = result.subtitle.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? result.subtitle
        
        if let existingCity = cities.first(where: { $0.city.name == cityName && $0.city.country == country }) {
            detailOpenedFromList = false
            tappedCity = existingCity
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                showingCityDetail = true
            }
            onCitySelected(existingCity)
            searchText = ""
            return
        }
        
        guard let coordinate = await citySearchManager.resolveCoordinate(for: result) else {
            return
        }
        
        let tempCity = City(name: cityName, country: country, latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let tempCityWeather = await weatherService.fetchWeatherForCity(tempCity) else {
            return
        }
        
        detailOpenedFromList = false
        tappedCity = tempCityWeather
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            showingCityDetail = true
        }
        onCitySelected(tempCityWeather)
        
        searchText = ""
    }
}
