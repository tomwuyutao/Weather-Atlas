//
//  ContentView.swift
//  Weather
//
//  Created by Tom on 25/02/2026.
//

import SwiftUI
import MapKit

struct ContentView: View {
    @State private var weatherService = WeatherService()
    
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.0, longitude: 10.0),
            span: MKCoordinateSpan(latitudeDelta: 30.0, longitudeDelta: 40.0)
        )
    )
    
    @State private var selectedCity: CityWeather?
    @State private var selectedDayOffset: Int = 0
    @State private var isEditMode: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isZoomedOut: Bool = true
    @State private var showingCityDetail: Bool = false
    @State private var tappedCity: CityWeather?
    @Namespace private var popupNamespace
    @State private var searchText: String = ""
    @State private var citySearchManager = CitySearchManager()
    @State private var showingSearchSheet: Bool = true
    @State private var selectedDetent: PresentationDetent = .height(80)
    @State private var lastRefreshText: String = ""
    @State private var showCloudCover: Bool = false
    
    private func timeSinceRefreshText() -> String {
        guard let lastFetch = weatherService.lastFetchDate else {
            return ""
        }
        let elapsed = Date().timeIntervalSince(lastFetch)
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
    
    var body: some View {
        #if os(macOS)
        desktopView
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            desktopView
        } else {
            iOSView
        }
        #endif
    }
    
    // MARK: - Desktop View (macOS & iPadOS)
    
    private var desktopView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar - uses the same content as the iOS large sheet
            DesktopSidebar(
                cities: weatherService.cityWeatherData,
                selectedCity: $selectedCity,
                selectedDayOffset: $selectedDayOffset,
                isEditMode: $isEditMode,
                searchText: $searchText,
                showingCityDetail: $showingCityDetail,
                tappedCity: $tappedCity,
                citySearchManager: citySearchManager,
                weatherService: weatherService,
                showCloudCover: showCloudCover,
                onCitySelected: { cityWeather in
                    selectedCity = cityWeather
                    withAnimation {
                        position = .region(
                            MKCoordinateRegion(
                                center: CLLocationCoordinate2D(
                                    latitude: cityWeather.city.latitude,
                                    longitude: cityWeather.city.longitude
                                ),
                                span: MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 5.0)
                            )
                        )
                    }
                },
                onDeleteCity: { cityWeather in
                    weatherService.removeCity(cityWeather)
                    if selectedCity?.id == cityWeather.id {
                        selectedCity = nil
                    }
                },
                onMoveCity: { source, destination in
                    weatherService.moveCity(from: source, to: destination)
                },
                onRefresh: {
                    await weatherService.refreshWeather()
                },
                lastFetchDate: weatherService.lastFetchDate,
                isRefreshing: weatherService.isLoading
            )
        } detail: {
            // Map view with bottom date bar
            mapView
                .overlay(alignment: .bottom) {
                    DesktopDateBar(selectedDayOffset: $selectedDayOffset, showCloudCover: $showCloudCover)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
        }
        .task {
            print("Starting weather fetch...")
            await weatherService.fetchWeatherForAllCities()
            print("Weather data count: \(weatherService.cityWeatherData.count)")
        }
    }
    
    // MARK: - iOS View
    
    #if !os(macOS)
    private var iOSView: some View {
        ZStack {
            // Map view as the main content
            mapView
        }
        .overlay(alignment: .topTrailing) {
            Button {
                Task {
                    await weatherService.refreshWeather()
                }
            } label: {
                Group {
                    if weatherService.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                            
                            Text(lastRefreshText)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(width: 50, height: 50)
                .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(weatherService.isLoading)
            .padding(.trailing, 16)
            .padding(.top, 60)
        }
        .onAppear {
            lastRefreshText = timeSinceRefreshText()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                lastRefreshText = timeSinceRefreshText()
            }
        }
        .onChange(of: weatherService.lastFetchDate) { _, _ in
            lastRefreshText = timeSinceRefreshText()
        }
        .sheet(isPresented: $showingSearchSheet) {
            NativeSearchSheet(
                cities: weatherService.cityWeatherData,
                selectedCity: $selectedCity,
                selectedDayOffset: $selectedDayOffset,
                isEditMode: $isEditMode,
                searchText: $searchText,
                showingCityDetail: $showingCityDetail,
                tappedCity: $tappedCity,
                citySearchManager: citySearchManager,
                weatherService: weatherService,
                selectedDetent: $selectedDetent,
                onCitySelected: { cityWeather in
                    selectedCity = cityWeather
                    // Animate to the selected city
                    withAnimation {
                        position = .region(
                            MKCoordinateRegion(
                                center: CLLocationCoordinate2D(
                                    latitude: cityWeather.city.latitude,
                                    longitude: cityWeather.city.longitude
                                ),
                                span: MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 5.0)
                            )
                        )
                    }
                },
                onDeleteCity: { cityWeather in
                    weatherService.removeCity(cityWeather)
                    if selectedCity?.id == cityWeather.id {
                        selectedCity = nil
                    }
                },
                onMoveCity: { source, destination in
                    weatherService.moveCity(from: source, to: destination)
                },
                onRefresh: {
                    await weatherService.refreshWeather()
                },
                lastFetchDate: weatherService.lastFetchDate,
                isRefreshing: weatherService.isLoading
            )
            .presentationDetents([.height(80), .medium, .large], selection: $selectedDetent)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .presentationBackground(Color(.systemBackground))
            .presentationCornerRadius(selectedDetent == .height(80) ? 65 : 45)
            .interactiveDismissDisabled()
        }
        .task {
            print("Starting weather fetch...")
            await weatherService.fetchWeatherForAllCities()
            print("Weather data count: \(weatherService.cityWeatherData.count)")
        }
    }
    #endif
    
    private var mapView: some View {
        ZStack {
            Map(position: $position, selection: $selectedCity) {
                ForEach(weatherService.cityWeatherData) { cityWeather in
                    Annotation(cityWeather.city.name, 
                             coordinate: CLLocationCoordinate2D(
                                latitude: cityWeather.city.latitude,
                                longitude: cityWeather.city.longitude
                             )) {
                        WeatherMarker(
                            cityWeather: cityWeather,
                            dayOffset: selectedDayOffset,
                            isCompact: isZoomedOut,
                            namespace: popupNamespace,
                            showCloudCover: showCloudCover
                        )
                        .onTapGesture {
                            tappedCity = cityWeather
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                showingCityDetail = true
                            }
                        }
                    }
                    .tag(cityWeather)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .mapControls {
                MapPitchToggle()
                // MapUserLocationButton removed
                // Scale and Compass are intentionally omitted to hide them
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                // Determine if zoomed out based on the span
                // If span is larger than ~8 degrees, consider it "zoomed out"
                let span = context.region.span
                isZoomedOut = span.latitudeDelta > 50.0 || span.longitudeDelta > 50.0
            }
            .ignoresSafeArea()
            
            // City detail popup
            if showingCityDetail, let city = tappedCity {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showingCityDetail = false
                        }
                    }
                    .transition(.opacity)
                
                WeatherDetailView(
                    cityWeather: city,
                    selectedDayOffset: selectedDayOffset,
                    namespace: popupNamespace,
                    onDismiss: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showingCityDetail = false
                        }
                    },
                    onAddCity: cityIsInSidebar(city) ? nil : {
                        Task {
                            await addCityToSidebar(city)
                        }
                    },
                    isInSidebar: cityIsInSidebar(city),
                    showCloudCover: showCloudCover
                )
            }
        }
    }
    
    private func cityIsInSidebar(_ cityWeather: CityWeather) -> Bool {
        weatherService.cityWeatherData.contains(where: { $0.city.name == cityWeather.city.name })
    }
    
    private func addCityToSidebar(_ cityWeather: CityWeather) async {
        await weatherService.addCity(cityWeather.city)
        // Update the tapped city to the newly added one from the sidebar
        if let newCity = weatherService.cityWeatherData.first(where: { $0.city.name == cityWeather.city.name }) {
            tappedCity = newCity
        }
    }
}

