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
    var forecastDays: [ForecastDay] = []
    
    private let weatherService = WeatherKit.WeatherService.shared
    
    // European cities
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
        
        // Nordic Countries
        City(name: "Stockholm", latitude: 59.3293, longitude: 18.0686),
        City(name: "Copenhagen", latitude: 55.6761, longitude: 12.5683),
        City(name: "Oslo", latitude: 59.9139, longitude: 10.7522),
        City(name: "Helsinki", latitude: 60.1699, longitude: 24.9384),
        
        // Southern Europe
        City(name: "Rome", latitude: 41.9028, longitude: 12.4964),
        City(name: "Athens", latitude: 37.9838, longitude: 23.7275),
        City(name: "Barcelona", latitude: 41.3851, longitude: 2.1734),
        City(name: "Milan", latitude: 45.4642, longitude: 9.1900),
        
        // Eastern Europe
        City(name: "Warsaw", latitude: 52.2297, longitude: 21.0122),
        City(name: "Budapest", latitude: 47.4979, longitude: 19.0402),
        City(name: "Bucharest", latitude: 44.4268, longitude: 26.1025),
        City(name: "Sofia", latitude: 42.6977, longitude: 23.3219),
        City(name: "Istanbul", latitude: 41.0082, longitude: 28.9784)
    ]
    
    func fetchWeatherForAllCities() async {
        isLoading = true
        defer { isLoading = false }
        
        // Generate 10 days of forecast data
        generateForecastDays()
        
        var weatherData: [CityWeather] = []
        
        for city in europeanCities {
            // Use dummy data for now
            let mockWeather = CityWeather(
                city: city,
                condition: .clear,
                temperature: Double.random(in: 10...25),
                symbolName: ["sun.max", "cloud.sun", "cloud", "cloud.rain", "cloud.drizzle"].randomElement()!,
                dailyForecasts: generateDummyForecast(for: city)
            )
            weatherData.append(mockWeather)
        }
        
        print("📊 Total cities loaded: \(weatherData.count)")
        self.cityWeatherData = weatherData
    }
    
    func removeCity(_ cityWeather: CityWeather) {
        cityWeatherData.removeAll { $0.id == cityWeather.id }
    }
    
    func moveCity(from source: IndexSet, to destination: Int) {
        cityWeatherData.move(fromOffsets: source, toOffset: destination)
    }
    
    private func generateForecastDays() {
        let calendar = Calendar.current
        let today = Date()
        
        forecastDays = (0..<10).map { dayOffset in
            let date = calendar.date(byAdding: .day, value: dayOffset, to: today)!
            return ForecastDay(date: date, dayOffset: dayOffset)
        }
    }
    
    private func generateDummyForecast(for city: City) -> [DailyForecast] {
        return (0..<10).map { dayOffset in
            // Generate semi-realistic temperature variations
            let baseTemp = Double.random(in: 8...22)
            let variation = Double.random(in: -3...3)
            let temp = baseTemp + variation
            
            // Random weather conditions with some continuity
            let conditions = ["sun.max", "sun.max", "cloud.sun", "cloud", "cloud.rain", "cloud.drizzle"]
            let symbol = conditions.randomElement()!
            
            return DailyForecast(
                dayOffset: dayOffset,
                temperature: temp,
                symbolName: symbol,
                condition: [.clear, .partlyCloudy, .cloudy, .rain, .drizzle].randomElement()!
            )
        }
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
    let dailyForecasts: [DailyForecast]
    
    // Hashable conformance
    static func == (lhs: CityWeather, rhs: CityWeather) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // Get forecast for a specific day
    func forecast(for dayOffset: Int) -> DailyForecast {
        dailyForecasts.first { $0.dayOffset == dayOffset } ?? dailyForecasts[0]
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
        } else {
            return .white
        }
    }
}
// MARK: - Forecast Models

struct ForecastDay: Identifiable {
    let id = UUID()
    let date: Date
    let dayOffset: Int
    
    var displayText: String {
        if dayOffset == 0 {
            return "Today"
        } else if dayOffset == 1 {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, MMM d"
            return formatter.string(from: date)
        }
    }
    
    var shortDisplayText: String {
        if dayOffset == 0 {
            return "Today"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE d"
            return formatter.string(from: date)
        }
    }
}

struct DailyForecast {
    let dayOffset: Int
    let temperature: Double
    let symbolName: String
    let condition: WeatherCondition
    
    var weatherIcon: String {
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
        } else {
            return symbolName
        }
    }
    
    var weatherColor: Color {
        if symbolName.contains("sun") && !symbolName.contains("cloud") {
            return .yellow
        } else {
            return .white
        }
    }
    
    var isRainIcon: Bool {
        symbolName.contains("rain") || symbolName.contains("drizzle")
    }
    
    var isPartiallySunnyIcon: Bool {
        symbolName.contains("cloud") && symbolName.contains("sun")
    }
}


