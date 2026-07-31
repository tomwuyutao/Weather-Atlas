//
//  WeatherCache.swift
//  Weather
//
//  Purpose: Defines Codable weather snapshots shared by legacy place import
//  and the place-keyed forecast cache.
//

import Foundation

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
    /// Optional bundled world-city source identity.
    let catalogIdentifier: String?

    /// Copies a domain city into its cache representation.
    init(from city: City) {
        self.id = city.id
        self.name = city.name
        self.country = city.country
        self.latitude = city.latitude
        self.longitude = city.longitude
        self.timeZoneIdentifier = city.timeZoneIdentifier
        self.catalogIdentifier = city.catalogIdentifier
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
        catalogIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .catalogIdentifier
        )
    }

    /// Restores the domain city without inventing missing metadata.
    func toCity() -> City {
        City(
            id: id,
            name: name,
            country: country,
            latitude: latitude,
            longitude: longitude,
            timeZoneIdentifier: timeZoneIdentifier,
            catalogIdentifier: catalogIdentifier
        )
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
    /// Normalized native WeatherKit condition when available.
    let currentCondition: AppWeatherCondition?
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
        currentCondition = cityWeather.currentCondition
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
            currentCondition: currentCondition,
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
    /// Normalized native WeatherKit daily condition.
    let condition: AppWeatherCondition?
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
        condition = forecast.condition
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
            condition: condition,
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
    /// Normalized native WeatherKit hourly condition.
    let condition: AppWeatherCondition?
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
        condition = forecast.condition
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
              // older symbol-only snapshots so PlaceWeatherStore performs one
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
            condition: condition,
            temperature: temperature,
            apparentTemperature: apparentTemperature,
            cloudCover: cloudCover,
            precipitationChance: precipitationChance,
            uvIndex: uvIndex,
            visibilityKilometers: visibilityKilometers
        )
    }
}
