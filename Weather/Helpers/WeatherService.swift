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

/// Look up a localized string for a specific locale (respects SwiftUI environment locale).
func localizedString(_ key: String.LocalizationValue, locale: Locale) -> String {
    var resource = LocalizedStringResource(key)
    resource.locale = locale
    return String(localized: resource)
}

enum AppWeatherCondition {
    case clear
    case partlyCloudy
    case cloudy
    case rain
    case drizzle
    case snow
    case fog
    case wind
    
    /// Internal name used for cache serialization — do NOT localize
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
    
    func localizedDisplayName(locale: Locale = .current) -> String {
        switch self {
        case .clear:
            return localizedString("Clear", locale: locale)
        case .partlyCloudy:
            return localizedString("Partly Cloudy", locale: locale)
        case .cloudy:
            return localizedString("Cloudy", locale: locale)
        case .rain:
            return localizedString("Rain", locale: locale)
        case .drizzle:
            return localizedString("Drizzle", locale: locale)
        case .snow:
            return localizedString("Snow", locale: locale)
        case .fog:
            return localizedString("Fog", locale: locale)
        case .wind:
            return localizedString("Windy", locale: locale)
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
        dotColor(for: AppTheme.shared.colors)
    }
    
    func dotColor(for theme: ThemeColors) -> Color {
        switch self {
        case .clear: return theme.dotSun
        case .partlyCloudy: return theme.dotPartlyCloudy
        case .cloudy: return theme.dotCloudy
        case .rain: return theme.dotRain
        case .drizzle: return theme.dotDrizzle
        case .snow: return theme.dotSnow
        case .fog: return theme.dotFog
        case .wind: return theme.dotWind
        }
    }
}

struct CityListID: Identifiable, Equatable, Hashable, Codable {
    let rawValue: String
    let displayName: String
    
    var id: String { rawValue }
    
    static let china = CityListID(rawValue: "china", displayName: "China")
    static let europe = CityListID(rawValue: "europe", displayName: "Europe")
    
    func localizedDisplayName(locale: Locale = .current) -> String {
        switch rawValue {
        case "china": return localizedString("China", locale: locale)
        case "europe": return localizedString("Europe", locale: locale)
        default: return displayName
        }
    }
    
    static let builtInLists: [CityListID] = [.china, .europe]
    
    private static let userListsKey = "userCreatedLists"
    private static let deletedBuiltInListsKey = "deletedBuiltInLists"
    private static let listOrderKey = "listOrder"
    
    static var allLists: [CityListID] {
        let deletedIDs = loadDeletedBuiltInIDs()
        // Build the unordered pool of available lists
        let availableBuiltIn = builtInLists.filter { !deletedIDs.contains($0.rawValue) }
        let userLists = loadUserLists()
        let allAvailable = availableBuiltIn + userLists
        
        // Apply custom order if saved
        if let orderData = UserDefaults.standard.data(forKey: listOrderKey),
           let orderedIDs = try? JSONDecoder().decode([String].self, from: orderData) {
            let lookup = Dictionary(uniqueKeysWithValues: allAvailable.map { ($0.rawValue, $0) })
            var ordered = orderedIDs.compactMap { lookup[$0] }
            // Append any lists not in the saved order (newly created)
            let orderedSet = Set(orderedIDs)
            for list in allAvailable where !orderedSet.contains(list.rawValue) {
                ordered.append(list)
            }
            return ordered
        }
        
        return allAvailable
    }
    
