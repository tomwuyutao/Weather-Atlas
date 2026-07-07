//
//  SunninessScoring.swift
//  Weather
//
//  Purpose: Provides the shared, minimal sunniness score used by home,
//  list ranking, and city detail.
//

import Foundation

enum SunninessScoring {
    static func score(
        condition: AppWeatherCondition,
        icon: String,
        cloudCover: Double?
    ) -> Double? {
        guard let cloudCover else {
            DeveloperWarningCenter.show(
                title: "Cloud Cover Missing",
                message: "A sunniness score could not be calculated because WeatherKit returned no cloud cover value."
            )
            return nil
        }

        return scoreValue(condition: condition, icon: icon, cloudCover: cloudCover)
    }

    static func daytimeAverageScore(for forecast: DailyForecast, timeZone: TimeZone) -> Double? {
        let daylightHours = daytimeHourlyForecasts(for: forecast, timeZone: timeZone)
        guard !daylightHours.isEmpty,
              daylightHours.allSatisfy({ $0.cloudCover != nil }) else {
            return nil
        }

        let hourlyScores: [Double] = daylightHours.compactMap { hour -> Double? in
            guard let cloudCover = hour.cloudCover else {
                return nil
            }
            return scoreValue(condition: hour.condition, icon: hour.weatherIcon, cloudCover: cloudCover)
        }

        return hourlyScores.reduce(0, +) / Double(hourlyScores.count)
    }

    static func hasDaytimeHourlyScoreData(for forecast: DailyForecast, timeZone: TimeZone) -> Bool {
        let daylightHours = daytimeHourlyForecasts(for: forecast, timeZone: timeZone)
        return !daylightHours.isEmpty && daylightHours.allSatisfy { $0.cloudCover != nil }
    }

    private static func scoreValue(
        condition: AppWeatherCondition,
        icon: String,
        cloudCover: Double
    ) -> Double {
        if icon.contains("moon") {
            return 0
        }

        let conditionBase: Double
        switch condition {
        case .clear:
            conditionBase = 100
        case .partlySunny:
            conditionBase = 82
        case .partlyCloudy:
            conditionBase = 66
        case .cloudy, .fog, .wind:
            conditionBase = 34
        case .rain, .drizzle, .snow:
            conditionBase = 12
        }

        let cloud = min(max(cloudCover, 0), 1)
        let cloudPenalty = cloud * 42
        return max(0, min(100, conditionBase - cloudPenalty))
    }

    private static func daytimeHourlyForecasts(for forecast: DailyForecast, timeZone: TimeZone) -> [HourlyForecast] {
        guard !forecast.hourlyForecasts.isEmpty else { return [] }
        guard let sunrise = forecast.sunrise,
              let sunset = forecast.sunset else {
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