struct WeatherMarker: View {
    let cityWeather: CityWeather
    let dayOffset: Int
    let isCompact: Bool
    let namespace: Namespace.ID
    let showCloudCover: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var forecast: DailyForecast {
        cityWeather.forecast(for: dayOffset)
    }
    
    var body: some View {
        if isCompact {
            // Compact mode: just the weather icon, no text
            Image(systemName: forecast.weatherIcon)
                .font(.title2)
                .symbolRenderingMode(.multicolor)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.2), radius: 2)
                .matchedGeometryEffect(id: "marker-\(cityWeather.id)", in: namespace)
        } else {
            // Full mode: weather icon + temperature or cloud cover
            VStack(spacing: 2) {
                Image(systemName: forecast.weatherIcon)
                    .font(.title2)
                    .symbolRenderingMode(.multicolor)
                    .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                
                Text(showCloudCover ? "\(forecast.cloudCoverPercent)%" : "\(Int(forecast.daytimeHigh))°")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .offset(x: 2)
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.4), value: dayOffset)
                    .animation(.smooth(duration: 0.4), value: showCloudCover)
            }
            .frame(width: 32, height: 46)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.2), radius: 3)
            .matchedGeometryEffect(id: "marker-\(cityWeather.id)", in: namespace)
        }
    }
    

}


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

