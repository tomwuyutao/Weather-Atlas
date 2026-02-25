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
    
    var body: some View {
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
        .task {
            print("Starting weather fetch...")
            await weatherService.fetchWeatherForAllCities()
            print("Weather data count: \(weatherService.cityWeatherData.count)")
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

#Preview {
    ContentView()
}
