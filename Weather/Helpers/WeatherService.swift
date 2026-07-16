//
//  WeatherService.swift
//  Weather
//
//  Purpose: Fetches WeatherKit data and defines the app's weather models.
//

import Foundation
import SwiftUI
import Observation
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
    var availableLists: [CityListID] = CityListID.allLists
    var weatherDataByListID: [String: [CityWeather]] = [:]
    var cityWeatherData: [CityWeather] {
        get { weatherDataByListID[activeListID.rawValue] ?? [] }
        set { weatherDataByListID[activeListID.rawValue] = newValue }
    }
    var isLoading = false
    var loadingProgress: Double = 0
    var errorMessage: String?
    var lastFetchDate: Date?
    var weatherAttribution: WeatherAttribution?
    var activeListID: CityListID = .europe
    @ObservationIgnored private var activeFetchTask: Task<Void, Never>?
    let weatherCacheDuration: TimeInterval = 30 * 60
    var listFetchDates: [String: Date] = [:]
    var resolvedTimeZones: [String: TimeZone] = [:]
    var resolvedPlaces: [String: ResolvedPlace] = [:]
    
    let weatherService = WeatherKit.WeatherService.shared
    
    static let activeListKey = "activeListID"
    
    // Per-list persistence keys
    var cacheTimestampKey: String { "weatherCacheTimestamp_\(activeListID.rawValue)" }
    var citiesListKey: String { "savedCitiesList_\(activeListID.rawValue)" }
    
    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.activeListKey),
           let listID = availableLists.first(where: { $0.rawValue == saved }) {
            activeListID = listID
        }
        if let cachedData = loadCachedWeatherData(for: activeListID), isWeatherDataFresh(for: activeListID) {
            cityWeatherData = cachedData
            lastFetchDate = fetchDate(for: activeListID)
        }
    }

    func reloadAvailableLists() {
        availableLists = CityListID.allLists
        if let refreshedActiveList = availableLists.first(where: { $0.rawValue == activeListID.rawValue }) {
            activeListID = refreshedActiveList
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
        activeFetchTask?.cancel()
        let targetListID = activeListID
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performActiveListFetch(for: targetListID, forceRefresh: forceRefresh)
        }
        activeFetchTask = task
        await task.value
    }

    private func performActiveListFetch(for targetListID: CityListID, forceRefresh: Bool) async {
        guard activeListID == targetListID, !Task.isCancelled else { return }
        errorMessage = nil
        let currentData = weatherDataByListID[targetListID.rawValue] ?? []
        if !forceRefresh,
           currentData.isEmpty,
           let cachedData = loadCachedWeatherData(for: activeListID),
           isWeatherDataFresh(for: activeListID) {
            weatherDataByListID[activeListID.rawValue] = cachedData
            lastFetchDate = fetchDate(for: activeListID)
            loadingProgress = 1
            isLoading = false
            return
        }

        if !forceRefresh,
           !currentData.isEmpty,
           isWeatherDataFresh(for: activeListID),
           cachedWeatherDataLooksCurrent(currentData, for: activeListID) {
            loadingProgress = 1
            isLoading = false
            return
        }

        isLoading = true
        loadingProgress = 0
        defer {
            if !Task.isCancelled, activeListID == targetListID {
                isLoading = false
            }
        }
        
        // Load the saved cities list, or use defaults for active list
        let citiesToFetch = loadSavedCities(for: targetListID) ?? targetListID.defaultCities
        guard !citiesToFetch.isEmpty else {
            weatherDataByListID[targetListID.rawValue] = []
            loadingProgress = 1
            return
        }
        
        var weatherData: [CityWeather] = []
        weatherDataByListID[targetListID.rawValue] = []
        
        for (index, city) in citiesToFetch.enumerated() {
            guard activeListID == targetListID, !Task.isCancelled else { return }
            do {
                let resolvedCity = try await resolvedCity(for: city)
                let location = CLLocation(latitude: resolvedCity.latitude, longitude: resolvedCity.longitude)
                let weather = try await weatherService.weather(for: location)
                let cityWeather = try await convertWeatherKitData(weather: weather, for: resolvedCity)
                guard activeListID == targetListID, !Task.isCancelled else { return }

                weatherData.append(cityWeather)
                weatherDataByListID[targetListID.rawValue] = weatherData
            } catch {
                guard !Task.isCancelled else { return }
                report(error)
            }
            loadingProgress = Double(index + 1) / Double(citiesToFetch.count)
        }
        
        guard !Task.isCancelled, activeListID == targetListID else {
            return
        }
        
        cacheData(weatherData, for: targetListID, updateFetchDate: true)
    }
    
    func refreshWeather() async {
        clearCache()
        await fetchWeatherForAllCities(forceRefresh: true)
    }
    
    func switchList(to listID: CityListID) async {
        guard listID != activeListID else { return }
        activeFetchTask?.cancel()
        activeListID = listID
        isLoading = false
        UserDefaults.standard.set(listID.rawValue, forKey: Self.activeListKey)
        weatherDataByListID[listID.rawValue] = weatherDataByListID[listID.rawValue]
            ?? loadCachedWeatherData(for: listID)
            ?? []
        lastFetchDate = fetchDate(for: listID)
        await fetchWeatherForAllCities()
    }

    func switchList(to listID: CityListID, prioritizing priorityCity: City) async -> CityWeather? {
        let existingData = weatherDataByListID[listID.rawValue]
            ?? (listID == activeListID ? cityWeatherData : nil)
            ?? loadCachedWeatherData(for: listID)
            ?? []
        if isWeatherDataFresh(for: listID),
           cachedWeatherDataLooksCurrent(existingData, for: listID),
           let existingCity = existingData.first(where: { citiesMatch($0.city, priorityCity) }) {
            activeFetchTask?.cancel()
            activeListID = listID
            UserDefaults.standard.set(listID.rawValue, forKey: Self.activeListKey)
            weatherDataByListID[listID.rawValue] = existingData
            lastFetchDate = fetchDate(for: listID)
            return existingCity
        }

        activeFetchTask?.cancel()
        activeListID = listID
        UserDefaults.standard.set(listID.rawValue, forKey: Self.activeListKey)
        lastFetchDate = nil
        loadingProgress = 0
        isLoading = true

        let citiesToFetch = orderedCitiesForFetch(listID: listID, prioritizing: priorityCity)
        guard !citiesToFetch.isEmpty else {
            weatherDataByListID[listID.rawValue] = []
            isLoading = false
            loadingProgress = 1
            return nil
        }

        weatherDataByListID[listID.rawValue] = []

        let priorityWeather = await fetchWeatherForCity(citiesToFetch[0])
        guard !Task.isCancelled, activeListID == listID else { return nil }
        guard let priorityWeather else {
            activeFetchTask = Task { [weak self] in
                guard let self else { return }
                await self.finishPrioritizedListFetch(
                    listID: listID,
                    citiesToFetch: citiesToFetch,
                    initialWeatherData: []
                )
            }
            return nil
        }

        weatherDataByListID[listID.rawValue] = [priorityWeather]
        loadingProgress = 1 / Double(citiesToFetch.count)

        activeFetchTask = Task { [weak self] in
            guard let self else { return }
            await self.finishPrioritizedListFetch(
                listID: listID,
                citiesToFetch: Array(citiesToFetch.dropFirst()),
                initialWeatherData: [priorityWeather]
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
        if lhs.name.caseInsensitiveCompare(rhs.name) == .orderedSame,
           lhs.country.caseInsensitiveCompare(rhs.country) == .orderedSame {
            return true
        }

        let lhsLocation = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
        let rhsLocation = CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
        return lhsLocation.distance(from: rhsLocation) <= 5_000
    }

    private func finishPrioritizedListFetch(
        listID: CityListID,
        citiesToFetch: [City],
        initialWeatherData: [CityWeather]
    ) async {
        var weatherData = initialWeatherData
        let totalCount = weatherData.count + citiesToFetch.count

        for city in citiesToFetch {
            guard !Task.isCancelled, activeListID == listID else { return }
            if let cityWeather = await fetchWeatherForCity(city) {
                guard !Task.isCancelled, activeListID == listID else { return }
                weatherData.append(cityWeather)
                weatherDataByListID[listID.rawValue] = weatherData
                loadingProgress = Double(weatherData.count) / Double(max(totalCount, 1))
            }
        }

        guard !Task.isCancelled, activeListID == listID else { return }
        isLoading = false
        loadingProgress = 1
        lastFetchDate = Date()
        weatherDataByListID[listID.rawValue] = weatherData
        cacheData(weatherData, for: listID, updateFetchDate: true)
    }
    
    func weatherData(for listID: CityListID) -> [CityWeather] {
        return weatherDataByListID[listID.rawValue] ?? []
    }

    func fetchWeatherForList(_ listID: CityListID) async {
        errorMessage = nil
        if let existingData = weatherDataByListID[listID.rawValue],
           !existingData.isEmpty,
           isWeatherDataFresh(for: listID),
           cachedWeatherDataLooksCurrent(existingData, for: listID) {
            return
        }
        if let cachedData = loadCachedWeatherData(for: listID), isWeatherDataFresh(for: listID) {
            weatherDataByListID[listID.rawValue] = cachedData
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
        weatherDataByListID[listID.rawValue] = weatherData
        cacheData(weatherData, for: listID, updateFetchDate: true)
    }
    
    func report(_ error: Error) {
        #if DEBUG
        print("[WeatherService] \(error.localizedDescription)")
        #endif

        let locale = Locale(identifier: UserDefaults.standard.string(forKey: "appLanguage") ?? Locale.autoupdatingCurrent.identifier)
        errorMessage = localizedString("We couldn't load weather. Please try again.", locale: locale)
    }

    func reportDeveloperWarning(title: String, message: String) {
        DeveloperWarningCenter.show(title: title, message: message)
    }

    func convertWeatherKitData(weather: Weather, for city: City) async throws -> CityWeather {
        let timeZone = try await resolvedTimeZoneOrThrow(for: city)
        return convertWeatherKitData(weather: weather, for: city, timeZone: timeZone)
    }
    
    func convertWeatherKitData(weather: Weather, for city: City, timeZone: TimeZone) -> CityWeather {
        let currentTemp = weather.currentWeather.temperature.value
        
        let dailyForecasts = weather.dailyForecast.forecast.prefix(10).enumerated().map { (index, day) -> DailyForecast in
            let daySymbol = day.symbolName
            let daytimeForecast = day.daytimeForecast
            let hourlyForecasts = generateHourlyFromDaily(
                day: day,
                allHourly: weather.hourlyForecast.forecast,
                timeZone: timeZone
            )

            return DailyForecast(
                date: day.date,
                dayOffset: index,
                dailyLow: day.lowTemperature.value,
                dailyHigh: day.highTemperature.value,
                symbolName: daySymbol,
                hourlyForecasts: hourlyForecasts,
                cloudCover: daytimeForecast.cloudCover,
                precipitationChance: daytimeForecast.precipitationChance,
                windSpeed: daytimeForecast.wind.speed.converted(to: .kilometersPerHour).value,
                uvIndex: day.uvIndex.value,
                sunrise: day.sun.sunrise,
                sunset: day.sun.sunset
            )
        }
        
        return CityWeather(
            city: city,
            temperature: currentTemp,
            dailyForecasts: Array(dailyForecasts),
            timeZone: timeZone
        )
    }
    
    private func generateHourlyFromDaily(day: DayWeather, allHourly: [HourWeather], timeZone: TimeZone) -> [HourlyForecast] {
        var calendar = Calendar.current
        calendar.timeZone = timeZone

        let dayStart = calendar.startOfDay(for: day.date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }

        let dayHourlyData = allHourly.filter { hourWeather in
            hourWeather.date >= dayStart && hourWeather.date < dayEnd
        }
        
        if dayHourlyData.isEmpty { return [] }
        
        return dayHourlyData.map { hourWeather in
            HourlyForecast(date: hourWeather.date, symbolName: hourWeather.symbolName)
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

        for listID in availableLists where listID.rawValue != activeListID.rawValue {
            replaceWeatherData(refreshedWeather, matching: cityWeather.id, in: listID)
        }

        return refreshedWeather
    }

    private func replaceWeatherData(_ refreshedWeather: CityWeather, matching cityID: UUID, in listID: CityListID) {
        if listID.rawValue == activeListID.rawValue {
            guard let index = cityWeatherData.firstIndex(where: { $0.id == cityID }) else { return }
            cityWeatherData[index] = refreshedWeather
            cacheData(cityWeatherData, for: listID)
            return
        }

        guard var listData = weatherDataByListID[listID.rawValue],
              let index = listData.firstIndex(where: { $0.id == cityID }) else {
            return
        }
        listData[index] = refreshedWeather
        weatherDataByListID[listID.rawValue] = listData
        cacheData(listData, for: listID)
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

}

struct CityWeather: Identifiable, Hashable {
    let id: UUID
    var city: City
    let temperature: Double
    let dailyForecasts: [DailyForecast]
    let timeZone: TimeZone

    init(
        id: UUID = UUID(),
        city: City,
        temperature: Double,
        dailyForecasts: [DailyForecast],
        timeZone: TimeZone
    ) {
        self.id = id
        self.city = city
        self.temperature = temperature
        self.dailyForecasts = dailyForecasts
        self.timeZone = timeZone
    }

    func replacingID(_ id: UUID) -> CityWeather {
        CityWeather(
            id: id,
            city: city,
            temperature: temperature,
            dailyForecasts: dailyForecasts,
            timeZone: timeZone
        )
    }

    static func == (lhs: CityWeather, rhs: CityWeather) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    func forecast(for dayOffset: Int) -> DailyForecast {
        if let forecast = dailyForecasts.first(where: { $0.dayOffset == dayOffset }) {
            return forecast
        }

        DeveloperWarningCenter.showOnce(
            key: "missing-forecast-day-\(id.uuidString)-\(dayOffset)",
            title: "Forecast Day Missing",
            message: "\(city.localizedName()) has no forecast data for day \(dayOffset). The app is showing its first available forecast instead."
        )
        return dailyForecasts.first ?? .unavailable(
            dayOffset: dayOffset,
            temperature: temperature,
            timeZone: timeZone
        )
    }
    
}
// MARK: - Forecast Models

struct DailyForecast: Identifiable {
    let id = UUID()
    let date: Date
    let dayOffset: Int
    let dailyLow: Double   // entire day low temperature
    let dailyHigh: Double  // entire day high temperature
    let symbolName: String
    let hourlyForecasts: [HourlyForecast]
    let cloudCover: Double?  // 0.0 to 1.0, nil if unavailable
    let precipitationChance: Double?  // 0.0 to 1.0, nil if unavailable
    let windSpeed: Double?      // km/h, full-day wind speed
    let uvIndex: Int?           // 0–11+
    let sunrise: Date?
    let sunset: Date?
    
    var weatherIcon: String {
        AppWeatherCondition.fromWeatherSymbol(symbolName).displayIcon
    }
    
    var cloudCoverPercent: Int? {
        cloudCover.map { Int($0 * 100) }
    }

    static func unavailable(dayOffset: Int, temperature: Double, timeZone: TimeZone) -> DailyForecast {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let date = calendar.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        return DailyForecast(
            date: date,
            dayOffset: dayOffset,
            dailyLow: temperature,
            dailyHigh: temperature,
            symbolName: "cloud",
            hourlyForecasts: [],
            cloudCover: nil,
            precipitationChance: nil,
            windSpeed: nil,
            uvIndex: nil,
            sunrise: nil,
            sunset: nil
        )
    }
}

struct HourlyForecast: Identifiable {
    let id = UUID()
    let date: Date
    let symbolName: String

    func hour(in timeZone: TimeZone) -> Int {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar.component(.hour, from: date)
    }
}
