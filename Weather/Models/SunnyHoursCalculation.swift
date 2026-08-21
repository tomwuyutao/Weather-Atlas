//
//  SunnyHoursCalculation.swift
//  Weather
//
//  Purpose: Counts available city-local daylight hours that are Clear or
//  Partly Sunny, without turning missing hourly data into zero hours.
//

import Foundation

/// Shared sunny-hours calculations for cards, status copy, and rankings.
enum SunnyHoursCalculation {
    struct SunnyHoursData {
        let hours: [HourlyForecast]
        let bounds: SunnyHoursChartBounds
        /// The actual astronomical events remain available to live status copy;
        /// chart bounds are rounded to whole hours and must not decide whether
        /// the sun is currently above the horizon.
        let daylightRegime: DaylightRegime
    }

    enum DailySunStatus: Equatable {
        case sunnyForHours(Double)
        case sunOutNow
        case sunOutIn(Date)
        case noSunToday
        case noMoreSunToday
        case noSunOnSelectedDay
    }

    /// Returns the forecast hours that intersect the selected city’s daylight.
    /// An empty or structurally incomplete source remains an issue, never a
    /// plausible `0 h` result.
    static func sunnyHoursData(
        for forecast: DailyForecast,
        timeZone: TimeZone,
        referenceDate: Date = .now
    ) -> Result<SunnyHoursData, WeatherDataIssue> {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let sourceResult = SunnyHoursSourceAnalysis.availableDaylightHours(
            on: forecast.date,
            sunrise: forecast.sunrise,
            sunset: forecast.sunset,
            from: forecast.hourlyForecasts,
            calendar: calendar,
            referenceDate: referenceDate,
            dateOf: \.date,
            isDaylight: \.isDaylight
        )
        guard case .success(let sourceData) = sourceResult else {
            if case .failure(let issue) = sourceResult {
                return .failure(issue.weatherDataIssue(at: forecast.date))
            }
            return .failure(.missingHourlyData(at: forecast.date))
        }
        guard let bounds = SunnyHoursChartBounds.daylight(
            regime: sourceData.regime,
            timeZone: timeZone
        ) else {
            return .failure(
                .invalidValue("Unable to derive daylight chart bounds", at: forecast.date)
            )
        }
        if let unknownHour = sourceData.hours.first(where: { $0.condition == nil }) {
            return .failure(
                .unknownWeatherSymbol(unknownHour.symbolName, at: unknownHour.date)
            )
        }
        return .success(
            SunnyHoursData(
                hours: sourceData.hours,
                bounds: bounds,
                daylightRegime: sourceData.regime
            )
        )
    }

    static func sunnyHourCount(in data: SunnyHoursData) -> Double {
        Double(data.hours.count(where: { $0.condition?.isSunnyOrPartlySunny == true }))
    }

    /// Finds the first later city-local forecast day with at least one clear or
    /// partly sunny daylight hour. A gap or invalid intervening day stops the
    /// search so callers never describe a merely later forecast as the next
    /// sunny day when an earlier day could not be assessed.
    static func nextSunnyForecastDate(
        after forecast: DailyForecast,
        in forecasts: [DailyForecast],
        timeZone: TimeZone,
        selectionCalendar: Calendar,
        referenceDate: Date = .now
    ) -> Date? {
        var cityCalendar = selectionCalendar
        cityCalendar.timeZone = timeZone
        let selectedDay = cityCalendar.startOfDay(for: forecast.date)
        var precedingDay = selectedDay
        let laterForecasts = forecasts
            .filter {
                cityCalendar.startOfDay(for: $0.date) > selectedDay
            }
            .sorted { $0.date < $1.date }

        for laterForecast in laterForecasts {
            guard let expectedDay = cityCalendar.date(
                byAdding: .day,
                value: 1,
                to: precedingDay
            ), cityCalendar.isDate(
                laterForecast.date,
                inSameDayAs: expectedDay
            ), case .success(let data) = sunnyHoursData(
                for: laterForecast,
                timeZone: timeZone,
                referenceDate: referenceDate
            ) else {
                return nil
            }

            if sunnyHourCount(in: data) > 0 {
                return laterForecast.date
            }
            precedingDay = expectedDay
        }

        return nil
    }