    static func saveListOrder(_ lists: [CityListID]) {
        let ids = lists.map(\.rawValue)
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: listOrderKey)
        }
    }
    
    static func loadUserLists() -> [CityListID] {
        guard let data = UserDefaults.standard.data(forKey: userListsKey),
              let lists = try? JSONDecoder().decode([CityListID].self, from: data) else {
            return []
        }
        // Give empty-named lists a fallback name instead of deleting them
        let fixed = lists.map { list in
            if list.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return CityListID(rawValue: list.rawValue, displayName: String(localized: "New List"))
            }
            return list
        }
        if fixed != lists {
            saveUserLists(fixed)
        }
        return fixed
    }
    
    static func saveUserLists(_ lists: [CityListID]) {
        if let data = try? JSONEncoder().encode(lists) {
            UserDefaults.standard.set(data, forKey: userListsKey)
        }
    }
    
    private static func loadDeletedBuiltInIDs() -> Set<String> {
        let ids = UserDefaults.standard.stringArray(forKey: deletedBuiltInListsKey) ?? []
        return Set(ids)
    }
    
    static func deleteBuiltInList(_ listID: CityListID) {
        var deleted = loadDeletedBuiltInIDs()
        deleted.insert(listID.rawValue)
        UserDefaults.standard.set(Array(deleted), forKey: deletedBuiltInListsKey)
    }
    
    static func restoreBuiltInLists() {
        UserDefaults.standard.removeObject(forKey: deletedBuiltInListsKey)
        UserDefaults.standard.removeObject(forKey: listOrderKey)
    }
    
    static func createList(name: String) -> CityListID {
        let id = CityListID(rawValue: UUID().uuidString, displayName: name)
        var userLists = loadUserLists()
        userLists.append(id)
        saveUserLists(userLists)
        return id
    }
    
    var defaultCities: [City] {
        switch rawValue {
        case "china":
            return [
                City(name: "Beijing", country: "China", latitude: 39.9042, longitude: 116.4074),
                City(name: "Shanghai", country: "China", latitude: 31.2304, longitude: 121.4737),
                City(name: "Chongqing", country: "China", latitude: 29.4316, longitude: 106.9123),
                City(name: "Tianjin", country: "China", latitude: 39.3434, longitude: 117.3616),
                City(name: "Guangzhou", country: "China", latitude: 23.1291, longitude: 113.2644),
                City(name: "Shenzhen", country: "China", latitude: 22.5431, longitude: 114.0579),
                City(name: "Hangzhou", country: "China", latitude: 30.2741, longitude: 120.1551),
                City(name: "Nanjing", country: "China", latitude: 32.0603, longitude: 118.7969),
                City(name: "Suzhou", country: "China", latitude: 31.2990, longitude: 120.5853),
                City(name: "Xiamen", country: "China", latitude: 24.4798, longitude: 118.0894),
                City(name: "Wuhan", country: "China", latitude: 30.5928, longitude: 114.3055),
                City(name: "Changsha", country: "China", latitude: 28.2282, longitude: 112.9388),
                City(name: "Zhengzhou", country: "China", latitude: 34.7466, longitude: 113.6253),
                City(name: "Xi'an", country: "China", latitude: 34.3416, longitude: 108.9398),
                City(name: "Harbin", country: "China", latitude: 45.8038, longitude: 126.5350),
                City(name: "Dalian", country: "China", latitude: 38.9140, longitude: 121.6147),
                City(name: "Qingdao", country: "China", latitude: 36.0671, longitude: 120.3826),
                City(name: "Chengdu", country: "China", latitude: 30.5728, longitude: 104.0668),
                City(name: "Kunming", country: "China", latitude: 25.0389, longitude: 102.7183),
                City(name: "Guiyang", country: "China", latitude: 26.6470, longitude: 106.6302),
                City(name: "Sanya", country: "China", latitude: 18.2528, longitude: 109.5120),
                City(name: "Fuzhou", country: "China", latitude: 26.0745, longitude: 119.2965),
                City(name: "Lhasa", country: "China", latitude: 29.6500, longitude: 91.1000),
                City(name: "Urumqi", country: "China", latitude: 43.8256, longitude: 87.6168),
                City(name: "Lanzhou", country: "China", latitude: 36.0611, longitude: 103.8343),
            ]
        case "europe":
            return [
                City(name: "London", country: "England", latitude: 51.5074, longitude: -0.1278),
                City(name: "Paris", country: "France", latitude: 48.8566, longitude: 2.3522),
                City(name: "Berlin", country: "Germany", latitude: 52.5200, longitude: 13.4050),
                City(name: "Madrid", country: "Spain", latitude: 40.4168, longitude: -3.7038),
                City(name: "Rome", country: "Italy", latitude: 41.9028, longitude: 12.4964),
                City(name: "Amsterdam", country: "Netherlands", latitude: 52.3676, longitude: 4.9041),
                City(name: "Vienna", country: "Austria", latitude: 48.2082, longitude: 16.3738),
                City(name: "Prague", country: "Czechia", latitude: 50.0755, longitude: 14.4378),
                City(name: "Barcelona", country: "Spain", latitude: 41.3874, longitude: 2.1686),
                City(name: "Munich", country: "Germany", latitude: 48.1351, longitude: 11.5820),
                City(name: "Milan", country: "Italy", latitude: 45.4642, longitude: 9.1900),
                City(name: "Stockholm", country: "Sweden", latitude: 59.3293, longitude: 18.0686),
                City(name: "Copenhagen", country: "Denmark", latitude: 55.6761, longitude: 12.5683),
                City(name: "Oslo", country: "Norway", latitude: 59.9139, longitude: 10.7522),
                City(name: "Helsinki", country: "Finland", latitude: 60.1699, longitude: 24.9384),
                City(name: "Warsaw", country: "Poland", latitude: 52.2297, longitude: 21.0122),
                City(name: "Budapest", country: "Hungary", latitude: 47.4979, longitude: 19.0402),
                City(name: "Lisbon", country: "Portugal", latitude: 38.7223, longitude: -9.1393),
                City(name: "Athens", country: "Greece", latitude: 37.9838, longitude: 23.7275),
                City(name: "Dublin", country: "Ireland", latitude: 53.3498, longitude: -6.2603),
                City(name: "Brussels", country: "Belgium", latitude: 50.8503, longitude: 4.3517),
                City(name: "Zurich", country: "Switzerland", latitude: 47.3769, longitude: 8.5417),
                City(name: "Istanbul", country: "Turkey", latitude: 41.0082, longitude: 28.9784),
                City(name: "Bucharest", country: "Romania", latitude: 44.4268, longitude: 26.1025),
                City(name: "Edinburgh", country: "Scotland", latitude: 55.9533, longitude: -3.1883),
            ]
        default:
            return [] // User-created lists start empty
        }
    }
}

