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
import MapKit
import Combine

enum AppWeatherCondition {
    case clear
    case partlyCloudy
    case cloudy
    case rain
    case drizzle
    case snow
    case fog
    case wind
    
    var displayName: String {
        switch self {
        case .clear:
            return "Clear"
        case .partlyCloudy:
            return "Partly Cloudy"
        case .cloudy:
            return "Cloudy"
        case .rain:
            return "Rain"
        case .drizzle:
            return "Drizzle"
        case .snow:
            return "Snow"
        case .fog:
            return "Fog"
        case .wind:
            return "Windy"
        }
    }
    
    var estimatedCloudCover: Int {
        switch self {
        case .clear: return 5
        case .partlyCloudy: return 35
        case .cloudy: return 80
        case .rain: return 90
        case .drizzle: return 90
        case .snow: return 85
        case .fog: return 70
        case .wind: return 20
        }
    }
    
    var dotColor: Color {
        switch self {
        case .clear: return .yellow
        case .partlyCloudy: return Color.yellow.opacity(0.6)
        case .cloudy: return .white
        case .rain: return .blue
        case .drizzle: return Color(red: 0.4, green: 0.55, blue: 0.9)
        case .snow: return Color(red: 0.55, green: 0.65, blue: 0.85)
        case .fog: return .gray
        case .wind: return .white
        }
    }
}

@Observable
@MainActor
class WeatherService {
    var cityWeatherData: [CityWeather] = []
    var isLoading = false
    var forecastDays: [ForecastDay] = []
    var lastFetchDate: Date?
    
    private let weatherService = WeatherKit.WeatherService.shared
    private let cacheKey = "cachedWeatherData"
    private let cacheTimestampKey = "weatherCacheTimestamp"
    private let citiesListKey = "savedCitiesList"  // NEW: Key for persisting the city list
    private let cacheDuration: TimeInterval = 2 * 60 * 60 // 2 hours
    
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
        print("🚀 [DEBUG] fetchWeatherForAllCities() CALLED")
        
        // Check if we have valid cached data
        print("🔍 [DEBUG] Checking cache...")
        let cachedData = loadCachedData()
        let cacheValid = isCacheValid()
        print("🔍 [DEBUG] cachedData=\(cachedData != nil ? "\(cachedData!.count) cities" : "nil"), cacheValid=\(cacheValid)")
        
        if let cachedData = cachedData, cacheValid {
            print("📦 Using CACHED weather data")
            for cw in cachedData {
                print("📦 CACHED \(cw.city.name): temp=\(Int(cw.temperature))°C, icon=\(cw.symbolName), cloud cover=\(cw.dailyForecasts.map { "\(Int($0.cloudCover * 100))%" }.joined(separator: ", ")) [from cache — may be ESTIMATED if old cache]")
            }
            self.cityWeatherData = cachedData
            generateForecastDays()
            print("🏁 [DEBUG] Returned from cache, done.")
            return
        }
        
        print("🌐 [DEBUG] No valid cache, will fetch from WeatherKit...")
        isLoading = true
        defer {
            isLoading = false
            print("🏁 [DEBUG] isLoading set to false")
        }
        
        // Generate 10 days of forecast data
        generateForecastDays()
        
        // Load the saved cities list, or use default European cities if none saved
        let citiesToFetch = loadSavedCities() ?? europeanCities
        print("📍 [DEBUG] Fetching weather for \(citiesToFetch.count) cities: \(citiesToFetch.map { $0.name }.joined(separator: ", "))")
        
        var weatherData: [CityWeather] = []
        
