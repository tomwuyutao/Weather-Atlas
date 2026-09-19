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
  /// Optional because snapshots written before live Detail conditions were
  /// retained have no value for this field.
  let currentWeather: CachedCurrentWeather?
  /// Required resolved timezone identifier for forecast interpretation.
  let timeZoneIdentifier: String

  /// Copies a domain weather aggregate into its cache representation.
  @MainActor
  init(from cityWeather: CityWeather) {
    city = cityWeather.city
    dailyForecasts = cityWeather.dailyForecasts.map { CachedDailyForecast(from: $0) }
    currentWeather = cityWeather.currentWeather.map(CachedCurrentWeather.init)
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
    let forecasts = dailyForecasts.map { daily in
      DailyForecast(
        date: daily.date,
        dailyLow: daily.dailyLow,
        dailyHigh: daily.dailyHigh,
        symbolName: daily.symbolName,
        condition: daily.condition,
        hourlyForecasts: daily.hourlyForecasts.map { hourly in
          HourlyForecast(
            date: hourly.date,
            symbolName: hourly.symbolName,
            condition: hourly.condition,
            isDaylight: hourly.isDaylight,
            temperature: hourly.temperature,
            apparentTemperature: hourly.apparentTemperature,
            cloudCover: hourly.cloudCover,
            precipitationChance: hourly.precipitationChance,
            uvIndex: hourly.uvIndex,
            visibilityKilometers: hourly.visibilityKilometers
          )
        },
        cloudCover: daily.cloudCover,
        precipitationChance: daily.precipitationChance,
        uvIndex: daily.uvIndex,
        sunrise: daily.sunrise,
        sunset: daily.sunset
      )
    }
    guard !forecasts.isEmpty else { return nil }

    return CityWeather(
      city: city,
      dailyForecasts: forecasts,
      currentWeather: currentWeather.map {
        CurrentWeatherPresentation(
          date: $0.date,
          symbolName: $0.symbolName,
          condition: $0.condition
        )
      },
      timeZone: timeZone
    )
  }
}

/// Codable representation of WeatherKit's live observation.
nonisolated struct CachedCurrentWeather: Codable, Sendable {
  let date: Date
  let symbolName: String
  let condition: AppWeatherCondition?

  @MainActor
  init(from currentWeather: CurrentWeatherPresentation) {
    date = currentWeather.date
    symbolName = currentWeather.symbolName
    condition = currentWeather.condition
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
  /// Exact WeatherKit daily condition raw value. Its single-string Codable
  /// form keeps snapshots written by earlier app releases decodable.
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

}

// MARK: - Hourly Snapshot

/// Codable representation of one hourly forecast.
nonisolated struct CachedHourlyForecast: Codable, Sendable {
  /// Absolute WeatherKit forecast instant.
  let date: Date
  /// Raw WeatherKit condition symbol.
  let symbolName: String
  /// Exact WeatherKit hourly condition raw value. Its single-string Codable
  /// form keeps snapshots written by earlier app releases decodable.
  let condition: AppWeatherCondition?
  /// WeatherKit's daylight bit used to select the day's sunny-hour rows.
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

}