@Observable
@MainActor
class WeatherService {
    var cityWeatherData: [CityWeather] = []
    var isLoading = false
    var loadingProgress: Double = 0
    var forecastDays: [ForecastDay] = []
    var lastFetchDate: Date?
    var activeListID: CityListID = .europe
    
    var hasSavedCities: Bool {
        UserDefaults.standard.data(forKey: citiesListKey) != nil
    }
    
    private let weatherService = WeatherKit.WeatherService.shared
    private let cacheDuration: TimeInterval = 2 * 60 * 60 // 2 hours
    
    private static let activeListKey = "activeListID"
    
    // Per-list cache keys
    private var cacheKey: String { "cachedWeatherData_\(activeListID.rawValue)" }
    private var cacheTimestampKey: String { "weatherCacheTimestamp_\(activeListID.rawValue)" }
    private var citiesListKey: String { "savedCitiesList_\(activeListID.rawValue)" }
    
    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.activeListKey),
           let listID = CityListID.allLists.first(where: { $0.rawValue == saved }) {
            activeListID = listID
        }
    }
    
    func fetchWeatherForAllCities() async {
        // Check if we have valid cached data
        let cachedData = loadCachedData()
        let cacheValid = isCacheValid()
        
        if let cachedData = cachedData, cacheValid {
            self.cityWeatherData = cachedData
            generateForecastDays()
            print("\(cachedData.count) cities loaded from cache")
            return
        }
        
        isLoading = true
        loadingProgress = 0
        defer {
            isLoading = false
        }
        
        // Generate 10 days of forecast data
        generateForecastDays()
        
        // Load the saved cities list, or use defaults for active list
        let citiesToFetch = loadSavedCities() ?? activeListID.defaultCities
        
        var weatherData: [CityWeather] = []
        
        for (index, city) in citiesToFetch.enumerated() {
            do {
                let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
                let weather = try await weatherService.weather(for: location)
                let cityWeather = await convertWeatherKitData(weather: weather, for: city)
                weatherData.append(cityWeather)
                withAnimation(.easeInOut(duration: 0.15)) {
                    loadingProgress = Double(index + 1) / Double(citiesToFetch.count)
                }
            } catch {
                withAnimation(.easeInOut(duration: 0.15)) {
                    loadingProgress = Double(index + 1) / Double(citiesToFetch.count)
                }
            }
        }
        
        print("\(weatherData.count)/\(citiesToFetch.count) cities fetched")
        self.cityWeatherData = weatherData
        otherListData[activeListID.rawValue] = weatherData
        
        // Cache the fetched data
        cacheData(weatherData)
    }
    
    func refreshWeather() async {
        clearCache()
        await fetchWeatherForAllCities()
    }
    
    func resetAllLists() async {
        // Clear saved cities for all lists (including user-created)
        for listID in CityListID.allLists {
            let citiesKey = "savedCitiesList_\(listID.rawValue)"
            let cacheKey = "cachedWeatherData_\(listID.rawValue)"
            let timestampKey = "weatherCacheTimestamp_\(listID.rawValue)"
            UserDefaults.standard.removeObject(forKey: citiesKey)
            UserDefaults.standard.removeObject(forKey: cacheKey)
            UserDefaults.standard.removeObject(forKey: timestampKey)
        }
        // Restore built-in lists and clear user-created lists
        CityListID.restoreBuiltInLists()
        CityListID.saveUserLists([])
        // Switch to first built-in list
        activeListID = .europe
        UserDefaults.standard.set(CityListID.europe.rawValue, forKey: Self.activeListKey)
        cityWeatherData = []
        await fetchWeatherForAllCities()
    }
    
    func switchList(to listID: CityListID) async {
        guard listID != activeListID else { return }
        cityWeatherData = []
        activeListID = listID
        UserDefaults.standard.set(listID.rawValue, forKey: Self.activeListKey)
        lastFetchDate = nil
        await fetchWeatherForAllCities()
    }
    
    func addNewList(name: String) async {
        let newList = CityListID.createList(name: name)
        cityWeatherData = []
        activeListID = newList
        UserDefaults.standard.set(newList.rawValue, forKey: Self.activeListKey)
        lastFetchDate = nil
        // New list starts empty, no fetch needed
    }
    
    func renameCurrentList(to newName: String) {
        let renamed = CityListID(rawValue: activeListID.rawValue, displayName: newName)
        // Load raw user lists without filtering to find lists with empty names
        var userLists: [CityListID] = {
            guard let data = UserDefaults.standard.data(forKey: "userCreatedLists"),
                  let lists = try? JSONDecoder().decode([CityListID].self, from: data) else {
                return []
            }
            return lists
        }()
        if let index = userLists.firstIndex(where: { $0.rawValue == activeListID.rawValue }) {
            userLists[index] = renamed
            CityListID.saveUserLists(userLists)
        }
        activeListID = renamed
    }
    
    func deleteCurrentList() async {
        let listToDelete = activeListID
        // Remove stored data for this list
        UserDefaults.standard.removeObject(forKey: "savedCitiesList_\(listToDelete.rawValue)")
        UserDefaults.standard.removeObject(forKey: "cachedWeatherData_\(listToDelete.rawValue)")
        UserDefaults.standard.removeObject(forKey: "weatherCacheTimestamp_\(listToDelete.rawValue)")
        // Remove from user lists or mark built-in as deleted
        if CityListID.builtInLists.contains(where: { $0.rawValue == listToDelete.rawValue }) {
            CityListID.deleteBuiltInList(listToDelete)
        } else {
            var userLists = CityListID.loadUserLists()
            userLists.removeAll { $0.rawValue == listToDelete.rawValue }
            CityListID.saveUserLists(userLists)
        }
        // Switch to the first available list, or create a default one if none left
        let remaining = CityListID.allLists
        if remaining.isEmpty {
            // All lists deleted — create a new empty list
            let newList = CityListID.createList(name: String(localized: "New List"))
            cityWeatherData = []
            activeListID = newList
            UserDefaults.standard.set(newList.rawValue, forKey: Self.activeListKey)
            lastFetchDate = nil
        } else {
            let fallback = remaining.first ?? .europe
            cityWeatherData = []
            activeListID = fallback
            UserDefaults.standard.set(fallback.rawValue, forKey: Self.activeListKey)
            lastFetchDate = nil
            await fetchWeatherForAllCities()
        }
    }
    
    // MARK: - Caching Methods
    
    private func isCacheValid() -> Bool {
        guard let timestamp = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date else {
            return false
        }
        
        let now = Date()
        let elapsed = now.timeIntervalSince(timestamp)
        let isValid = elapsed < cacheDuration
        
        return isValid
    }
    
    private func cacheData(_ data: [CityWeather]) {
        do {
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(data.map { CachedCityWeather(from: $0) })
            UserDefaults.standard.set(encoded, forKey: cacheKey)
            UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
            lastFetchDate = Date()
        } catch {
        }
    }
    
    private func loadCachedData() -> [CityWeather]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let cachedWeather = try decoder.decode([CachedCityWeather].self, from: data)
            lastFetchDate = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date
            return cachedWeather.map { $0.toCityWeather() }
        } catch {
            return nil
        }
    }
    
    private func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: cacheTimestampKey)
        lastFetchDate = nil
    }
    
    /// Load cached weather data for a specific list (without switching the active list)
    func loadCachedData(for listID: CityListID) -> [CityWeather]? {
        let key = "cachedWeatherData_\(listID.rawValue)"
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        do {
            let cachedWeather = try JSONDecoder().decode([CachedCityWeather].self, from: data)
            return cachedWeather.map { $0.toCityWeather() }
        } catch {
            return nil
        }
    }
    
    /// Stores fetched weather data for other lists (keyed by list rawValue)
    var otherListData: [String: [CityWeather]] = [:]
    
    /// Fetch weather for a specific list without switching active list, storing in otherListData
    func fetchWeatherForList(_ listID: CityListID) async {
        // Already have data?
        if let cached = loadCachedData(for: listID), !cached.isEmpty {
            otherListData[listID.rawValue] = cached
            return
        }
        // Load cities for this list
        let citiesKey = "savedCitiesList_\(listID.rawValue)"
        let citiesToFetch: [City]
        if let data = UserDefaults.standard.data(forKey: citiesKey),
           let cached = try? JSONDecoder().decode([CachedCity].self, from: data) {
            // Migrate: fill in empty country from default city lists
            let defaults = CityListID.builtInLists.flatMap { $0.defaultCities }
            citiesToFetch = cached.map { c -> City in
                var city = c.toCity()
                if city.country.isEmpty, let match = defaults.first(where: { $0.name == city.name }) {
                    city = City(id: city.id, name: city.name, country: match.country, latitude: city.latitude, longitude: city.longitude)
                }
                return city
            }
        } else {
            citiesToFetch = listID.defaultCities
        }
        guard !citiesToFetch.isEmpty else { return }
        
        var weatherData: [CityWeather] = []
        for city in citiesToFetch {
            do {
                let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
                let weather = try await weatherService.weather(for: location)
                let cityWeather = await convertWeatherKitData(weather: weather, for: city)
                weatherData.append(cityWeather)
            } catch {
                // Skip failed cities
            }
        }
        // Cache the data
        let cacheKey = "cachedWeatherData_\(listID.rawValue)"
        if let encoded = try? JSONEncoder().encode(weatherData.map { CachedCityWeather(from: $0) }) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
            UserDefaults.standard.set(Date(), forKey: "weatherCacheTimestamp_\(listID.rawValue)")
        }
        otherListData[listID.rawValue] = weatherData
    }
    
    // MARK: - Cities List Persistence
    
    /// Save the current list of cities (just the City objects, not the weather data)
    private func saveCitiesList() {
        let cities = cityWeatherData.map { $0.city }
        
        do {
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(cities.map { CachedCity(from: $0) })
            UserDefaults.standard.set(encoded, forKey: citiesListKey)
        } catch {
        }
    }
    
    /// Load the saved cities list (returns nil if no list was saved)
    private func loadSavedCities() -> [City]? {
        guard let data = UserDefaults.standard.data(forKey: citiesListKey) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let cachedCities = try decoder.decode([CachedCity].self, from: data)
            // Migrate: fill in empty country from default city lists
            let defaults = CityListID.builtInLists.flatMap { $0.defaultCities }
            let cities = cachedCities.map { cached -> City in
                var city = cached.toCity()
                if city.country.isEmpty,
                   let match = defaults.first(where: { $0.name == city.name }) {
                    city = City(id: city.id, name: city.name, country: match.country, latitude: city.latitude, longitude: city.longitude)
                }
                return city
            }
            return cities
        } catch {
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

            }
        }
        // Fallback to UTC if we can't determine the timezone
        return TimeZone(identifier: "UTC") ?? TimeZone.current
    }
    
    private func convertWeatherKitData(weather: Weather, for city: City) async -> CityWeather {
        let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
        let timeZone = await getTimeZone(for: location)
        return convertWeatherKitData(weather: weather, for: city, timeZone: timeZone)
    }
    
    private func convertWeatherKitData(weather: Weather, for city: City, timeZone: TimeZone) -> CityWeather {
        // Current weather
        let currentTemp = weather.currentWeather.temperature.value
        let currentCondition = mapWeatherKitCondition(weather.currentWeather.condition)
        let currentSymbol = weather.currentWeather.symbolName
        
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
                precipitationChance: daytimeForecast.precipitationChance,
                sunrise: day.sun.sunrise,
                sunset: day.sun.sunset
            )
        }
        
        return CityWeather(
            city: city,
            condition: currentCondition,
            temperature: currentTemp,
            symbolName: currentSymbol,
            dailyForecasts: Array(dailyForecasts),
            timeZone: timeZone
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
            
        } catch {
        }
    }
    
    func addCityToList(_ city: City, listID: CityListID) async {
        let listKey = "savedCitiesList_\(listID.rawValue)"
        let cacheKey = "cachedWeatherData_\(listID.rawValue)"
        let cacheTimestampKey = "weatherCacheTimestamp_\(listID.rawValue)"
        
        do {
            let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
            let weather = try await weatherService.weather(for: location)
            let cityWeather = await convertWeatherKitData(weather: weather, for: city)
            
            // Load existing cities for the target list
            var existingCities: [City] = []
            if let data = UserDefaults.standard.data(forKey: listKey),
               let cached = try? JSONDecoder().decode([CachedCity].self, from: data) {
                existingCities = cached.map { $0.toCity() }
            }
            existingCities.insert(city, at: 0)
            
            // Save updated cities list
            let encoded = try JSONEncoder().encode(existingCities.map { CachedCity(from: $0) })
            UserDefaults.standard.set(encoded, forKey: listKey)
            
            // Update cache for the target list
            var existingWeather: [CityWeather] = []
            if let cacheData = UserDefaults.standard.data(forKey: cacheKey),
               let cached = try? JSONDecoder().decode([CachedCityWeather].self, from: cacheData) {
                existingWeather = cached.map { $0.toCityWeather() }
            }
            existingWeather.insert(cityWeather, at: 0)
            let encodedWeather = try JSONEncoder().encode(existingWeather.map { CachedCityWeather(from: $0) })
            UserDefaults.standard.set(encodedWeather, forKey: cacheKey)
            UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
            
            // If this is the active list, also update in-memory data
            if listID == activeListID {
                cityWeatherData.insert(cityWeather, at: 0)
            } else {
                // Update otherListData if loaded
                otherListData[listID.rawValue]?.insert(cityWeather, at: 0)
            }
            
        } catch {
        }
    }
    
    func fetchWeatherForCity(_ city: City) async -> CityWeather? {
        do {
            // Fetch weather for the city
            let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
            let weather = try await weatherService.weather(for: location)
            
            // Convert to our model
            let cityWeather = await convertWeatherKitData(weather: weather, for: city)
            
            return cityWeather
        } catch {
            return nil
        }
    }
    
    /// Fetch weather for a grid of points (used by Country Overview).
    /// Reports each result progressively via `onResult` and progress via `onProgress`.
    /// Looks up the timezone once from the first grid point and reuses it for all.
    func fetchWeatherForGrid(_ gridCities: [City], onProgress: @escaping (Double) -> Void, onResult: ((CityWeather) -> Void)? = nil) async -> [CityWeather] {
        var results: [CityWeather] = []
        let total = gridCities.count
        
        // Resolve timezone once from the first point to avoid rate-limiting
        var gridTimeZone: TimeZone?
        
        for (index, city) in gridCities.enumerated() {
            do {
                let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
                let weather = try await weatherService.weather(for: location)
                
                // Look up timezone only for the first point
                if gridTimeZone == nil {
                    gridTimeZone = await getTimeZone(for: location)
                }
                
                let cityWeather = convertWeatherKitData(weather: weather, for: city, timeZone: gridTimeZone ?? .current)
                results.append(cityWeather)
                onResult?(cityWeather)
            } catch {
            }
            onProgress(Double(index + 1) / Double(total))
        }
        
        return results
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
    let country: String
    let latitude: Double
    let longitude: Double
    
    init(id: UUID = UUID(), name: String, country: String = "", latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
    }
    
    /// Returns the city name localized for the given locale.
    /// For known default cities, returns a translated name; otherwise returns `name` as-is
    /// (user-added cities already get localized names from MapKit search).
    func localizedName(locale: Locale = .current) -> String {
        guard locale.language.languageCode?.identifier == "zh" else { return name }
        return Self.chineseNames[name] ?? name
    }
    
    private static let chineseNames: [String: String] = [
        // China
        "Beijing": "北京", "Shanghai": "上海", "Chongqing": "重庆",
        "Tianjin": "天津", "Guangzhou": "广州", "Shenzhen": "深圳",
        "Hangzhou": "杭州", "Nanjing": "南京", "Suzhou": "苏州",
        "Xiamen": "厦门", "Wuhan": "武汉", "Changsha": "长沙",
        "Zhengzhou": "郑州", "Xi'an": "西安", "Harbin": "哈尔滨",
        "Dalian": "大连", "Qingdao": "青岛", "Chengdu": "成都",
        "Kunming": "昆明", "Guiyang": "贵阳", "Sanya": "三亚",
        "Fuzhou": "福州", "Lhasa": "拉萨", "Urumqi": "乌鲁木齐",
        "Lanzhou": "兰州",
        // Europe
        "London": "伦敦", "Paris": "巴黎", "Berlin": "柏林",
        "Madrid": "马德里", "Rome": "罗马", "Amsterdam": "阿姆斯特丹",
        "Vienna": "维也纳", "Prague": "布拉格", "Barcelona": "巴塞罗那",
        "Munich": "慕尼黑", "Milan": "米兰", "Stockholm": "斯德哥尔摩",
        "Copenhagen": "哥本哈根", "Oslo": "奥斯陆", "Helsinki": "赫尔辛基",
        "Warsaw": "华沙", "Budapest": "布达佩斯", "Lisbon": "里斯本",
        "Athens": "雅典", "Dublin": "都柏林", "Brussels": "布鲁塞尔",
        "Zurich": "苏黎世", "Istanbul": "伊斯坦布尔", "Bucharest": "布加勒斯特",
        "Edinburgh": "爱丁堡",
    ]
}