        for (index, city) in citiesToFetch.enumerated() {
            print("🌤️ [DEBUG] [\(index + 1)/\(citiesToFetch.count)] Fetching \(city.name)...")
            do {
                // Fetch real weather data from WeatherKit
                let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
                print("🌤️ [DEBUG] Calling weatherService.weather(for: \(city.name))...")
                let weather = try await weatherService.weather(for: location)
                print("🌤️ [DEBUG] Got WeatherKit response for \(city.name)")
                
                // Convert WeatherKit data to our model
                let cityWeather = await convertWeatherKitData(weather: weather, for: city)
                weatherData.append(cityWeather)
                
                print("✅ [\(index + 1)/\(citiesToFetch.count)] Fetched REAL weather for \(city.name): \(Int(cityWeather.temperature))°C, cloud cover: \(cityWeather.dailyForecasts.map { "\(Int($0.cloudCover * 100))%" }.joined(separator: ", "))")
            } catch let error as NSError {
                print("❌ [DEBUG] Error for \(city.name): domain=\(error.domain), code=\(error.code), desc=\(error.localizedDescription)")
                // Check if this is a WeatherKit authentication error
                if error.domain == "WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors" && error.code == 2 {
                    print("⚠️ WeatherKit authentication failed for \(city.name). Make sure WeatherKit capability is enabled.")
                    print("   Using mock data instead. To fix:")
                    print("   1. Add WeatherKit capability in Signing & Capabilities")
                    print("   2. Enable WeatherKit for your App ID in Developer Portal")
                } else {
                    print("❌ Error fetching weather for \(city.name): \(error.localizedDescription)")
                }
                
                // Skip city — no mock data, will retry on next refresh
                print("⚠️ Skipping \(city.name) — no data available")
            } catch {
                print("❌ [DEBUG] Unexpected error for \(city.name): \(error)")
            }
        }
        
        print("📊 [DEBUG] Total cities loaded: \(weatherData.count) out of \(citiesToFetch.count)")
        self.cityWeatherData = weatherData
        
