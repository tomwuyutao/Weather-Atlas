//
//  SunnyHoursCalculation.swift
//  Weather
//
//  Purpose: Counts city-local daylight hours that are clear.
//
//  Reading guide: chart geometry and locale-safe formatting are shared with
//  WidgetKit. App-only policy below the compile guard interprets WeatherKit's
//  daylight flags for forecasts, rankings, and live status text.
//

import Foundation

// MARK: - Chart Domain

/// Integer-hour domain shared by the sunny-hours timelines.
///
/// Bounds use an inclusive start and exclusive end, so 0...24 represents a
/// full local day without needing a separate midnight data point.
struct SunnyHoursChartBounds {
    let startHour: Int
    let endHour: Int

    init(startHour: Int, endHour: Int) {
        self.startHour = max(0, min(startHour, 23))
        self.endHour = max(self.startHour + 1, min(endHour, 24))
    }

    static let fullDay = SunnyHoursChartBounds(startHour: 0, endHour: 24)

    /// Produces one domain spanning several charts so comparable rows align.
    static func merged(_ bounds: [SunnyHoursChartBounds]) -> SunnyHoursChartBounds? {
        guard let first = bounds.map(\.startHour).min(),
              let last = bounds.map(\.endHour).max() else {
            return nil
        }
        return SunnyHoursChartBounds(startHour: first, endHour: last)
    }

    /// Chooses sparse, even tick intervals while always retaining the end bound.
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

    /// Maps a possibly out-of-range hour into the chart's clamped x-domain.
    func xPosition(for hour: Double, width: CGFloat) -> CGFloat {
        let hour = min(max(hour, Double(startHour)), Double(endHour))
        return CGFloat(
            (hour - Double(startHour)) / Double(endHour - startHour)
        ) * width
    }

    /// Maps current city-local time into the chart, clamping before/after the
    /// represented daylight window to its leading/trailing edge.
    func currentTimeXPosition(
        at date: Date,
        timeZone: TimeZone,
        width: CGFloat
    ) -> CGFloat? {
        guard let hour = Self.fractionalHour(for: date, timeZone: timeZone) else {
            return nil
        }
        return xPosition(for: hour, width: width)
    }

    /// Converts an inclusive hourly interval into a visible bar width.
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

// MARK: - Shared Formatting

/// Formatting shared by the app and widget sunny-hours charts.
enum SunnyHoursFormatting {
    /// Formats the compact hour count as one localizable unit expression. The
    /// widget reads the same key from the app-published copy so its selected
    /// language remains independent from the device language.
    static func hourCountLabel(_ hours: Double, locale: Locale) -> String {
        let format: String
#if WEATHER_WIDGETS
        format = WidgetDataStore.localizedText(for: "%@ h")
#else
        format = localizedString("%@ h", locale: locale)
#endif
        return String(
            format: format,
            locale: locale,
            hourCountText(hours, locale: locale)
        )
    }

#if !WEATHER_WIDGETS
    /// Upper endpoint used by Map's legend, where the plus sign means “or
    /// more”. Keeping the entire unit expression localizable lets languages
    /// move or expand that qualifier around the number.
    static func maximumHourCountLabel(_ hours: Double, locale: Locale) -> String {
        String(
            format: localizedString("%@ h+", locale: locale),
            locale: locale,
            hourCountText(hours, locale: locale)
        )
    }
#endif

    /// Keeps whole-hour values free of a decimal while retaining one fractional digit.
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

    /// Preserves `24` as the chart endpoint instead of wrapping it to `00`.
    nonisolated static func chartHourLabel(_ hour: Int) -> String {
        hour == 24 ? "24" : String(format: "%02d", ((hour % 24) + 24) % 24)
    }
}

#if !WEATHER_WIDGETS

// MARK: - App Sunny-Hours Policy

/// Shared sunny-hours calculations for cards, status copy, and rankings.
enum SunnyHoursCalculation {
    // MARK: - Result Types

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

