//
//  WeatherCache.swift
//  Weather
//
//  Purpose: Persists per-list weather snapshots and validates cache freshness.
//

import Foundation

private enum WeatherSnapshotStorage {
    private static let directoryName = "WeatherSnapshots"

    static func read(for listID: CityListID) throws -> Data? {
        let url = try fileURL(for: listID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    static func write(_ data: Data, for listID: CityListID) throws {
        let url = try fileURL(for: listID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    static func remove(for listID: CityListID) {
        guard let url = try? fileURL(for: listID) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func fileURL(for listID: CityListID) throws -> URL {
        let caches = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let safeID = listID.rawValue.map { character in
            character.isLetter || character.isNumber || character == "-" ? character : "_"
        }
        return caches
            .appending(path: directoryName, directoryHint: .isDirectory)
            .appending(path: String(safeID) + ".json")
    }
}

// MARK: - Weather Cache

extension WeatherService {
    func saveCachedWeatherData(_ data: [CityWeather], for listID: CityListID) {
        do {
            let cached = data.map { CachedCityWeather(from: $0) }
            let encoded = try JSONEncoder().encode(cached)
            try WeatherSnapshotStorage.write(encoded, for: listID)
            UserDefaults.standard.removeObject(forKey: "cachedWeatherData_\(listID.rawValue)")
        } catch {
            WeatherSnapshotStorage.remove(for: listID)
        }
    }

    func loadCachedWeatherData(for listID: CityListID) -> [CityWeather]? {
        let key = "cachedWeatherData_\(listID.rawValue)"
        do {
            let data: Data
            if let storedData = try WeatherSnapshotStorage.read(for: listID) {
                data = storedData
            } else if let legacyData = UserDefaults.standard.data(forKey: key) {
                data = legacyData
                try WeatherSnapshotStorage.write(legacyData, for: listID)
                UserDefaults.standard.removeObject(forKey: key)
            } else {
                return nil
            }
            let decodedCache = try JSONDecoder().decode([CachedCityWeather].self, from: data)
            let cachedData = decodedCache.compactMap { $0.toCityWeather() }
            if cachedData.count != decodedCache.count {
                reportDeveloperWarning(
                    title: "Cached Weather Invalid",
                    message: "Some cached weather entries for \(listID.rawValue) could not be restored and the cache was removed."
                )
                removeCache(for: listID)
                return nil
            }
            guard cachedWeatherDataLooksCurrent(cachedData, for: listID) else {
                reportDeveloperWarning(
                    title: "Cached Weather Stale",
                    message: "The cached weather data for \(listID.rawValue) was not current enough to reuse and was removed."
                )
                removeCache(for: listID)
                return nil
            }
            return cachedData
        } catch {
            reportDeveloperWarning(
                title: "Cached Weather Corrupt",
                message: "The cached weather data for \(listID.rawValue) could not be decoded and was removed."
            )
            removeCache(for: listID)
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
                  let firstHour = todayForecast.hourlyForecasts.map({ $0.hour(in: cityWeather.timeZone) }).min() else {
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

    func clearCache() {
        removeCache(for: activeListID)
    }

    func removeCache(for listID: CityListID) {
        WeatherSnapshotStorage.remove(for: listID)
        UserDefaults.standard.removeObject(forKey: "cachedWeatherData_\(listID.rawValue)")
        UserDefaults.standard.removeObject(forKey: "weatherCacheTimestamp_\(listID.rawValue)")
        listFetchDates[listID.rawValue] = nil
        if listID.rawValue == activeListID.rawValue {
            lastFetchDate = nil
        }
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
        City(id: id, name: name, country: country, latitude: latitude, longitude: longitude, timeZoneIdentifier: timeZoneIdentifier)
    }
}

struct CachedCityWeather: Codable {
    let id: UUID
    let city: CachedCity
    let temperature: Double
    let dailyForecasts: [CachedDailyForecast]
    let timeZoneIdentifier: String

    init(from cityWeather: CityWeather) {
        id = cityWeather.id
        city = CachedCity(from: cityWeather.city)
        temperature = cityWeather.temperature
        dailyForecasts = cityWeather.dailyForecasts.map { CachedDailyForecast(from: $0) }
        timeZoneIdentifier = cityWeather.timeZone.identifier
    }

    func toCityWeather() -> CityWeather? {
        let decodedCity = city.toCity()
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
        let forecasts = dailyForecasts.map { $0.toDailyForecast(timeZone: timeZone) }
        guard !forecasts.isEmpty else { return nil }

        return CityWeather(
            id: id,
            city: decodedCity,
            temperature: temperature,
            dailyForecasts: forecasts,
            timeZone: timeZone
        )
    }
}

struct CachedDailyForecast: Codable {
    let date: Date?
    let dayOffset: Int
    let dailyLow: Double
    let dailyHigh: Double
    let symbolName: String
    let hourlyForecasts: [CachedHourlyForecast]
    let cloudCover: Double?
    let precipitationChance: Double?
    let windSpeed: Double?
    let uvIndex: Int?
    let sunrise: Date?
    let sunset: Date?

    init(from forecast: DailyForecast) {
        date = forecast.date
        dayOffset = forecast.dayOffset
        dailyLow = forecast.dailyLow
        dailyHigh = forecast.dailyHigh
        symbolName = forecast.symbolName
        hourlyForecasts = forecast.hourlyForecasts.map { CachedHourlyForecast(from: $0) }
        cloudCover = forecast.cloudCover
        precipitationChance = forecast.precipitationChance
        windSpeed = forecast.windSpeed
        uvIndex = forecast.uvIndex
        sunrise = forecast.sunrise
        sunset = forecast.sunset
    }

    func toDailyForecast(timeZone: TimeZone) -> DailyForecast {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let restoredDate = date
            ?? sunrise
            ?? sunset
            ?? calendar.date(byAdding: .day, value: dayOffset, to: Date())
            ?? Date()
        return DailyForecast(
            date: restoredDate,
            dayOffset: dayOffset,
            dailyLow: dailyLow,
            dailyHigh: dailyHigh,
            symbolName: symbolName,
            hourlyForecasts: hourlyForecasts.map { $0.toHourlyForecast(on: restoredDate, timeZone: timeZone) },
            cloudCover: cloudCover,
            precipitationChance: precipitationChance,
            windSpeed: windSpeed,
            uvIndex: uvIndex,
            sunrise: sunrise,
            sunset: sunset
        )
    }
}

struct CachedHourlyForecast: Codable {
    let date: Date?
    let hour: Int?
    let symbolName: String

    init(from forecast: HourlyForecast) {
        date = forecast.date
        hour = nil
        symbolName = forecast.symbolName
    }

    func toHourlyForecast(on day: Date, timeZone: TimeZone) -> HourlyForecast {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let restoredDate = date
            ?? hour.flatMap { calendar.date(bySettingHour: $0, minute: 0, second: 0, of: day) }
            ?? day
        return HourlyForecast(
            date: restoredDate,
            symbolName: symbolName
        )
    }
}
