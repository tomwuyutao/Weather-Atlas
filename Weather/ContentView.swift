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
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var isZoomedOut: Bool = true
    @State private var showingCityDetail: Bool = false
    @State private var tappedCity: CityWeather?
    @Namespace private var popupNamespace
    @State private var searchText: String = ""
    @State private var citySearchManager = CitySearchManager()
    @State private var showingSearchSheet: Bool = true
    @State private var selectedDetent: PresentationDetent = .height(80)
    @State private var showTimeSlider: Bool = false
    
    var body: some View {
        #if os(macOS)
        macOSView
        #else
        iOSView
        #endif
    }
    
    // MARK: - macOS View
    
    private var macOSView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar
            CityListSidebar(
                cities: weatherService.cityWeatherData,
                selectedCity: $selectedCity,
                selectedDayOffset: selectedDayOffset,
                isEditMode: $isEditMode,
                columnVisibility: $columnVisibility,
                searchText: $searchText,
                showingCityDetail: $showingCityDetail,
                tappedCity: $tappedCity,
                citySearchManager: citySearchManager,
                weatherService: weatherService,
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
        } detail: {
            // Map view
            mapView
        }
        .task {
            print("Starting weather fetch...")
            await weatherService.fetchWeatherForAllCities()
            print("Weather data count: \(weatherService.cityWeatherData.count)")
        }
    }
    
    // MARK: - iOS View
    
    private var iOSView: some View {
        ZStack {
            // Map view as the main content
            mapView
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
            .presentationBackground(.regularMaterial)
            .presentationCornerRadius(65)
            .interactiveDismissDisabled()
        }
        .task {
            print("Starting weather fetch...")
            await weatherService.fetchWeatherForAllCities()
            print("Weather data count: \(weatherService.cityWeatherData.count)")
        }
    }
    
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
                            namespace: popupNamespace
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
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
            .mapControls {
                MapPitchToggle()
                MapUserLocationButton()
                // Scale and Compass are intentionally omitted to hide them
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                // Determine if zoomed out based on the span
                // If span is larger than ~8 degrees, consider it "zoomed out"
                let span = context.region.span
                isZoomedOut = span.latitudeDelta > 50.0 || span.longitudeDelta > 50.0
            }
            .ignoresSafeArea()
            
            // Time slider - now moved to search sheet
            // Keeping this code commented for reference
            /*
            #if os(iOS)
            VStack {
                Spacer()
                
                if !weatherService.forecastDays.isEmpty && selectedDetent != .large {
                    VStack(spacing: 12) {
                        // Time slider (revealed when showTimeSlider is true)
                        if showTimeSlider {
                            VStack(spacing: 12) {
                                // Current date display
                                Text(currentForecastDay?.displayText ?? "")
                                    .font(.headline)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .id("date-\(selectedDayOffset)")
                                    .transition(.asymmetric(
                                        insertion: .push(from: .trailing).combined(with: .opacity),
                                        removal: .push(from: .leading).combined(with: .opacity)
                                    ))
                                
                                // Slider without day labels
                                Slider(value: Binding(
                                    get: { Double(selectedDayOffset) },
                                    set: { newValue in
                                        withAnimation(.smooth(duration: 0.1)) {
                                            selectedDayOffset = Int(newValue)
                                        }
                                    }
                                ), in: 0...9, step: 1)
                                .tint(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                                .frame(maxWidth: 500)
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                        // "Today" button (always visible)
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                if showTimeSlider {
                                    // If slider is showing, toggle it off and reset to today
                                    selectedDayOffset = 0
                                    showTimeSlider = false
                                } else {
                                    // If slider is hidden, reveal it
                                    showTimeSlider = true
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: showTimeSlider ? "calendar" : "calendar.badge.clock")
                                    .font(.system(size: 16, weight: .medium))
                                Text(showTimeSlider ? "Hide" : "Today")
                                    .font(.headline)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, sliderBottomPadding)
                    .animation(.smooth(duration: 0.3), value: selectedDetent)
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: showTimeSlider)
                }
            }
            #else
            VStack {
                Spacer()
                
                if !weatherService.forecastDays.isEmpty {
                    VStack(spacing: 12) {
                        // Time slider (revealed when showTimeSlider is true)
                        if showTimeSlider {
                            VStack(spacing: 12) {
                                // Current date display
                                Text(currentForecastDay?.displayText ?? "")
                                    .font(.headline)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .id("date-\(selectedDayOffset)")
                                    .transition(.asymmetric(
                                        insertion: .push(from: .trailing).combined(with: .opacity),
                                        removal: .push(from: .leading).combined(with: .opacity)
                                    ))
                                
                                // Slider without day labels
                                Slider(value: Binding(
                                    get: { Double(selectedDayOffset) },
                                    set: { newValue in
                                        withAnimation(.smooth(duration: 0.1)) {
                                            selectedDayOffset = Int(newValue)
                                        }
                                    }
                                ), in: 0...9, step: 1)
                                .tint(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                                .frame(maxWidth: 500)
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                        // "Today" button (always visible)
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                if showTimeSlider {
                                    // If slider is showing, toggle it off and reset to today
                                    selectedDayOffset = 0
                                    showTimeSlider = false
                                } else {
                                    // If slider is hidden, reveal it
                                    showTimeSlider = true
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: showTimeSlider ? "calendar" : "calendar.badge.clock")
                                    .font(.system(size: 16, weight: .medium))
                                Text(showTimeSlider ? "Hide" : "Today")
                                    .font(.headline)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: showTimeSlider)
                }
            }
            #endif
            */
            
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
                    isInSidebar: cityIsInSidebar(city)
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
    
    private var currentForecastDay: ForecastDay? {
        weatherService.forecastDays.first { $0.dayOffset == selectedDayOffset }
    }
    
    private var sliderBottomPadding: CGFloat {
        switch selectedDetent {
        case .height(80):
            return 100  // Above minimized sheet
        case .medium:
            return UIScreen.main.bounds.height * 0.5 + 20  // Above medium sheet
        default:
            return 20  // Hidden when large, but keep minimal padding
        }
    }
}