    // MARK: - Daylight Extraction

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
        Double(data.hours.count(where: { $0.condition?.countsAsSunnyHour == true }))
    }

    /// Whether at least four fifths of the available WeatherKit daylight
    /// capsules are clear or mostly clear. The comparison is deliberately
    /// integer-based so the inclusive 80% boundary cannot drift through
    /// floating-point rounding. A day without a daylight capsule is not a
    /// qualifying day: its zero-over-zero share is undefined rather than 100%.
    static func hasAtLeastEightyPercentSunnyDaylight(
        in data: SunnyHoursData
    ) -> Bool {
        let daylightCapsuleCount = data.hours.count
        guard daylightCapsuleCount > 0 else { return false }

        let sunnyCapsuleCount = data.hours.count {
            $0.condition?.countsAsSunnyHour == true
        }
        return sunnyCapsuleCount * 5 >= daylightCapsuleCount * 4
    }

    // MARK: - Future Forecast Search

    /// Finds the first later city-local forecast day with at least one clear
    /// WeatherKit daylight hour. Available forecast rows are
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

    /// Returns the number of future forecast dates only when every one is
    /// assessable and contains no sunny hour. Today is deliberately excluded,
    /// and a single future sunny date suppresses the horizon-wide claim.
    static func sunlessFutureForecastDayCount(
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

        guard !laterForecasts.isEmpty else { return nil }

        for laterForecast in laterForecasts {
            let data = sunnyHoursData(
                for: laterForecast,
                timeZone: timeZone
            )

            // Missing daylight rows or conditions cannot prove that a date is
            // sunless, so fall back to the honest day-specific status instead.
            guard !data.hours.isEmpty,
                  data.hours.allSatisfy({ $0.condition != nil }),
                  sunnyHourCount(in: data) == 0 else {
                return nil
            }
        }

        return laterForecasts.count
    }

    // MARK: - Daily Status

    /// Resolves status in city-local time, giving solar-event boundaries
    /// precedence over the coarser one-hour WeatherKit intervals used in charts.
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
            $0.condition?.countsAsSunnyHour == true
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
           currentHour.condition?.countsAsSunnyHour == true {
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

// MARK: - City Forecast Planning

/// Outcome of assessing one city's retained future hourly forecasts against
/// the mostly-sunny threshold. A missing hourly horizon is distinct from a
/// complete assessed horizon that simply contains no qualifying day.
enum MostlySunnyForecastSearchResult {
    case match(forecast: DailyForecast, selectionDate: Date)
    case noMatch
    case unavailable
}

extension CityWeather {
    /// Finds the first city-local forecast day on or after the reference day
    /// whose available daylight capsules are at least 80% clear or mostly
    /// clear. The paired selection date carries the same literal year, month,
    /// and day into the app-wide forecast calendar for navigation.
    func mostlySunnyForecastSearch(
        onOrAfter referenceDate: Date,
        selectionCalendar: Calendar = .current
    ) -> MostlySunnyForecastSearchResult {
        var cityCalendar = selectionCalendar
        cityCalendar.timeZone = timeZone
        let referenceDay = cityCalendar.startOfDay(for: referenceDate)
        var assessedForecast = false

        let candidateForecasts = dailyForecasts
            .filter {
                cityCalendar.startOfDay(for: $0.date) >= referenceDay
            }
            .sorted { $0.date < $1.date }

        for forecast in candidateForecasts {
            let data = SunnyHoursCalculation.sunnyHoursData(
                for: forecast,
                timeZone: timeZone
            )
            guard !data.hours.isEmpty else { continue }
            assessedForecast = true

            guard SunnyHoursCalculation
                .hasAtLeastEightyPercentSunnyDaylight(in: data),
                  let selectionDate = selectionDate(
                      for: forecast,
                      selectionCalendar: selectionCalendar
                  ) else {
                continue
            }
            return .match(
                forecast: forecast,
                selectionDate: selectionDate
            )
        }

        return assessedForecast ? .noMatch : .unavailable
    }
}

// MARK: - Local-Time Disclosure

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