        // Cache the fetched data
        cacheData(weatherData)
    }
    
    func refreshWeather() async {
        print("🔄 Forcing weather refresh")
        clearCache()
        await fetchWeatherForAllCities()
    }
    
    // MARK: - Caching Methods
    
    private func isCacheValid() -> Bool {
        guard let timestamp = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date else {
            return false
        }
        
        let now = Date()
        let elapsed = now.timeIntervalSince(timestamp)
        let isValid = elapsed < cacheDuration
        
        if isValid {
            print("✅ Cache is valid (age: \(Int(elapsed/60)) minutes)")
        } else {
            print("⏰ Cache expired (age: \(Int(elapsed/60)) minutes)")
        }
        
        return isValid
    }
    
    private func cacheData(_ data: [CityWeather]) {
        do {
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(data.map { CachedCityWeather(from: $0) })
            UserDefaults.standard.set(encoded, forKey: cacheKey)
            UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
            lastFetchDate = Date()
            print("💾 Cached weather data for \(data.count) cities")
        } catch {
            print("❌ Failed to cache weather data: \(error)")
        }
    }
    
    private func loadCachedData() -> [CityWeather]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
            print("📭 No cached data found")
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let cachedWeather = try decoder.decode([CachedCityWeather].self, from: data)
            lastFetchDate = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date
            return cachedWeather.map { $0.toCityWeather() }
        } catch {
            print("❌ Failed to decode cached data: \(error)")
            return nil
        }
    }
    
    private func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: cacheTimestampKey)
        lastFetchDate = nil
        print("🗑️ Cache cleared")
    }
    
    // MARK: - Cities List Persistence
    
    /// Save the current list of cities (just the City objects, not the weather data)
    private func saveCitiesList() {
        let cities = cityWeatherData.map { $0.city }
        
        do {
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(cities.map { CachedCity(from: $0) })
            UserDefaults.standard.set(encoded, forKey: citiesListKey)
            print("💾 Saved cities list: \(cities.map { $0.name }.joined(separator: ", "))")
        } catch {
            print("❌ Failed to save cities list: \(error)")
        }
    }
    
    /// Load the saved cities list (returns nil if no list was saved)
    private func loadSavedCities() -> [City]? {
        guard let data = UserDefaults.standard.data(forKey: citiesListKey) else {
            print("📭 No saved cities list found, using default European cities")
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let cachedCities = try decoder.decode([CachedCity].self, from: data)
            let cities = cachedCities.map { $0.toCity() }
            print("📍 Loaded \(cities.count) saved cities: \(cities.map { $0.name }.joined(separator: ", "))")
            return cities
        } catch {
            print("❌ Failed to decode saved cities: \(error)")
            return nil
        }
    }
    
    // Helper function to get timezone for a location
    private func getTimeZone(for location: CLLocation) async -> TimeZone {
        if let request = MKReverseGeocodingRequest(location: location) {
            do {
                let mapItems = try await request.mapItems
                if let timeZone = mapItems.first?.timeZone {
                    return timeZone
                }
            } catch {
                print("⚠️ Could not determine timezone for location: \(error.localizedDescription)")
            }
        }
        // Fallback to UTC if we can't determine the timezone
        return TimeZone(identifier: "UTC") ?? TimeZone.current
    }
    
    private func convertWeatherKitData(weather: Weather, for city: City) async -> CityWeather {
        // Current weather
        let currentTemp = weather.currentWeather.temperature.value
        let currentCondition = mapWeatherKitCondition(weather.currentWeather.condition)
        let currentSymbol = weather.currentWeather.symbolName
        
        // Get timezone for the city location
        let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
        let timeZone = await getTimeZone(for: location)
        
        // Daily forecasts
        let dailyForecasts = weather.dailyForecast.forecast.prefix(10).enumerated().map { (index, day) -> DailyForecast in
            let daytimeForecast = day.daytimeForecast
            let daySymbol = day.symbolName
            let dayCondition = mapWeatherKitCondition(day.condition)
            
            // Generate hourly forecasts for this day
            let hourlyForecasts = generateHourlyFromDaily(day: day, dayOffset: index, allHourly: weather.hourlyForecast.forecast, timeZone: timeZone)
            
            return DailyForecast(
                dayOffset: index,
                daytimeLow: daytimeForecast.lowTemperature.value,
                daytimeHigh: daytimeForecast.highTemperature.value,
                symbolName: daySymbol,
                condition: dayCondition,
                hourlyForecasts: hourlyForecasts,
                cloudCover: daytimeForecast.cloudCover,
                precipitationChance: day.precipitationChance
            )
        }
        
        return CityWeather(
            city: city,
            condition: currentCondition,
            temperature: currentTemp,
            symbolName: currentSymbol,
            dailyForecasts: Array(dailyForecasts)
        )
    }
    
    private func generateHourlyFromDaily(day: DayWeather, dayOffset: Int, allHourly: [HourWeather], timeZone: TimeZone) -> [HourlyForecast] {
        // Use the city's local calendar for the day calculation
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        
        let dayStart = calendar.startOfDay(for: day.date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        
        // Filter hourly forecasts for this specific day
        let dayHourlyData = allHourly.filter { hourWeather in
            hourWeather.date >= dayStart && hourWeather.date < dayEnd
        }
        
        // If we have real hourly data, use it
        if !dayHourlyData.isEmpty {
            return dayHourlyData.map { hourWeather in
                // Extract hour in the city's local timezone
                let hour = calendar.component(.hour, from: hourWeather.date)
                return HourlyForecast(
                    hour: hour,
                    temperature: hourWeather.temperature.value,
                    symbolName: hourWeather.symbolName,
                    condition: mapWeatherKitCondition(hourWeather.condition),
                    precipitationChance: hourWeather.precipitationChance,
                    cloudCover: hourWeather.cloudCover
                )
            }
        }
        
        // Fallback: Generate 24 hours based on the daily forecast
        print("⚠️ No real hourly data for day \(dayOffset), using fallback hourly from daily forecast")
        let daytime = day.daytimeForecast
        let fallbackCloudCover = daytime.cloudCover
        let baseTemp = (daytime.lowTemperature.value + daytime.highTemperature.value) / 2.0
        return (0..<24).map { hour in
            let hourVariation = calculateHourVariation(hour: hour)
            let temp = baseTemp + hourVariation
            
            return HourlyForecast(
                hour: hour,
                temperature: temp,
                symbolName: day.symbolName,
                condition: mapWeatherKitCondition(day.condition),
                precipitationChance: day.precipitationChance,
                cloudCover: fallbackCloudCover
            )
        }
    }
    
    private func calculateHourVariation(hour: Int) -> Double {
        if hour < 6 {
            return -6.0
        } else if hour < 12 {
            return -3.0 + Double(hour - 6) * 0.5
        } else if hour < 16 {
            return 0.0
        } else if hour < 20 {
            return -1.0 - Double(hour - 16) * 0.5
        } else {
            return -4.0
        }
    }
    
    private func mapWeatherKitCondition(_ condition: WeatherCondition) -> AppWeatherCondition {
        switch condition {
        case .clear, .mostlyClear:
            return .clear
        case .partlyCloudy, .mostlyCloudy:
            return .partlyCloudy
        case .cloudy:
            return .cloudy
        case .rain, .heavyRain, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms, .thunderstorms, .sunShowers:
            return .rain
        case .drizzle, .freezingDrizzle:
            return .drizzle
        case .snow, .blowingSnow, .flurries, .freezingRain, .heavySnow, .sleet, .wintryMix, .sunFlurries:
            return .snow
        case .haze, .smoky, .foggy:
            return .fog
        case .blizzard, .blowingDust, .breezy, .frigid, .hail, .hot, .hurricane, .tropicalStorm, .windy:
            return .wind
        @unknown default:
            return .partlyCloudy
        }
    }
    
    func removeCity(_ cityWeather: CityWeather) {
        cityWeatherData.removeAll { $0.id == cityWeather.id }
        // Update cache after removing city
        cacheData(cityWeatherData)
        // Save the updated cities list
        saveCitiesList()
    }
    
    func addCity(_ city: City) async {
        print("📍 Adding city: \(city.name)")
        
        do {
            // Fetch weather for the new city
            let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
            let weather = try await weatherService.weather(for: location)
            
            // Convert to our model
            let cityWeather = await convertWeatherKitData(weather: weather, for: city)
            
            // Add to the beginning of the list
            cityWeatherData.insert(cityWeather, at: 0)
            
            // Update cache with the new city included
            cacheData(cityWeatherData)
            
            // Save the updated cities list
            saveCitiesList()
            
            print("✅ Added REAL weather for \(city.name): \(Int(cityWeather.temperature))°C, cloud cover: \(cityWeather.dailyForecasts.map { "\(Int($0.cloudCover * 100))%" }.joined(separator: ", "))")
        } catch {
            print("❌ Error fetching weather for \(city.name): \(error.localizedDescription)")
            print("⚠️ City \(city.name) not added — no data available")
        }
    }
    
    func fetchWeatherForCity(_ city: City) async -> CityWeather? {
        print("🔍 Fetching weather for \(city.name) (temporary)")
        
        do {
            // Fetch weather for the city
            let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
            let weather = try await weatherService.weather(for: location)
            
            // Convert to our model
            let cityWeather = await convertWeatherKitData(weather: weather, for: city)
            
            print("✅ Fetched REAL weather for \(city.name): \(Int(cityWeather.temperature))°C, cloud cover: \(cityWeather.dailyForecasts.map { "\(Int($0.cloudCover * 100))%" }.joined(separator: ", "))")
            return cityWeather
        } catch {
            print("❌ Error fetching weather for \(city.name): \(error.localizedDescription)")
            print("⚠️ No data available for \(city.name)")
            return nil
        }
    }
    
    func moveCity(from source: IndexSet, to destination: Int) {
        cityWeatherData.move(fromOffsets: source, toOffset: destination)
        // Update cache after reordering cities
        cacheData(cityWeatherData)
        // Save the updated cities list
        saveCitiesList()
    }
    
    private func generateForecastDays() {
        let calendar = Calendar.current
        let today = Date()
        
        forecastDays = (0..<10).map { dayOffset in
            let date = calendar.date(byAdding: .day, value: dayOffset, to: today)!
            return ForecastDay(date: date, dayOffset: dayOffset)
        }
    }
    
}

