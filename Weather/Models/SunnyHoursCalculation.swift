//
//  SunnyHoursCalculation.swift
//  Weather
//
//  Purpose: Counts city-local daylight hours that are Clear or Partly Sunny.
//

import Foundation

/// Integer-hour domain shared by the sunny-hours timelines.
///
/// Bounds use an inclusive start and exclusive end, so 0...24 represents a
/// full local day without needing a separate midnight data point.
struct SunnyHoursChartBounds: Codable, Hashable {
    let startHour: Int
    let endHour: Int

    init(startHour: Int, endHour: Int) {
        self.startHour = max(0, min(startHour, 23))
        self.endHour = max(self.startHour + 1, min(endHour, 24))
    }

    static let fullDay = SunnyHoursChartBounds(startHour: 0, endHour: 24)

    static func merged(_ bounds: [SunnyHoursChartBounds]) -> SunnyHoursChartBounds? {
        guard let first = bounds.map(\.startHour).min(),
              let last = bounds.map(\.endHour).max() else {
            return nil
        }
        return SunnyHoursChartBounds(startHour: first, endHour: last)
    }

    func axisHours(maximumTickCount: Int = 9) -> [Int] {
        let span = endHour - startHour
        guard span > 0 else { return [startHour] }

        let minimumStep = Int(
            ceil(Double(span) / Double(max(maximumTickCount - 1, 1)))
        )
        let step: Int
        switch minimumStep {
        case ...2: step = 2
        case 3: step = 3
        default: step = 4
        }

        var hours = Array(stride(from: startHour, through: endHour, by: step))
        if hours.last != endHour {
            hours.append(endHour)
        }
        return hours
    }

    func xPosition(for hour: Double, width: CGFloat) -> CGFloat {
        let hour = min(max(hour, Double(startHour)), Double(endHour))
        return CGFloat(
            (hour - Double(startHour)) / Double(endHour - startHour)
        ) * width
    }

    func currentTimeXPosition(
        at date: Date,
        timeZone: TimeZone,
        width: CGFloat
    ) -> CGFloat? {
        guard let hour = Self.fractionalHour(for: date, timeZone: timeZone),
              hour >= Double(startHour),
              hour <= Double(endHour) else {
            return nil
        }
        return xPosition(for: hour, width: width)
    }

    func width(
        for range: ClosedRange<Int>,
        timelineWidth: CGFloat,
        minimumWidth: CGFloat = 8
    ) -> CGFloat {
        let start = xPosition(for: Double(range.lowerBound), width: timelineWidth)
        let end = xPosition(
            for: Double(range.upperBound + 1),
            width: timelineWidth
        )
        return max(end - start, minimumWidth)
    }

    private static func fractionalHour(
        for date: Date,
        timeZone: TimeZone
    ) -> Double? {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.hour, .minute, .second],
            from: date
        )
        guard let hour = components.hour,
              let minute = components.minute,
              let second = components.second else {
            return nil
        }
        return Double(hour) + Double(minute) / 60 + Double(second) / 3_600
    }
}

/// Formatting shared by the app and widget sunny-hours charts.
enum SunnyHoursFormatting {
    static func hourCountLabel(_ hours: Double, locale: Locale) -> String {
        "\(hourCountText(hours, locale: locale)) h"
    }

    static func hourCountText(_ hours: Double, locale: Locale) -> String {
        hours.formatted(
            .number
                .grouping(.never)
                .precision(
                    .fractionLength(hours.rounded() == hours ? 0 : 1)
                )
                .locale(locale)
        )
    }

    nonisolated static func chartHourLabel(_ hour: Int) -> String {
        hour == 24 ? "24" : String(format: "%02d", ((hour % 24) + 24) % 24)
    }
}

#if !WEATHER_WIDGETS

/// Shared sunny-hours calculations for cards, status copy, and rankings.
enum SunnyHoursCalculation {
    struct SunnyHoursData {
        let hours: [HourlyForecast]
        let bounds: SunnyHoursChartBounds
        /// Solar events are presentation details for the live status line.
        /// Daylight inclusion and chart bounds come directly from WeatherKit's
        /// per-hour `isDaylight` value.
        let sunrise: Date?
        let sunset: Date?
    }

    enum DailySunStatus: Equatable {
        case sunnyForHours(Double)
        case sunOutNow
        case sunOutIn(Date)
        case noSunToday
        case noMoreSunToday
        case noSunOnSelectedDay
    }

    /// Returns the selected city's WeatherKit daylight hours. WeatherKit has
    /// already marked each hourly record with `isDaylight`, so sunrise and
    /// sunset are not needed to validate, filter, or bound the chart.
    static func sunnyHoursData(
        for forecast: DailyForecast,
        timeZone: TimeZone
    ) -> SunnyHoursData {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let daylightHours = forecast.hourlyForecasts
            .filter {
                calendar.isDate($0.date, inSameDayAs: forecast.date)
                    && $0.isDaylight
            }
            .sorted { $0.date < $1.date }

        return SunnyHoursData(
            hours: daylightHours,
            bounds: chartBounds(for: daylightHours, timeZone: timeZone),
            sunrise: forecast.sunrise,
            sunset: forecast.sunset
        )
    }

