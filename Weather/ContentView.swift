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
                }
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
        ZStack(alignment: .bottom) {
            Map(position: $position, selection: $selectedCity) {
                ForEach(weatherService.cityWeatherData) { cityWeather in
                    Annotation(cityWeather.city.name, 
                             coordinate: CLLocationCoordinate2D(
                                latitude: cityWeather.city.latitude,
                                longitude: cityWeather.city.longitude
                             )) {
                        WeatherMarker(
                            cityWeather: cityWeather,
                            dayOffset: selectedDayOffset
                        )
                    }
                    .tag(cityWeather)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapPitchToggle()
                MapUserLocationButton()
                // Scale is intentionally omitted to hide it
            }
            .ignoresSafeArea()
            
            // Time slider
            if !weatherService.forecastDays.isEmpty {
                VStack(spacing: 12) {
                    // Current date display
                    Text(currentForecastDay?.displayText ?? "")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                    
                    // Slider
                    VStack(spacing: 8) {
                        Slider(value: Binding(
                            get: { Double(selectedDayOffset) },
                            set: { selectedDayOffset = Int($0) }
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
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
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
    
    private var forecast: DailyForecast {
        cityWeather.forecast(for: dayOffset)
    }
    
    var body: some View {
        VStack(spacing: 4) {
            if forecast.isRainIcon {
                // For rain icons, use palette rendering
                // Cloud is white, raindrops are blue
                Image(systemName: forecast.weatherIcon)
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .blue)
            } else if forecast.isPartiallySunnyIcon {
                // For partially sunny icons
                // Cloud is white, sun is yellow
                Image(systemName: forecast.weatherIcon)
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .yellow)
            } else {
                // For other icons, use the standard color
                Image(systemName: forecast.weatherIcon)
                    .font(.title2)
                    .foregroundStyle(forecast.weatherColor)
            }
            
            Text("\(Int(forecast.temperature))°C")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 3)
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
    
    private var isSidebarVisible: Bool {
        columnVisibility != .detailOnly
    }
    
    var body: some View {
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
    
    private var forecast: DailyForecast {
        cityWeather.forecast(for: dayOffset)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Weather icon
            if forecast.isRainIcon {
                Image(systemName: forecast.weatherIcon)
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .blue)
                    .frame(width: 32, height: 28)
            } else if forecast.isPartiallySunnyIcon {
                Image(systemName: forecast.weatherIcon)
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .yellow)
                    .frame(width: 32, height: 28)
            } else {
                Image(systemName: forecast.weatherIcon)
                    .font(.title3)
                    .foregroundStyle(forecast.weatherColor)
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