struct City: Identifiable, Hashable, Codable {
    var id = UUID()
    let name: String
    let latitude: Double
    let longitude: Double
}

struct CityWeather: Identifiable, Hashable {
    let id = UUID()
    let city: City
    let condition: AppWeatherCondition
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
        } else if dayOffset == 1 {
            return "Tomorrow"
        } else {
            let calendar = Calendar.current
            let day = calendar.component(.day, from: date)
            let month = calendar.component(.month, from: date)
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            let weekday = formatter.string(from: date)
            return "\(weekday), \(day)/\(month)"
        }
    }
    
    var veryShortDisplayText: String {
        if dayOffset == 0 {
            return "Today"
        } else if dayOffset == 1 {
            return "Tmrw"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter.string(from: date)
        }
    }
}

struct DailyForecast: Identifiable {
    let id = UUID()
    let dayOffset: Int
    let daytimeLow: Double   // 7AM-7PM low temperature
    let daytimeHigh: Double  // 7AM-7PM high temperature
    let symbolName: String
    let condition: AppWeatherCondition
    let hourlyForecasts: [HourlyForecast]
    let cloudCover: Double  // 0.0 to 1.0
    let precipitationChance: Double  // 0.0 to 1.0
    
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
    
    // Light mode high-contrast color
    func weatherColor(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .light {
            // Subtle contrast increase for light mode
            if symbolName.contains("sun") && !symbolName.contains("cloud") {
                return Color(red: 1.0, green: 0.8, blue: 0.0)  // Slightly more orange than yellow
            } else {
                return .white  // Keep original cloud color
            }
        } else {
            // Keep original colors for dark mode
            return weatherColor
        }
    }
    
