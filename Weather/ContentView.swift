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
    @State private var filterSunny: Bool = false
    @State private var isPlaying: Bool = false

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
                    DesktopDateBar(selectedDayOffset: $selectedDayOffset, showCloudCover: $showCloudCover, filterSunny: $filterSunny, isPlaying: $isPlaying)
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
                    let forecast = cityWeather.forecast(for: selectedDayOffset)
                    let passesFilter = !filterSunny || (forecast.condition == .clear && forecast.cloudCover < 0.30)

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
                            showCloudCover: showCloudCover,
                            filterSunny: filterSunny,
                            passesFilter: passesFilter,
                            isPlaying: isPlaying
                        )
                        .opacity(passesFilter ? 1 : 0)
                        .animation(.easeInOut(duration: 0.3), value: passesFilter)
                        .allowsHitTesting(passesFilter)
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

#Preview {
    ContentView()
}

struct WeatherMarker: View {
    let cityWeather: CityWeather
    let dayOffset: Int
    let isCompact: Bool
    let namespace: Namespace.ID
    let showCloudCover: Bool
    var filterSunny: Bool = false
    var passesFilter: Bool = true
    var isPlaying: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var forecast: DailyForecast {
        cityWeather.forecast(for: dayOffset)
    }

    private var displayIcon: String {
        if filterSunny {
            if isPlaying {
                // During playback: always sun so no icon transitions
                return "sun.max.fill"
            } else {
                // Not playing: only sun for passing cities, others keep real icon for clean fade out
                return passesFilter ? "sun.max.fill" : forecast.weatherIcon
            }
        }
        return forecast.weatherIcon
    }

    var body: some View {
        if isCompact {
            // Compact mode: just the weather icon, no text
            Image(systemName: displayIcon)
                .id(isPlaying ? "playing" : "filter-\(filterSunny)")
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
                Image(systemName: displayIcon)
                    .id(isPlaying ? "playing" : "filter-\(filterSunny)")
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
