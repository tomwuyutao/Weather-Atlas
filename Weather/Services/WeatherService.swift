//
//  WeatherService.swift
//  Weather
//
//  Purpose: Owns weather fetching, caching, list persistence, weather models,
//  forecast models, and cache serialization.
//

import Foundation
import SwiftUI
import WeatherKit
import CoreLocation

// MARK: - Shared Errors and Localization

enum WeatherServiceError: LocalizedError {
    case undefinedTimeZone(city: String)

    var errorDescription: String? {
        switch self {
        case .undefinedTimeZone(let city):
            return "Timezone undefined for \(city)"
        }
    }
}

/// Look up a localized string for a specific locale (respects SwiftUI environment locale).
func localizedString(_ key: String.LocalizationValue, locale: Locale) -> String {
    var resource = LocalizedStringResource(key)
    resource.locale = locale
    return String(localized: resource)
}

// MARK: - Weather Condition Model

enum AppWeatherCondition: String, Codable {
    case clear
    case partlySunny
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
        case .partlySunny:
            return "Partly Sunny"
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
        case .partlySunny:
            return localizedString("Partly Sunny", locale: locale)
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
        case .partlySunny: return 35
        case .partlyCloudy: return 65
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
        case .partlySunny: return theme.dotPartlyCloudy
        case .partlyCloudy: return theme.dotCloudy
        case .cloudy: return theme.dotCloudy
        case .rain: return theme.dotRain
        case .drizzle: return theme.dotDrizzle
        case .snow: return theme.dotSnow
        case .fog: return theme.dotFog
        case .wind: return theme.dotWind
        }
    }
}

// MARK: - List Identity

struct CityListID: Identifiable, Equatable, Hashable, Codable {
    let rawValue: String
    let displayName: String
    
    var id: String { rawValue }
    
    static let europe = CityListID(rawValue: "europe", displayName: "Europe")
    static let asia = CityListID(rawValue: "asia", displayName: "Asia")
    static let northAmerica = CityListID(rawValue: "northAmerica", displayName: "North America")
    static let southAmerica = CityListID(rawValue: "southAmerica", displayName: "South America")
    static let africa = CityListID(rawValue: "africa", displayName: "Africa")
    static let australia = CityListID(rawValue: "australia", displayName: "Australia")
    
    func localizedDisplayName(locale: Locale = .current) -> String {
        if let customName = Self.customDisplayName(for: rawValue) {
            return customName
        }
        switch rawValue {
        case "europe": return localizedString("Europe", locale: locale)
        case "asia": return localizedString("Asia", locale: locale)
        case "northAmerica": return localizedString("North America", locale: locale)
        case "southAmerica": return localizedString("South America", locale: locale)
        case "africa": return localizedString("Africa", locale: locale)
        case "australia": return localizedString("Australia", locale: locale)
        default: return displayName
        }
    }

    static let builtInLists: [CityListID] = [.europe, .asia, .northAmerica, .southAmerica, .africa, .australia]
    
    private static let userListsKey = "userCreatedLists"
    private static let deletedBuiltInListsKey = "deletedBuiltInLists"
    private static let listOrderKey = "listOrder"
    private static let customListNamesKey = "customListNames"
    
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