    // Palette colors for rain icons in light mode
    func rainPaletteColors(for colorScheme: ColorScheme) -> (primary: Color, secondary: Color) {
        if colorScheme == .light {
            return (.white, Color(red: 0.0, green: 0.48, blue: 1.0))  // Original cloud, slightly deeper blue rain
        } else {
            return (.white, .blue)  // Original for dark mode
        }
    }
    
    // Palette colors for partially sunny icons in light mode
    func partlySunnyPaletteColors(for colorScheme: ColorScheme) -> (primary: Color, secondary: Color) {
        if colorScheme == .light {
            return (.white, Color(red: 1.0, green: 0.8, blue: 0.0))  // Original cloud, slightly more orange sun
        } else {
            return (.white, .yellow)  // Original for dark mode
        }
    }
    
    var isRainIcon: Bool {
        symbolName.contains("rain") || symbolName.contains("drizzle")
    }
    
    var isPartiallySunnyIcon: Bool {
        symbolName.contains("cloud") && symbolName.contains("sun")
    }
    
    var cloudCoverPercent: Int {
        Int(cloudCover * 100)
    }
    
    var daytimeTempString: String {
        "\(Int(daytimeLow))-\(Int(daytimeHigh))°"
    }
}

struct HourlyForecast: Identifiable {
    let id = UUID()
    let hour: Int  // 0-23
    let temperature: Double
    let symbolName: String
    let condition: AppWeatherCondition
    let precipitationChance: Double  // 0.0 to 1.0
    let cloudCover: Double  // 0.0 to 1.0
    
