//
//  WeatherModels.swift
//  Weather
//
//  Purpose: Defines the city, city-weather, daily-forecast, and hourly-forecast
//  values shared by fetching, caching, ranking, maps, and views.
//

import Foundation

// MARK: - City

/// Persistable place identity used before and after weather is fetched.
struct City: Identifiable, Hashable, Codable {
    /// Stable row and persistence identity.
    let id: UUID
    /// User-facing place name, preserving the selected search result when applicable.
    let name: String
    /// Canonical country or region name returned by place resolution.
    let country: String
    /// Geographic latitude used by WeatherKit and MapKit.
    let latitude: Double
    /// Geographic longitude used by WeatherKit and MapKit.
    let longitude: Double
    /// Optional IANA or fixed-offset identifier retained with saved place data.
    let timeZoneIdentifier: String?
    /// Stable source identity when this city came from a bundled city catalog.
    let catalogIdentifier: String?

    /// Creates a fully named saved city.
    init(
        id: UUID = UUID(),
        name: String,
        country: String,
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String? = nil,
        catalogIdentifier: String? = nil
    ) {
        self.id = id
        self.name = name
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.catalogIdentifier = catalogIdentifier
    }

    /// Returns the best available display name.
    var displayName: String {
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return String(format: "%.2f, %.2f", latitude, longitude)
    }
}

// MARK: - City Weather

/// Resolved city plus its daily WeatherKit-backed forecast values.
struct CityWeather: Identifiable, Hashable {
    /// Canonical resolved place metadata.
    let city: City
    /// Stable identity inherited directly from the saved city.
    var id: UUID { city.id }
    /// Available daily forecasts, whose horizons may legitimately differ by city.
    let dailyForecasts: [DailyForecast]
    /// Resolved timezone used for all city-local calendar comparisons.
    let timeZone: TimeZone

    /// Creates a resolved weather aggregate without synthesizing missing fields.
    init(
        city: City,
        dailyForecasts: [DailyForecast],
        timeZone: TimeZone
    ) {
        self.city = city
        self.dailyForecasts = dailyForecasts
        self.timeZone = timeZone
    }

    /// Compares stable identity because forecast arrays are replaceable snapshots.
    static func == (lhs: CityWeather, rhs: CityWeather) -> Bool {
        lhs.id == rhs.id
    }

    /// Hashes stable city identity to match equality semantics.
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

// MARK: - Forecasts

/// One WeatherKit daily forecast and its associated hourly source values.
struct DailyForecast: Identifiable {
    /// WeatherKit date interpreted using the parent city's timezone.
    let date: Date
    /// Stable identity for this forecast day.
    var id: Date { date }
    /// Forecast daily low in Celsius.
    let dailyLow: Double
    /// Forecast daily high in Celsius.
    let dailyHigh: Double
    /// Raw WeatherKit condition symbol requiring explicit classification.
    let symbolName: String
    /// Normalized WeatherKit condition, falling back to its symbol when needed.
    let condition: AppWeatherCondition?
    /// Whether WeatherKit's source condition was exactly `.clear`. This keeps
    /// the nearest-sunny feature stricter than the app's display grouping,
    /// which intentionally presents `.mostlyClear` with the clear icon.
    let isFullyClear: Bool
    /// Hourly forecasts associated with this local day.
    let hourlyForecasts: [HourlyForecast]
    /// Optional WeatherKit cloud fraction used by rankings.
    let cloudCover: Double?
    /// Optional WeatherKit precipitation probability.
    let precipitationChance: Double?
    /// Optional daily WeatherKit UV index.
    let uvIndex: Int?
    /// Optional city-local sunrise instant.
    let sunrise: Date?
    /// Optional city-local sunset instant.
    let sunset: Date?

    /// Rounded cloud-cover percentage when WeatherKit supplied the fraction.
    var cloudCoverPercent: Int? {
        cloudCover.map { Int(($0 * 100).rounded()) }
    }

    /// Daily visibility derived as the arithmetic mean of every available
    /// WeatherKit hourly visibility reading for this city-local day.
    var averageVisibilityKilometers: Double? {
        let values = hourlyForecasts.compactMap(\.visibilityKilometers)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Creates one daily WeatherKit forecast.
    init(
        date: Date,
        dailyLow: Double,
        dailyHigh: Double,
        symbolName: String,
        condition: AppWeatherCondition?,
        isFullyClear: Bool,
        hourlyForecasts: [HourlyForecast],
        cloudCover: Double?,
        precipitationChance: Double?,
        uvIndex: Int?,
        sunrise: Date?,
        sunset: Date?
    ) {
        self.date = date
        self.dailyLow = dailyLow
        self.dailyHigh = dailyHigh
        self.symbolName = symbolName
        self.condition = condition ?? AppWeatherCondition.fromWeatherSymbol(symbolName)
        self.isFullyClear = isFullyClear
        self.hourlyForecasts = hourlyForecasts
        self.cloudCover = cloudCover
        self.precipitationChance = precipitationChance
        self.uvIndex = uvIndex
        self.sunrise = sunrise
        self.sunset = sunset
    }
}

/// Hourly WeatherKit source record used by sunny-window and detail charts.
struct HourlyForecast: Identifiable {
    /// Absolute WeatherKit forecast instant.
    let date: Date
    /// Stable identity for this absolute forecast instant.
    var id: Date { date }
    /// Raw WeatherKit symbol requiring explicit classification.
    let symbolName: String
    /// Normalized WeatherKit condition, with symbol parsing as a fallback.
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

    /// Creates an hourly WeatherKit record.
    init(
        date: Date,
        symbolName: String,
        condition: AppWeatherCondition?,
        temperature: Double?,
        apparentTemperature: Double?,
        cloudCover: Double?,
        precipitationChance: Double?,
        uvIndex: Int?,
        visibilityKilometers: Double?
    ) {
        self.date = date
        self.symbolName = symbolName
        self.condition = condition ?? AppWeatherCondition.fromWeatherSymbol(symbolName)
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.cloudCover = cloudCover
        self.precipitationChance = precipitationChance
        self.uvIndex = uvIndex
        self.visibilityKilometers = visibilityKilometers
    }

    /// Returns this instant's integer clock hour in a supplied city timezone.
    func hour(in timeZone: TimeZone) -> Int {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar.component(.hour, from: date)
    }
}