    private static func loadCustomListNames() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: customListNamesKey),
              let names = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return names
    }

    static func customDisplayName(for rawValue: String) -> String? {
        loadCustomListNames()[rawValue]
    }

    static func saveCustomDisplayName(_ name: String, for rawValue: String) {
        var names = loadCustomListNames()
        names[rawValue] = name
        if let data = try? JSONEncoder().encode(names) {
            UserDefaults.standard.set(data, forKey: customListNamesKey)
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
        UserDefaults.standard.removeObject(forKey: customListNamesKey)
    }

    static func keepBuiltInLists(withRawValues selectedIDs: Set<String>) {
        let deleted = builtInLists
            .map(\.rawValue)
            .filter { !selectedIDs.contains($0) }
        UserDefaults.standard.set(deleted, forKey: deletedBuiltInListsKey)
        UserDefaults.standard.removeObject(forKey: listOrderKey)
        UserDefaults.standard.removeObject(forKey: customListNamesKey)
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
        case "europe":
            return [
                City(name: "Istanbul", country: "Turkey", latitude: 41.0082, longitude: 28.9784),
                City(name: "Moscow", country: "Russia", latitude: 55.7558, longitude: 37.6173),
                City(name: "London", country: "England", latitude: 51.5074, longitude: -0.1278),
                City(name: "Saint Petersburg", country: "Russia", latitude: 59.9311, longitude: 30.3609),
                City(name: "Berlin", country: "Germany", latitude: 52.5200, longitude: 13.4050),
                City(name: "Madrid", country: "Spain", latitude: 40.4168, longitude: -3.7038),
                City(name: "Rome", country: "Italy", latitude: 41.9028, longitude: 12.4964),
                City(name: "Kyiv", country: "Ukraine", latitude: 50.4501, longitude: 30.5234),
                City(name: "Paris", country: "France", latitude: 48.8566, longitude: 2.3522),
                City(name: "Bucharest", country: "Romania", latitude: 44.4268, longitude: 26.1025),
                City(name: "Minsk", country: "Belarus", latitude: 53.9006, longitude: 27.5590),
                City(name: "Vienna", country: "Austria", latitude: 48.2082, longitude: 16.3738),
                City(name: "Hamburg", country: "Germany", latitude: 53.5511, longitude: 9.9937),
                City(name: "Warsaw", country: "Poland", latitude: 52.2297, longitude: 21.0122),
                City(name: "Budapest", country: "Hungary", latitude: 47.4979, longitude: 19.0402),
                City(name: "Barcelona", country: "Spain", latitude: 41.3874, longitude: 2.1686),
                City(name: "Munich", country: "Germany", latitude: 48.1351, longitude: 11.5820),
                City(name: "Milan", country: "Italy", latitude: 45.4642, longitude: 9.1900),
                City(name: "Prague", country: "Czechia", latitude: 50.0755, longitude: 14.4378),
                City(name: "Sofia", country: "Bulgaria", latitude: 42.6977, longitude: 23.3219),
            ]
        case "asia":
            return [
                City(name: "Tokyo", country: "Japan", latitude: 35.6762, longitude: 139.6503),
                City(name: "Delhi", country: "India", latitude: 28.7041, longitude: 77.1025),
                City(name: "Shanghai", country: "China", latitude: 31.2304, longitude: 121.4737),
                City(name: "Dhaka", country: "Bangladesh", latitude: 23.8103, longitude: 90.4125),
                City(name: "Beijing", country: "China", latitude: 39.9042, longitude: 116.4074),
                City(name: "Mumbai", country: "India", latitude: 19.0760, longitude: 72.8777),
                City(name: "Osaka", country: "Japan", latitude: 34.6937, longitude: 135.5023),
                City(name: "Karachi", country: "Pakistan", latitude: 24.8607, longitude: 67.0011),
                City(name: "Chongqing", country: "China", latitude: 29.4316, longitude: 106.9123),
                City(name: "Guangzhou", country: "China", latitude: 23.1291, longitude: 113.2644),
                City(name: "Lahore", country: "Pakistan", latitude: 31.5204, longitude: 74.3587),
                City(name: "Shenzhen", country: "China", latitude: 22.5431, longitude: 114.0579),
                City(name: "Bangalore", country: "India", latitude: 12.9716, longitude: 77.5946),
                City(name: "Chennai", country: "India", latitude: 13.0827, longitude: 80.2707),
                City(name: "Kolkata", country: "India", latitude: 22.5726, longitude: 88.3639),
                City(name: "Bangkok", country: "Thailand", latitude: 13.7563, longitude: 100.5018),
                City(name: "Tehran", country: "Iran", latitude: 35.6892, longitude: 51.3890),
                City(name: "Hyderabad", country: "India", latitude: 17.3850, longitude: 78.4867),
                City(name: "Chengdu", country: "China", latitude: 30.5728, longitude: 104.0668),
                City(name: "Ho Chi Minh City", country: "Vietnam", latitude: 10.8231, longitude: 106.6297),
            ]
        case "northAmerica":
            return [
                City(name: "Mexico City", country: "Mexico", latitude: 19.4326, longitude: -99.1332),
                City(name: "New York", country: "United States", latitude: 40.7128, longitude: -74.0060),
                City(name: "Los Angeles", country: "United States", latitude: 34.0522, longitude: -118.2437),
                City(name: "Toronto", country: "Canada", latitude: 43.6532, longitude: -79.3832),
                City(name: "Chicago", country: "United States", latitude: 41.8781, longitude: -87.6298),
                City(name: "Dallas", country: "United States", latitude: 32.7767, longitude: -96.7970),
                City(name: "Houston", country: "United States", latitude: 29.7604, longitude: -95.3698),
                City(name: "Miami", country: "United States", latitude: 25.7617, longitude: -80.1918),
                City(name: "Philadelphia", country: "United States", latitude: 39.9526, longitude: -75.1652),
                City(name: "Atlanta", country: "United States", latitude: 33.7490, longitude: -84.3880),
                City(name: "Washington", country: "United States", latitude: 38.9072, longitude: -77.0369),
                City(name: "Boston", country: "United States", latitude: 42.3601, longitude: -71.0589),
                City(name: "Phoenix", country: "United States", latitude: 33.4484, longitude: -112.0740),
                City(name: "Monterrey", country: "Mexico", latitude: 25.6866, longitude: -100.3161),
                City(name: "Guadalajara", country: "Mexico", latitude: 20.6597, longitude: -103.3496),
                City(name: "San Francisco", country: "United States", latitude: 37.7749, longitude: -122.4194),
                City(name: "Detroit", country: "United States", latitude: 42.3314, longitude: -83.0458),
                City(name: "Montreal", country: "Canada", latitude: 45.5017, longitude: -73.5673),
                City(name: "Seattle", country: "United States", latitude: 47.6062, longitude: -122.3321),
                City(name: "Minneapolis", country: "United States", latitude: 44.9778, longitude: -93.2650),
            ]
        case "southAmerica":
            return [
                City(name: "Sao Paulo", country: "Brazil", latitude: -23.5558, longitude: -46.6396),
                City(name: "Buenos Aires", country: "Argentina", latitude: -34.6037, longitude: -58.3816),
                City(name: "Rio de Janeiro", country: "Brazil", latitude: -22.9068, longitude: -43.1729),
                City(name: "Lima", country: "Peru", latitude: -12.0464, longitude: -77.0428),
                City(name: "Bogota", country: "Colombia", latitude: 4.7110, longitude: -74.0721),
                City(name: "Santiago", country: "Chile", latitude: -33.4489, longitude: -70.6693),
                City(name: "Belo Horizonte", country: "Brazil", latitude: -19.9167, longitude: -43.9345),
                City(name: "Caracas", country: "Venezuela", latitude: 10.4806, longitude: -66.9036),
                City(name: "Porto Alegre", country: "Brazil", latitude: -30.0346, longitude: -51.2177),
                City(name: "Brasilia", country: "Brazil", latitude: -15.8267, longitude: -47.9218),
                City(name: "Recife", country: "Brazil", latitude: -8.0476, longitude: -34.8770),
                City(name: "Fortaleza", country: "Brazil", latitude: -3.7319, longitude: -38.5267),
                City(name: "Salvador", country: "Brazil", latitude: -12.9777, longitude: -38.5016),
                City(name: "Medellin", country: "Colombia", latitude: 6.2442, longitude: -75.5812),
                City(name: "Guayaquil", country: "Ecuador", latitude: -2.1700, longitude: -79.9224),
                City(name: "Curitiba", country: "Brazil", latitude: -25.4284, longitude: -49.2733),
                City(name: "Quito", country: "Ecuador", latitude: -0.1807, longitude: -78.4678),
                City(name: "Cali", country: "Colombia", latitude: 3.4516, longitude: -76.5320),
                City(name: "Montevideo", country: "Uruguay", latitude: -34.9011, longitude: -56.1645),
                City(name: "Asuncion", country: "Paraguay", latitude: -25.2637, longitude: -57.5759),
            ]
        case "africa":
            return [
                City(name: "Lagos", country: "Nigeria", latitude: 6.5244, longitude: 3.3792),
                City(name: "Cairo", country: "Egypt", latitude: 30.0444, longitude: 31.2357),
                City(name: "Kinshasa", country: "Democratic Republic of the Congo", latitude: -4.4419, longitude: 15.2663),
                City(name: "Johannesburg", country: "South Africa", latitude: -26.2041, longitude: 28.0473),
                City(name: "Luanda", country: "Angola", latitude: -8.8390, longitude: 13.2894),
                City(name: "Dar es Salaam", country: "Tanzania", latitude: -6.7924, longitude: 39.2083),
                City(name: "Khartoum", country: "Sudan", latitude: 15.5007, longitude: 32.5599),
                City(name: "Abidjan", country: "Cote d'Ivoire", latitude: 5.3600, longitude: -4.0083),
                City(name: "Alexandria", country: "Egypt", latitude: 31.2001, longitude: 29.9187),
                City(name: "Nairobi", country: "Kenya", latitude: -1.2921, longitude: 36.8219),
                City(name: "Addis Ababa", country: "Ethiopia", latitude: 8.9806, longitude: 38.7578),
                City(name: "Cape Town", country: "South Africa", latitude: -33.9249, longitude: 18.4241),
                City(name: "Casablanca", country: "Morocco", latitude: 33.5731, longitude: -7.5898),
                City(name: "Accra", country: "Ghana", latitude: 5.6037, longitude: -0.1870),
                City(name: "Durban", country: "South Africa", latitude: -29.8587, longitude: 31.0218),
                City(name: "Dakar", country: "Senegal", latitude: 14.7167, longitude: -17.4677),
                City(name: "Kano", country: "Nigeria", latitude: 12.0022, longitude: 8.5920),
                City(name: "Ibadan", country: "Nigeria", latitude: 7.3775, longitude: 3.9470),
                City(name: "Pretoria", country: "South Africa", latitude: -25.7479, longitude: 28.2293),
                City(name: "Kampala", country: "Uganda", latitude: 0.3476, longitude: 32.5825),
            ]
        case "australia":
            return [
                City(name: "Sydney", country: "Australia", latitude: -33.8688, longitude: 151.2093),
                City(name: "Melbourne", country: "Australia", latitude: -37.8136, longitude: 144.9631),
                City(name: "Brisbane", country: "Australia", latitude: -27.4698, longitude: 153.0251),
                City(name: "Perth", country: "Australia", latitude: -31.9523, longitude: 115.8613),
                City(name: "Adelaide", country: "Australia", latitude: -34.9285, longitude: 138.6007),
                City(name: "Gold Coast", country: "Australia", latitude: -28.0167, longitude: 153.4000),
                City(name: "Canberra", country: "Australia", latitude: -35.2809, longitude: 149.1300),
                City(name: "Newcastle", country: "Australia", latitude: -32.9283, longitude: 151.7817),
                City(name: "Central Coast", country: "Australia", latitude: -33.4267, longitude: 151.3417),
                City(name: "Wollongong", country: "Australia", latitude: -34.4278, longitude: 150.8931),
            ]
        default:
            return [] // User-created lists start empty
        }
    }
}

// MARK: - Weather Service

@Observable
@MainActor
class WeatherService {
    var cityWeatherData: [CityWeather] = []
    var isLoading = false
    var loadingProgress: Double = 0
    var errorMessage: String?
    var forecastDays: [ForecastDay] = []
    var lastFetchDate: Date?
    var weatherAttribution: WeatherAttribution?
    var activeListID: CityListID = .europe
    private var activeFetchToken = UUID()
    private let weatherCacheDuration: TimeInterval = 2 * 60 * 60
    private var listFetchDates: [String: Date] = [:]
    private var resolvedTimeZones: [String: TimeZone] = [:]
    