    var weatherIcon: String {
        if symbolName.contains("sun") && !symbolName.contains("cloud") {
            return "sun.max.fill"
        } else if symbolName.contains("moon") && !symbolName.contains("cloud") {
            return "moon.fill"
        } else if symbolName.contains("cloud") && symbolName.contains("sun") {
            return "cloud.sun.fill"
        } else if symbolName.contains("cloud") && symbolName.contains("moon") {
            return "cloud.moon.fill"
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
    
    func weatherColor(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .light {
            if symbolName.contains("sun") && !symbolName.contains("cloud") {
                return Color(red: 1.0, green: 0.8, blue: 0.0)
            } else if symbolName.contains("moon") && !symbolName.contains("cloud") {
                return .indigo
            } else {
                return .white
            }
        } else {
            if symbolName.contains("sun") && !symbolName.contains("cloud") {
                return .yellow
            } else if symbolName.contains("moon") && !symbolName.contains("cloud") {
                return .white
            } else {
                return .white
            }
        }
    }
    
    func rainPaletteColors(for colorScheme: ColorScheme) -> (primary: Color, secondary: Color) {
        if colorScheme == .light {
            return (.white, Color(red: 0.0, green: 0.48, blue: 1.0))
        } else {
            return (.white, .blue)
        }
    }
    
    func partlySunnyPaletteColors(for colorScheme: ColorScheme) -> (primary: Color, secondary: Color) {
        if colorScheme == .light {
            return (.white, Color(red: 1.0, green: 0.8, blue: 0.0))
        } else {
            return (.white, .yellow)
        }
    }
    
    func partlyMoonPaletteColors(for colorScheme: ColorScheme) -> (primary: Color, secondary: Color) {
        if colorScheme == .light {
            return (.white, .indigo)
        } else {
            return (.white, .white)
        }
    }
    
    var isRainIcon: Bool {
        symbolName.contains("rain") || symbolName.contains("drizzle")
    }
    
    var isPartiallySunnyIcon: Bool {
        symbolName.contains("cloud") && symbolName.contains("sun")
    }
    
    var isPartlyMoonIcon: Bool {
        symbolName.contains("cloud") && symbolName.contains("moon")
    }
    
    var cloudCoverPercent: Int {
        Int(cloudCover * 100)
    }
    
    var formattedHour: String {
        if hour == 0 {
            return "12 AM"
        } else if hour < 12 {
            return "\(hour) AM"
        } else if hour == 12 {
            return "12 PM"
        } else {
            return "\(hour - 12) PM"
        }
    }
    
    var shortFormattedHour: String {
        if hour == 0 {
            return "12am"
        } else if hour < 12 {
            return "\(hour)am"
        } else if hour == 12 {
            return "12pm"
        } else {
            return "\(hour - 12)pm"
        }
    }
}

// MARK: - Cache Models

struct CachedCity: Codable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    
    init(from city: City) {
        self.id = city.id
        self.name = city.name
        self.latitude = city.latitude
        self.longitude = city.longitude
    }
    
    func toCity() -> City {
        return City(id: id, name: name, latitude: latitude, longitude: longitude)
    }
}

struct CachedCityWeather: Codable {
    let cityId: UUID
    let cityName: String
    let cityLatitude: Double
    let cityLongitude: Double
    let condition: String
    let temperature: Double
    let symbolName: String
    let dailyForecasts: [CachedDailyForecast]
    
    init(from cityWeather: CityWeather) {
        self.cityId = cityWeather.city.id
        self.cityName = cityWeather.city.name
        self.cityLatitude = cityWeather.city.latitude
        self.cityLongitude = cityWeather.city.longitude
        self.condition = cityWeather.condition.displayName
        self.temperature = cityWeather.temperature
        self.symbolName = cityWeather.symbolName
        self.dailyForecasts = cityWeather.dailyForecasts.map { CachedDailyForecast(from: $0) }
    }
    
    func toCityWeather() -> CityWeather {
        let city = City(id: cityId, name: cityName, latitude: cityLatitude, longitude: cityLongitude)
        let appCondition = AppWeatherCondition.fromDisplayName(condition)
        let forecasts = dailyForecasts.map { $0.toDailyForecast() }
        
        return CityWeather(
            city: city,
            condition: appCondition,
            temperature: temperature,
            symbolName: symbolName,
            dailyForecasts: forecasts
        )
    }
}
struct CachedDailyForecast: Codable {
    let dayOffset: Int
    let daytimeLow: Double
    let daytimeHigh: Double
    let symbolName: String
    let condition: String
    let hourlyForecasts: [CachedHourlyForecast]
    let cloudCover: Double
    let precipitationChance: Double
    
