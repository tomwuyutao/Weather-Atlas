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
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar
            CityListSidebar(
                cities: weatherService.cityWeatherData,
                selectedCity: $selectedCity,
                selectedDayOffset: selectedDayOffset,
                isEditMode: $isEditMode,
                columnVisibility: $columnVisibility,
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
                            isExpanded: showingCityDetail && tappedCity?.id == cityWeather.id
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
                MapCompass()
                MapPitchToggle()
                MapUserLocationButton()
                // Scale is intentionally omitted to hide it
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                // Determine if zoomed out based on the span
                // If span is larger than ~8 degrees, consider it "zoomed out"
                let span = context.region.span
                isZoomedOut = span.latitudeDelta > 50.0 || span.longitudeDelta > 50.0
            }
            .ignoresSafeArea()
            
            // Time slider
            VStack {
                Spacer()
                
                if !weatherService.forecastDays.isEmpty {
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
                    
                    // Slider
                    VStack(spacing: 8) {
                        Slider(value: Binding(
                            get: { Double(selectedDayOffset) },
                            set: { newValue in
                                withAnimation(.smooth(duration: 0.1)) {
                                    selectedDayOffset = Int(newValue)
                                }
                            }
                        ), in: 0...9, step: 1)
                        .tint(.blue)
                        
                        // Day labels aligned with slider positions
                        GeometryReader { geometry in
                            let thumbRadius: CGFloat = 10  // Approximate slider thumb radius
                            let trackWidth = geometry.size.width - (thumbRadius * 2)
                            let stepWidth = trackWidth / 9  // 9 intervals for 10 positions (0-9)
                            
                            ForEach(Array(weatherService.forecastDays.prefix(10).enumerated()), id: \.element.id) { index, day in
                                Text(dayOfWeek(for: day.date))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .position(
                                        x: thumbRadius + (CGFloat(index) * stepWidth),
                                        y: geometry.size.height / 2
                                    )
                            }
                        }
                        .frame(height: 20)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: 500)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
            
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
                    }
                )
            }
        }
    }
    
    private var currentForecastDay: ForecastDay? {
        weatherService.forecastDays.first { $0.dayOffset == selectedDayOffset }
    }
    
    private func dayOfWeek(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

struct WeatherMarker: View {
    let cityWeather: CityWeather
    let dayOffset: Int
    let isCompact: Bool
    let namespace: Namespace.ID
    let isExpanded: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var forecast: DailyForecast {
        cityWeather.forecast(for: dayOffset)
    }
    
    var body: some View {
        Group {
            if !isExpanded {
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
    }
}



// MARK: - City List Sidebar

struct CityListSidebar: View {
    let cities: [CityWeather]
    @Binding var selectedCity: CityWeather?
    let selectedDayOffset: Int
    @Binding var isEditMode: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility
    let onCitySelected: (CityWeather) -> Void
    let onDeleteCity: (CityWeather) -> Void
    let onMoveCity: (IndexSet, Int) -> Void
    let onRefresh: () async -> Void
    let lastFetchDate: Date?
    let isRefreshing: Bool
    
    private var isSidebarVisible: Bool {
        columnVisibility != .detailOnly
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
                ForEach(cities) { cityWeather in
                    CityRow(cityWeather: cityWeather, dayOffset: selectedDayOffset)
                        .tag(cityWeather)
                        #if os(macOS)
                        .contextMenu {
                            Button(role: .destructive) {
                                onDeleteCity(cityWeather)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        #else
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !isEditMode {
                                onCitySelected(cityWeather)
                            }
                        }
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
                        onDeleteCity(cities[index])
                    }
                }
                .onMove { source, destination in
                    onMoveCity(source, destination)
                }
            }
            #if os(macOS)
            .listStyle(.sidebar)
            .onChange(of: selectedCity) { oldValue, newValue in
                if let city = newValue {
                    onCitySelected(city)
                }
            }
            #else
            .environment(\.editMode, .constant(isEditMode ? .active : .inactive))
            #endif
            
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

#Preview {
    ContentView()
}

