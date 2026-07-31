//
//  SunninessScoring.swift
//  Weather
//
//  Purpose: Provides shared sunniness scoring and sunny-hour calculations.
//

import Foundation

// MARK: - Sunny-Hour Validation and Scoring

/// Pure source-data validation and sunny-hour classification operations.
enum SunninessScoring {
    /// Validated daylight bounds and hourly forecasts used by timelines.
    struct SunnyHoursData {
        /// Source hours whose one-hour intervals intersect daylight.
        let hours: [HourlyForecast]
        /// Sunrise/sunset-derived chart domain shared by those hours.
        let bounds: SunnyHoursChartBounds
    }

    /// Classifies a source symbol, preserving unknown values as `nil`.
    static func condition(for symbolName: String) -> AppWeatherCondition? {
        AppWeatherCondition.fromWeatherSymbol(symbolName)
    }

    /// Prefers WeatherKit's semantic condition, retaining symbol parsing only
    /// for older cache entries and source-compatible fixtures.
    static func condition(for forecast: DailyForecast) -> AppWeatherCondition? {
        forecast.condition ?? condition(for: forecast.symbolName)
    }

    /// Prefers WeatherKit's semantic condition for one hourly forecast.
    static func condition(for forecast: HourlyForecast) -> AppWeatherCondition? {
        forecast.condition ?? condition(for: forecast.symbolName)
    }

    /// Validates solar/hourly inputs and returns only hours overlapping daylight.
    static func sunnyHoursData(
        for forecast: DailyForecast,
        timeZone: TimeZone
    ) -> Result<SunnyHoursData, WeatherDataIssue> {
        if let issue = WeatherDataIssue.missingSunEvent(
            sunrise: forecast.sunrise,
            sunset: forecast.sunset
        ) {
            return .failure(issue)
        }
        guard let sunrise = forecast.sunrise,
              let sunset = forecast.sunset,
              let bounds = SunnyHoursChartBounds.daylight(
                sunrise: sunrise,
                sunset: sunset,
                timeZone: timeZone
              ) else {
            return .failure(.missingSunriseOrSunset)
        }
        guard !forecast.hourlyForecasts.isEmpty else {
            return .failure(.missingHourlyData)
        }
        let daylightHours = forecast.hourlyForecasts
            .filter { hourlyForecast in
                SunnyHoursChartBounds.hourlyIntervalOverlapsDaylight(
                    at: hourlyForecast.date,
                    sunrise: sunrise,
                    sunset: sunset,
                    timeZone: timeZone
                )
            }
            .sorted { $0.date < $1.date }

        guard !daylightHours.isEmpty else {
            return .failure(.missingHourlyData)
        }
        if let unknownHour = daylightHours.first(where: {
            condition(for: $0) == nil
        }) {
            return .failure(.unknownWeatherSymbol(unknownHour.symbolName))
        }
        return .success(SunnyHoursData(hours: daylightHours, bounds: bounds))
    }

    /// Convenience accessor for validated daylight hours, or `nil` on any issue.
    static func daytimeHours(for forecast: DailyForecast, timeZone: TimeZone) -> [HourlyForecast]? {
        guard case .success(let data) = sunnyHoursData(for: forecast, timeZone: timeZone) else {
            return nil
        }
        return data.hours
    }

    /// Whether a forecast has all solar, hourly, and symbol inputs needed to score.
    static func hasDaytimeHourlyScoreData(for forecast: DailyForecast, timeZone: TimeZone) -> Bool {
        guard case .success = sunnyHoursData(for: forecast, timeZone: timeZone) else {
            return false
        }
        return true
    }

    /// Returns the longest contiguous run of fully or partly sunny local hours.
    static func longestSunnyHourRange(in forecasts: [HourlyForecast], timeZone: TimeZone) -> ClosedRange<Int>? {
        let sunnyHours = forecasts.compactMap { forecast in
            condition(for: forecast)?.isSunnyOrPartlySunny == true
                ? forecast.hour(in: timeZone)
                : nil
        }
        return SunnyHoursFormatting.contiguousRanges(in: sunnyHours).reduce(nil) { longest, range in
            guard let longest else { return range }
            return range.upperBound - range.lowerBound > longest.upperBound - longest.lowerBound
                ? range
                : longest
        }
    }

    /// Locale-aware compact hour used by summary cards. This follows the app's
    /// selected locale, including its 12-hour/24-hour convention and day periods.
    static func compactHourLabel(_ hour: Int, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.hour = ((hour % 24) + 24) % 24
        components.minute = 0
        guard let date = components.date else {
            return SunnyHoursFormatting.chartHourLabel(hour)
        }
        return formatter.string(from: date)
    }

}