struct CityWeather: Identifiable, Hashable {
    let id = UUID()
    let city: City
    let condition: AppWeatherCondition
    let temperature: Double
    let symbolName: String
    let dailyForecasts: [DailyForecast]
    let timeZone: TimeZone
    
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
        let theme = AppTheme.shared.colors
        if symbolName.contains("sun") && !symbolName.contains("cloud") {
            return theme.sunIconColor
        } else {
            return theme.cloudIconColor
        }
    }
}
// MARK: - Forecast Models

struct ForecastDay: Identifiable {
    let id = UUID()
    let date: Date
    let dayOffset: Int
    
    func displayText(locale: Locale = .current) -> String {
        if dayOffset == 0 {
            return localizedString("Today", locale: locale)
        } else if dayOffset == 1 {
            return localizedString("Tomorrow", locale: locale)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "EEEMMMd", options: 0, locale: locale)
            formatter.locale = locale
            return formatter.string(from: date)
        }
    }
    
    func shortDisplayText(locale: Locale = .current) -> String {
        if dayOffset == 0 {
            return localizedString("Today", locale: locale)
        } else if dayOffset == 1 {
            return localizedString("Tomorrow", locale: locale)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "EEEdM", options: 0, locale: locale)
            formatter.locale = locale
            return formatter.string(from: date)
        }
    }
    
    func veryShortDisplayText(locale: Locale = .current) -> String {
        if dayOffset == 0 {
            return localizedString("Today", locale: locale)
        } else if dayOffset == 1 {
            return localizedString("Tmrw", locale: locale)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "EEE", options: 0, locale: locale)
            formatter.locale = locale
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
    let sunrise: Date?
    let sunset: Date?
    
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
        let theme = AppTheme.shared.colors
        if symbolName.contains("sun") && !symbolName.contains("cloud") {
            return theme.sunIconColor
        } else {
            return theme.cloudIconColor
        }
    }
    
    // Themed color variant
    func weatherColor(for colorScheme: ColorScheme) -> Color {
        return weatherColor
    }
    
    // Palette colors for rain icons
    func rainPaletteColors(for colorScheme: ColorScheme) -> (primary: Color, secondary: Color) {
        let theme = AppTheme.shared.colors
        return (theme.cloudIconColor, theme.rainIconColor)
    }
    
    // Palette colors for partially sunny icons
    func partlySunnyPaletteColors(for colorScheme: ColorScheme) -> (primary: Color, secondary: Color) {
        let theme = AppTheme.shared.colors
        return (theme.cloudIconColor, theme.sunIconColor)
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
        let theme = AppTheme.shared.colors
        if symbolName.contains("sun") && !symbolName.contains("cloud") {
            return theme.sunIconColor
        } else if symbolName.contains("moon") && !symbolName.contains("cloud") {
            return colorScheme == .light ? .indigo : .white
        } else {
            return theme.cloudIconColor
        }
    }
    
    func rainPaletteColors(for colorScheme: ColorScheme) -> (primary: Color, secondary: Color) {
        let theme = AppTheme.shared.colors
        return (theme.cloudIconColor, theme.rainIconColor)
    }
    
    func partlySunnyPaletteColors(for colorScheme: ColorScheme) -> (primary: Color, secondary: Color) {
        let theme = AppTheme.shared.colors
        return (theme.cloudIconColor, theme.sunIconColor)
    }
    
    func partlyMoonPaletteColors(for colorScheme: ColorScheme) -> (primary: Color, secondary: Color) {
        let theme = AppTheme.shared.colors
        return (theme.cloudIconColor, colorScheme == .light ? .indigo : .white)
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
    
    func formattedHour(locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)
        formatter.locale = locale
        var components = DateComponents()
        components.hour = hour
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(hour)"
    }
    
    func shortFormattedHour(locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)
        formatter.locale = locale
        var components = DateComponents()
        components.hour = hour
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date).lowercased()
        }
        return "\(hour)"
    }
}

