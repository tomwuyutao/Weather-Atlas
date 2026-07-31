//
//  WeatherModels.swift
//  Weather
//
//  Purpose: Defines the city, city-weather, daily-forecast, and hourly-forecast
//  values shared by fetching, caching, ranking, maps, and views.
//

import Foundation

// MARK: - City

/// Persistable place identity used by lists before and after weather is fetched.
struct City: Identifiable, Hashable, Codable {
    /// Stable row and persistence identity.
    var id = UUID()
    /// User-facing place name, preserving the selected search result when applicable.
    var name: String
    /// Canonical country or region name returned by place resolution.
    var country: String
    /// Geographic latitude used by WeatherKit and MapKit.
    let latitude: Double
    /// Geographic longitude used by WeatherKit and MapKit.
    let longitude: Double
    /// Optional IANA or fixed-offset identifier retained with saved place data.
    let timeZoneIdentifier: String?
    /// Stable source identity when this city came from the bundled world-city
    /// dataset. Older, geocoded, and user-created records legitimately omit it.
    let catalogIdentifier: String?

    /// Creates a fully named saved city.
    init(
        id: UUID = UUID(),
        name: String,
        country: String = "",
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

    /// Creates an unresolved coordinate placeholder for later reverse geocoding.
    init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String? = nil,
        catalogIdentifier: String? = nil
    ) {
        self.init(
            id: id,
            name: "",
            country: "",
            latitude: latitude,
            longitude: longitude,
            timeZoneIdentifier: timeZoneIdentifier,
            catalogIdentifier: catalogIdentifier
        )
    }

    /// Decodes old saved cities while preserving compatibility with newer fields.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        catalogIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .catalogIdentifier
        )
    }

    /// Returns the display city name stored with the city record.
    /// Returns the best localized display name for this city-country pair.
    func localizedName(locale: Locale = .current) -> String {
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return String(format: "%.2f, %.2f", latitude, longitude)
    }
}

// MARK: - City Weather

/// Resolved city plus current and daily WeatherKit-backed forecast values.
struct CityWeather: Identifiable, Hashable {
    /// Canonical resolved place metadata.
    var city: City
    /// Stable identity inherited directly from the saved city.
    var id: UUID { city.id }
    /// Current temperature in Celsius.
    let temperature: Double
    /// WeatherKit's current-condition symbol, absent when the source omits it.
    let currentSymbolName: String?
    /// Normalized WeatherKit condition, with symbol classification retained as
    /// a compatibility fallback for older cached snapshots.
    let currentCondition: AppWeatherCondition?
    /// Available daily forecasts, whose horizons may legitimately differ by city.
    let dailyForecasts: [DailyForecast]
    /// Resolved timezone used for all city-local calendar comparisons.
    let timeZone: TimeZone

    /// Creates a resolved weather aggregate without synthesizing missing fields.
    init(
        // Retain the legacy label so existing cache restoration continues to
        // compile. Identity now always comes from `city.id`.
        id _: UUID? = nil,
        city: City,
        temperature: Double,
        currentSymbolName: String? = nil,
        currentCondition: AppWeatherCondition? = nil,
        dailyForecasts: [DailyForecast],
        timeZone: TimeZone
    ) {
        self.city = city
        self.temperature = temperature
        self.currentSymbolName = currentSymbolName
        self.currentCondition = currentCondition
            ?? currentSymbolName.flatMap(AppWeatherCondition.fromWeatherSymbol)
        self.dailyForecasts = dailyForecasts
        self.timeZone = timeZone
    }

    /// Copies fetched data while restoring a saved city's stable identity.
    func replacingID(_ id: UUID) -> CityWeather {
        var identifiedCity = city
        identifiedCity.id = id
        return CityWeather(
            city: identifiedCity,
            temperature: temperature,
            currentSymbolName: currentSymbolName,
            currentCondition: currentCondition,
            dailyForecasts: dailyForecasts,
            timeZone: timeZone
        )
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

// MARK: - Forecasts

/// One WeatherKit daily forecast and its associated hourly source values.
struct DailyForecast: Identifiable {
    /// WeatherKit date interpreted using the parent city's timezone.
    let date: Date
    /// Stable identity for this forecast day.
    var id: Date { date }
    /// Position in the returned forecast sequence.
    let dayOffset: Int
    /// Forecast daily low in Celsius.
    let dailyLow: Double
    /// Forecast daily high in Celsius.
    let dailyHigh: Double
    /// Raw WeatherKit condition symbol requiring explicit classification.
    let symbolName: String
    /// Normalized WeatherKit condition, falling back to the symbol only when
    /// restoring an older cache that predates native condition persistence.
    let condition: AppWeatherCondition?
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

    /// Recognized display symbol, or `nil` for an unknown source symbol.
    var weatherIcon: String? {
        condition?.displayIcon
    }

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

    /// Creates one daily forecast while keeping legacy symbol-backed fixtures
    /// and cache restoration source-compatible.
    init(
        date: Date,
        dayOffset: Int,
        dailyLow: Double,
        dailyHigh: Double,
        symbolName: String,
        condition: AppWeatherCondition? = nil,
        hourlyForecasts: [HourlyForecast],
        cloudCover: Double?,
        precipitationChance: Double?,
        uvIndex: Int?,
        sunrise: Date?,
        sunset: Date?
    ) {
        self.date = date
        self.dayOffset = dayOffset
        self.dailyLow = dailyLow
        self.dailyHigh = dailyHigh
        self.symbolName = symbolName
        self.condition = condition ?? AppWeatherCondition.fromWeatherSymbol(symbolName)
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
    /// Normalized WeatherKit condition, with symbol parsing retained only for
    /// older cache entries and fixtures.
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

    /// Creates an hourly record while keeping legacy symbol-only fixtures valid.
    init(
        date: Date,
        symbolName: String,
        condition: AppWeatherCondition? = nil,
        temperature: Double? = nil,
        apparentTemperature: Double? = nil,
        cloudCover: Double? = nil,
        precipitationChance: Double? = nil,
        uvIndex: Int? = nil,
        visibilityKilometers: Double? = nil
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
