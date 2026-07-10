//
//  WeatherService.swift
//  Weather
//
//  Purpose: Owns weather fetching, weather caching, weather models, forecast
//  models, and cache serialization. List mutation lives in ListManager.swift.
//

import Foundation
import SwiftUI
import WeatherKit
import CoreLocation

// MARK: - Shared Errors and Localization

enum WeatherServiceError: LocalizedError {
    case undefinedTimeZone(city: String)
    case unresolvedPlace(city: String)

    var errorDescription: String? {
        switch self {
        case .undefinedTimeZone(let city):
            return "Timezone undefined for \(city)"
        case .unresolvedPlace(let city):
            return "Place unresolved for \(city)"
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
    case night
    
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
        case .night:
            return "Night"
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
        case .night:
            return localizedString("Night", locale: locale)
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
        case .night: return theme.moonIconColor
        }
    }

    var sunninessScore: Double {
        switch self {
        case .clear:
            return 100
        case .partlySunny:
            return 50
        default:
            return 0
        }
    }

    var sunninessRank: Int {
        switch self {
        case .clear: return 0
        case .partlySunny: return 1
        case .partlyCloudy: return 2
        case .cloudy: return 3
        case .wind: return 4
        case .fog: return 5
        case .drizzle: return 6
        case .rain: return 7
        case .snow: return 8
        case .night: return 9
        }
    }

    var isSunny: Bool {
        self == .clear
    }

    var isSunnyOrPartlySunny: Bool {
        self == .clear || self == .partlySunny
    }

    static func fromWeatherSymbol(_ symbolName: String) -> AppWeatherCondition {
        let symbol = symbolName.lowercased()

        if symbol.contains("moon") { return .night }
        if symbol.contains("drizzle") { return .drizzle }
        if symbol.contains("rain") || symbol.contains("thunderstorm") || symbol.contains("storm") { return .rain }
        if symbol.contains("snow") || symbol.contains("sleet") || symbol.contains("flurr") { return .snow }
        if symbol.contains("wind") || symbol.contains("hurricane") || symbol.contains("tropicalstorm") { return .wind }
        if symbol.contains("fog") || symbol.contains("haze") || symbol.contains("smoke") { return .fog }
        if symbol.contains("cloud") && symbol.contains("sun") { return .partlySunny }
        if symbol.contains("sun.max") || symbol == "sun" || symbol == "sun.fill" { return .clear }
        if symbol.contains("partly") && symbol.contains("cloud") { return .partlyCloudy }
        if symbol.contains("cloud") { return .cloudy }
        return .cloudy
    }

