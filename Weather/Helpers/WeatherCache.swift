//
//  WeatherCache.swift
//  Weather
//
//  Purpose: Defines Codable snapshots for the place-keyed forecast cache.
//

import Foundation

// MARK: - Cache Models

/// Codable representation of a complete city weather snapshot.
struct CachedCityWeather: Codable {
    /// Cached source city metadata.
    let city: City
    /// Available encoded daily forecasts.
    let dailyForecasts: [CachedDailyForecast]
    /// Required resolved timezone identifier for forecast interpretation.
    let timeZoneIdentifier: String

    /// Copies a domain weather aggregate into its cache representation.
    init(from cityWeather: CityWeather) {
        city = cityWeather.city
        dailyForecasts = cityWeather.dailyForecasts.map { CachedDailyForecast(from: $0) }
        timeZoneIdentifier = cityWeather.timeZone.identifier
    }

    /// Restores a domain aggregate only when timezone and every day are valid.
    func toCityWeather() -> CityWeather? {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
        let forecasts = dailyForecasts.compactMap { $0.toDailyForecast() }
        guard !forecasts.isEmpty, forecasts.count == dailyForecasts.count else { return nil }

        return CityWeather(
            city: city,
            dailyForecasts: forecasts,
            timeZone: timeZone
        )
    }
}

/// Codable representation of one daily forecast.
struct CachedDailyForecast: Codable {
    /// Absolute WeatherKit forecast date.
    let date: Date
    /// Daily low in Celsius.
    let dailyLow: Double
    /// Daily high in Celsius.
    let dailyHigh: Double
    /// Raw WeatherKit condition symbol.
    let symbolName: String
    /// Normalized native WeatherKit daily condition.
    let condition: AppWeatherCondition?
    /// Exact clear-state provenance used by strict nearest-sunny matching.
    let isFullyClear: Bool
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
        dailyLow = forecast.dailyLow
        dailyHigh = forecast.dailyHigh
        symbolName = forecast.symbolName
        condition = forecast.condition
        isFullyClear = forecast.isFullyClear
        hourlyForecasts = forecast.hourlyForecasts.map { CachedHourlyForecast(from: $0) }
        cloudCover = forecast.cloudCover
        precipitationChance = forecast.precipitationChance
        uvIndex = forecast.uvIndex
        sunrise = forecast.sunrise
        sunset = forecast.sunset
    }

    /// Restores a complete daily forecast.
    func toDailyForecast() -> DailyForecast? {
        let restoredHours = hourlyForecasts.compactMap { $0.toHourlyForecast() }
        guard restoredHours.count == hourlyForecasts.count else { return nil }
        return DailyForecast(
            date: date,
            dailyLow: dailyLow,
            dailyHigh: dailyHigh,
            symbolName: symbolName,
            condition: condition,
            isFullyClear: isFullyClear,
            hourlyForecasts: restoredHours,
            cloudCover: cloudCover,
            precipitationChance: precipitationChance,
            uvIndex: uvIndex,
            sunrise: sunrise,
            sunset: sunset
        )
    }
}

/// Codable representation of one hourly forecast.
struct CachedHourlyForecast: Codable {
    /// Absolute WeatherKit forecast instant.
    let date: Date
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
        symbolName = forecast.symbolName
        condition = forecast.condition
        temperature = forecast.temperature
        apparentTemperature = forecast.apparentTemperature
        cloudCover = forecast.cloudCover
        precipitationChance = forecast.precipitationChance
        uvIndex = forecast.uvIndex
        visibilityKilometers = forecast.visibilityKilometers
    }

    /// Restores a complete hourly forecast.
    func toHourlyForecast() -> HourlyForecast? {
        guard let temperature,
              let apparentTemperature,
              let cloudCover,
              let precipitationChance,
              let uvIndex,
              let visibilityKilometers else {
            return nil
        }
        return HourlyForecast(
            date: date,
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