// MARK: - Desktop Date Bar (macOS & iPadOS)

struct DesktopDateBar: View {
    @Binding var selectedDayOffset: Int
    @Binding var showCloudCover: Bool
    
    @State private var showingDatePopover = false
    @State private var previousDayOffset: Int = 0
    @State private var isPlaying = false
    @State private var playbackTask: Task<Void, Never>?
    
    private var selectedDate: Date {
        Calendar.current.date(byAdding: .day, value: selectedDayOffset, to: Date()) ?? Date()
    }
    
    private var dateRange: ClosedRange<Date> {
        Date()...(Calendar.current.date(byAdding: .day, value: 9, to: Date()) ?? Date())
    }
    
    private var shortDateWithDayText: String {
        if selectedDayOffset == 0 { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, EEE"
        return formatter.string(from: selectedDate)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Cloud cover toggle
            Button {
                withAnimation(.smooth(duration: 0.3)) {
                    showCloudCover.toggle()
                }
            } label: {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(showCloudCover ? .blue : .secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(.thickMaterial, in: Circle())
            
            HStack(spacing: 2) {
                // Previous day button
                Button {
                    stopPlayback()
                    if selectedDayOffset > 0 {
                        withAnimation(.smooth(duration: 0.2)) {
                            selectedDayOffset -= 1
                        }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedDayOffset > 0 ? .primary : .tertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(LongPressGesture().onEnded { _ in
                    stopPlayback()
                    withAnimation(.smooth(duration: 0.3)) {
                        selectedDayOffset = 0
                    }
                })
                
                // Day indicator
                Button {
                    showingDatePopover.toggle()
                } label: {
                    Text(shortDateWithDayText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .id("desktop-date-\(selectedDayOffset)")
                        .transition(.asymmetric(
                            insertion: .move(edge: selectedDayOffset >= previousDayOffset ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: selectedDayOffset >= previousDayOffset ? .leading : .trailing).combined(with: .opacity)
                        ))
                        .frame(width: 80)
                        .clipped()
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingDatePopover) {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { selectedDate },
                            set: { newDate in
                                let calendar = Calendar.current
                                let components = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: newDate))
                                if let days = components.day {
                                    withAnimation(.smooth(duration: 0.2)) {
                                        selectedDayOffset = max(0, min(9, days))
                                    }
                                }
                            }
                        ),
                        in: dateRange,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(width: 280, height: 300)
                    .padding(8)
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(.thickMaterial)
                }
                
                // Next day button
                Button {
                    stopPlayback()
                    if selectedDayOffset < 9 {
                        withAnimation(.smooth(duration: 0.2)) {
                            selectedDayOffset += 1
                        }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedDayOffset < 9 ? .primary : .tertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(LongPressGesture().onEnded { _ in
                    stopPlayback()
                    withAnimation(.smooth(duration: 0.3)) {
                        selectedDayOffset = 9
                    }
                })
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .fixedSize()
            .background(.thickMaterial, in: Capsule())
            
            // Play/pause button
            Button {
                if isPlaying {
                    stopPlayback()
                } else {
                    startPlayback()
                }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .background(.thickMaterial, in: Circle())
        }
        .onChange(of: selectedDayOffset) { oldValue, _ in
            previousDayOffset = oldValue
        }
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
    
    private func startPlayback() {
        isPlaying = true
        // If already at the end, restart from the beginning
        if selectedDayOffset >= 9 {
            selectedDayOffset = 0
        }
        playbackTask = Task {
            while !Task.isCancelled && selectedDayOffset < 9 {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { break }
                withAnimation(.smooth(duration: 0.4)) {
                    selectedDayOffset += 1
                }
            }
            // Playback finished naturally
            if !Task.isCancelled {
                isPlaying = false
            }
        }
    }
    
    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }
}

// MARK: - City Search Manager

@Observable
class CitySearchManager: NSObject, MKLocalSearchCompleterDelegate {
    var searchResults: [MKLocalSearchCompletion] = []
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
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // Filter to only show city-level results (Title: "Bologna", Subtitle: "Italy")
        searchResults = completer.results.filter { result in
            // We want results where NEITHER title nor subtitle contain commas
            // This gives us simple city results like "Bologna" / "Italy" or "London" / "England"
            // And filters out more specific results like "LHR, London" / "England"
            let titleHasNoComma = !result.title.contains(",")
            let subtitleHasNoComma = !result.subtitle.contains(",")
            
            // Also ensure subtitle is not empty (to avoid invalid results)
            let hasSubtitle = !result.subtitle.isEmpty
            
            return titleHasNoComma && subtitleHasNoComma && hasSubtitle
        }
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Search error: \(error.localizedDescription)")
    }
}

#if !os(macOS)
// MARK: - Native Search Sheet (iOS - using native sheet presentation)
struct NativeSearchSheet: View {
    let cities: [CityWeather]
    @Binding var selectedCity: CityWeather?
    @Binding var selectedDayOffset: Int
    @Binding var isEditMode: Bool
    @Binding var searchText: String
    @Binding var showingCityDetail: Bool
    @Binding var tappedCity: CityWeather?
    @State var citySearchManager: CitySearchManager
    let weatherService: WeatherService
    @Binding var selectedDetent: PresentationDetent
    let onCitySelected: (CityWeather) -> Void
    let onDeleteCity: (CityWeather) -> Void
    let onMoveCity: (IndexSet, Int) -> Void
    let onRefresh: () async -> Void
    let lastFetchDate: Date?
    let isRefreshing: Bool
    
    @State private var isLoadingSearchedCity = false
    @State private var showingAddCityView = false
    @State private var showingDatePopover = false
    @State private var previousDayOffset: Int = 0
    
    private var isMinimized: Bool {
        selectedDetent == .height(80)
    }
    
    private var selectedDate: Date {
        Calendar.current.date(byAdding: .day, value: selectedDayOffset, to: Date()) ?? Date()
    }
    
    private var dateRange: ClosedRange<Date> {
        Date()...(Calendar.current.date(byAdding: .day, value: 9, to: Date()) ?? Date())
    }
    
    private var shortDateText: String {
        if selectedDayOffset == 0 { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: selectedDate)
    }
    
    private var shortDateWithDayText: String {
        if selectedDayOffset == 0 { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, EEE"
        return formatter.string(from: selectedDate)
    }
    
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
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Date navigation - only show when minimized
                if isMinimized {
                    HStack {
                        // Previous day button - left edge
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(selectedDayOffset > 0 ? .primary : .tertiary)
                            .frame(width: 44, height: 50)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedDayOffset > 0 {
                                    withAnimation(.smooth(duration: 0.2)) {
                                        selectedDayOffset -= 1
                                    }
                                }
                            }
                            .onLongPressGesture {
                                withAnimation(.smooth(duration: 0.3)) {
                                    selectedDayOffset = 0
                                }
                            }
                        
                        Spacer()
                        
                        // Day indicator - tappable capsule
                        Text(shortDateWithDayText)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .id("minimized-date-\(selectedDayOffset)")
                            .transition(.asymmetric(
                                insertion: .move(edge: selectedDayOffset >= previousDayOffset ? .trailing : .leading).combined(with: .opacity),
                                removal: .move(edge: selectedDayOffset >= previousDayOffset ? .leading : .trailing).combined(with: .opacity)
                            ))
                            .frame(width: 100, height: 50)
                            .clipped()
                            .glassEffect(.regular.interactive())
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !showingDatePopover {
                                    showingDatePopover = true
                                }
                            }
                        
                        Spacer()
                        
                        // Next day button - right edge
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(selectedDayOffset < 9 ? .primary : .tertiary)
                            .frame(width: 44, height: 50)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedDayOffset < 9 {
                                    withAnimation(.smooth(duration: 0.2)) {
                                        selectedDayOffset += 1
                                    }
                                }
                            }
                            .onLongPressGesture {
                                withAnimation(.smooth(duration: 0.3)) {
                                    selectedDayOffset = 9
                                }
                            }
                    }
                    .onChange(of: selectedDayOffset) { oldValue, _ in
                        previousDayOffset = oldValue
                    }
                    .popover(isPresented: $showingDatePopover) {
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { selectedDate },
                                set: { newDate in
                                    let calendar = Calendar.current
                                    let components = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: newDate))
                                    if let days = components.day {
                                        withAnimation(.smooth(duration: 0.2)) {
                                            selectedDayOffset = max(0, min(9, days))
                                        }
                                    }
                                }
                            ),
                            in: dateRange,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .frame(width: 280, height: 300)
                        .padding(8)
                        .presentationCompactAdaptation(.popover)
                        .presentationBackground(.thickMaterial)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 22)
                    .padding(.bottom, 16)
                }
                