    /// Keep the chart tightly focused on the available daylight records. A
    /// full-day domain is a harmless fallback when WeatherKit has no daylight
    /// records for this date, including unusual latitude and rolling-feed cases.
    private static func chartBounds(
        for daylightHours: [HourlyForecast],
        timeZone: TimeZone
    ) -> SunnyHoursChartBounds {
        guard let firstHour = daylightHours.map({ $0.hour(in: timeZone) }).min(),
              let lastHour = daylightHours.map({ $0.hour(in: timeZone) }).max()
        else {
            return .fullDay
        }
        return SunnyHoursChartBounds(
            startHour: firstHour,
            endHour: lastHour + 1
        )
    }

    static func sunnyHourCount(in data: SunnyHoursData) -> Double {
        Double(data.hours.count(where: { $0.condition?.isSunnyOrPartlySunny == true }))
    }

    /// Finds the first later city-local forecast day with at least one clear or
    /// partly sunny WeatherKit daylight hour. Available forecast rows are
    /// independent: a short horizon or a skipped date must not hide a later
    /// useful result.
    static func nextSunnyForecastDate(
        after forecast: DailyForecast,
        in forecasts: [DailyForecast],
        timeZone: TimeZone,
        selectionCalendar: Calendar
    ) -> Date? {
        var cityCalendar = selectionCalendar
        cityCalendar.timeZone = timeZone
        let selectedDay = cityCalendar.startOfDay(for: forecast.date)
        let laterForecasts = forecasts
            .filter {
                cityCalendar.startOfDay(for: $0.date) > selectedDay
            }
            .sorted { $0.date < $1.date }

        for laterForecast in laterForecasts {
            let data = sunnyHoursData(
                for: laterForecast,
                timeZone: timeZone
            )

            if sunnyHourCount(in: data) > 0 {
                return laterForecast.date
            }
        }

        return nil
    }

    /// Returns the number of available later forecast rows before the first
    /// sunny one. This intentionally does not impose a contiguous ten-day
    /// horizon: WeatherKit may supply fewer rows.
    static func followingSunlessForecastDayCount(
        after forecast: DailyForecast,
        in forecasts: [DailyForecast],
        timeZone: TimeZone,
        selectionCalendar: Calendar
    ) -> Int? {
        var cityCalendar = selectionCalendar
        cityCalendar.timeZone = timeZone
        let selectedDay = cityCalendar.startOfDay(for: forecast.date)
        let laterForecasts = forecasts
            .filter {
                cityCalendar.startOfDay(for: $0.date) > selectedDay
            }
            .sorted { $0.date < $1.date }

        var count = 0
        for laterForecast in laterForecasts {
            let data = sunnyHoursData(
                for: laterForecast,
                timeZone: timeZone
            )

            guard sunnyHourCount(in: data) == 0 else { break }
            count += 1
        }

        return count
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

        // Sunrise and sunset refine ordinary live copy only; the hourly
        // WeatherKit flag remains the sole source for sunny-hour data.
        if let sunset = data.sunset, referenceDate >= sunset {
            return sunnyHours.isEmpty ? .noSunToday : .noMoreSunToday
        }
        if let sunrise = data.sunrise, sunrise > referenceDate {
            if sunnyHours.contains(where: { hourlyInterval($0, contains: sunrise) }) {
                return .sunOutIn(sunrise)
            }
        }
        guard !sunnyHours.isEmpty else { return .noSunToday }

        if let currentHour = data.hours.last(where: { $0.date <= referenceDate }),
           hourlyInterval(currentHour, contains: referenceDate),
           currentHour.condition?.isSunnyOrPartlySunny == true {
            return .sunOutNow
        }
        if let nextHour = sunnyHours.first(where: { $0.date > referenceDate }) {
            return .sunOutIn(nextHour.date)
        }
        return .noMoreSunToday
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

}

extension SunnyHoursFormatting {
    static func localTimeDisclosure(
        placeName: String,
        timeZone: TimeZone,
        at date: Date,
        locale: Locale
    ) -> String {
        let placeName = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = placeName.isEmpty
            ? localizedString("Place", locale: locale)
            : placeName
        return localizedString(
            "Times shown in \(name) local time (\(utcOffsetLabel(for: timeZone, at: date, locale: locale)))",
            locale: locale
        )
    }

    private static func utcOffsetLabel(
        for timeZone: TimeZone,
        at date: Date,
        locale: Locale
    ) -> String {
        let minutes = timeZone.secondsFromGMT(for: date) / 60
        let sign = minutes >= 0 ? "+" : "−"
        let absoluteMinutes = abs(minutes)
        let hours = (absoluteMinutes / 60).formatted(
            .number.grouping(.never).locale(locale)
        )
        let remainder = absoluteMinutes % 60
        guard remainder != 0 else { return "UTC\(sign)\(hours)" }
        let minuteText = remainder.formatted(
            .number
                .precision(.integerLength(2))
                .grouping(.never)
                .locale(locale)
        )
        return "UTC\(sign)\(hours):\(minuteText)"
    }
}

#endif