    private let weatherService = WeatherKit.WeatherService.shared
    
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
        if let cachedData = loadCachedWeatherData(for: activeListID), isWeatherDataFresh(for: activeListID) {
            cityWeatherData = cachedData
            otherListData[activeListID.rawValue] = cachedData
            lastFetchDate = fetchDate(for: activeListID)
        }
    }

    var weatherAttributionMarkText: String {
        " Weather"
    }

    var weatherLegalPageURL: URL? {
        weatherAttribution?.legalPageURL
    }

    func loadWeatherAttributionIfNeeded() async {
        guard weatherAttribution == nil else { return }
        do {
            weatherAttribution = try await weatherService.attribution
        } catch {
            print("Failed to load WeatherKit attribution: \(error)")
        }
    }
    
    func fetchWeatherForAllCities(forceRefresh: Bool = false) async {
        generateForecastDays()
        errorMessage = nil
        if !forceRefresh,
           cityWeatherData.isEmpty,
           let cachedData = loadCachedWeatherData(for: activeListID),
           isWeatherDataFresh(for: activeListID) {
            cityWeatherData = cachedData
            otherListData[activeListID.rawValue] = cachedData
            lastFetchDate = fetchDate(for: activeListID)
            return
        }

        if !forceRefresh,
           !cityWeatherData.isEmpty,
           isWeatherDataFresh(for: activeListID) {
            return
        }

        let fetchToken = UUID()
        activeFetchToken = fetchToken
        let targetListID = activeListID
        isLoading = true
        loadingProgress = 0
        defer {
            if activeFetchToken == fetchToken {
                isLoading = false
            }
        }
        
        // Load the saved cities list, or use defaults for active list
        let citiesToFetch = loadSavedCities(for: targetListID) ?? targetListID.defaultCities
        guard !citiesToFetch.isEmpty else {
            cityWeatherData = []
            otherListData[targetListID.rawValue] = []
            loadingProgress = 1
            return
        }
        
        var weatherData: [CityWeather] = []
        otherListData[targetListID.rawValue] = []
        if activeListID.rawValue == targetListID.rawValue {
            cityWeatherData = []
        }
        
        for (index, city) in citiesToFetch.enumerated() {
            do {
                let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
                let weather = try await weatherService.weather(for: location)
                let cityWeather = try await convertWeatherKitData(weather: weather, for: city)
                guard activeFetchToken == fetchToken else { return }

                weatherData.append(cityWeather)
                otherListData[targetListID.rawValue] = weatherData
                if activeListID.rawValue == targetListID.rawValue {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        cityWeatherData = weatherData
                        loadingProgress = Double(index + 1) / Double(citiesToFetch.count)
                    }
                }
            } catch {
                report(error)
                if activeFetchToken == fetchToken {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        loadingProgress = Double(index + 1) / Double(citiesToFetch.count)
                    }
                }
            }
        }
        
        print("\(weatherData.count)/\(citiesToFetch.count) cities fetched")
        guard activeFetchToken == fetchToken, activeListID.rawValue == targetListID.rawValue else {
            return
        }
        
        // Mark this list as freshly fetched.
        cacheData(weatherData, updateFetchDate: true)
    }
    
    func refreshWeather() async {
        clearCache()
        await fetchWeatherForAllCities(forceRefresh: true)
    }
    
    func resetAllLists(preloadListIDs: Set<String> = []) async {
        // Clear saved cities for all lists (including user-created)
        for listID in CityListID.allLists {
            let citiesKey = "savedCitiesList_\(listID.rawValue)"
            let cacheKey = "cachedWeatherData_\(listID.rawValue)"
            let timestampKey = "weatherCacheTimestamp_\(listID.rawValue)"
            UserDefaults.standard.removeObject(forKey: citiesKey)
            UserDefaults.standard.removeObject(forKey: cacheKey)
            UserDefaults.standard.removeObject(forKey: timestampKey)
        }
        listFetchDates.removeAll()
        otherListData.removeAll()
        // Restore built-in lists and clear user-created lists
        CityListID.restoreBuiltInLists()
        CityListID.saveUserLists([])
        // Switch to first built-in list
        activeListID = .europe
        UserDefaults.standard.set(CityListID.europe.rawValue, forKey: Self.activeListKey)
        cityWeatherData = []
        await fetchWeatherForAllCities()

        for listID in CityListID.builtInLists where preloadListIDs.contains(listID.rawValue) && listID != activeListID {
            await fetchWeatherForList(listID)
        }
    }
    
    func switchList(to listID: CityListID) async {
        guard listID != activeListID else { return }
        activeFetchToken = UUID()
        activeListID = listID
        UserDefaults.standard.set(listID.rawValue, forKey: Self.activeListKey)
        cityWeatherData = otherListData[listID.rawValue] ?? loadCachedWeatherData(for: listID) ?? []
        otherListData[listID.rawValue] = cityWeatherData
        lastFetchDate = fetchDate(for: listID)
        await fetchWeatherForAllCities()
    }

    func switchList(to listID: CityListID, prioritizing priorityCity: City) async -> CityWeather? {
        let existingData = otherListData[listID.rawValue]
            ?? (listID == activeListID ? cityWeatherData : nil)
            ?? loadCachedWeatherData(for: listID)
            ?? []
        if isWeatherDataFresh(for: listID),
           let existingCity = existingData.first(where: { citiesMatch($0.city, priorityCity) }) {
            activeFetchToken = UUID()
            activeListID = listID
            UserDefaults.standard.set(listID.rawValue, forKey: Self.activeListKey)
            cityWeatherData = existingData
            lastFetchDate = fetchDate(for: listID)
            return existingCity
        }

        let fetchToken = UUID()
        activeFetchToken = fetchToken
        activeListID = listID
        UserDefaults.standard.set(listID.rawValue, forKey: Self.activeListKey)
        lastFetchDate = nil
        loadingProgress = 0
        isLoading = true

        let citiesToFetch = orderedCitiesForFetch(listID: listID, prioritizing: priorityCity)
        guard !citiesToFetch.isEmpty else {
            cityWeatherData = []
            otherListData[listID.rawValue] = []
            isLoading = false
            loadingProgress = 1
            return nil
        }

        cityWeatherData = []
        otherListData[listID.rawValue] = []

        guard let priorityWeather = await fetchWeatherForCity(citiesToFetch[0]),
              activeFetchToken == fetchToken,
              activeListID == listID else {
            Task {
                await finishPrioritizedListFetch(
                    listID: listID,
                    citiesToFetch: citiesToFetch,
                    initialWeatherData: [],
                    fetchToken: fetchToken
                )
            }
            return nil
        }

        cityWeatherData = [priorityWeather]
        otherListData[listID.rawValue] = [priorityWeather]
        loadingProgress = 1 / Double(citiesToFetch.count)

        Task {
            await finishPrioritizedListFetch(
                listID: listID,
                citiesToFetch: Array(citiesToFetch.dropFirst()),
                initialWeatherData: [priorityWeather],
                fetchToken: fetchToken
            )
        }

        return priorityWeather
    }

    private func orderedCitiesForFetch(listID: CityListID, prioritizing priorityCity: City) -> [City] {
        let cities = loadSavedCities(for: listID) ?? listID.defaultCities
        guard let priorityIndex = cities.firstIndex(where: { citiesMatch($0, priorityCity) }) else {
            return [priorityCity] + cities.filter { !citiesMatch($0, priorityCity) }
        }

        var orderedCities = cities
        let city = orderedCities.remove(at: priorityIndex)
        orderedCities.insert(city, at: 0)
        return orderedCities
    }

    private func citiesMatch(_ lhs: City, _ rhs: City) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }

    private func finishPrioritizedListFetch(
        listID: CityListID,
        citiesToFetch: [City],
        initialWeatherData: [CityWeather],
        fetchToken: UUID
    ) async {
        var weatherData = initialWeatherData
        let totalCount = weatherData.count + citiesToFetch.count

        for city in citiesToFetch {
            guard activeFetchToken == fetchToken else { return }
            if let cityWeather = await fetchWeatherForCity(city) {
                guard activeFetchToken == fetchToken else { return }
                weatherData.append(cityWeather)
                otherListData[listID.rawValue] = weatherData
                if activeListID == listID {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        cityWeatherData = weatherData
                        loadingProgress = Double(weatherData.count) / Double(max(totalCount, 1))
                    }
                }
            }
        }

        guard activeFetchToken == fetchToken else { return }
        if activeListID == listID {
            isLoading = false
            loadingProgress = 1
            lastFetchDate = Date()
        }
        otherListData[listID.rawValue] = weatherData
        cacheData(weatherData, for: listID, updateFetchDate: true)
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
    
    func deleteCurrentList() {
        let listToDelete = activeListID
        // Remove stored data for this list
        UserDefaults.standard.removeObject(forKey: "savedCitiesList_\(listToDelete.rawValue)")
        UserDefaults.standard.removeObject(forKey: "cachedWeatherData_\(listToDelete.rawValue)")
        UserDefaults.standard.removeObject(forKey: "weatherCacheTimestamp_\(listToDelete.rawValue)")
        otherListData[listToDelete.rawValue] = nil
        listFetchDates[listToDelete.rawValue] = nil
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
            activeListID = fallback
            UserDefaults.standard.set(fallback.rawValue, forKey: Self.activeListKey)
            cityWeatherData = otherListData[fallback.rawValue] ?? []
            lastFetchDate = fetchDate(for: fallback)
            Task {
                await fetchWeatherForAllCities()
            }
        }
    }

    func renameList(_ listID: CityListID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if CityListID.builtInLists.contains(where: { $0.rawValue == listID.rawValue }) {
            CityListID.saveCustomDisplayName(trimmed, for: listID.rawValue)
            if activeListID.rawValue == listID.rawValue {
                activeListID = CityListID(rawValue: listID.rawValue, displayName: trimmed)
            }
            return
        }

        var userLists = CityListID.loadUserLists()
        guard let index = userLists.firstIndex(where: { $0.rawValue == listID.rawValue }) else { return }
        let renamed = CityListID(rawValue: listID.rawValue, displayName: trimmed)
        userLists[index] = renamed
        CityListID.saveUserLists(userLists)
        if activeListID.rawValue == listID.rawValue {
            activeListID = renamed
        }
    }

    func deleteList(_ listID: CityListID) {
        if listID.rawValue == activeListID.rawValue {
            deleteCurrentList()
            return
        }

        UserDefaults.standard.removeObject(forKey: "savedCitiesList_\(listID.rawValue)")
        UserDefaults.standard.removeObject(forKey: "cachedWeatherData_\(listID.rawValue)")
        UserDefaults.standard.removeObject(forKey: "weatherCacheTimestamp_\(listID.rawValue)")
        otherListData[listID.rawValue] = nil
        listFetchDates[listID.rawValue] = nil

        if CityListID.builtInLists.contains(where: { $0.rawValue == listID.rawValue }) {
            CityListID.deleteBuiltInList(listID)
        } else {
            var userLists = CityListID.loadUserLists()
            userLists.removeAll { $0.rawValue == listID.rawValue }
            CityListID.saveUserLists(userLists)
        }
        CityListID.saveListOrder(CityListID.allLists)
    }

    func moveList(_ listID: CityListID, direction: ListMoveDirection) {
        var lists = CityListID.allLists
        guard let index = lists.firstIndex(where: { $0.rawValue == listID.rawValue }) else { return }
        let newIndex: Int
        switch direction {
        case .up:
            newIndex = max(0, index - 1)
        case .down:
            newIndex = min(lists.count - 1, index + 1)
        }
        guard newIndex != index else { return }
        lists.swapAt(index, newIndex)
        CityListID.saveListOrder(lists)
    }

    func moveLists(from source: IndexSet, to destination: Int) {
        var lists = CityListID.allLists
        lists.move(fromOffsets: source, toOffset: destination)
        CityListID.saveListOrder(lists)
    }
    
    // MARK: - Caching Methods
    
    private func cacheData(_ data: [CityWeather], updateFetchDate: Bool = false) {
        saveCachedWeatherData(data, for: activeListID)
        guard updateFetchDate else { return }

        let fetchDate = Date()
        listFetchDates[activeListID.rawValue] = fetchDate
        UserDefaults.standard.set(fetchDate, forKey: cacheTimestampKey)
        lastFetchDate = fetchDate
    }

    private func cacheData(_ data: [CityWeather], for listID: CityListID, updateFetchDate: Bool = false) {
        saveCachedWeatherData(data, for: listID)
        guard updateFetchDate else { return }

        let fetchDate = Date()
        listFetchDates[listID.rawValue] = fetchDate
        UserDefaults.standard.set(fetchDate, forKey: "weatherCacheTimestamp_\(listID.rawValue)")
        if listID.rawValue == activeListID.rawValue {
            lastFetchDate = fetchDate
        }
    }
    
    private func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: cacheTimestampKey)
        listFetchDates[activeListID.rawValue] = nil
        lastFetchDate = nil
    }
    
    func weatherData(for listID: CityListID) -> [CityWeather] {
        if listID.rawValue == activeListID.rawValue {
            return cityWeatherData
        }
        return otherListData[listID.rawValue] ?? []
    }

    func cityListCoordinates(for listID: CityListID? = nil) -> [City] {
        let targetListID = listID ?? activeListID
        return loadSavedCities(for: targetListID) ?? targetListID.defaultCities
    }

    func listContainingCity(named name: String, country: String) -> CityListID? {
        CityListID.allLists.first { listID in
            cityListCoordinates(for: listID).contains { city in
                city.name == name && city.country == country
            }
        }
    }

    private func saveCachedWeatherData(_ data: [CityWeather], for listID: CityListID) {
        let key = "cachedWeatherData_\(listID.rawValue)"
        do {
            let cached = data.map { CachedCityWeather(from: $0) }
            let encoded = try JSONEncoder().encode(cached)
            UserDefaults.standard.set(encoded, forKey: key)
        } catch {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func loadCachedWeatherData(for listID: CityListID) -> [CityWeather]? {
        let key = "cachedWeatherData_\(listID.rawValue)"
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        do {
            let cachedData = try JSONDecoder().decode([CachedCityWeather].self, from: data).compactMap { $0.toCityWeather() }
            guard cachedWeatherDataLooksCurrent(cachedData, for: listID) else {
                UserDefaults.standard.removeObject(forKey: key)
                UserDefaults.standard.removeObject(forKey: "weatherCacheTimestamp_\(listID.rawValue)")
                listFetchDates[listID.rawValue] = nil
                if listID.rawValue == activeListID.rawValue {
                    lastFetchDate = nil
                }
                return nil
            }
            return cachedData
        } catch {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
    }

    private func cachedWeatherDataLooksCurrent(_ data: [CityWeather], for listID: CityListID, now: Date = Date()) -> Bool {
        guard fetchDate(for: listID) != nil else { return false }
        return data.allSatisfy { cityWeather in
            guard hasResolvedTimeZone(cityWeather) else {
                return false
            }

            guard let todayForecast = cityWeather.dailyForecasts.first(where: { $0.dayOffset == 0 }) else {
                return false
            }
            guard !todayForecast.hourlyForecasts.isEmpty else { return false }

            var calendar = Calendar.current
            calendar.timeZone = cityWeather.timeZone
            let currentHour = calendar.component(.hour, from: now)
            guard currentHour < 20,
                  let firstHour = todayForecast.hourlyForecasts.map(\.hour).min() else {
                return true
            }

            return firstHour <= currentHour + 2
        }
    }

    func hasResolvedTimeZone(_ cityWeather: CityWeather) -> Bool {
        let identifier = cityWeather.timeZone.identifier
        guard identifier == "UTC" || identifier == "GMT" || identifier.hasPrefix("GMT+") || identifier.hasPrefix("GMT-") else {
            return true
        }

        // A named city should use the civil timezone returned by Core Location.
        // Raw GMT zones here mean an older cache entry or failed lookup would draw local-time charts incorrectly.
        return cityWeather.city.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func clearPersistedWeatherCaches() {
        UserDefaults.standard.removeObject(forKey: "cachedWeatherData")
        UserDefaults.standard.removeObject(forKey: "weatherCacheTimestamp")
        for listID in CityListID.allLists {
            UserDefaults.standard.removeObject(forKey: "cachedWeatherData_\(listID.rawValue)")
        }
    }

    private func fetchDate(for listID: CityListID) -> Date? {
        if let fetchDate = listFetchDates[listID.rawValue] {
            return fetchDate
        }

        let key = "weatherCacheTimestamp_\(listID.rawValue)"
        guard let fetchDate = UserDefaults.standard.object(forKey: key) as? Date else {
            return nil
        }
        listFetchDates[listID.rawValue] = fetchDate
        return fetchDate
    }

    private func isWeatherDataFresh(for listID: CityListID, now: Date = Date()) -> Bool {
        guard let fetchDate = fetchDate(for: listID) else {
            return false
        }
        return now.timeIntervalSince(fetchDate) < weatherCacheDuration
    }

    private func saveCities(_ cities: [City], for listID: CityListID) {
        let key = "savedCitiesList_\(listID.rawValue)"
        do {
            let encoded = try JSONEncoder().encode(cities.map { CachedCity(from: $0) })
            UserDefaults.standard.set(encoded, forKey: key)
        } catch {
        }
    }
    
    /// Stores fetched weather data for other lists (keyed by list rawValue)
    var otherListData: [String: [CityWeather]] = [:]
    
    /// Fetch weather for a specific list without switching active list, storing in otherListData
    func fetchWeatherForList(_ listID: CityListID) async {
        errorMessage = nil
        if otherListData[listID.rawValue]?.isEmpty == false,
           isWeatherDataFresh(for: listID) {
            return
        }
        if let cachedData = loadCachedWeatherData(for: listID), isWeatherDataFresh(for: listID) {
            otherListData[listID.rawValue] = cachedData
            return
        }
        // Load cities for this list
        let citiesKey = "savedCitiesList_\(listID.rawValue)"
        let citiesToFetch: [City]
        if let data = UserDefaults.standard.data(forKey: citiesKey),
           let cached = try? JSONDecoder().decode([CachedCity].self, from: data) {
            // Migrate: fill in empty country from default city lists
            let defaults = CityListID.builtInLists.flatMap { $0.defaultCities }
            citiesToFetch = cached.compactMap { c -> City? in
                var city = c.toCity()
                if city.country.isEmpty, let match = defaults.first(where: { $0.name == city.name }) {
                    city = City(id: city.id, name: city.name, country: match.country, latitude: city.latitude, longitude: city.longitude)
                }
                return isValidPersistedCity(city) ? city : nil
            }
            if citiesToFetch.count != cached.count {
                saveCities(citiesToFetch, for: listID)
            }
        } else {
            if UserDefaults.standard.data(forKey: citiesKey) != nil {
                UserDefaults.standard.removeObject(forKey: citiesKey)
            }
            citiesToFetch = listID.defaultCities
        }
        guard !citiesToFetch.isEmpty else { return }
        
        var weatherData: [CityWeather] = []
        for city in citiesToFetch {
            do {
                let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
                let weather = try await weatherService.weather(for: location)
                let cityWeather = try await convertWeatherKitData(weather: weather, for: city)
                weatherData.append(cityWeather)
            } catch {
                report(error)
            }
        }
        otherListData[listID.rawValue] = weatherData
        cacheData(weatherData, for: listID, updateFetchDate: true)
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

    private func report(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func isValidPersistedCity(_ city: City) -> Bool {
        let name = city.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { return false }
        guard city.latitude.isFinite, city.longitude.isFinite,
              (-90...90).contains(city.latitude), (-180...180).contains(city.longitude) else { return false }

        let allowedNameScalars = CharacterSet.letters
            .union(.decimalDigits)
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "-'’.(),"))
        return name.unicodeScalars.allSatisfy { allowedNameScalars.contains($0) }
    }
    
    /// Load the saved cities list (returns nil if no list was saved)
    private func loadSavedCities(for listID: CityListID) -> [City]? {
        let key = "savedCitiesList_\(listID.rawValue)"
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let cachedCities = try decoder.decode([CachedCity].self, from: data)
            // Migrate: fill in empty country from default city lists
            let defaults = CityListID.builtInLists.flatMap { $0.defaultCities }
            let cities = cachedCities.compactMap { cached -> City? in
                var city = cached.toCity()
                if city.country.isEmpty,
                   let match = defaults.first(where: { $0.name == city.name }) {
                    city = City(id: city.id, name: city.name, country: match.country, latitude: city.latitude, longitude: city.longitude)
                }
                return isValidPersistedCity(city) ? city : nil
            }
            if cities.count != cachedCities.count {
                saveCities(cities, for: listID)
            }
            return cities
        } catch {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
    }
    
    private func coordinateKey(for city: City) -> String {
        String(format: "%.3f,%.3f", city.latitude, city.longitude)
    }

    private func resolvedTimeZone(for city: City) async -> TimeZone? {
        let key = coordinateKey(for: city)
        if let cachedTimeZone = resolvedTimeZones[key] {
            return cachedTimeZone
        }

        let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "en_US_POSIX"))
            if let timeZone = placemarks.first?.timeZone {
                resolvedTimeZones[key] = timeZone
                return timeZone
            }
        } catch {
            print("⚠️ [WeatherService] Time zone lookup failed for \(city.name): \(error.localizedDescription)")
        }

        if let fallbackTimeZone = knownDefaultCityTimeZone(for: city) {
            resolvedTimeZones[key] = fallbackTimeZone
            return fallbackTimeZone
        }

        return nil
    }

    private func knownDefaultCityTimeZone(for city: City) -> TimeZone? {
        let key = "\(city.name.lowercased())|\(city.country.lowercased())"
        return Self.defaultCityTimeZoneIdentifiers[key].flatMap(TimeZone.init(identifier:))
    }

    private static let defaultCityTimeZoneIdentifiers: [String: String] = [
        "istanbul|turkey": "Europe/Istanbul",
        "moscow|russia": "Europe/Moscow",
        "london|england": "Europe/London",
        "saint petersburg|russia": "Europe/Moscow",
        "berlin|germany": "Europe/Berlin",
        "madrid|spain": "Europe/Madrid",
        "rome|italy": "Europe/Rome",
        "kyiv|ukraine": "Europe/Kyiv",
        "paris|france": "Europe/Paris",
        "bucharest|romania": "Europe/Bucharest",
        "minsk|belarus": "Europe/Minsk",
        "vienna|austria": "Europe/Vienna",
        "hamburg|germany": "Europe/Berlin",
        "warsaw|poland": "Europe/Warsaw",
        "budapest|hungary": "Europe/Budapest",
        "barcelona|spain": "Europe/Madrid",
        "munich|germany": "Europe/Berlin",
        "milan|italy": "Europe/Rome",
        "prague|czechia": "Europe/Prague",
        "sofia|bulgaria": "Europe/Sofia",
        "tokyo|japan": "Asia/Tokyo",
        "delhi|india": "Asia/Kolkata",
        "shanghai|china": "Asia/Shanghai",
        "dhaka|bangladesh": "Asia/Dhaka",
        "beijing|china": "Asia/Shanghai",
        "mumbai|india": "Asia/Kolkata",
        "osaka|japan": "Asia/Tokyo",
        "karachi|pakistan": "Asia/Karachi",
        "chongqing|china": "Asia/Shanghai",
        "guangzhou|china": "Asia/Shanghai",
        "lahore|pakistan": "Asia/Karachi",
        "shenzhen|china": "Asia/Shanghai",
        "bangalore|india": "Asia/Kolkata",
        "chennai|india": "Asia/Kolkata",
        "kolkata|india": "Asia/Kolkata",
        "bangkok|thailand": "Asia/Bangkok",
        "tehran|iran": "Asia/Tehran",
        "hyderabad|india": "Asia/Kolkata",
        "chengdu|china": "Asia/Shanghai",
        "ho chi minh city|vietnam": "Asia/Ho_Chi_Minh",
        "mexico city|mexico": "America/Mexico_City",
        "new york|united states": "America/New_York",
        "los angeles|united states": "America/Los_Angeles",
        "toronto|canada": "America/Toronto",
        "chicago|united states": "America/Chicago",
        "dallas|united states": "America/Chicago",
        "houston|united states": "America/Chicago",
        "miami|united states": "America/New_York",
        "philadelphia|united states": "America/New_York",
        "atlanta|united states": "America/New_York",
        "washington|united states": "America/New_York",
        "boston|united states": "America/New_York",
        "phoenix|united states": "America/Phoenix",
        "monterrey|mexico": "America/Monterrey",
        "guadalajara|mexico": "America/Mexico_City",
        "san francisco|united states": "America/Los_Angeles",
        "detroit|united states": "America/Detroit",
        "montreal|canada": "America/Toronto",
        "seattle|united states": "America/Los_Angeles",
        "minneapolis|united states": "America/Chicago",
        "sao paulo|brazil": "America/Sao_Paulo",
        "buenos aires|argentina": "America/Argentina/Buenos_Aires",
        "rio de janeiro|brazil": "America/Sao_Paulo",
        "lima|peru": "America/Lima",
        "bogota|colombia": "America/Bogota",
        "santiago|chile": "America/Santiago",
        "belo horizonte|brazil": "America/Sao_Paulo",
        "caracas|venezuela": "America/Caracas",
        "porto alegre|brazil": "America/Sao_Paulo",
        "brasilia|brazil": "America/Sao_Paulo",
        "recife|brazil": "America/Recife",
        "fortaleza|brazil": "America/Fortaleza",
        "salvador|brazil": "America/Bahia",
        "medellin|colombia": "America/Bogota",
        "guayaquil|ecuador": "America/Guayaquil",
        "curitiba|brazil": "America/Sao_Paulo",
        "quito|ecuador": "America/Guayaquil",
        "cali|colombia": "America/Bogota",
        "montevideo|uruguay": "America/Montevideo",
        "asuncion|paraguay": "America/Asuncion",
        "lagos|nigeria": "Africa/Lagos",
        "cairo|egypt": "Africa/Cairo",
        "kinshasa|democratic republic of the congo": "Africa/Kinshasa",
        "johannesburg|south africa": "Africa/Johannesburg",
        "luanda|angola": "Africa/Luanda",
        "dar es salaam|tanzania": "Africa/Dar_es_Salaam",
        "khartoum|sudan": "Africa/Khartoum",
        "abidjan|cote d'ivoire": "Africa/Abidjan",
        "alexandria|egypt": "Africa/Cairo",
        "nairobi|kenya": "Africa/Nairobi",
        "addis ababa|ethiopia": "Africa/Addis_Ababa",
        "cape town|south africa": "Africa/Johannesburg",
        "casablanca|morocco": "Africa/Casablanca",
        "accra|ghana": "Africa/Accra",
        "durban|south africa": "Africa/Johannesburg",
        "dakar|senegal": "Africa/Dakar",
        "kano|nigeria": "Africa/Lagos",
        "ibadan|nigeria": "Africa/Lagos",
        "pretoria|south africa": "Africa/Johannesburg",
        "kampala|uganda": "Africa/Kampala",
        "sydney|australia": "Australia/Sydney",
        "melbourne|australia": "Australia/Melbourne",
        "brisbane|australia": "Australia/Brisbane",
        "perth|australia": "Australia/Perth",
        "adelaide|australia": "Australia/Adelaide",
        "gold coast|australia": "Australia/Brisbane",
        "canberra|australia": "Australia/Sydney",
        "newcastle|australia": "Australia/Sydney",
        "central coast|australia": "Australia/Sydney",
        "wollongong|australia": "Australia/Sydney"
    ]

    private func resolvedTimeZoneOrThrow(for city: City) async throws -> TimeZone {
        if let timeZone = await resolvedTimeZone(for: city) {
            return timeZone
        }

        throw WeatherServiceError.undefinedTimeZone(city: city.name)
    }

    private func convertWeatherKitData(weather: Weather, for city: City) async throws -> CityWeather {
        let timeZone = try await resolvedTimeZoneOrThrow(for: city)
        return convertWeatherKitData(weather: weather, for: city, timeZone: timeZone)
    }
    
    private func convertWeatherKitData(weather: Weather, for city: City, timeZone: TimeZone) -> CityWeather {
        // Current weather
        let currentTemp = weather.currentWeather.temperature.value
        let currentSymbol = weather.currentWeather.symbolName
        let currentCondition = mapWeatherKitCondition(weather.currentWeather.condition, symbolName: currentSymbol)
        
        // Current weather overlay data
        let currentFeelsLike = weather.currentWeather.apparentTemperature.converted(to: .celsius).value
        let currentVisibilityKm = weather.currentWeather.visibility.converted(to: .kilometers).value
        let currentHumidity = weather.currentWeather.humidity
        let currentWindSpeedKmh = weather.currentWeather.wind.speed.converted(to: .kilometersPerHour).value
        let currentUV = weather.currentWeather.uvIndex.value
        let currentCloudCover = weather.currentWeather.cloudCover
        
        // Daily forecasts
        let dailyForecasts = weather.dailyForecast.forecast.prefix(10).enumerated().map { (index, day) -> DailyForecast in
            let daySymbol = day.symbolName
            let dayCondition = mapWeatherKitCondition(day.condition, symbolName: daySymbol)
            
            // Generate hourly forecasts for this day
            let hourlyForecasts = generateHourlyFromDaily(day: day, dayOffset: index, allHourly: weather.hourlyForecast.forecast, timeZone: timeZone)
            
            // Derive full-day feels-like range from all hourly apparent temperatures
            let apparentTemps = hourlyForecasts.compactMap(\.apparentTemperature)
            let feelsLikeLow = apparentTemps.min()
            let feelsLikeHigh = apparentTemps.max()
            if hourlyForecasts.isEmpty {
                print("⚠️ [WeatherService] No hourly data for day \(index) — feels-like and hourly precipitation will be nil.")
            } else if apparentTemps.isEmpty {
                print("⚠️ [WeatherService] No apparent temperature data in hourly forecasts for day \(index).")
            }
            
            // Compute full-day values from hourly data so the app remains compatible with iOS 17.
            let hourlyPrecipChances = hourlyForecasts.compactMap(\.precipitationChance)
            let hourlyCloudCover = hourlyForecasts.compactMap(\.cloudCover)
            let hourlyHumidity = hourlyForecasts.compactMap(\.humidity)
            let hourlyVisibility = hourlyForecasts.compactMap(\.visibility)
            let fullDayPrecipChance: Double? = hourlyPrecipChances.max()
            let fullDayCloudCover = hourlyCloudCover.isEmpty ? nil : hourlyCloudCover.reduce(0, +) / Double(hourlyCloudCover.count)

            return DailyForecast(
                dayOffset: index,
                dailyLow: day.lowTemperature.value,
                dailyHigh: day.highTemperature.value,
                symbolName: daySymbol,
                condition: dayCondition,
                hourlyForecasts: hourlyForecasts,
                cloudCover: index == 0 ? currentCloudCover : fullDayCloudCover,
                precipitationChance: fullDayPrecipChance,
                visibility: index == 0 ? currentVisibilityKm : nil,
                feelsLikeLow: feelsLikeLow,
                feelsLikeHigh: feelsLikeHigh,
                humidity: index == 0 ? currentHumidity : nil,
                windSpeed: day.wind.speed.converted(to: .kilometersPerHour).value,
                uvIndex: day.uvIndex.value,
                maxHumidity: hourlyHumidity.max(),
                maxVisibility: hourlyVisibility.max(),
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
            timeZone: timeZone,
            currentFeelsLike: currentFeelsLike,
            currentCloudCover: currentCloudCover,
            currentWindSpeed: currentWindSpeedKmh,
            currentUVIndex: currentUV,
            currentHumidity: currentHumidity,
            currentVisibility: currentVisibilityKm
        )
    }
    
    private func generateHourlyFromDaily(day: DayWeather, dayOffset: Int, allHourly: [HourWeather], timeZone: TimeZone) -> [HourlyForecast] {
        // Use the city's local calendar for the day calculation
        var calendar = Calendar.current
        calendar.timeZone = timeZone

        let todayStart = calendar.startOfDay(for: Date())
        let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: todayStart)
            ?? calendar.startOfDay(for: day.date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        
        // Filter hourly forecasts for this specific day
        let dayHourlyData = allHourly.filter { hourWeather in
            hourWeather.date >= dayStart && hourWeather.date < dayEnd
        }
        
        if dayHourlyData.isEmpty {
            print("⚠️ [WeatherService] No hourly data available for day \(dayOffset) (\(day.date)). Returning empty hourly forecasts.")
            return []
        }
        
        return dayHourlyData.map { hourWeather in
            // Extract hour in the city's local timezone
            let hour = calendar.component(.hour, from: hourWeather.date)
            return HourlyForecast(
                hour: hour,
                temperature: hourWeather.temperature.value,
                apparentTemperature: hourWeather.apparentTemperature.value,
                symbolName: hourWeather.symbolName,
                condition: mapWeatherKitCondition(hourWeather.condition, symbolName: hourWeather.symbolName),
                precipitationChance: hourWeather.precipitationChance,
                cloudCover: hourWeather.cloudCover,
                windSpeed: hourWeather.wind.speed.converted(to: .kilometersPerHour).value,
                uvIndex: hourWeather.uvIndex.value,
                humidity: hourWeather.humidity,
                visibility: hourWeather.visibility.converted(to: .kilometers).value
            )
        }
    }
    
    
    private func mapWeatherKitCondition(_ condition: WeatherCondition, symbolName: String) -> AppWeatherCondition {
        switch condition {
        case .clear, .mostlyClear:
            return .clear
        case .partlyCloudy:
            return symbolName.contains("sun") ? .partlySunny : .partlyCloudy
        case .mostlyCloudy:
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

    func removeCity(_ cityWeather: CityWeather, from listID: CityListID) {
        if listID.rawValue == activeListID.rawValue {
            removeCity(cityWeather)
            return
        }
        var listData = otherListData[listID.rawValue] ?? []
        listData.removeAll { $0.id == cityWeather.id }
        otherListData[listID.rawValue] = listData
        saveCities(listData.map(\.city), for: listID)
        cacheData(listData, for: listID)
    }

    func renameCity(_ cityWeather: CityWeather, to newName: String) {
        guard let index = cityWeatherData.firstIndex(where: { $0.id == cityWeather.id }) else { return }
        cityWeatherData[index].city.name = newName
        cacheData(cityWeatherData)
        saveCitiesList()
    }

    func renameCity(_ cityWeather: CityWeather, in listID: CityListID, to newName: String) {
        if listID.rawValue == activeListID.rawValue {
            renameCity(cityWeather, to: newName)
            return
        }
        var listData = otherListData[listID.rawValue] ?? []
        guard let index = listData.firstIndex(where: { $0.id == cityWeather.id }) else { return }
        listData[index].city.name = newName
        otherListData[listID.rawValue] = listData
        saveCities(listData.map(\.city), for: listID)
        cacheData(listData, for: listID)
    }
    
    func addCity(_ city: City) async {
        do {
            // Fetch weather for the new city
            errorMessage = nil
            let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
            let weather = try await weatherService.weather(for: location)
            
            // Convert to our model
            let cityWeather = try await convertWeatherKitData(weather: weather, for: city)
            
            // Add to the beginning of the list
            cityWeatherData.insert(cityWeather, at: 0)
            
            // Update cache with the new city included
            cacheData(cityWeatherData)
            
            // Save the updated cities list
            saveCitiesList()
            
        } catch {
            report(error)
        }
    }
    
    func addCityToList(_ city: City, listID: CityListID) async {
        let listKey = "savedCitiesList_\(listID.rawValue)"
        
        do {
            errorMessage = nil
            let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
            let weather = try await weatherService.weather(for: location)
            let cityWeather = try await convertWeatherKitData(weather: weather, for: city)
            
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
            
            // If this is the active list, also update in-memory data
            if listID == activeListID {
                cityWeatherData.insert(cityWeather, at: 0)
            } else {
                // Update otherListData if loaded
                otherListData[listID.rawValue]?.insert(cityWeather, at: 0)
            }
            
        } catch {
            report(error)
        }
    }

    func createCustomList(name: String, cities: [City]) async -> CityListID {
        let listID = CityListID.createList(name: name)
        saveCities(cities, for: listID)
        otherListData[listID.rawValue] = []
        await switchList(to: listID)
        return listID
    }

    func addCities(_ cities: [City], to listID: CityListID) async {
        guard !cities.isEmpty else { return }
        let existingCities = cityListCoordinates(for: listID)
        var mergedCities = existingCities
        for city in cities where !mergedCities.contains(where: { citiesMatch($0, city) }) {
            mergedCities.append(city)
        }

        saveCities(mergedCities, for: listID)
        UserDefaults.standard.removeObject(forKey: "cachedWeatherData_\(listID.rawValue)")
        UserDefaults.standard.removeObject(forKey: "weatherCacheTimestamp_\(listID.rawValue)")
        otherListData[listID.rawValue] = nil
        listFetchDates[listID.rawValue] = nil

        if listID.rawValue == activeListID.rawValue {
            cityWeatherData = []
            lastFetchDate = nil
            await fetchWeatherForAllCities(forceRefresh: true)
        }
    }
    
    func fetchWeatherForCity(_ city: City) async -> CityWeather? {
        do {
            // Fetch weather for the city
            errorMessage = nil
            let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
            let weather = try await weatherService.weather(for: location)
            
            // Convert to our model
            let cityWeather = try await convertWeatherKitData(weather: weather, for: city)
            
            return cityWeather
        } catch {
            report(error)
            return nil
        }
    }

    func refreshWeatherForCity(_ cityWeather: CityWeather) async -> CityWeather? {
        guard let fetchedWeather = await fetchWeatherForCity(cityWeather.city) else {
            return nil
        }

        let refreshedWeather = fetchedWeather.replacingID(cityWeather.id)
        replaceWeatherData(refreshedWeather, matching: cityWeather.id, in: activeListID)

        for listID in CityListID.allLists where listID.rawValue != activeListID.rawValue {
            replaceWeatherData(refreshedWeather, matching: cityWeather.id, in: listID)
        }

        return refreshedWeather
    }

    private func replaceWeatherData(_ refreshedWeather: CityWeather, matching cityID: UUID, in listID: CityListID) {
        if listID.rawValue == activeListID.rawValue {
            guard let index = cityWeatherData.firstIndex(where: { $0.id == cityID }) else { return }
            cityWeatherData[index] = refreshedWeather
            otherListData[listID.rawValue] = cityWeatherData
            cacheData(cityWeatherData, for: listID)
            return
        }

        guard var listData = otherListData[listID.rawValue],
              let index = listData.firstIndex(where: { $0.id == cityID }) else {
            return
        }
        listData[index] = refreshedWeather
        otherListData[listID.rawValue] = listData
        cacheData(listData, for: listID)
    }
    
    func moveCity(from source: IndexSet, to destination: Int) {
        var reorderedCities = cityWeatherData
        reorderedCities.move(fromOffsets: source, toOffset: destination)
        cityWeatherData = reorderedCities
        // Update cache after reordering cities
        cacheData(cityWeatherData)
        // Save the updated cities list
        saveCitiesList()
    }

    func moveCity(in listID: CityListID, from source: IndexSet, to destination: Int) {
        if listID.rawValue == activeListID.rawValue {
            moveCity(from: source, to: destination)
            return
        }
        var listData = otherListData[listID.rawValue] ?? []
        listData.move(fromOffsets: source, toOffset: destination)
        otherListData[listID.rawValue] = listData
        saveCities(listData.map(\.city), for: listID)
        cacheData(listData, for: listID)
    }

    func moveCity(id cityID: String, from sourceListID: CityListID, to targetListID: CityListID, destination: Int?) -> Bool {
        var sourceData = weatherData(for: sourceListID)
        guard let sourceIndex = sourceData.firstIndex(where: { $0.id.uuidString == cityID }) else { return false }
        let city = sourceData.remove(at: sourceIndex)

        var targetData = sourceListID == targetListID ? sourceData : weatherData(for: targetListID)
        let rawDestination = destination ?? targetData.count
        let adjustedDestination: Int
        if sourceListID == targetListID, rawDestination > sourceIndex {
            adjustedDestination = max(0, min(targetData.count, rawDestination - 1))
        } else {
            adjustedDestination = max(0, min(targetData.count, rawDestination))
        }
        targetData.insert(city, at: adjustedDestination)

        setWeatherData(sourceData, for: sourceListID)
        if sourceListID == targetListID {
            setWeatherData(targetData, for: sourceListID)
        } else {
            setWeatherData(targetData, for: targetListID)
        }
        return true
    }

    private func setWeatherData(_ data: [CityWeather], for listID: CityListID) {
        if listID.rawValue == activeListID.rawValue {
            cityWeatherData = data
            cacheData(cityWeatherData)
            saveCitiesList()
        } else {
            otherListData[listID.rawValue] = data
            saveCities(data.map(\.city), for: listID)
            cacheData(data, for: listID)
        }
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

enum ListMoveDirection {
    case up
    case down
}

// MARK: - City Models

struct City: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
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
    func localizedName(locale: Locale = .current) -> String {
        localizedString(String.LocalizationValue(name), locale: locale)
    }
}

struct CityWeather: Identifiable, Hashable {
    let id: UUID
    var city: City
    let condition: AppWeatherCondition
    let temperature: Double
    let symbolName: String
    let dailyForecasts: [DailyForecast]
    let timeZone: TimeZone
    
    // Current weather overlay data (for "Now" mode)
    var currentFeelsLike: Double?       // °C
    var currentCloudCover: Double?
    var currentWindSpeed: Double?       // km/h
    var currentUVIndex: Int?
    var currentHumidity: Double?        // 0-1
    var currentVisibility: Double?      // km

    init(
        id: UUID = UUID(),
        city: City,
        condition: AppWeatherCondition,
        temperature: Double,
        symbolName: String,
        dailyForecasts: [DailyForecast],
        timeZone: TimeZone,
        currentFeelsLike: Double? = nil,
        currentCloudCover: Double? = nil,
        currentWindSpeed: Double? = nil,
        currentUVIndex: Int? = nil,
        currentHumidity: Double? = nil,
        currentVisibility: Double? = nil
    ) {
        self.id = id
        self.city = city
        self.condition = condition
        self.temperature = temperature
        self.symbolName = symbolName
        self.dailyForecasts = dailyForecasts
        self.timeZone = timeZone
        self.currentFeelsLike = currentFeelsLike
        self.currentCloudCover = currentCloudCover
        self.currentWindSpeed = currentWindSpeed
        self.currentUVIndex = currentUVIndex
        self.currentHumidity = currentHumidity
        self.currentVisibility = currentVisibility
    }

    func replacingID(_ id: UUID) -> CityWeather {
        CityWeather(
            id: id,
            city: city,
            condition: condition,
            temperature: temperature,
            symbolName: symbolName,
            dailyForecasts: dailyForecasts,
            timeZone: timeZone,
            currentFeelsLike: currentFeelsLike,
            currentCloudCover: currentCloudCover,
            currentWindSpeed: currentWindSpeed,
            currentUVIndex: currentUVIndex,
            currentHumidity: currentHumidity,
            currentVisibility: currentVisibility
        )
    }
    
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
    
    /// Whether current weather data is available for the given overlay mode ("Now" mode).
    func hasCurrentData(forOverlay overlayMode: String) -> Bool {
        switch overlayMode {
        case "cloudCover":    return currentCloudCover != nil
        case "precipitation": return true // derived from condition
        case "windSpeed":     return currentWindSpeed != nil
        case "uvIndex":       return currentUVIndex != nil
        case "humidity":      return currentHumidity != nil
        case "visibility":    return currentVisibility != nil
        default:              return true
        }
    }
    
    var weatherIcon: String {
        // Map SF Symbol names to simplified icons
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
    let dailyLow: Double   // entire day low temperature
    let dailyHigh: Double  // entire day high temperature
    let symbolName: String
    let condition: AppWeatherCondition
    let hourlyForecasts: [HourlyForecast]
    let cloudCover: Double?  // 0.0 to 1.0, nil if unavailable
    let precipitationChance: Double?  // 0.0 to 1.0, nil if unavailable
    let visibility: Double?     // km, only available for day 0 (current weather)
    let feelsLikeLow: Double?   // °C, full-day min apparent temp
    let feelsLikeHigh: Double?  // °C, full-day max apparent temp
    let humidity: Double?       // 0.0–1.0, only available for day 0 (current weather)
    let windSpeed: Double?      // km/h, full-day wind speed
    let uvIndex: Int?           // 0–11+
    let maxHumidity: Double?    // 0.0–1.0, daily max humidity
    let maxVisibility: Double?  // km, daily max visibility
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
    
    var cloudCoverPercent: Int? {
        cloudCover.map { Int($0 * 100) }
    }
    
    var dailyTempString: String {
        "\(Int(dailyLow))-\(Int(dailyHigh))°"
    }
    
    /// Whether this forecast has the data required by the given overlay mode.
    func hasData(forOverlay overlayMode: String) -> Bool {
        switch overlayMode {
        case "cloudCover":    return cloudCover != nil
        case "precipitation": return precipitationChance != nil
        case "windSpeed":     return windSpeed != nil
        case "uvIndex":       return uvIndex != nil
        case "humidity":      return maxHumidity != nil
        case "visibility":    return maxVisibility != nil
        default:              return true
        }
    }
}

extension DailyForecast {
    static func previewSunny(dayOffset: Int) -> DailyForecast {
        DailyForecast(
            dayOffset: dayOffset,
            dailyLow: 18,
            dailyHigh: 24,
            symbolName: "sun.max.fill",
            condition: .clear,
            hourlyForecasts: [],
            cloudCover: nil,
            precipitationChance: nil,
            visibility: nil,
            feelsLikeLow: nil,
            feelsLikeHigh: nil,
            humidity: nil,
            windSpeed: nil,
            uvIndex: nil,
            maxHumidity: nil,
            maxVisibility: nil,
            sunrise: nil,
            sunset: nil
        )
    }

    static func previewCloudy(dayOffset: Int) -> DailyForecast {
        DailyForecast(
            dayOffset: dayOffset,
            dailyLow: 18,
            dailyHigh: 24,
            symbolName: "cloud.fill",
            condition: .cloudy,
            hourlyForecasts: [],
            cloudCover: nil,
            precipitationChance: nil,
            visibility: nil,
            feelsLikeLow: nil,
            feelsLikeHigh: nil,
            humidity: nil,
            windSpeed: nil,
            uvIndex: nil,
            maxHumidity: nil,
            maxVisibility: nil,
            sunrise: nil,
            sunset: nil
        )
    }
}

struct HourlyForecast: Identifiable {
    let id = UUID()
    let hour: Int  // 0-23
    let temperature: Double
    let apparentTemperature: Double?  // feels like, nil if unavailable
    let symbolName: String
    let condition: AppWeatherCondition
    let precipitationChance: Double?  // 0.0 to 1.0, nil if unavailable
    let cloudCover: Double?  // 0.0 to 1.0, nil if unavailable
    let windSpeed: Double?  // km/h
    let uvIndex: Int?
    let humidity: Double?  // 0.0 to 1.0
    let visibility: Double?  // km
    
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
    
    var cloudCoverPercent: Int? {
        cloudCover.map { Int($0 * 100) }
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
        return String(format: "%02d", hour)
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
    let id: UUID
    let city: CachedCity
    let condition: AppWeatherCondition
    let temperature: Double
    let symbolName: String
    let dailyForecasts: [CachedDailyForecast]
    let timeZoneIdentifier: String
    let currentFeelsLike: Double?
    let currentCloudCover: Double?
    let currentWindSpeed: Double?
    let currentUVIndex: Int?
    let currentHumidity: Double?
    let currentVisibility: Double?

    init(from cityWeather: CityWeather) {
        id = cityWeather.id
        city = CachedCity(from: cityWeather.city)
        condition = cityWeather.condition
        temperature = cityWeather.temperature
        symbolName = cityWeather.symbolName
        dailyForecasts = cityWeather.dailyForecasts.map { CachedDailyForecast(from: $0) }
        timeZoneIdentifier = cityWeather.timeZone.identifier
        currentFeelsLike = cityWeather.currentFeelsLike
        currentCloudCover = cityWeather.currentCloudCover
        currentWindSpeed = cityWeather.currentWindSpeed
        currentUVIndex = cityWeather.currentUVIndex
        currentHumidity = cityWeather.currentHumidity
        currentVisibility = cityWeather.currentVisibility
    }

    func toCityWeather() -> CityWeather? {
        let decodedCity = city.toCity()
        let forecasts = dailyForecasts.map { $0.toDailyForecast() }
        guard !forecasts.isEmpty else { return nil }
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return nil }

        return CityWeather(
            id: id,
            city: decodedCity,
            condition: condition,
            temperature: temperature,
            symbolName: symbolName,
            dailyForecasts: forecasts,
            timeZone: timeZone,
            currentFeelsLike: currentFeelsLike,
            currentCloudCover: currentCloudCover,
            currentWindSpeed: currentWindSpeed,
            currentUVIndex: currentUVIndex,
            currentHumidity: currentHumidity,
            currentVisibility: currentVisibility
        )
    }
}

struct CachedDailyForecast: Codable {
    let dayOffset: Int
    let dailyLow: Double
    let dailyHigh: Double
    let symbolName: String
    let condition: AppWeatherCondition
    let hourlyForecasts: [CachedHourlyForecast]
    let cloudCover: Double?
    let precipitationChance: Double?
    let visibility: Double?
    let feelsLikeLow: Double?
    let feelsLikeHigh: Double?
    let humidity: Double?
    let windSpeed: Double?
    let uvIndex: Int?
    let maxHumidity: Double?
    let maxVisibility: Double?
    let sunrise: Date?
    let sunset: Date?

    init(from forecast: DailyForecast) {
        dayOffset = forecast.dayOffset
        dailyLow = forecast.dailyLow
        dailyHigh = forecast.dailyHigh
        symbolName = forecast.symbolName
        condition = forecast.condition
        hourlyForecasts = forecast.hourlyForecasts.map { CachedHourlyForecast(from: $0) }
        cloudCover = forecast.cloudCover
        precipitationChance = forecast.precipitationChance
        visibility = forecast.visibility
        feelsLikeLow = forecast.feelsLikeLow
        feelsLikeHigh = forecast.feelsLikeHigh
        humidity = forecast.humidity
        windSpeed = forecast.windSpeed
        uvIndex = forecast.uvIndex
        maxHumidity = forecast.maxHumidity
        maxVisibility = forecast.maxVisibility
        sunrise = forecast.sunrise
        sunset = forecast.sunset
    }

    func toDailyForecast() -> DailyForecast {
        DailyForecast(
            dayOffset: dayOffset,
            dailyLow: dailyLow,
            dailyHigh: dailyHigh,
            symbolName: symbolName,
            condition: condition,
            hourlyForecasts: hourlyForecasts.map { $0.toHourlyForecast() },
            cloudCover: cloudCover,
            precipitationChance: precipitationChance,
            visibility: visibility,
            feelsLikeLow: feelsLikeLow,
            feelsLikeHigh: feelsLikeHigh,
            humidity: humidity,
            windSpeed: windSpeed,
            uvIndex: uvIndex,
            maxHumidity: maxHumidity,
            maxVisibility: maxVisibility,
            sunrise: sunrise,
            sunset: sunset
        )
    }
}

struct CachedHourlyForecast: Codable {
    let hour: Int
    let temperature: Double
    let apparentTemperature: Double?
    let symbolName: String
    let condition: AppWeatherCondition
    let precipitationChance: Double?
    let cloudCover: Double?
    let windSpeed: Double?
    let uvIndex: Int?
    let humidity: Double?
    let visibility: Double?

    init(from forecast: HourlyForecast) {
        hour = forecast.hour
        temperature = forecast.temperature
        apparentTemperature = forecast.apparentTemperature
        symbolName = forecast.symbolName
        condition = forecast.condition
        precipitationChance = forecast.precipitationChance
        cloudCover = forecast.cloudCover
        windSpeed = forecast.windSpeed
        uvIndex = forecast.uvIndex
        humidity = forecast.humidity
        visibility = forecast.visibility
    }

    func toHourlyForecast() -> HourlyForecast {
        HourlyForecast(
            hour: hour,
            temperature: temperature,
            apparentTemperature: apparentTemperature,
            symbolName: symbolName,
            condition: condition,
            precipitationChance: precipitationChance,
            cloudCover: cloudCover,
            windSpeed: windSpeed,
            uvIndex: uvIndex,
            humidity: humidity,
            visibility: visibility
        )
    }
}