                // Content - only show when not minimized
                if !isMinimized {
                    if shouldShowSearchResults {
                        // Search results
                        VStack(spacing: 0) {
                            HStack {
                                Text("Search Results")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            
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
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowSeparator(.visible)
                                    .listRowBackground(Color.clear)
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                        }
                    } else if !filteredCities.isEmpty {
                        // Cities list
                        VStack(spacing: 0) {
                            // Use List in both modes, but with consistent styling
                            List {
                                ForEach(filteredCities) { cityWeather in
                                    Button {
                                        if !isEditMode {
                                            onCitySelected(cityWeather)
                                            tappedCity = cityWeather
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                                showingCityDetail = true
                                                selectedDetent = .height(80)
                                            }
                                        }
                                    } label: {
                                        CityRow(
                                            cityWeather: cityWeather,
                                            dayOffset: selectedDayOffset,
                                            showCloudCover: false
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowSeparator(.visible)
                                    .listRowBackground(Color.clear)
                                    .contextMenu {
                                        Button {
                                            onCitySelected(cityWeather)
                                            tappedCity = cityWeather
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                                showingCityDetail = true
                                                selectedDetent = .height(80)
                                            }
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
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                            .environment(\.editMode, .constant(isEditMode ? .active : .inactive))
                        }
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                if !isMinimized {
                                    // Date picker button in toolbar when expanded
                                    Button {
                                        showingDatePopover.toggle()
                                    } label: {
                                        Text(shortDateText)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .frame(width: 60)
                                    }
                                    .popover(isPresented: $showingDatePopover) {
                                        DatePicker(
                                            "",
                                            selection: Binding(
                                                get: { selectedDate },
                                                set: { newDate in
                                                    let calendar = Calendar.current
                                                    let components = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: newDate))
                                                    if let days = components.day {
                                                        withAnimation(.smooth(duration: 0.2)) {
                                                            selectedDayOffset = max(0, min(9, days))
                                                        }
                                                    }
                                                }
                                            ),
                                            in: dateRange,
                                            displayedComponents: .date
                                        )
                                        .datePickerStyle(.graphical)
                                        .labelsHidden()
                                        .frame(width: 280, height: 300)
                                        .padding(8)
                                        .presentationCompactAdaptation(.popover)
                                        .presentationBackground(.thickMaterial)
                                    }
                                }
                            }
                            
                            ToolbarItem(placement: .principal) {
                                Text("My Cities")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            
                            ToolbarItemGroup(placement: .topBarTrailing) {
                                Button {
                                    withAnimation {
                                        isEditMode.toggle()
                                    }
                                } label: {
                                    Label(isEditMode ? "Done" : "Edit", systemImage: isEditMode ? "checkmark" : "pencil")
                                }
                                
                                Button {
                                    showingAddCityView = true
                                } label: {
                                    Label("Add", systemImage: "plus")
                                }
                            }
                        }
                        .toolbarTitleDisplayMode(.inline)
                    } else {
                        Spacer()
                        Text("No cities added yet")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .navigationDestination(isPresented: $showingAddCityView) {
                AddCitySearchView(
                    cities: cities,
                    citySearchManager: CitySearchManager(),
                    weatherService: weatherService,
                    onCitySelected: { cityWeather in
                        onCitySelected(cityWeather)
                        tappedCity = cityWeather
                        showingCityDetail = true
                        showingAddCityView = false
                        selectedDetent = .height(80)
                    }
                )
            }
            .onChange(of: searchText) { oldValue, newValue in
                citySearchManager.search(query: newValue)
            }
        }
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
                        // Minimize the search sheet
                        selectedDetent = .height(80)
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
                    // Minimize the search sheet
                    selectedDetent = .height(80)
                }
                onCitySelected(tempCityWeather)
                
                searchText = ""
            }
        } catch {
            print("Error searching for location: \(error.localizedDescription)")
        }
    }
}

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
                    dismiss()
                    return
                }
                
                // Create and fetch weather for new city
                let tempCity = City(name: cityName, latitude: coordinate.latitude, longitude: coordinate.longitude)
                guard let tempCityWeather = await weatherService.fetchWeatherForCity(tempCity) else {
                    print("⚠️ Could not fetch weather for \(cityName)")
                    return
                }
                
                onCitySelected(tempCityWeather)
                dismiss()
            }
        } catch {
            print("Error searching for location: \(error.localizedDescription)")
        }
    }
}
#endif

