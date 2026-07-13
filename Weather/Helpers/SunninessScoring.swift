//
//  SunninessScoring.swift
//  Weather
//
//  Purpose: Provides shared sunniness scoring and sunny-hour calculations.
//

import Foundation

enum SunninessScoring {
    static func condition(for symbolName: String) -> AppWeatherCondition {
        AppWeatherCondition.fromWeatherSymbol(symbolName)
    }

    static func score(for symbolName: String) -> Double {
        condition(for: symbolName).sunninessScore
    }

    static func score(for forecast: DailyForecast) -> Double {
        score(for: forecast.symbolName)
    }

    static func score(for forecast: HourlyForecast) -> Double {
        score(for: forecast.symbolName)
    }

    static func daytimeHours(for forecast: DailyForecast, timeZone: TimeZone) -> [HourlyForecast] {
        daytimeHourlyForecasts(for: forecast, timeZone: timeZone)
    }

    static func hasDaytimeHourlyScoreData(for forecast: DailyForecast, timeZone: TimeZone) -> Bool {
        let daylightHours = daytimeHourlyForecasts(for: forecast, timeZone: timeZone)
        return !daylightHours.isEmpty
    }

    static func longestSunnyHourRange(in forecasts: [HourlyForecast]) -> ClosedRange<Int>? {
        let sunnyHours = forecasts.compactMap { forecast in
            condition(for: forecast.symbolName) == .clear ? forecast.hour : nil
        }
        return contiguousHourRanges(sunnyHours).reduce(nil) { longest, range in
            guard let longest else { return range }
            return range.upperBound - range.lowerBound > longest.upperBound - longest.lowerBound
                ? range
                : longest
        }
    }

    static func contiguousHourRanges(_ hours: [Int]) -> [ClosedRange<Int>] {
        let sortedHours = hours.sorted()
        guard let firstHour = sortedHours.first else { return [] }

        var ranges: [ClosedRange<Int>] = []
        var start = firstHour
        var end = firstHour

        for hour in sortedHours.dropFirst() {
            if hour == end + 1 {
                end = hour
            } else {
                ranges.append(start...end)
                start = hour
                end = hour
            }
        }

        ranges.append(start...end)
        return ranges
    }

    static func formattedHour(_ hour: Int, timeZone: TimeZone, locale: Locale) -> String {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = 0

        let date = calendar.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)
        return formatter.string(from: date)
    }

    private static func daytimeHourlyForecasts(for forecast: DailyForecast, timeZone: TimeZone) -> [HourlyForecast] {
        guard !forecast.hourlyForecasts.isEmpty else { return [] }
        guard let sunrise = forecast.sunrise,
              let sunset = forecast.sunset else {
            DeveloperWarningCenter.showOnce(
                key: "daytime-hours-fallback-\(timeZone.identifier)-\(forecast.dayOffset)",
                title: "Sunrise or Sunset Missing",
                message: "Forecast day \(forecast.dayOffset) has no sunrise or sunset data. The app is using 6 AM to 9 PM as its daytime range."
            )
            return forecast.hourlyForecasts
                .filter { (6...21).contains($0.hour) }
                .sorted { $0.hour < $1.hour }
        }

        let sunriseHour = fractionalHour(for: sunrise, timeZone: timeZone)
        let sunsetHour = fractionalHour(for: sunset, timeZone: timeZone)

        return forecast.hourlyForecasts
            .filter { hourlyForecast in
                let hourStart = Double(hourlyForecast.hour)
                let hourEnd = hourStart + 1
                return hourEnd > sunriseHour && hourStart < sunsetHour
            }
            .sorted { $0.hour < $1.hour }
    }

    private static func fractionalHour(for date: Date, timeZone: TimeZone) -> Double {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
    }
}
