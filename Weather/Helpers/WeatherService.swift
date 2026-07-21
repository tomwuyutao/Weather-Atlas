//
//  WeatherService.swift
//  Weather
//
//  Purpose: Fetches WeatherKit data, converts it into app models, and manages
//  the in-memory weather state for every saved list.
//

import Foundation
import Observation
import WeatherKit
import CoreLocation

// MARK: - Service Errors

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

@Observable
@MainActor
class WeatherService {
    // MARK: Observable State

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
    
    // MARK: WeatherKit and Persistence Keys

    let weatherKitService = WeatherKit.WeatherService.shared
    
    static let activeListKey = "activeListID"
    
    // Per-list persistence keys
    var cacheTimestampKey: String { "weatherCacheTimestamp_\(activeListID.rawValue)" }
    var citiesListKey: String { "savedCitiesList_\(activeListID.rawValue)" }
    
    // MARK: Initialization

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

    // MARK: List State

    func reloadAvailableLists() {
        availableLists = CityListID.allLists
        if let refreshedActiveList = availableLists.first(where: { $0.rawValue == activeListID.rawValue }) {
            activeListID = refreshedActiveList
        }
    }

    // MARK: Weather Attribution

    var weatherAttributionMarkText: String {
        " Weather"
    }

    var weatherLegalPageURL: URL? {
        weatherAttribution?.legalPageURL
    }

    func loadWeatherAttributionIfNeeded() async {
        guard weatherAttribution == nil else { return }
        do {
            weatherAttribution = try await weatherKitService.attribution
        } catch { }
    }
    
    // MARK: Active-List Fetching

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
                let weather = try await weatherKitService.weather(for: location)
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
        
        if weatherData.count == citiesToFetch.count {
            cacheData(weatherData, for: targetListID, updateFetchDate: true)
        } else {
            invalidateIncompleteCache(for: targetListID)
        }
    }
    
    // MARK: Refreshing and List Switching

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
        errorMessage = nil
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

    // MARK: Prioritized Fetch Support

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

    // MARK: City Identity

    func citiesMatch(_ lhs: City, _ rhs: City) -> Bool {
        guard cityIdentityName(lhs.name) == cityIdentityName(rhs.name) else {
            return false
        }
        let lhsLocation = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
        let rhsLocation = CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
        return lhsLocation.distance(from: rhsLocation) < 5_000
    }

    /// City identity keeps spelling, letter case, and diacritics significant.
    /// Trimming and canonical composition prevent invisible whitespace and
    /// equivalent Unicode encodings from producing accidental mismatches.
    private func cityIdentityName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
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
        weatherDataByListID[listID.rawValue] = weatherData
        if weatherData.count == totalCount {
            cacheData(weatherData, for: listID, updateFetchDate: true)
        } else {
            invalidateIncompleteCache(for: listID)
        }
    }
    
    // MARK: Data Access and Error Reporting

    func weatherData(for listID: CityListID) -> [CityWeather] {
        return weatherDataByListID[listID.rawValue] ?? []
    }

    func report(_ error: Error) {
        #if DEBUG
        print("[WeatherService] \(error.localizedDescription)")
        #endif

        let locale = Locale(identifier: UserDefaults.standard.string(forKey: "appLanguage") ?? Locale.autoupdatingCurrent.identifier)
        if let serviceError = error as? WeatherServiceError {
            switch serviceError {
            case .undefinedTimeZone(let city):
                errorMessage = weatherDataIssueMessage(
                    .missingTimeZone,
                    cityName: city,
                    locale: locale
                )
            case .unresolvedPlace(let city):
                errorMessage = String(
                    format: localizedString("Missing place data for %@.", locale: locale),
                    locale: locale,
                    city
                )
            }
        } else {
            errorMessage = String(
                format: localizedString("Weather data could not be loaded: %@", locale: locale),
                locale: locale,
                error.localizedDescription
            )
        }
    }

    func reportDeveloperWarning(title: String, message: String) {
        DeveloperWarningCenter.show(title: title, message: message)
    }

    // MARK: WeatherKit Conversion

    func convertWeatherKitData(weather: Weather, for city: City) async throws -> CityWeather {
        let timeZone = try await resolvedTimeZoneOrThrow(for: city)
        return convertWeatherKitData(weather: weather, for: city, timeZone: timeZone)
    }
    
    func convertWeatherKitData(weather: Weather, for city: City, timeZone: TimeZone) -> CityWeather {
        let currentTemp = weather.currentWeather.temperature.value

        let dailyForecasts = weather.dailyForecast.forecast.enumerated().map { (index, day) -> DailyForecast in
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
                uvIndex: day.uvIndex.value,
                sunrise: day.sun.sunrise,
                sunset: day.sun.sunset
            )
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let daytimeSymbolName = dailyForecasts.first(where: {
            calendar.isDate($0.date, inSameDayAs: Date())
        })?.symbolName
        
        return CityWeather(
            city: city,
            temperature: currentTemp,
            currentSymbolName: daytimeSymbolName,
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
    // MARK: Per-City Fetching and Replacement

    func fetchWeatherForCity(_ city: City) async -> CityWeather? {
        do {
            // Fetch weather for the city
            let resolvedCity = try await resolvedCity(for: city)
            let location = CLLocation(latitude: resolvedCity.latitude, longitude: resolvedCity.longitude)
            let weather = try await weatherKitService.weather(for: location)
            
            // Convert to our model
            let cityWeather = try await convertWeatherKitData(weather: weather, for: resolvedCity)
            
            return cityWeather
        } catch {
            report(error)
            return nil
        }
    }

    func refreshWeatherForCity(_ cityWeather: CityWeather) async -> CityWeather? {
        errorMessage = nil
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
