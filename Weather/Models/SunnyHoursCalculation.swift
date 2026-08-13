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
        return .success(SunnyHoursData(hours: sourceData.hours, bounds: bounds))
    }

    static func sunnyHourCount(in data: SunnyHoursData) -> Double {
        Double(data.hours.count(where: { $0.condition?.isSunnyOrPartlySunny == true }))
    }

    static func longestSunnyHourRange(
        in forecasts: [HourlyForecast],
        timeZone: TimeZone
    ) -> ClosedRange<Int>? {
        guard forecasts.allSatisfy({ $0.condition != nil }) else { return nil }
        let hours = forecasts.compactMap { forecast in
            forecast.condition?.isSunnyOrPartlySunny == true
                ? forecast.hour(in: timeZone)
                : nil
        }
        return SunnyHoursFormatting.contiguousRanges(in: hours).max { lhs, rhs in
            lhs.upperBound - lhs.lowerBound < rhs.upperBound - rhs.lowerBound
        }
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
        guard !sunnyHours.isEmpty else { return .noSunToday }

        if let currentHour = data.hours.last(where: { $0.date <= referenceDate }),
           currentHour.condition?.isSunnyOrPartlySunny == true {
            return .sunOutNow
        }
        if let nextHour = sunnyHours.first(where: { $0.date > referenceDate }) {
            return .sunOutIn(nextHour.date)
        }
        return .noMoreSunToday
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
