//
//  WeatherService.swift
//  Weather
//
//  Created by Tom on 25/02/2026.
//

import Foundation
import SwiftUI
import WeatherKit
import CoreLocation
import Combine

@Observable
@MainActor
class WeatherService {
    var cityWeatherData: [CityWeather] = []
    var isLoading = false
    
    private let weatherService = WeatherKit.WeatherService.shared
    
    // Major European cities
    let europeanCities: [City] = [
        // Western Europe
        City(name: "London", latitude: 51.5074, longitude: -0.1278),
        City(name: "Paris", latitude: 48.8566, longitude: 2.3522),
        City(name: "Madrid", latitude: 40.4168, longitude: -3.7038),
        City(name: "Lisbon", latitude: 38.7223, longitude: -9.1393),
        City(name: "Dublin", latitude: 53.3498, longitude: -6.2603),
        City(name: "Amsterdam", latitude: 52.3676, longitude: 4.9041),
        City(name: "Brussels", latitude: 50.8503, longitude: 4.3517),
        
        // Central Europe
        City(name: "Berlin", latitude: 52.5200, longitude: 13.4050),
        City(name: "Munich", latitude: 48.1351, longitude: 11.5820),
        City(name: "Vienna", latitude: 48.2082, longitude: 16.3738),
        City(name: "Prague", latitude: 50.0755, longitude: 14.4378),
        City(name: "Zurich", latitude: 47.3769, longitude: 8.5417),
        City(name: "Milan", latitude: 45.4642, longitude: 9.1900),
        
        // Nordic Countries
        City(name: "Stockholm", latitude: 59.3293, longitude: 18.0686),
        City(name: "Copenhagen", latitude: 55.6761, longitude: 12.5683),
        City(name: "Oslo", latitude: 59.9139, longitude: 10.7522),
        City(name: "Helsinki", latitude: 60.1699, longitude: 24.9384),
        
        // Southern Europe
        City(name: "Rome", latitude: 41.9028, longitude: 12.4964),
        City(name: "Athens", latitude: 37.9838, longitude: 23.7275),
        City(name: "Barcelona", latitude: 41.3851, longitude: 2.1734),
        City(name: "Naples", latitude: 40.8518, longitude: 14.2681),
        
        // Eastern Europe
        City(name: "Warsaw", latitude: 52.2297, longitude: 21.0122),
        City(name: "Budapest", latitude: 47.4979, longitude: 19.0402),
        City(name: "Bucharest", latitude: 44.4268, longitude: 26.1025),
        City(name: "Sofia", latitude: 42.6977, longitude: 23.3219),
        City(name: "Kiev", latitude: 50.4501, longitude: 30.5234),
        
        // Other major cities
        City(name: "Istanbul", latitude: 41.0082, longitude: 28.9784),
        City(name: "Lyon", latitude: 45.7640, longitude: 4.8357),
        City(name: "Hamburg", latitude: 53.5511, longitude: 9.9937),
        City(name: "Porto", latitude: 41.1579, longitude: -8.6291)
    ]
    
    func fetchWeatherForAllCities() async {
        isLoading = true
        defer { isLoading = false }
        
        var weatherData: [CityWeather] = []
        
        for city in europeanCities {
            do {
                let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
                let weather = try await weatherService.weather(for: location)
                
                let cityWeather = CityWeather(
                    city: city,
                    condition: weather.currentWeather.condition,
                    temperature: weather.currentWeather.temperature.value,
                    symbolName: weather.currentWeather.symbolName
                )
                
                weatherData.append(cityWeather)
                print("✅ Fetched weather for \(city.name): \(cityWeather.symbolName)")
                
                // Small delay to avoid rate limiting
                try? await Task.sleep(for: .milliseconds(100))
            } catch {
                print("❌ Failed to fetch weather for \(city.name): \(error.localizedDescription)")
                // Add mock data as fallback for testing
                let mockWeather = CityWeather(
                    city: city,
                    condition: .clear,
                    temperature: Double.random(in: 10...25),
                    symbolName: ["sun.max", "cloud.sun", "cloud", "cloud.rain", "cloud.drizzle"].randomElement()!
                )
                weatherData.append(mockWeather)
            }
        }
        
        print("📊 Total cities loaded: \(weatherData.count)")
        self.cityWeatherData = weatherData
    }
}

struct City: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let latitude: Double
    let longitude: Double
}

struct CityWeather: Identifiable, Hashable {
    let id = UUID()
    let city: City
    let condition: WeatherCondition
    let temperature: Double
    let symbolName: String
    
    // Hashable conformance
    static func == (lhs: CityWeather, rhs: CityWeather) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    var weatherIcon: String {
        // Map SF Symbol names to simplified icons
        if symbolName.contains("sun") && !symbolName.contains("cloud") {
            return "sun.max.fill"
        } else if symbolName.contains("cloud") && symbolName.contains("sun") {
            return "cloud.sun.fill"
        } else if symbolName.contains("cloud.rain") || symbolName.contains("rain") {
            return "cloud.rain.fill"
        } else if symbolName.contains("cloud.drizzle") || symbolName.contains("drizzle") {
            return "cloud.drizzle.fill"
        } else if symbolName.contains("snow") {
            return "cloud.snow.fill"
        } else if symbolName.contains("cloud") {
            return "cloud.fill"
        } else if symbolName.contains("wind") {
            return "wind"
        } else if symbolName.contains("fog") {
            return "cloud.fog.fill"
        } else {
            return symbolName
        }
    }
    
    var weatherColor: Color {
        if symbolName.contains("sun") && !symbolName.contains("cloud") {
            return .yellow
        } else if symbolName.contains("cloud") && symbolName.contains("sun") {
            return .orange
        } else if symbolName.contains("rain") {
            return .blue
        } else if symbolName.contains("snow") {
            return .cyan
        } else if symbolName.contains("cloud") {
            return .gray
        } else {
            return .primary
        }
    }
}