// MARK: - Cache Models

struct CachedCity: Codable {
    let id: UUID
    let name: String
    let country: String
    let latitude: Double
    let longitude: Double
    
    init(from city: City) {
        self.id = city.id
        self.name = city.name
        self.country = city.country
        self.latitude = city.latitude
        self.longitude = city.longitude
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
    }
    
    func toCity() -> City {
        return City(id: id, name: name, country: country, latitude: latitude, longitude: longitude)
    }
}

struct CachedCityWeather: Codable {
    let cityId: UUID
    let cityName: String
    let cityCountry: String
    let cityLatitude: Double
    let cityLongitude: Double
    let condition: String
    let temperature: Double
    let symbolName: String
    let dailyForecasts: [CachedDailyForecast]
    let timeZoneIdentifier: String?
    
    init(from cityWeather: CityWeather) {
        self.cityId = cityWeather.city.id
        self.cityName = cityWeather.city.name
        self.cityCountry = cityWeather.city.country
        self.cityLatitude = cityWeather.city.latitude
        self.cityLongitude = cityWeather.city.longitude
        self.condition = cityWeather.condition.displayName
        self.temperature = cityWeather.temperature
        self.symbolName = cityWeather.symbolName
        self.dailyForecasts = cityWeather.dailyForecasts.map { CachedDailyForecast(from: $0) }
        self.timeZoneIdentifier = cityWeather.timeZone.identifier
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cityId = try container.decode(UUID.self, forKey: .cityId)
        cityName = try container.decode(String.self, forKey: .cityName)
        cityCountry = try container.decodeIfPresent(String.self, forKey: .cityCountry) ?? ""
        cityLatitude = try container.decode(Double.self, forKey: .cityLatitude)
        cityLongitude = try container.decode(Double.self, forKey: .cityLongitude)
        condition = try container.decode(String.self, forKey: .condition)
        temperature = try container.decode(Double.self, forKey: .temperature)
        symbolName = try container.decode(String.self, forKey: .symbolName)
        dailyForecasts = try container.decode([CachedDailyForecast].self, forKey: .dailyForecasts)
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
    }
    