    static func dailySunStatus(
        in data: SunnyHoursData,
        selectedDate: Date,
        timeZone: TimeZone,
        selectionCalendar: Calendar,
        referenceDate: Date = .now
    ) -> DailySunStatus {
        var cityCalendar = selectionCalendar
        cityCalendar.timeZone = timeZone
        let sunnyHours = data.hours.filter {
            $0.condition?.isSunnyOrPartlySunny == true
        }

        guard cityCalendar.isDateInToday(selectedDate) else {
            return sunnyHours.isEmpty
                ? .noSunOnSelectedDay
                : .sunnyForHours(sunnyHourCount(in: data))
        }

        // The last chartable hourly record can overlap a small part of the
        // final daylight hour, so it remains in `data.hours` after the real
        // sunset instant. Status copy must use that exact astronomical instant,
        // not the rounded hourly chart boundary or the last cached condition.
        if sunsetHasPassed(in: data.daylightRegime, at: referenceDate) {
            return sunnyHours.isEmpty ? .noSunToday : .noMoreSunToday
        }
        guard !sunnyHours.isEmpty else { return .noSunToday }

        // The first hourly cell can begin before the real sunrise while still
        // overlapping it. Before sunrise, its favorable condition describes
        // the upcoming daylight interval—not the current dark sky—so report
        // the exact astronomical event rather than "Sun out now."
        if let sunrise = upcomingSunrise(
            in: data.daylightRegime,
            after: referenceDate
        ) {
            if sunnyHours.contains(where: { hourlyInterval($0, contains: sunrise) }) {
                return .sunOutIn(sunrise)
            }
            if let nextHour = sunnyHours.first(where: { $0.date > referenceDate }) {
                return .sunOutIn(nextHour.date)
            }
            return .noSunToday
        }

        if let currentHour = data.hours.last(where: { $0.date <= referenceDate }),
           currentHour.condition?.isSunnyOrPartlySunny == true {
            return .sunOutNow
        }
        if let nextHour = sunnyHours.first(where: { $0.date > referenceDate }) {
            return .sunOutIn(nextHour.date)
        }
        return .noMoreSunToday
    }

    /// Returns today's still-future real sunrise for normal and sunrise-only
    /// regimes. Polar days have no sunrise event to count down to.
    private static func upcomingSunrise(
        in regime: DaylightRegime,
        after referenceDate: Date
    ) -> Date? {
        let sunrise: Date?
        switch regime {
        case .normal(let event, _), .sunriseOnly(let event):
            sunrise = event
        case .sunsetOnly, .polarDay, .polarNight:
            sunrise = nil
        }
        guard let sunrise, sunrise > referenceDate else { return nil }
        return sunrise
    }

    /// WeatherKit's hourly values describe one-hour intervals beginning at
    /// their timestamp. This preserves a precise solar-event countdown even
    /// when the interval starts before the event.
    private static func hourlyInterval(
        _ forecast: HourlyForecast,
        contains date: Date
    ) -> Bool {
        forecast.date <= date
            && date < forecast.date.addingTimeInterval(60 * 60)
    }

    /// A sunset closes an ordinary city-local day. A normal regime whose
    /// sunset precedes sunrise wraps across midnight at high latitudes, so the
    /// later sunrise can still begin a second daylight interval and must not
    /// be treated as an all-day sunset cutoff.
    private static func sunsetHasPassed(
        in regime: DaylightRegime,
        at referenceDate: Date
    ) -> Bool {
        switch regime {
        case .normal(let sunrise, let sunset):
            sunset >= sunrise && referenceDate > sunset
        case .sunsetOnly(let sunset):
            referenceDate > sunset
        case .sunriseOnly, .polarDay, .polarNight:
            false
        }
    }
}

private extension SunnyHoursSourceIssue {
    func weatherDataIssue(at date: Date) -> WeatherDataIssue {
        switch self {
        case .missingHourlyData:
            .missingHourlyData(at: date)
        case .missingSunriseData:
            WeatherDataIssue(kind: .missingSunriseData, forecastDate: date)
        case .missingSunsetData:
            WeatherDataIssue(kind: .missingSunsetData, forecastDate: date)
        case .missingSunriseOrSunset:
            WeatherDataIssue(kind: .missingSunriseOrSunset, forecastDate: date)
        }
    }
}
