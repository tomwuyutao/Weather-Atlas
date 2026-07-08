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
import MapKit

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
    private let weatherCacheDuration: TimeInterval = 2 * 60 * 60
    var listFetchDates: [String: Date] = [:]
    var otherListData: [String: [CityWeather]] = [:]
    private var resolvedTimeZones: [String: TimeZone] = [:]
    private var resolvedPlaces: [String: ResolvedPlace] = [:]
    
    let weatherService = WeatherKit.WeatherService.shared
    
    static let activeListKey = "activeListID"
    
    // Per-list cache keys
    private var cacheKey: String { "cachedWeatherData_\(activeListID.rawValue)" }
    private var cacheTimestampKey: String { "weatherCacheTimestamp_\(activeListID.rawValue)" }
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
    
    // MARK: - Caching Methods
    
    func saveCachedWeatherData(_ data: [CityWeather], for listID: CityListID) {
        let key = "cachedWeatherData_\(listID.rawValue)"
        do {
            let cached = data.map { CachedCityWeather(from: $0) }
            let encoded = try JSONEncoder().encode(cached)
            UserDefaults.standard.set(encoded, forKey: key)
        } catch {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func loadCachedWeatherData(for listID: CityListID) -> [CityWeather]? {
        let key = "cachedWeatherData_\(listID.rawValue)"
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        do {
            let decodedCache = try JSONDecoder().decode([CachedCityWeather].self, from: data)
            let cachedData = decodedCache.compactMap { $0.toCityWeather() }
            if cachedData.count != decodedCache.count {
                reportDeveloperWarning(
                    title: "Cached Weather Invalid",
                    message: "Some cached weather entries for \(listID.rawValue) could not be restored and the cache was removed."
                )
                UserDefaults.standard.removeObject(forKey: key)
                UserDefaults.standard.removeObject(forKey: "weatherCacheTimestamp_\(listID.rawValue)")
                listFetchDates[listID.rawValue] = nil
                if listID.rawValue == activeListID.rawValue {
                    lastFetchDate = nil
                }
                return nil
            }
            guard cachedWeatherDataLooksCurrent(cachedData, for: listID) else {
                reportDeveloperWarning(
                    title: "Cached Weather Stale",
                    message: "The cached weather data for \(listID.rawValue) was not current enough to reuse and was removed."
                )
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
            reportDeveloperWarning(
                title: "Cached Weather Corrupt",
                message: "The cached weather data for \(listID.rawValue) could not be decoded and was removed."
            )
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
    }

    func cachedWeatherDataLooksCurrent(_ data: [CityWeather], for listID: CityListID, now: Date = Date()) -> Bool {
        guard fetchDate(for: listID) != nil else { return false }
        return data.allSatisfy { cityWeather in
            guard hasResolvedTimeZone(cityWeather) else {
                return false
            }

            guard let todayForecast = cityWeather.dailyForecasts.first(where: { $0.dayOffset == 0 }) else {
                return false
            }
            guard !todayForecast.hourlyForecasts.isEmpty else { return false }
            guard SunninessScoring.hasDaytimeHourlyScoreData(for: todayForecast, timeZone: cityWeather.timeZone) else {
                return false
            }

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

    func clearPersistedWeatherCaches() {
        UserDefaults.standard.removeObject(forKey: "cachedWeatherData")
        UserDefaults.standard.removeObject(forKey: "weatherCacheTimestamp")
        for listID in CityListID.allLists {
            UserDefaults.standard.removeObject(forKey: "cachedWeatherData_\(listID.rawValue)")
        }
    }

    func fetchDate(for listID: CityListID) -> Date? {
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

    func isWeatherDataFresh(for listID: CityListID, now: Date = Date()) -> Bool {
        guard let fetchDate = fetchDate(for: listID) else {
            return false
        }
        return now.timeIntervalSince(fetchDate) < weatherCacheDuration
    }

    func cacheData(_ data: [CityWeather], updateFetchDate: Bool = false) {
        saveCachedWeatherData(data, for: activeListID)
        guard updateFetchDate else { return }

        let fetchDate = Date()
        listFetchDates[activeListID.rawValue] = fetchDate
        UserDefaults.standard.set(fetchDate, forKey: cacheTimestampKey)
        lastFetchDate = fetchDate
    }

    func cacheData(_ data: [CityWeather], for listID: CityListID, updateFetchDate: Bool = false) {
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

    private func coordinateKey(for city: City) -> String {
        String(format: "%.3f,%.3f", city.latitude, city.longitude)
    }

    private func preferredGeocodingLocale() -> Locale {
        let identifier = UserDefaults.standard.string(forKey: "appLanguage") ?? Locale.autoupdatingCurrent.identifier
        return Locale(identifier: identifier)
    }

    private func resolvedPlace(for city: City) async -> ResolvedPlace? {
        let key = coordinateKey(for: city)
        if let cachedPlace = resolvedPlaces[key] {
            return cachedPlace
        }

        let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
        if #available(iOS 26.0, *) {
            if let place = await resolvedPlaceWithMapKit(for: city, location: location) {
                resolvedPlaces[key] = place
                if let timeZone = place.timeZone {
                    resolvedTimeZones[key] = timeZone
                }
                return place
            }
            return nil
        }

        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: preferredGeocodingLocale())
            guard let placemark = placemarks.first else {
                reportDeveloperWarning(
                    title: "Geocoder Returned No Placemark",
                    message: "Apple reverse geocoding returned no placemark for \(city.localizedName()) at \(city.latitude), \(city.longitude)."
                )
                return nil
            }
            let resolvedName = resolvedCityName(from: placemark, originalCity: city)
            guard let resolvedName else {
                reportDeveloperWarning(
                    title: "Geocoder Returned No City Name",
                    message: "Apple reverse geocoding returned only district/road-level names for \(city.latitude), \(city.longitude). Contact developer to correct this coordinate."
                )
                return nil
            }
            let resolvedCountry = placemark.country
                ?? placemark.isoCountryCode
            guard let resolvedCountry else {
                reportDeveloperWarning(
                    title: "Geocoder Returned No Country",
                    message: "Apple reverse geocoding returned a placemark without a country for \(resolvedName) at \(city.latitude), \(city.longitude)."
                )
                return nil
            }
            let place = ResolvedPlace(name: resolvedName, country: resolvedCountry, timeZone: placemark.timeZone)
            resolvedPlaces[key] = place
            if let timeZone = placemark.timeZone {
                resolvedTimeZones[key] = timeZone
            }
            return place
        } catch {
            reportDeveloperWarning(
                title: "Geocoder Failed",
                message: "Apple reverse geocoding failed for \(city.localizedName()) at \(city.latitude), \(city.longitude): \(error.localizedDescription)"
            )
            return nil
        }
    }

    @available(iOS 26.0, *)
    private func resolvedPlaceWithMapKit(for city: City, location: CLLocation) async -> ResolvedPlace? {
        let request = MKReverseGeocodingRequest(location: location)
        request?.preferredLocale = preferredGeocodingLocale()

        do {
            guard let mapItems = try await request?.mapItems,
                  let mapItem = mapItems.first else {
                reportDeveloperWarning(
                    title: "MapKit Returned No Placemark",
                    message: "Apple reverse geocoding returned no map item for \(city.localizedName()) at \(city.latitude), \(city.longitude)."
                )
                return nil
            }

            let placemark = mapItem.placemark
            guard let resolvedName = resolvedCityName(from: placemark, originalCity: city) else {
                reportDeveloperWarning(
                    title: "MapKit Returned No City Name",
                    message: "Apple reverse geocoding returned only district/road-level names for \(city.latitude), \(city.longitude). Contact developer to correct this coordinate."
                )
                return nil
            }

            guard let resolvedCountry = placemark.country ?? placemark.isoCountryCode else {
                reportDeveloperWarning(
                    title: "MapKit Returned No Country",
                    message: "Apple reverse geocoding returned a placemark without a country for \(resolvedName) at \(city.latitude), \(city.longitude)."
                )
                return nil
            }

            return ResolvedPlace(name: resolvedName, country: resolvedCountry, timeZone: placemark.timeZone)
        } catch {
            reportDeveloperWarning(
                title: "MapKit Geocoder Failed",
                message: "Apple reverse geocoding failed for \(city.localizedName()) at \(city.latitude), \(city.longitude): \(error.localizedDescription)"
            )
            return nil
        }
    }

    private func resolvedCityName(from placemark: CLPlacemark, originalCity city: City) -> String? {
        if let locality = cleanGeocodedCityName(placemark.locality) {
            return locality
        }

        if let explicitName = cleanGeocodedCityName(city.name) {
            return explicitName
        }

        return nil
    }

    private func cleanGeocodedCityName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func resolvedCity(for city: City) async throws -> City {
        if !city.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !city.country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return city
        }

        guard let place = await resolvedPlace(for: city) else {
            throw WeatherServiceError.unresolvedPlace(city: city.localizedName())
        }
        return City(
            id: city.id,
            name: place.name,
            country: place.country,
            latitude: city.latitude,
            longitude: city.longitude,
            timeZoneIdentifier: city.timeZoneIdentifier
        )
    }

    private func resolvedTimeZone(for city: City) async -> TimeZone? {
        let key = coordinateKey(for: city)
        if let identifier = city.timeZoneIdentifier {
            guard let timeZone = TimeZone(identifier: identifier) else {
                reportDeveloperWarning(
                    title: "Invalid City Time Zone",
                    message: "The city \(city.localizedName()) has an invalid time zone identifier: \(identifier)."
                )
                return nil
            }
            resolvedTimeZones[key] = timeZone
            return timeZone
        }
        if let cachedTimeZone = resolvedTimeZones[key] {
            return cachedTimeZone
        }
        if let timeZone = await resolvedPlace(for: city)?.timeZone {
            return timeZone
        }
        return nil
    }

    private func resolvedTimeZoneOrThrow(for city: City) async throws -> TimeZone {
        if let timeZone = await resolvedTimeZone(for: city) {
            return timeZone
        }

        reportDeveloperWarning(
            title: "Time Zone Missing",
            message: "No Apple-provided time zone was available for \(city.localizedName()) at \(city.latitude), \(city.longitude)."
        )
        throw WeatherServiceError.undefinedTimeZone(city: city.localizedName())
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

private struct ResolvedPlace {
    let name: String
    let country: String
    let timeZone: TimeZone?
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

// MARK: - Cache Models

struct CachedCity: Codable {
    let id: UUID
    let name: String
    let country: String
    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String?
    
    init(from city: City) {
        self.id = city.id
        self.name = city.name
        self.country = city.country
        self.latitude = city.latitude
        self.longitude = city.longitude
        self.timeZoneIdentifier = city.timeZoneIdentifier
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
    }
    
    func toCity() -> City {
        return City(id: id, name: name, country: country, latitude: latitude, longitude: longitude, timeZoneIdentifier: timeZoneIdentifier)
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
        temperature = cityWeather.temperature
        symbolName = cityWeather.symbolName
        condition = AppWeatherCondition.fromWeatherSymbol(cityWeather.symbolName)
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
            condition: AppWeatherCondition.fromWeatherSymbol(symbolName),
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
        condition = AppWeatherCondition.fromWeatherSymbol(forecast.symbolName)
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
            condition: AppWeatherCondition.fromWeatherSymbol(symbolName),
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
        condition = AppWeatherCondition.fromWeatherSymbol(forecast.symbolName)
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
            condition: AppWeatherCondition.fromWeatherSymbol(symbolName),
            precipitationChance: precipitationChance,
            cloudCover: cloudCover,
            windSpeed: windSpeed,
            uvIndex: uvIndex,
            humidity: humidity,
            visibility: visibility
        )
    }
}
