//
//  WeatherCache.swift
//  Weather
//
//  Purpose: Persists per-list weather snapshots and validates cache freshness.
//

import Foundation

/// File-backed storage for potentially large encoded weather snapshots.
private enum WeatherSnapshotStorage {
    /// Reads one list snapshot, migrating from no file as `nil`.
    static func read(for listID: CityListID) throws -> Data? {
        let url = try fileURL(for: listID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    /// Atomically writes one encoded list snapshot to Application Support.
    static func write(_ data: Data, for listID: CityListID) throws {
        let url = try fileURL(for: listID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    /// Removes one list's snapshot file when it exists.
    static func remove(for listID: CityListID) {
        guard let url = try? fileURL(for: listID) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Returns a filesystem-safe URL derived from the list's stable identifier.
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
            // Store each list below the app's dedicated snapshot subdirectory.
            .appending(path: "WeatherSnapshots", directoryHint: .isDirectory)
            .appending(path: String(safeID) + ".json")
    }
}

// MARK: - Weather Cache

extension WeatherService {
    /// Encodes and writes a complete WeatherKit-derived snapshot for one list.
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

    /// Decodes, validates, and identity-reconciles one list's cached weather.
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
                // Cache migrations are recoverable: discard the incompatible
                // snapshot and let the normal fetch pipeline replace it.
                removeCache(for: listID)
                return nil
            }
            guard cachedWeatherDataLooksCurrent(cachedData, for: listID) else {
                // Stale coverage is not a user-facing error. A live fetch below
                // will surface its own error only if replacement also fails.
                removeCache(for: listID)
                return nil
            }
            return cachedData
        } catch {
            // Corrupt cache bytes are disposable. Keep this recovery silent;
            // WeatherService's subsequent live request owns persistent errors.
            removeCache(for: listID)
            return nil
        }
    }

    /// Checks city coverage, forecast dates, and timezones before accepting a cache.
    func cachedWeatherDataLooksCurrent(_ data: [CityWeather], for listID: CityListID, now: Date = Date()) -> Bool {
        guard !data.isEmpty, fetchDate(for: listID) != nil else { return false }
        return data.allSatisfy { cityWeather in
            let timeZoneIdentifier = cityWeather.timeZone.identifier
            let hasRawGMTTimeZone = timeZoneIdentifier == "UTC"
                || timeZoneIdentifier == "GMT"
                || timeZoneIdentifier.hasPrefix("GMT+")
                || timeZoneIdentifier.hasPrefix("GMT-")
            // A named city should use Core Location's civil timezone. A raw GMT
            // value here identifies an older cache entry or a failed lookup.
            guard !hasRawGMTTimeZone
                    || cityWeather.city.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return false
            }

            guard let todayForecast = cityWeather.forecastForLocalDate(containing: now) else {
                return false
            }
            guard !todayForecast.hourlyForecasts.isEmpty else { return false }

            // Polar day and polar night legitimately omit sunrise or sunset.
            // Cache freshness is about date/hour coverage, not whether every
            // optional solar input needed by the sunny-hours feature exists.

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

    /// Returns the in-memory or persisted fetch timestamp for one list.
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

    /// Whether a list's fetch timestamp is within the configured cache duration.
    func isWeatherDataFresh(for listID: CityListID, now: Date = Date()) -> Bool {
        guard let fetchDate = fetchDate(for: listID) else {
            return false
        }
        return now.timeIntervalSince(fetchDate) < weatherCacheDuration
    }

    /// Caches weather for the active list.
    func cacheData(_ data: [CityWeather], updateFetchDate: Bool = false) {
        saveCachedWeatherData(data, for: activeListID)
        guard updateFetchDate else { return }

        let fetchDate = Date()
        listFetchDates[activeListID.rawValue] = fetchDate
        // Preserve the legacy active-list timestamp key used by existing installs.
        UserDefaults.standard.set(
            fetchDate,
            forKey: "weatherCacheTimestamp_\(activeListID.rawValue)"
        )
        lastFetchDate = fetchDate
    }

    /// Caches weather for a specified list and optionally advances freshness time.
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

    /// Successful cities remain in memory for the current session, but a
    /// partial list is never persisted or labeled as a fresh snapshot.
    func invalidateIncompleteCache(for listID: CityListID) {
        removeCache(for: listID)
    }

    /// Removes one list's file-backed snapshot and all timestamp state.
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

/// Codable representation of a persisted source city.
struct CachedCity: Codable {
    /// Stable city identity.
    let id: UUID
    /// Canonical city name.
    let name: String
    /// Canonical country name.
    let country: String
    /// Geographic latitude.
    let latitude: Double
    /// Geographic longitude.
    let longitude: Double
    /// Optional resolved timezone identifier.
    let timeZoneIdentifier: String?

    /// Copies a domain city into its cache representation.
    init(from city: City) {
        self.id = city.id
        self.name = city.name
        self.country = city.country
        self.latitude = city.latitude
        self.longitude = city.longitude
        self.timeZoneIdentifier = city.timeZoneIdentifier
    }

    /// Decodes current and legacy city payloads.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        country = try container.decode(String.self, forKey: .country)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
    }

    /// Restores the domain city without inventing missing metadata.
    func toCity() -> City {
        City(id: id, name: name, country: country, latitude: latitude, longitude: longitude, timeZoneIdentifier: timeZoneIdentifier)
    }
}

/// Codable representation of a complete city weather snapshot.
struct CachedCityWeather: Codable {
    /// Stable city-weather identity.
    let id: UUID
    /// Cached source city metadata.
    let city: CachedCity
    /// Current temperature in Celsius.
    let temperature: Double
    /// Optional raw current-condition symbol.
    let currentSymbolName: String?
    /// Available encoded daily forecasts.
    let dailyForecasts: [CachedDailyForecast]
    /// Required resolved timezone identifier for forecast interpretation.
    let timeZoneIdentifier: String

    /// Copies a domain weather aggregate into its cache representation.
    init(from cityWeather: CityWeather) {
        id = cityWeather.id
        city = CachedCity(from: cityWeather.city)
        temperature = cityWeather.temperature
        currentSymbolName = cityWeather.currentSymbolName
        dailyForecasts = cityWeather.dailyForecasts.map { CachedDailyForecast(from: $0) }
        timeZoneIdentifier = cityWeather.timeZone.identifier
    }

    /// Restores a domain aggregate only when timezone and every day are valid.
    func toCityWeather() -> CityWeather? {
        let decodedCity = city.toCity()
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
        let forecasts = dailyForecasts.compactMap { $0.toDailyForecast(timeZone: timeZone) }
        guard !forecasts.isEmpty, forecasts.count == dailyForecasts.count else { return nil }

        return CityWeather(
            id: id,
            city: decodedCity,
            temperature: temperature,
            currentSymbolName: currentSymbolName,
            dailyForecasts: forecasts,
            timeZone: timeZone
        )
    }
}

/// Codable daily forecast supporting current and legacy cache formats.
struct CachedDailyForecast: Codable {
    /// Absolute forecast date in current cache versions.
    let date: Date?
    /// Legacy and current position in the forecast sequence.
    let dayOffset: Int
    /// Daily low in Celsius.
    let dailyLow: Double
    /// Daily high in Celsius.
    let dailyHigh: Double
    /// Raw WeatherKit condition symbol.
    let symbolName: String
    /// Encoded hourly source forecasts.
    let hourlyForecasts: [CachedHourlyForecast]
    /// Optional cloud-cover fraction.
    let cloudCover: Double?
    /// Optional precipitation probability.
    let precipitationChance: Double?
    /// Optional UV index.
    let uvIndex: Int?
    /// Optional sunrise instant.
    let sunrise: Date?
    /// Optional sunset instant.
    let sunset: Date?

    /// Copies a domain daily forecast into its cache representation.
    init(from forecast: DailyForecast) {
        date = forecast.date
        dayOffset = forecast.dayOffset
        dailyLow = forecast.dailyLow
        dailyHigh = forecast.dailyHigh
        symbolName = forecast.symbolName
        hourlyForecasts = forecast.hourlyForecasts.map { CachedHourlyForecast(from: $0) }
        cloudCover = forecast.cloudCover
        precipitationChance = forecast.precipitationChance
        uvIndex = forecast.uvIndex
        sunrise = forecast.sunrise
        sunset = forecast.sunset
    }

    /// Restores a daily forecast, reconstructing only supported legacy dates.
    func toDailyForecast(timeZone: TimeZone) -> DailyForecast? {
        // Exact calendar-date matching requires the original WeatherKit date.
        // Legacy cache entries without it are rejected so the app refetches.
        guard let restoredDate = date else { return nil }
        let restoredHours = hourlyForecasts.compactMap {
            $0.toHourlyForecast(on: restoredDate, timeZone: timeZone)
        }
        guard restoredHours.count == hourlyForecasts.count else { return nil }
        return DailyForecast(
            date: restoredDate,
            dayOffset: dayOffset,
            dailyLow: dailyLow,
            dailyHigh: dailyHigh,
            symbolName: symbolName,
            hourlyForecasts: restoredHours,
            cloudCover: cloudCover,
            precipitationChance: precipitationChance,
            uvIndex: uvIndex,
            sunrise: sunrise,
            sunset: sunset
        )
    }
}

/// Codable hourly forecast supporting old integer-hour snapshots.
struct CachedHourlyForecast: Codable {
    /// Absolute forecast instant in current cache versions.
    let date: Date?
    /// Legacy local integer hour when no absolute date was stored.
    let hour: Int?
    /// Raw WeatherKit condition symbol.
    let symbolName: String
    /// Optional hourly air temperature in Celsius.
    let temperature: Double?
    /// Optional hourly apparent temperature in Celsius.
    let apparentTemperature: Double?
    /// Optional hourly cloud-cover fraction.
    let cloudCover: Double?
    /// Optional hourly precipitation probability.
    let precipitationChance: Double?
    /// Optional hourly UV index.
    let uvIndex: Int?
    /// Optional horizontal visibility in kilometres.
    let visibilityKilometers: Double?

    /// Copies a domain hourly forecast into its cache representation.
    init(from forecast: HourlyForecast) {
        date = forecast.date
        hour = nil
        symbolName = forecast.symbolName
        temperature = forecast.temperature
        apparentTemperature = forecast.apparentTemperature
        cloudCover = forecast.cloudCover
        precipitationChance = forecast.precipitationChance
        uvIndex = forecast.uvIndex
        visibilityKilometers = forecast.visibilityKilometers
    }

    /// Restores an absolute hour using a supplied local day for legacy payloads.
    func toHourlyForecast(on day: Date, timeZone: TimeZone) -> HourlyForecast? {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        guard let restoredDate = date
            ?? hour.flatMap({ calendar.date(bySettingHour: $0, minute: 0, second: 0, of: day) }),
              // Chart View requires the complete hourly metric payload. Reject
              // older symbol-only snapshots so WeatherService performs one
              // fresh fetch instead of presenting misleading empty charts.
              let temperature,
              let apparentTemperature,
              let cloudCover,
              let precipitationChance,
              let uvIndex,
              let visibilityKilometers else {
            return nil
        }
        return HourlyForecast(
            date: restoredDate,
            symbolName: symbolName,
            temperature: temperature,
            apparentTemperature: apparentTemperature,
            cloudCover: cloudCover,
            precipitationChance: precipitationChance,
            uvIndex: uvIndex,
            visibilityKilometers: visibilityKilometers
        )
    }
}
