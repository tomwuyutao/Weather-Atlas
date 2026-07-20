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

    static func fromWeatherSymbol(_ symbolName: String) -> AppWeatherCondition? {
        guard let classification = WeatherSymbolClassification.resolve(symbolName) else {
            return nil
        }

        switch classification {
        case .clear: return .clear
        case .partlySunny: return .partlySunny
        case .partlyCloudy: return .partlyCloudy
        case .cloudy: return .cloudy
        case .rain: return .rain
        case .drizzle: return .drizzle
        case .snow: return .snow
        case .fog: return .fog
        case .wind: return .wind
        case .night: return .night
        }
    }

    var displayIcon: String {
        switch self {
        case .clear:
            return WeatherIconSymbol.clear
        case .partlySunny, .partlyCloudy:
            return WeatherIconSymbol.partlyCloudy
        case .cloudy:
            return WeatherIconSymbol.cloudy
        case .rain:
            return WeatherIconSymbol.rain
        case .drizzle:
            return WeatherIconSymbol.drizzle
        case .snow:
            return WeatherIconSymbol.snow
        case .fog:
            return WeatherIconSymbol.fog
        case .wind:
            return WeatherIconSymbol.wind
        case .night:
            return WeatherIconSymbol.night
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
        
        if weatherData.count == citiesToFetch.count {
            cacheData(weatherData, for: targetListID, updateFetchDate: true)
        } else {
            invalidateIncompleteCache(for: targetListID)
        }
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

    func convertWeatherKitData(weather: Weather, for city: City) async throws -> CityWeather {
        let timeZone = try await resolvedTimeZoneOrThrow(for: city)
        return convertWeatherKitData(weather: weather, for: city, timeZone: timeZone)
    }
    
    func convertWeatherKitData(weather: Weather, for city: City, timeZone: TimeZone) -> CityWeather {
        let currentTemp = weather.currentWeather.temperature.value
        let currentSymbolName = weather.currentWeather.symbolName
        
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
        
        return CityWeather(
            city: city,
            temperature: currentTemp,
            currentSymbolName: currentSymbolName,
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
        id = try container.decode(UUID.self, forKey: .id)
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
    /// WeatherKit's actual current-condition symbol. This remains optional so
    /// older caches decode without inventing a replacement condition.
    let currentSymbolName: String?
    let dailyForecasts: [DailyForecast]
    let timeZone: TimeZone

    init(
        id: UUID = UUID(),
        city: City,
        temperature: Double,
        currentSymbolName: String? = nil,
        dailyForecasts: [DailyForecast],
        timeZone: TimeZone
    ) {
        self.id = id
        self.city = city
        self.temperature = temperature
        self.currentSymbolName = currentSymbolName
        self.dailyForecasts = dailyForecasts
        self.timeZone = timeZone
    }

    func replacingID(_ id: UUID) -> CityWeather {
        CityWeather(
            id: id,
            city: city,
            temperature: temperature,
            currentSymbolName: currentSymbolName,
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
    
    /// Finds the forecast whose city-local calendar date matches the date shown
    /// by the app-wide selector. This keeps a label such as "July 19" literal
    /// across every city instead of silently substituting a neighboring date.
    func forecastIfAvailable(
        on selectedDate: Date,
        selectionCalendar: Calendar = .current
    ) -> DailyForecast? {
        let selectedComponents = selectionCalendar.dateComponents(
            [.year, .month, .day],
            from: selectedDate
        )
        var cityCalendar = selectionCalendar
        cityCalendar.timeZone = timeZone

        return dailyForecasts.first { forecast in
            let forecastComponents = cityCalendar.dateComponents(
                [.year, .month, .day],
                from: forecast.date
            )
            return forecastComponents.year == selectedComponents.year
                && forecastComponents.month == selectedComponents.month
                && forecastComponents.day == selectedComponents.day
        }
    }

    /// A boundary omission occurs when the literal selected date lies outside
    /// the real forecast range returned for this city. WeatherKit can return
    /// different range lengths for different cities, so no fixed day count is
    /// required here. A gap inside the returned range is still an error.
    func isForecastBoundaryOmission(
        on selectedDate: Date,
        selectionCalendar: Calendar = .current
    ) -> Bool {
        guard forecastIfAvailable(on: selectedDate, selectionCalendar: selectionCalendar) == nil else {
            return false
        }

        let selectedDay = selectionCalendar.startOfDay(for: selectedDate)
        let forecastDates = dailyForecasts.compactMap {
            selectionDate(for: $0, selectionCalendar: selectionCalendar)
        }
        guard let firstDate = forecastDates.min(), let lastDate = forecastDates.max() else {
            return false
        }
        return selectedDay < firstDate || selectedDay > lastDate
    }

    /// Finds the forecast for the city's local calendar day containing an
    /// absolute instant, used for city-specific current-day data such as widgets.
    func forecastForLocalDate(containing instant: Date) -> DailyForecast? {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return dailyForecasts.first { calendar.isDate($0.date, inSameDayAs: instant) }
    }

    /// Converts the forecast's city-local year, month, and day into the device
    /// calendar used by the app-wide selector. The resulting union can be wider
    /// than one city's range when a list crosses several time zones.
    func selectionDate(
        for forecast: DailyForecast,
        selectionCalendar: Calendar = .current
    ) -> Date? {
        var cityCalendar = selectionCalendar
        cityCalendar.timeZone = timeZone
        let components = cityCalendar.dateComponents(
            [.year, .month, .day],
            from: forecast.date
        )
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let date = selectionCalendar.date(
                from: DateComponents(year: year, month: month, day: day)
              ) else {
            return nil
        }
        return selectionCalendar.startOfDay(for: date)
    }

}

/// A city may have a shorter real WeatherKit range than its peers, or its local
/// range may shift at a time-zone boundary. Both are expected omissions when a
/// peer supplies the selected date. Empty forecasts and internal gaps remain
/// genuine missing-data errors.
func isExpectedForecastBoundaryOmission(
    for cityWeather: CityWeather,
    among cities: [CityWeather],
    on selectedDate: Date,
    selectionCalendar: Calendar = .current
) -> Bool {
    guard cities.contains(where: {
        $0.id != cityWeather.id
            && $0.forecastIfAvailable(
                on: selectedDate,
                selectionCalendar: selectionCalendar
            ) != nil
    }) else {
        return false
    }

    return cityWeather.isForecastBoundaryOmission(
        on: selectedDate,
        selectionCalendar: selectionCalendar
    )
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
    let uvIndex: Int?           // 0–11+
    let sunrise: Date?
    let sunset: Date?
    
    var weatherIcon: String? {
        AppWeatherCondition.fromWeatherSymbol(symbolName)?.displayIcon
    }
    
    var cloudCoverPercent: Int? {
        cloudCover.map { Int(($0 * 100).rounded()) }
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
