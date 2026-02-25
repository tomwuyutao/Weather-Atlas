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
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Map(position: $position, selection: $selectedCity) {
                ForEach(weatherService.cityWeatherData) { cityWeather in
                    Annotation(cityWeather.city.name, 
                             coordinate: CLLocationCoordinate2D(
                                latitude: cityWeather.city.latitude,
                                longitude: cityWeather.city.longitude
                             )) {
                        WeatherMarker(cityWeather: cityWeather)
                    }
                    .tag(cityWeather)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea()
            
            // Debug info overlay
            VStack(alignment: .leading, spacing: 8) {
                Text("Cities loaded: \(weatherService.cityWeatherData.count)")
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                
                if weatherService.isLoading {
                    Text("Loading weather...")
                        .font(.caption)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            
            // Refresh button
            VStack(spacing: 12) {
                Button(action: {
                    Task {
                        await weatherService.fetchWeatherForAllCities()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .disabled(weatherService.isLoading)
                
                if weatherService.isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding()
        }
        .task {
            print("Starting weather fetch...")
            await weatherService.fetchWeatherForAllCities()
            print("Weather data count: \(weatherService.cityWeatherData.count)")
        }
    }
}

struct WeatherMarker: View {
    let cityWeather: CityWeather
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: cityWeather.weatherIcon)
                .font(.title2)
                .foregroundStyle(cityWeather.weatherColor)
                .shadow(color: .black.opacity(0.3), radius: 2)
            
            Text(cityWeather.city.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
            
            Text("\(Int(cityWeather.temperature))°C")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

#Preview {
    ContentView()
}