struct WeatherMarker: View {
    let cityWeather: CityWeather
    let dayOffset: Int
    let isCompact: Bool
    let namespace: Namespace.ID
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var forecast: DailyForecast {
        cityWeather.forecast(for: dayOffset)
    }
    
    var body: some View {
        if isCompact {
            // Compact mode: just the icon with rounded square background, no temperature
            Group {
                if forecast.isRainIcon {
                    let colors = forecast.rainPaletteColors(for: colorScheme)
                    Image(systemName: forecast.weatherIcon)
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(colors.primary, colors.secondary)
                } else if forecast.isPartiallySunnyIcon {
                    let colors = forecast.partlySunnyPaletteColors(for: colorScheme)
                    Image(systemName: forecast.weatherIcon)
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(colors.primary, colors.secondary)
                } else {
                    Image(systemName: forecast.weatherIcon)
                        .font(.title2)
                        .foregroundStyle(forecast.weatherColor(for: colorScheme))
                }
            }
            .frame(width: 32, height: 32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.2), radius: 2)
            .contentTransition(.symbolEffect(.replace))
            .matchedGeometryEffect(id: "marker-\(cityWeather.id)", in: namespace)
            .id("compact-\(cityWeather.id)-\(dayOffset)")
        } else {
            // Full mode: icon + temperature + background
            VStack(spacing: 4) {
                if forecast.isRainIcon {
                    // For rain icons, use palette rendering
                    let colors = forecast.rainPaletteColors(for: colorScheme)
                    Image(systemName: forecast.weatherIcon)
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(colors.primary, colors.secondary)
                        .contentTransition(.symbolEffect(.replace))
                } else if forecast.isPartiallySunnyIcon {
                    // For partially sunny icons
                    let colors = forecast.partlySunnyPaletteColors(for: colorScheme)
                    Image(systemName: forecast.weatherIcon)
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(colors.primary, colors.secondary)
                        .contentTransition(.symbolEffect(.replace))
                } else {
                    // For other icons, use the color scheme-aware color
                    Image(systemName: forecast.weatherIcon)
                        .font(.title2)
                        .foregroundStyle(forecast.weatherColor(for: colorScheme))
                        .contentTransition(.symbolEffect(.replace))
                }
                
                Text("\(Int(forecast.temperature))°C")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .frame(minWidth: 40)
                    .contentTransition(.numericText())
            }
            .frame(width: 40, height: 56)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.2), radius: 3)
            .matchedGeometryEffect(id: "marker-\(cityWeather.id)", in: namespace)
            .id("full-\(cityWeather.id)-\(dayOffset)")
        }
    }
}