    func toCityWeather() -> CityWeather {
        let city = City(id: cityId, name: cityName, country: cityCountry, latitude: cityLatitude, longitude: cityLongitude)
        let appCondition = AppWeatherCondition.fromDisplayName(condition)
        let forecasts = dailyForecasts.map { $0.toDailyForecast() }
        let tz = timeZoneIdentifier.flatMap { TimeZone(identifier: $0) } ?? TimeZone.current
        
        return CityWeather(
            city: city,
            condition: appCondition,
            temperature: temperature,
            symbolName: symbolName,
            dailyForecasts: forecasts,
            timeZone: tz
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
    let sunrise: Date?
    let sunset: Date?
    
    init(from forecast: DailyForecast) {
        self.dayOffset = forecast.dayOffset
        self.daytimeLow = forecast.daytimeLow
        self.daytimeHigh = forecast.daytimeHigh
        self.symbolName = forecast.symbolName
        self.condition = forecast.condition.displayName
        self.hourlyForecasts = forecast.hourlyForecasts.map { CachedHourlyForecast(from: $0) }
        self.cloudCover = forecast.cloudCover
        self.precipitationChance = forecast.precipitationChance
        self.sunrise = forecast.sunrise
        self.sunset = forecast.sunset
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
        sunrise = try container.decodeIfPresent(Date.self, forKey: .sunrise)
        sunset = try container.decodeIfPresent(Date.self, forKey: .sunset)
    }
    
    // Keep the old key for migration during decoding
    private enum CodingKeys: String, CodingKey {
        case dayOffset, daytimeLow, daytimeHigh, symbolName, condition, hourlyForecasts, cloudCover, precipitationChance, temperature, sunrise, sunset
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
        try container.encodeIfPresent(sunrise, forKey: .sunrise)
        try container.encodeIfPresent(sunset, forKey: .sunset)
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
            precipitationChance: precipitationChance,
            sunrise: sunrise,
            sunset: sunset
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


