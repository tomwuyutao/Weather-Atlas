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

/// Service failures that must surface instead of producing fabricated weather.
enum WeatherServiceError: LocalizedError {
    case undefinedTimeZone(city: String)
    case unresolvedPlace(city: String)

    /// Diagnostic description forwarded to the native warning pipeline.
    var errorDescription: String? {
        switch self {
        case .undefinedTimeZone(let city):
            return "Timezone undefined for \(city)"
        case .unresolvedPlace(let city):
            return "Place unresolved for \(city)"
        }
    }
}

/// Source of truth for lists, WeatherKit fetching, and weather caches.
@Observable
@MainActor
class WeatherService {
    // MARK: Observable State

    /// Persisted list catalog in user-defined order.
    var availableLists: [CityListID] = CityListID.allLists
    /// Loaded weather snapshots indexed by stable list raw value.
    var weatherDataByListID: [String: [CityWeather]] = [:]
    /// Read-write adapter exposing the active list's loaded snapshot.
    var cityWeatherData: [CityWeather] {
        get { weatherDataByListID[activeListID.rawValue] ?? [] }
        set { weatherDataByListID[activeListID.rawValue] = newValue }
    }
    /// Whether the active list currently has an in-flight fetch.
    var isLoading = false
    /// Fraction of active-list city fetch attempts completed.
    var loadingProgress: Double = 0
    /// Most recent user-presentable service failure message.
    var errorMessage: String?
    /// Fetch date associated with the active list.
    var lastFetchDate: Date?
    /// WeatherKit legal attribution loaded for presentation.
    var weatherAttribution: WeatherAttribution?
    /// Stable identity of the currently selected list.
    var activeListID: CityListID = .europe
    /// Cancellable task owning the active-list fetch pipeline.
    @ObservationIgnored private var activeFetchTask: Task<Void, Never>?
    /// Duration for which successful snapshots remain fresh.
    let weatherCacheDuration: TimeInterval = 30 * 60
    /// In-memory per-list fetch timestamps.
    var listFetchDates: [String: Date] = [:]
    /// In-process timezone cache keyed by rounded coordinates.
    var resolvedTimeZones: [String: TimeZone] = [:]
    /// In-process place cache keyed by rounded coordinates.
    var resolvedPlaces: [String: ResolvedPlace] = [:]
    
    // MARK: WeatherKit and Persistence Keys

    /// Shared Apple WeatherKit client.
    let weatherKitService = WeatherKit.WeatherService.shared

    /// Preference key containing the active list raw value.
    static let activeListKey = "activeListID"
    
    // MARK: Initialization

    /// Restores list identity and any valid cache needed for initial rendering.
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

    /// Reloads metadata and reconciles the active identity after mutations.
    func reloadAvailableLists() {
        availableLists = CityListID.allLists
        if let refreshedActiveList = availableLists.first(where: { $0.rawValue == activeListID.rawValue }) {
            activeListID = refreshedActiveList
        }
    }

    // MARK: Weather Attribution

    // MARK: Active-List Fetching

    /// Cancels any prior active-list fetch and starts a replacement pipeline.
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

    /// Loads cache or fetches every configured city while guarding list identity.
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

    /// Invalidates the active cache and forces a complete replacement fetch.
    func refreshWeather() async {
        // Remove the active list's weather snapshot and timestamp before refetching.
        removeCache(for: activeListID)
        await fetchWeatherForAllCities(forceRefresh: true)
    }
    
    /// Activates a list, restores any snapshot, and fetches when needed.
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

    /// Activates a list and fetches one requested city before its remaining peers.
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

        // Move the requested city first without duplicating coordinate identity.
        let savedCities = loadSavedCities(for: listID) ?? listID.defaultCities
        let citiesToFetch: [City]
        if let priorityIndex = savedCities.firstIndex(where: { citiesMatch($0, priorityCity) }) {
            var reorderedCities = savedCities
            reorderedCities.insert(reorderedCities.remove(at: priorityIndex), at: 0)
            citiesToFetch = reorderedCities
        } else {
            citiesToFetch = [priorityCity] + savedCities.filter { !citiesMatch($0, priorityCity) }
        }
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

    // MARK: City Identity

    /// Matches canonical names and coordinates within five kilometers.
    func citiesMatch(_ lhs: City, _ rhs: City) -> Bool {
        // Keep spelling, case, and diacritics significant while normalizing invisible
        // whitespace and canonically equivalent Unicode encodings.
        guard lhs.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            == rhs.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .precomposedStringWithCanonicalMapping else {
            return false
        }
        let lhsLocation = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
        let rhsLocation = CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
        return lhsLocation.distance(from: rhsLocation) < 5_000
    }

    /// Completes the background remainder of a priority-first list fetch.
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

    /// Returns the currently loaded snapshot for a stable list identity.
    func weatherData(for listID: CityListID) -> [CityWeather] {
        return weatherDataByListID[listID.rawValue] ?? []
    }

    /// Logs a service error and converts it into localized native-alert copy.
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

    /// Sends an invariant or persistence warning to the shared alert queue.
    func reportDeveloperWarning(title: String, message: String) {
        DeveloperWarningCenter.show(title: title, message: message)
    }

    // MARK: WeatherKit Conversion

    /// Resolves timezone before converting WeatherKit data for a city.
    func convertWeatherKitData(weather: Weather, for city: City) async throws -> CityWeather {
        let timeZone = try await resolvedTimeZoneOrThrow(for: city)
        return convertWeatherKitData(weather: weather, for: city, timeZone: timeZone)
    }
    
    /// Converts WeatherKit source values without filling omitted optional fields.
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
    
    /// Selects hourly records whose absolute instants fall in one city-local day.
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
            HourlyForecast(
                date: hourWeather.date,
                symbolName: hourWeather.symbolName,
                temperature: hourWeather.temperature.value,
                apparentTemperature: hourWeather.apparentTemperature.value,
                cloudCover: hourWeather.cloudCover,
                precipitationChance: hourWeather.precipitationChance,
                uvIndex: hourWeather.uvIndex.value,
                visibilityKilometers: hourWeather.visibility.converted(to: .kilometers).value
            )
        }
    }
    // MARK: Per-City Fetching and Replacement

    /// Resolves and fetches one city, reporting failure and returning `nil`.
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

    /// Refetches one city and replaces its matching entries across loaded lists.
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

    /// Replaces one loaded city snapshot and immediately persists that list cache.
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