    init(from forecast: DailyForecast) {
        self.dayOffset = forecast.dayOffset
        self.daytimeLow = forecast.daytimeLow
        self.daytimeHigh = forecast.daytimeHigh
        self.symbolName = forecast.symbolName
        self.condition = forecast.condition.displayName
        self.hourlyForecasts = forecast.hourlyForecasts.map { CachedHourlyForecast(from: $0) }
        self.cloudCover = forecast.cloudCover
        self.precipitationChance = forecast.precipitationChance
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayOffset = try container.decode(Int.self, forKey: .dayOffset)
        // Migration: old cache had single `temperature`, new cache has daytimeLow/daytimeHigh
        if let low = try container.decodeIfPresent(Double.self, forKey: .daytimeLow),
           let high = try container.decodeIfPresent(Double.self, forKey: .daytimeHigh) {
            daytimeLow = low
            daytimeHigh = high
        } else {
            let temp = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 15.0
            daytimeLow = temp - 3.0
            daytimeHigh = temp
        }
        symbolName = try container.decode(String.self, forKey: .symbolName)
        condition = try container.decode(String.self, forKey: .condition)
        hourlyForecasts = try container.decode([CachedHourlyForecast].self, forKey: .hourlyForecasts)
        cloudCover = try container.decodeIfPresent(Double.self, forKey: .cloudCover)
            ?? Double(AppWeatherCondition.fromDisplayName(condition).estimatedCloudCover) / 100.0
        precipitationChance = try container.decodeIfPresent(Double.self, forKey: .precipitationChance) ?? 0.0
    }
    
    // Keep the old key for migration during decoding
    private enum CodingKeys: String, CodingKey {
        case dayOffset, daytimeLow, daytimeHigh, symbolName, condition, hourlyForecasts, cloudCover, precipitationChance, temperature
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dayOffset, forKey: .dayOffset)
        try container.encode(daytimeLow, forKey: .daytimeLow)
        try container.encode(daytimeHigh, forKey: .daytimeHigh)
        try container.encode(symbolName, forKey: .symbolName)
        try container.encode(condition, forKey: .condition)
        try container.encode(hourlyForecasts, forKey: .hourlyForecasts)
        try container.encode(cloudCover, forKey: .cloudCover)
        try container.encode(precipitationChance, forKey: .precipitationChance)
    }
    
    func toDailyForecast() -> DailyForecast {
        let appCondition = AppWeatherCondition.fromDisplayName(condition)
        let forecasts = hourlyForecasts.map { $0.toHourlyForecast() }
        
        return DailyForecast(
            dayOffset: dayOffset,
            daytimeLow: daytimeLow,
            daytimeHigh: daytimeHigh,
            symbolName: symbolName,
            condition: appCondition,
            hourlyForecasts: forecasts,
            cloudCover: cloudCover,
            precipitationChance: precipitationChance
        )
    }
}

struct CachedHourlyForecast: Codable {
    let hour: Int
    let temperature: Double
    let symbolName: String
    let condition: String
    let precipitationChance: Double
    let cloudCover: Double
    
    init(from forecast: HourlyForecast) {
        self.hour = forecast.hour
        self.temperature = forecast.temperature
        self.symbolName = forecast.symbolName
        self.condition = forecast.condition.displayName
        self.precipitationChance = forecast.precipitationChance
        self.cloudCover = forecast.cloudCover
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hour = try container.decode(Int.self, forKey: .hour)
        temperature = try container.decode(Double.self, forKey: .temperature)
        symbolName = try container.decode(String.self, forKey: .symbolName)
        condition = try container.decode(String.self, forKey: .condition)
        precipitationChance = try container.decode(Double.self, forKey: .precipitationChance)
        cloudCover = try container.decodeIfPresent(Double.self, forKey: .cloudCover)
            ?? Double(AppWeatherCondition.fromDisplayName(condition).estimatedCloudCover) / 100.0
    }
    
    func toHourlyForecast() -> HourlyForecast {
        let appCondition = AppWeatherCondition.fromDisplayName(condition)
        
        return HourlyForecast(
            hour: hour,
            temperature: temperature,
            symbolName: symbolName,
            condition: appCondition,
            precipitationChance: precipitationChance,
            cloudCover: cloudCover
        )
    }
}

extension AppWeatherCondition {
    static func fromDisplayName(_ name: String) -> AppWeatherCondition {
        switch name {
        case "Clear":
            return .clear
        case "Partly Cloudy":
            return .partlyCloudy
        case "Cloudy":
            return .cloudy
        case "Rain":
            return .rain
        case "Drizzle":
            return .drizzle
        case "Snow":
            return .snow
        case "Fog":
            return .fog
        case "Windy":
            return .wind
        default:
            return .partlyCloudy
        }
    }
}