// MARK: - City List Sidebar

struct CityListSidebar: View {
    let cities: [CityWeather]
    @Binding var selectedCity: CityWeather?
    let selectedDayOffset: Int
    @Binding var isEditMode: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var searchText: String
    @Binding var showingCityDetail: Bool
    @Binding var tappedCity: CityWeather?
    @State var citySearchManager: CitySearchManager
    let weatherService: WeatherService
    let onCitySelected: (CityWeather) -> Void
    let onDeleteCity: (CityWeather) -> Void
    let onMoveCity: (IndexSet, Int) -> Void
    let onRefresh: () async -> Void
    let lastFetchDate: Date?
    let isRefreshing: Bool
    
    @State private var isSearching = false
    @State private var isLoadingSearchedCity = false
    
    private var isSidebarVisible: Bool {
        columnVisibility != .detailOnly
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
    
    private var cacheStatusText: String {
        guard let lastFetch = lastFetchDate else {
            return "Never updated"
        }
        
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFetch)
        let minutes = Int(elapsed / 60)
        
        if minutes < 1 {
            return "Just now"
        } else if minutes < 60 {
            return "\(minutes)m ago"
        } else {
            let hours = minutes / 60
            return "\(hours)h ago"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedCity) {
                // Show search results if searching
                if shouldShowSearchResults {
                    Section {
                        ForEach(Array(citySearchManager.searchResults.enumerated()), id: \.element.title) { index, result in
                            VStack(spacing: 0) {
                                Button {
                                    Task {
                                        await selectSearchResult(result)
                                    }
                                } label: {
                                    HStack {
                                        Text("\(result.title), \(result.subtitle)")
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if isLoadingSearchedCity {
                                            ProgressView()
                                                .controlSize(.small)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                .disabled(isLoadingSearchedCity)
                                
                                // Divider between results (except for the last one)
                                if index < citySearchManager.searchResults.count - 1 {
                                    Divider()
                                        .padding(.leading, 0)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16))
                        }
                    }
                }
                
                // Show existing cities
                if !filteredCities.isEmpty {
                    Section(shouldShowSearchResults ? "My Cities" : "") {
                        ForEach(filteredCities) { cityWeather in
                            #if os(macOS)
                            CityRow(
                                cityWeather: cityWeather,
                                dayOffset: selectedDayOffset
                            )
                                .tag(cityWeather)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        onDeleteCity(cityWeather)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            #else
                            Button {
                                if !isEditMode {
                                    // When tapping a city in the list, open the detail popup
                                    tappedCity = cityWeather
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        showingCityDetail = true
                                    }
                                    // Also update selection and map position
                                    onCitySelected(cityWeather)
                                }
                            } label: {
                                CityRow(
                                    cityWeather: cityWeather,
                                    dayOffset: selectedDayOffset
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    onDeleteCity(cityWeather)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            #endif
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
                }
            }
            #if os(macOS)
            .listStyle(.sidebar)
            .onChange(of: selectedCity) { oldValue, newValue in
                if let city = newValue {
                    // On macOS, open the detail popup when selecting from list
                    tappedCity = city
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        showingCityDetail = true
                    }
                    onCitySelected(city)
                }
            }
            #else
            .environment(\.editMode, .constant(isEditMode ? .active : .inactive))
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
        .navigationTitle("Cities")
        .toolbar {
            if isSidebarVisible {
                #if !os(macOS)
                ToolbarItem(placement: .automatic) {
                    Button {
                        withAnimation {
                            isEditMode.toggle()
                        }
                    } label: {
                        Label(isEditMode ? "Done" : "Edit", systemImage: isEditMode ? "checkmark" : "pencil")
                    }
                }
                #endif
            }
        }
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        #endif
    }
    
    private func selectSearchResult(_ result: MKLocalSearchCompletion) async {
        isLoadingSearchedCity = true
        defer { isLoadingSearchedCity = false }
        
        // Get the full location details
        let searchRequest = MKLocalSearch.Request(completion: result)
        let search = MKLocalSearch(request: searchRequest)
        
        do {
            let response = try await search.start()
            if let mapItem = response.mapItems.first {
                let coordinate = mapItem.placemark.coordinate
                let cityName = result.title
                
                // Check if this city already exists in the sidebar
                if let existingCity = cities.first(where: { $0.city.name == cityName }) {
                    print("City \(cityName) already exists in sidebar")
                    // Just show the existing city's detail
                    tappedCity = existingCity
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        showingCityDetail = true
                    }
                    onCitySelected(existingCity)
                    searchText = ""
                    return
                }
                
                // Create a temporary city and fetch its weather to show in detail view
                print("Fetching weather for \(cityName) (not adding to sidebar)")
                let tempCity = City(name: cityName, latitude: coordinate.latitude, longitude: coordinate.longitude)
                
                // Fetch weather for display only
                let tempCityWeather = await weatherService.fetchWeatherForCity(tempCity)
                
                // Show the detail popup for this city
                tappedCity = tempCityWeather
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    showingCityDetail = true
                }
                onCitySelected(tempCityWeather)
                
                // Clear search
                searchText = ""
            }
        } catch {
            print("Error searching for location: \(error.localizedDescription)")
        }
    }
}

// MARK: - City Row

struct CityRow: View {
    let cityWeather: CityWeather
    let dayOffset: Int
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var forecast: DailyForecast {
        cityWeather.forecast(for: dayOffset)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Weather icon
            if forecast.isRainIcon {
                let colors = forecast.rainPaletteColors(for: colorScheme)
                Image(systemName: forecast.weatherIcon)
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(colors.primary, colors.secondary)
                    .frame(width: 32, height: 28)
            } else if forecast.isPartiallySunnyIcon {
                let colors = forecast.partlySunnyPaletteColors(for: colorScheme)
                Image(systemName: forecast.weatherIcon)
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(colors.primary, colors.secondary)
                    .frame(width: 32, height: 28)
            } else {
                Image(systemName: forecast.weatherIcon)
                    .font(.title3)
                    .foregroundStyle(forecast.weatherColor(for: colorScheme))
                    .frame(width: 32, height: 28)
            }
            
            // City name
            Text(cityWeather.city.name)
                .font(.body)
            
            Spacer()
            
            // Temperature
            Text("\(Int(forecast.temperature))°C")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
    
    private var isMinimized: Bool {
        selectedDetent == .height(80)
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
    
    private var currentForecastDay: ForecastDay? {
        weatherService.forecastDays.first { $0.dayOffset == selectedDayOffset }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Time slider with day indicator
                HStack(spacing: 12) {
                    // Day indicator capsule on the left
                    Text(currentForecastDay?.shortDisplayText ?? "Today")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(width: 75)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .id("date-\(selectedDayOffset)")
                        .transition(.asymmetric(
                            insertion: .push(from: .trailing).combined(with: .opacity),
                            removal: .push(from: .leading).combined(with: .opacity)
                        ))
                    
                    // Time slider
                    Slider(value: Binding(
                        get: { Double(selectedDayOffset) },
                        set: { newValue in
                            withAnimation(.smooth(duration: 0.1)) {
                                selectedDayOffset = Int(newValue)
                            }
                        }
                    ), in: 0...9, step: 1)
                    .tint(.blue)
                }
                .padding(.horizontal, 24)
                .padding(.top, isMinimized ? 22 : 36)
                .padding(.bottom, 16)
                
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
                            
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(citySearchManager.searchResults.enumerated()), id: \.element.title) { index, result in
                                        Button {
                                            Task {
                                                await selectSearchResult(result)
                                            }
                                        } label: {
                                            HStack(spacing: 12) {
                                                Image(systemName: "mappin.circle.fill")
                                                    .font(.title2)
                                                    .foregroundStyle(.red)
                                                
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(result.title)
                                                        .font(.body)
                                                        .foregroundStyle(.primary)
                                                    
                                                    Text(result.subtitle)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                
                                                Spacer()
                                                
                                                if isLoadingSearchedCity {
                                                    ProgressView()
                                                        .controlSize(.small)
                                                }
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(.clear)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(isLoadingSearchedCity)
                                        
                                        if index < citySearchManager.searchResults.count - 1 {
                                            Divider()
                                                .padding(.leading, 60)
                                        }
                                    }
                                }
                            }
                        }
                    } else if !filteredCities.isEmpty {
                        // Cities list
                        VStack(spacing: 0) {
                            HStack {
                                Text("My Cities")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                Spacer()
                                
                                // Add city button
                                Button {
                                    showingAddCityView = true
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(filteredCities.enumerated()), id: \.element.id) { index, cityWeather in
                                        Button {
                                            onCitySelected(cityWeather)
                                            tappedCity = cityWeather
                                            showingCityDetail = true
                                        } label: {
                                            CityRow(
                                                cityWeather: cityWeather,
                                                dayOffset: selectedDayOffset
                                            )
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                        }
                                        .buttonStyle(.plain)
                                        
                                        if index < filteredCities.count - 1 {
                                            Divider()
                                                .padding(.leading, 60)
                                        }
                                    }
                                }
                            }
                        }
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
                let coordinate = mapItem.placemark.coordinate
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
                let tempCityWeather = await weatherService.fetchWeatherForCity(tempCity)
                
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
    @Environment(\.dismiss) private var dismiss
    
    private var shouldShowSearchResults: Bool {
        !searchText.isEmpty && !citySearchManager.searchResults.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 16, weight: .medium))
                
                TextField("Search for a city", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .autocorrectionDisabled()
                
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
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            
            // Search results
            if shouldShowSearchResults {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(citySearchManager.searchResults.enumerated()), id: \.element.title) { index, result in
                            Button {
                                Task {
                                    await selectSearchResult(result)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.red)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.title)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        
                                        Text(result.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if isLoadingCity {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(.clear)
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoadingCity)
                            
                            if index < citySearchManager.searchResults.count - 1 {
                                Divider()
                                    .padding(.leading, 60)
                            }
                        }
                    }
                }
            } else if searchText.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    
                    Text("Search for a city")
                        .font(.title3)
                        .fontWeight(.medium)
                    
                    Text("Start typing to find cities around the world")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
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
        .onChange(of: searchText) { oldValue, newValue in
            citySearchManager.search(query: newValue)
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
                let coordinate = mapItem.placemark.coordinate
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
                let tempCityWeather = await weatherService.fetchWeatherForCity(tempCity)
                
                onCitySelected(tempCityWeather)
                dismiss()
            }
        } catch {
            print("Error searching for location: \(error.localizedDescription)")
        }
    }
}