    var displayIcon: String {
        switch self {
        case .clear:
            return "sun.max.fill"
        case .partlySunny:
            return "cloud.sun"
        case .partlyCloudy, .cloudy:
            return "cloud"
        case .rain:
            return "cloud.rain"
        case .drizzle:
            return "cloud.drizzle"
        case .snow:
            return "cloud.snow"
        case .fog:
            return "cloud.fog"
        case .wind:
            return "wind"
        case .night:
            return "moon.fill"
        }
    }
}

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
    let weatherCacheDuration: TimeInterval = 2 * 60 * 60
    var listFetchDates: [String: Date] = [:]
    var otherListData: [String: [CityWeather]] = [:]
    var resolvedTimeZones: [String: TimeZone] = [:]
    var resolvedPlaces: [String: ResolvedPlace] = [:]
    
    let weatherService = WeatherKit.WeatherService.shared
    
    static let activeListKey = "activeListID"
    
    // Per-list cache keys
    var cacheKey: String { "cachedWeatherData_\(activeListID.rawValue)" }
    var cacheTimestampKey: String { "weatherCacheTimestamp_\(activeListID.rawValue)" }
    var citiesListKey: String { "savedCitiesList_\(activeListID.rawValue)" }
    
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
        } catch { }
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
           isWeatherDataFresh(for: activeListID),
           cachedWeatherDataLooksCurrent(cityWeatherData, for: activeListID) {
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
                let resolvedCity = try await resolvedCity(for: city)
                let location = CLLocation(latitude: resolvedCity.latitude, longitude: resolvedCity.longitude)
                let weather = try await weatherService.weather(for: location)
                let cityWeather = try await convertWeatherKitData(weather: weather, for: resolvedCity)
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
           cachedWeatherDataLooksCurrent(existingData, for: listID),
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

    func citiesMatch(_ lhs: City, _ rhs: City) -> Bool {
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
    
    func weatherData(for listID: CityListID) -> [CityWeather] {
        if listID.rawValue == activeListID.rawValue {
            return cityWeatherData
        }
        return otherListData[listID.rawValue] ?? []
    }

    func fetchWeatherForList(_ listID: CityListID) async {
        errorMessage = nil
        if let existingData = otherListData[listID.rawValue],
           !existingData.isEmpty,
           isWeatherDataFresh(for: listID),
           cachedWeatherDataLooksCurrent(existingData, for: listID) {
            return
        }
        if let cachedData = loadCachedWeatherData(for: listID), isWeatherDataFresh(for: listID) {
            otherListData[listID.rawValue] = cachedData
            return
        }
        let citiesToFetch = loadSavedCities(for: listID) ?? listID.defaultCities
        guard !citiesToFetch.isEmpty else { return }
        
        var weatherData: [CityWeather] = []
        for city in citiesToFetch {
            do {
                let resolvedCity = try await resolvedCity(for: city)
                let location = CLLocation(latitude: resolvedCity.latitude, longitude: resolvedCity.longitude)
                let weather = try await weatherService.weather(for: location)
                let cityWeather = try await convertWeatherKitData(weather: weather, for: resolvedCity)
                weatherData.append(cityWeather)
            } catch {
                report(error)
            }
        }
        otherListData[listID.rawValue] = weatherData
        cacheData(weatherData, for: listID, updateFetchDate: true)
    }
    
    func report(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    func reportDeveloperWarning(title: String, message: String) {
        DeveloperWarningCenter.show(title: title, message: message)
    }

    func convertWeatherKitData(weather: Weather, for city: City) async throws -> CityWeather {
        let timeZone = try await resolvedTimeZoneOrThrow(for: city)
        return convertWeatherKitData(weather: weather, for: city, timeZone: timeZone)
    }
    
    func convertWeatherKitData(weather: Weather, for city: City, timeZone: TimeZone) -> CityWeather {
        // Current weather
        let currentTemp = weather.currentWeather.temperature.value
        let currentSymbol = weather.currentWeather.symbolName
        let currentCondition = AppWeatherCondition.fromWeatherSymbol(currentSymbol)
        
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
            let dayCondition = AppWeatherCondition.fromWeatherSymbol(daySymbol)
            
            // Generate hourly forecasts for this day
            let hourlyForecasts = generateHourlyFromDaily(day: day, dayOffset: index, allHourly: weather.hourlyForecast.forecast, timeZone: timeZone)
            
            // Derive full-day feels-like range from all hourly apparent temperatures
            let apparentTemps = hourlyForecasts.compactMap(\.apparentTemperature)
            let feelsLikeLow = apparentTemps.min()
            let feelsLikeHigh = apparentTemps.max()
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
        
        if dayHourlyData.isEmpty { return [] }
        
        return dayHourlyData.map { hourWeather in
            // Extract hour in the city's local timezone
            let hour = calendar.component(.hour, from: hourWeather.date)
            return HourlyForecast(
                hour: hour,
                temperature: hourWeather.temperature.value,
                apparentTemperature: hourWeather.apparentTemperature.value,
                symbolName: hourWeather.symbolName,
                condition: AppWeatherCondition.fromWeatherSymbol(hourWeather.symbolName),
                precipitationChance: hourWeather.precipitationChance,
                cloudCover: hourWeather.cloudCover,
                windSpeed: hourWeather.wind.speed.converted(to: .kilometersPerHour).value,
                uvIndex: hourWeather.uvIndex.value,
                humidity: hourWeather.humidity,
                visibility: hourWeather.visibility.converted(to: .kilometers).value
            )
        }
    }
    func fetchWeatherForCity(_ city: City) async -> CityWeather? {
        do {
            // Fetch weather for the city
            errorMessage = nil
            let resolvedCity = try await resolvedCity(for: city)
            let location = CLLocation(latitude: resolvedCity.latitude, longitude: resolvedCity.longitude)
            let weather = try await weatherService.weather(for: location)
            
            // Convert to our model
            let cityWeather = try await convertWeatherKitData(weather: weather, for: resolvedCity)
            
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
    
    private func generateForecastDays() {
        let calendar = Calendar.current
        let today = Date()
        
        forecastDays = (0..<10).map { dayOffset in
            let date = calendar.date(byAdding: .day, value: dayOffset, to: today)!
            return ForecastDay(date: date, dayOffset: dayOffset)
        }
    }
    
}

// MARK: - City Models

struct City: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var country: String
    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String?
    
    init(id: UUID = UUID(), name: String, country: String = "", latitude: Double, longitude: Double, timeZoneIdentifier: String? = nil) {
        self.id = id
        self.name = name
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    init(id: UUID = UUID(), latitude: Double, longitude: Double, timeZoneIdentifier: String? = nil) {
        self.init(id: id, name: "", country: "", latitude: latitude, longitude: longitude, timeZoneIdentifier: timeZoneIdentifier)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
    }
    
    /// Returns the display city name stored with the city record.
    func localizedName(locale: Locale = .current) -> String {
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return String(format: "%.2f, %.2f", latitude, longitude)
    }

    /// Returns the display country name, localized through the string catalog when available.
    func localizedCountry(locale: Locale = .current) -> String {
        guard !country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return localizedString(String.LocalizationValue(country), locale: locale)
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
    
    // Current weather metrics used by map overlays and detail cards.
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
    
    /// Whether current weather data is available for the given overlay mode.
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
        AppWeatherCondition.fromWeatherSymbol(symbolName).displayIcon
    }
    
    var weatherColor: Color {
        AppWeatherCondition.fromWeatherSymbol(symbolName).dotColor
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
        AppWeatherCondition.fromWeatherSymbol(symbolName).displayIcon
    }
    
    var weatherColor: Color {
        AppWeatherCondition.fromWeatherSymbol(symbolName).dotColor
    }
    
    // Themed color variant
    func weatherColor(for colorScheme: ColorScheme) -> Color {
        return weatherColor
    }
    
    // Palette colors for rain icons
    func rainPaletteColors(for colorScheme: ColorScheme) -> (primary: Color, secondary: Color) {
        let theme = AppTheme.shared.colors
        return (theme.cloudIconColor, theme.cloudIconColor)
    }
    
    // Palette colors for partially sunny icons
    func partlySunnyPaletteColors(for colorScheme: ColorScheme) -> (primary: Color, secondary: Color) {
        let theme = AppTheme.shared.colors
        return (theme.cloudIconColor, theme.sunIconColor)
    }
    
    var isRainIcon: Bool {
        [.rain, .drizzle].contains(AppWeatherCondition.fromWeatherSymbol(symbolName))
    }
    
    var isPartiallySunnyIcon: Bool {
        AppWeatherCondition.fromWeatherSymbol(symbolName) == .partlySunny
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
        AppWeatherCondition.fromWeatherSymbol(symbolName).displayIcon
    }
    
    func weatherColor(for colorScheme: ColorScheme) -> Color {
        AppWeatherCondition.fromWeatherSymbol(symbolName).dotColor
    }
    
    func rainPaletteColors(for colorScheme: ColorScheme) -> (primary: Color, secondary: Color) {
        let theme = AppTheme.shared.colors
        return (theme.cloudIconColor, theme.cloudIconColor)
    }
    
    func partlySunnyPaletteColors(for colorScheme: ColorScheme) -> (primary: Color, secondary: Color) {
        let theme = AppTheme.shared.colors
        return (theme.cloudIconColor, theme.sunIconColor)
    }
    
    func partlyMoonPaletteColors(for colorScheme: ColorScheme) -> (primary: Color, secondary: Color) {
        let theme = AppTheme.shared.colors
        return (theme.cloudIconColor, theme.moonIconColor)
    }
    
    var isRainIcon: Bool {
        [.rain, .drizzle].contains(AppWeatherCondition.fromWeatherSymbol(symbolName))
    }
    
    var isPartiallySunnyIcon: Bool {
        AppWeatherCondition.fromWeatherSymbol(symbolName) == .partlySunny
    }
    
    var isPartlyMoonIcon: Bool {
        AppWeatherCondition.fromWeatherSymbol(symbolName) == .night
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
