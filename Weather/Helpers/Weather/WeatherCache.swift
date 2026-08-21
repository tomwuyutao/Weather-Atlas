//
//  WeatherCache.swift
//  Weather
//
//  Purpose: Defines Codable snapshots for the place-keyed forecast cache.
//  These types mirror the app's richer weather models using only Codable
//  Foundation values, which makes an on-disk cache safe to read after launch.
//

import Foundation

// MARK: - Cache Models

// Cache records are intentionally layered to mirror the live weather aggregate:
// city → daily forecasts → hourly forecasts. Keeping each level separate makes
// schema changes and validation failures easy to locate when reading the code.

// MARK: - City Snapshot

/// Codable representation of a complete city weather snapshot.
///
/// The cache is intentionally separate from `CityWeather`: the live model can
/// evolve around WeatherKit while this representation stays constrained to
/// values `JSONEncoder` can serialize predictably.
nonisolated struct CachedCityWeather: Codable, Sendable {
    /// Cached source city metadata.
    let city: City
    /// Available encoded daily forecasts.
    let dailyForecasts: [CachedDailyForecast]
    /// Required resolved timezone identifier for forecast interpretation.
    let timeZoneIdentifier: String

    /// Copies a domain weather aggregate into its cache representation.
    @MainActor
    init(from cityWeather: CityWeather) {
        city = cityWeather.city
        dailyForecasts = cityWeather.dailyForecasts.map { CachedDailyForecast(from: $0) }
        timeZoneIdentifier = cityWeather.timeZone.identifier
    }

    /// Restores a domain aggregate when its timezone and forecast collection can
    /// still be interpreted by the current cache schema.
    ///
    /// Malformed JSON or incompatible field types fail during document decoding;
    /// this conversion keeps WeatherKit's optional measurements unchanged.
    @MainActor
    func toCityWeather() -> CityWeather? {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
        let forecasts = dailyForecasts.map { $0.toDailyForecast() }
        guard !forecasts.isEmpty else { return nil }

        return CityWeather(
            city: city,
            dailyForecasts: forecasts,
            timeZone: timeZone
        )
    }
}

// MARK: - Daily Snapshot

/// Codable representation of one daily forecast.
/// Optional values stay optional in the cache because an omitted WeatherKit
/// measurement is materially different from a fabricated zero.
nonisolated struct CachedDailyForecast: Codable, Sendable {
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
    @MainActor
    init(from forecast: DailyForecast) {
        date = forecast.date
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

    /// Restores one daily forecast without dropping hours that contain nil
    /// optional metrics.
    @MainActor
    func toDailyForecast() -> DailyForecast {
        let restoredHours = hourlyForecasts.map { $0.toHourlyForecast() }
        return DailyForecast(
            date: date,
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

// MARK: - Hourly Snapshot

/// Codable representation of one hourly forecast.
nonisolated struct CachedHourlyForecast: Codable, Sendable {
    /// Absolute WeatherKit forecast instant.
    let date: Date
    /// Raw WeatherKit condition symbol.
    let symbolName: String
    /// Normalized native WeatherKit hourly condition.
    let condition: AppWeatherCondition?
    /// Source daylight bit required to distinguish polar day/night from missing
    /// sunrise or sunset timestamps.
    let isDaylight: Bool
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
    @MainActor
    init(from forecast: HourlyForecast) {
        date = forecast.date
        symbolName = forecast.symbolName
        condition = forecast.condition
        isDaylight = forecast.isDaylight
        temperature = forecast.temperature
        apparentTemperature = forecast.apparentTemperature
        cloudCover = forecast.cloudCover
        precipitationChance = forecast.precipitationChance
        uvIndex = forecast.uvIndex
        visibilityKilometers = forecast.visibilityKilometers
    }

    /// Restores one hourly forecast while preserving every optional metric.
    /// Missing UV, visibility, or temperature data must blank only that field;
    /// dropping the whole hour/day/city would hide the actual failure and discard
    /// unrelated valid source data.
    @MainActor
    func toHourlyForecast() -> HourlyForecast {
        HourlyForecast(
            date: date,
            symbolName: symbolName,
            condition: condition,
            isDaylight: isDaylight,
            temperature: temperature,
            apparentTemperature: apparentTemperature,
            cloudCover: cloudCover,
            precipitationChance: precipitationChance,
            uvIndex: uvIndex,
            visibilityKilometers: visibilityKilometers
        )
    }
}
