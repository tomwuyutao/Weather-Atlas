//
//  DaylightHours.swift
//  Weather
//
//  Purpose: Defines shared daylight bounds, segments, layout, and formatting.
//
//  Reading guide: WeatherKit gives this app dated hourly samples plus sunrise
//  and sunset instants. This file turns those facts into simple integer-hour
//  ranges that every sunny-hours chart can draw in the same way.
//

import Foundation

// MARK: - Sunny-Hour Chart Models

/// Astronomical daylight shape for one city-local forecast day.
///
/// Sunrise and sunset are legitimately absent around polar day/night, and a
/// transition day can contain only one event. This shared file is compiled into
/// both the app and widget targets so both can use the same daylight vocabulary.
enum DaylightRegime: Hashable {
    /// Ordinary daylight bounded by two real solar events.
    case normal(sunrise: Date, sunset: Date)
    /// The sun rises during this local day and does not set before its end.
    case sunriseOnly(sunrise: Date)
    /// The sun is already up at local midnight and sets during this day.
    case sunsetOnly(sunset: Date)
    /// Every available hourly source record is daylight and no event occurs.
    case polarDay
    /// Every available hourly source record is night and no event occurs.
    case polarNight
}

/// Integer-hour chart domain derived exclusively from real solar-event times.
/// The lower boundary is inclusive and the upper boundary is exclusive, which
/// makes a full day naturally representable as `0..<24`.
struct SunnyHoursChartBounds: Codable, Hashable {
    /// Inclusive first hour represented by the chart.
    let startHour: Int
    /// Exclusive upper hour boundary represented by the chart.
    let endHour: Int

    // MARK: - Bounds Construction

    /// Creates a valid nonempty domain, clamping external input to clock hours.
    /// `endHour` is forced at least one hour after `startHour`, so chart layout
    /// never has to divide by zero or render a zero-width daylight domain.
    init(startHour: Int, endHour: Int) {
        self.startHour = max(0, min(startHour, 23))
        self.endHour = max(self.startHour + 1, min(endHour, 24))
    }

    /// Honest local-day domain used for polar day/night, where no sunrise or
    /// sunset occurs and therefore no event-derived narrower bounds exist.
    static let fullDay = SunnyHoursChartBounds(startHour: 0, endHour: 24)

    /// Derives chart bounds from sunrise and sunset in the city's timezone.
    /// `floor` and `ceil` expand real event times to whole hourly cells, so a
    /// sunrise at 06:42 still makes the 06:00–07:00 cell available to draw.
    static func daylight(
        sunrise: Date?,
        sunset: Date?,
        timeZone: TimeZone
    ) -> SunnyHoursChartBounds? {
        guard let sunrise, let sunset else { return nil }
        guard let sunriseHour = fractionalHour(for: sunrise, timeZone: timeZone),
              let sunsetHour = fractionalHour(for: sunset, timeZone: timeZone) else {
            return nil
        }

        // At high latitudes, WeatherKit can report a real sunset just after
        // local midnight and a later sunrise on the same forecast date. That
        // daylight occupies both edges of the local day. The chart therefore
        // clips the two real intervals to the calendar-day boundaries; these
        // are not substitute sunrise or sunset values.
        if sunsetHour < sunriseHour {
            return SunnyHoursChartBounds(startHour: 0, endHour: 24)
        }

        let startHour = Int(floor(sunriseHour))
        let endHour = Int(ceil(sunsetHour))
        guard endHour > startHour else { return nil }
        return SunnyHoursChartBounds(startHour: startHour, endHour: endHour)
    }

    /// Derives a chart domain from an already validated astronomical regime.
    /// One-event transition days clip to the real event and a calendar edge;
    /// polar regimes use the entire local day without inventing solar times.
    static func daylight(
        regime: DaylightRegime,
        timeZone: TimeZone
    ) -> SunnyHoursChartBounds? {
        switch regime {
        case .normal(let sunrise, let sunset):
            return daylight(
                sunrise: sunrise,
                sunset: sunset,
                timeZone: timeZone
            )

        case .sunriseOnly(let sunrise):
            guard let sunriseHour = fractionalHour(
                for: sunrise,
                timeZone: timeZone
            ) else {
                return nil
            }
            return SunnyHoursChartBounds(
                startHour: Int(floor(sunriseHour)),
                endHour: 24
            )

        case .sunsetOnly(let sunset):
            guard let sunsetHour = fractionalHour(
                for: sunset,
                timeZone: timeZone
            ) else {
                return nil
            }
            return SunnyHoursChartBounds(
                startHour: 0,
                endHour: Int(ceil(sunsetHour))
            )

        case .polarDay, .polarNight:
            return .fullDay
        }
    }

    /// Tests whether a forecast's one-hour interval intersects actual daylight,
    /// including daylight that wraps across local midnight.
    static func hourlyIntervalOverlapsDaylight(
        at hourStart: Date,
        sunrise: Date,
        sunset: Date,
        timeZone: TimeZone
    ) -> Bool {
        guard let hour = fractionalHour(for: hourStart, timeZone: timeZone),
              let sunriseHour = fractionalHour(for: sunrise, timeZone: timeZone),
              let sunsetHour = fractionalHour(for: sunset, timeZone: timeZone) else {
            return false
        }

        // Hourly WeatherKit entries represent a one-hour cell. Compare the
        // cell's two endpoints instead of merely asking whether its start lies
        // inside daylight; that preserves a partially lit first or last hour.
        let hourEnd = hour + 1
        if sunsetHour < sunriseHour {
            return hour < sunsetHour || hourEnd > sunriseHour
        }
        return hourEnd > sunriseHour && hour < sunsetHour
    }

    /// Tests an hourly interval against a validated normal, transition, or polar
    /// daylight regime. This handles legitimate absent events without converting
    /// them to guessed midnight sunrise/sunset timestamps.
    static func hourlyIntervalOverlapsDaylight(
        at hourStart: Date,
        regime: DaylightRegime,
        timeZone: TimeZone
    ) -> Bool {
        switch regime {
        case .normal(let sunrise, let sunset):
            return hourlyIntervalOverlapsDaylight(
                at: hourStart,
                sunrise: sunrise,
                sunset: sunset,
                timeZone: timeZone
            )

        case .sunriseOnly(let sunrise):
            guard let hour = fractionalHour(
                for: hourStart,
                timeZone: timeZone
            ),
            let sunriseHour = fractionalHour(
                for: sunrise,
                timeZone: timeZone
            ) else {
                return false
            }
            return hour + 1 > sunriseHour

        case .sunsetOnly(let sunset):
            guard let hour = fractionalHour(
                for: hourStart,
                timeZone: timeZone
            ),
            let sunsetHour = fractionalHour(
                for: sunset,
                timeZone: timeZone
            ) else {
                return false
            }
            return hour < sunsetHour

        case .polarDay:
            return true
        case .polarNight:
            return false
        }
    }

    // MARK: - Time Conversion and Chart Coordinates

    /// Converts an absolute `Date` into a decimal clock hour in the requested
    /// city timezone. `Date` itself has no timezone; the calendar supplies the
    /// human-facing local interpretation.
    private static func fractionalHour(for date: Date, timeZone: TimeZone) -> Double? {
        // Copy before changing `timeZone`: calendars are value types, so this
        // does not mutate the caller's calendar or the global current calendar.
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        guard let hour = components.hour,
              let minute = components.minute,
              let second = components.second else {
            return nil
        }
        return Double(hour) + Double(minute) / 60 + Double(second) / 3_600
    }

    /// Returns the smallest domain containing every supplied nonempty bound.
    /// This lets a multi-day or multi-place comparison share one horizontal scale.
    static func merged(_ bounds: [SunnyHoursChartBounds]) -> SunnyHoursChartBounds? {
        guard let earliestStart = bounds.map(\.startHour).min(),
              let latestEnd = bounds.map(\.endHour).max() else {
            return nil
        }
        return SunnyHoursChartBounds(startHour: earliestStart, endHour: latestEnd)
    }

    /// Chooses evenly spaced integer tick hours within the real domain.
    /// The step is deliberately limited to 2, 3, or 4 hours for readable compact
    /// labels rather than attempting a mathematically exact tick count.
    func axisHours(maximumTickCount: Int = 9) -> [Int] {
        let span = endHour - startHour
        guard span > 0 else { return [startHour] }
        let availableIntervals = max(maximumTickCount - 1, 1)
        let minimumStep = Int(ceil(Double(span) / Double(availableIntervals)))
        let step: Int
        switch minimumStep {
        case ...2: step = 2
        case 3: step = 3
        default: step = 4
        }

        // `stride` produces evenly spaced integers. Append the exact right edge
        // when the chosen step does not land on it.
        var result = Array(stride(from: startHour, through: endHour, by: step))
        if result.last != endHour {
            result.append(endHour)
        }
        return result
    }

    /// Maps a decimal clock hour into a clamped horizontal chart coordinate.
    /// Clamping makes callers safe even if they pass a current time just outside
    /// the daylight domain.
    func xPosition(for hour: Double, width: CGFloat) -> CGFloat {
        let clampedHour = min(max(hour, Double(startHour)), Double(endHour))
        let fraction = (clampedHour - Double(startHour)) / Double(endHour - startHour)
        return CGFloat(fraction) * width
    }

    /// Maps current city-local time to the chart, or hides it outside daylight.
    /// Returning `nil` outside the bounds prevents a misleading marker pinned to
    /// the chart edge.
    func currentTimeXPosition(
        at date: Date,
        timeZone: TimeZone,
        width: CGFloat
    ) -> CGFloat? {
        guard let localHour = Self.fractionalHour(for: date, timeZone: timeZone),
              localHour >= Double(startHour),
              localHour <= Double(endHour) else {
            return nil
        }
        return xPosition(for: localHour, width: width)
    }

    /// Returns the rendered width of an inclusive integer-hour range. Add one to
    /// the upper bound because `ClosedRange` includes both endpoints.
    func width(
        for range: ClosedRange<Int>,
        timelineWidth: CGFloat,
        minimumWidth: CGFloat = 8
    ) -> CGFloat {
        let start = xPosition(for: Double(range.lowerBound), width: timelineWidth)
        let end = xPosition(for: Double(range.upperBound + 1), width: timelineWidth)
        return max(end - start, minimumWidth)
    }
}

// MARK: - Shared Source Analysis

/// Small, source-agnostic failure vocabulary for resolving available daylight.
///
/// The shared timeline target must not depend on the app's `DailyForecast` or
/// the widget's `HourWeather`. App and widget callers translate these cases into
/// their own dated diagnostics at the boundary where those source types exist.
enum SunnyHoursSourceIssue: Error, Hashable {
    case missingHourlyData
    case missingSunriseData
    case missingSunsetData
    case missingSunriseOrSunset
}

/// Available records from one city-local day paired with their proven daylight
/// regime. The generic record stays untouched so app and widget callers retain
/// all of their own weather fields after the shared filtering step.
struct AvailableDaylightHours<Hour> {
    let regime: DaylightRegime
    let hours: [Hour]
}

/// Dependency-light policy shared by the app and widget weather adapters.
///
/// Generic closures expose only the facts this analysis needs: each record's
/// instant and daylight flag. Condition normalization stays in the shared
/// `AppWeatherCondition` provider adapter.
enum SunnyHoursSourceAnalysis {
    /// Filters one city-local day to the source records that overlap real
    /// daylight and resolves legitimate normal, transition, and polar regimes.
    ///
    /// Hourly feeds are rolling. In particular, after local sunset WeatherKit
    /// can retain only nighttime records for the remainder of today. That is a
    /// valid empty *available daylight* result, not missing hourly data. Future
    /// or otherwise unresolved days still fail when no daylight record exists.
    static func availableDaylightHours<Hour>(
        on date: Date,
        sunrise: Date?,
        sunset: Date?,
        from forecasts: [Hour],
        calendar: Calendar,
        referenceDate: Date = .now,
        dateOf: (Hour) -> Date,
        isDaylight: (Hour) -> Bool
    ) -> Result<AvailableDaylightHours<Hour>, SunnyHoursSourceIssue> {
        let matchingHours = forecasts
            .filter { calendar.isDate(dateOf($0), inSameDayAs: date) }
            .sorted { dateOf($0) < dateOf($1) }

        let regime: DaylightRegime
        switch (sunrise, sunset) {
        case let (.some(sunrise), .some(sunset)):
            regime = .normal(sunrise: sunrise, sunset: sunset)

        case (nil, nil):
            guard !matchingHours.isEmpty else {
                return .failure(.missingHourlyData)
            }
            if matchingHours.allSatisfy(isDaylight) {
                regime = .polarDay
            } else if matchingHours.allSatisfy({ !isDaylight($0) }) {
                regime = .polarNight
            } else {
                return .failure(.missingSunriseOrSunset)
            }

        case let (nil, .some(sunset)):
            let isFinishedCurrentDay = calendar.isDate(
                date,
                inSameDayAs: referenceDate
            ) && referenceDate >= sunset
            guard matchingHours.contains(where: isDaylight)
                    || isFinishedCurrentDay else {
                return .failure(.missingSunriseData)
            }
            regime = .sunsetOnly(sunset: sunset)

        case let (.some(sunrise), nil):
            guard !matchingHours.isEmpty,
                  matchingHours.contains(where: isDaylight) else {
                return .failure(.missingSunsetData)
            }
            regime = .sunriseOnly(sunrise: sunrise)
        }

        if matchingHours.isEmpty {
            if calendar.isDate(date, inSameDayAs: referenceDate),
               daylightHasEnded(in: regime, at: referenceDate) {
                return .success(
                    AvailableDaylightHours(regime: regime, hours: [])
                )
            }
            return .failure(.missingHourlyData)
        }

        let daylightHours = matchingHours.filter { hour in
            SunnyHoursChartBounds.hourlyIntervalOverlapsDaylight(
                at: dateOf(hour),
                regime: regime,
                timeZone: calendar.timeZone
            )
        }

        if regime == .polarNight {
            return .success(
                AvailableDaylightHours(regime: regime, hours: [])
            )
        }
        if !daylightHours.isEmpty {
            return .success(
                AvailableDaylightHours(regime: regime, hours: daylightHours)
            )
        }

        // An empty current-day result is truthful only once ordinary daylight
        // has finished. Before sunrise there are still future daylight records
        // expected from a rolling feed, so their absence remains a data issue.
        if calendar.isDate(date, inSameDayAs: referenceDate),
           daylightHasEnded(in: regime, at: referenceDate) {
            return .success(
                AvailableDaylightHours(regime: regime, hours: [])
            )
        }
        return .failure(.missingHourlyData)
    }

    /// Determines whether a no-daylight-hours result can be explained by the
    /// rolling feed starting after today's final real sunset.
    private static func daylightHasEnded(
        in regime: DaylightRegime,
        at referenceDate: Date
    ) -> Bool {
        switch regime {
        case .normal(let sunrise, let sunset):
            // `sunset < sunrise` represents daylight clipped across both edges
            // of a high-latitude day, so another lit interval remains after the
            // sunrise and an empty feed cannot be accepted by this shortcut.
            return sunset >= sunrise && referenceDate >= sunset
        case .sunsetOnly(let sunset):
            return referenceDate >= sunset
        case .polarNight:
            return true
        case .sunriseOnly, .polarDay:
            return false
        }
    }
}

// MARK: - Sunny-Hour Formatting

/// Shared deterministic formatting for chart ranges and axis labels.
enum SunnyHoursFormatting {
    // MARK: - Sunny-Hour Counts

    /// Formats a whole or half sunny-hour total with the active locale's
    /// decimal separator and the app-wide spaced unit convention (for example,
    /// `11 h`, never `11h`).
    static func hourCountLabel(_ hours: Double, locale: Locale) -> String {
        "\(hourCountText(hours, locale: locale)) h"
    }

    /// Formats the numeric portion separately for status sentences that supply
    /// their own localized surrounding text.
    static func hourCountText(_ hours: Double, locale: Locale) -> String {
        if hours.rounded() == hours {
            return hours.formatted(
                .number
                    .grouping(.never)
                    .precision(.fractionLength(0))
                    .locale(locale)
            )
        }
        return hours.formatted(
            .number
                .grouping(.never)
                .precision(.fractionLength(1))
                .locale(locale)
        )
    }

    // MARK: - Axis Labels

    /// Formats an integer hour as a fixed-width 24-hour chart tick. Chart ticks
    /// are intentionally compact and language-neutral, unlike general date text.
    nonisolated static func chartHourLabel(_ hour: Int) -> String {
        // Keep the right edge of a full local-day chart distinct from its 00
        // start. This is a boundary label, not another midnight forecast cell.
        hour == 24 ? "24" : String(format: "%02d", ((hour % 24) + 24) % 24)
    }

    /// Explains the clock used by a weather chart, including the destination's
    /// UTC offset at the represented forecast instant. Passing the forecast
    /// date (rather than `Date.now`) keeps daylight-saving changes accurate.
    static func localTimeDisclosure(
        placeName: String,
        timeZone: TimeZone,
        at date: Date,
        locale: Locale
    ) -> String {
        let trimmedName = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty
            ? localizedString("Place", locale: locale)
            : trimmedName
        let offset = utcOffsetLabel(for: timeZone, at: date, locale: locale)
        return localizedString(
            "Times shown in \(resolvedName) local time (\(offset))",
            locale: locale
        )
    }

    /// Produces a compact offset such as `UTC+14`, `UTC−4`, or `UTC+5:30`.
    /// Numeric formatting follows the app's locale while UTC punctuation stays
    /// stable and recognizable across languages.
    private static func utcOffsetLabel(
        for timeZone: TimeZone,
        at date: Date,
        locale: Locale
    ) -> String {
        let totalMinutes = timeZone.secondsFromGMT(for: date) / 60
        let sign = totalMinutes >= 0 ? "+" : "−"
        let absoluteMinutes = abs(totalMinutes)
        let hours = absoluteMinutes / 60
        let minutes = absoluteMinutes % 60
        let hourText = hours.formatted(
            .number
                .grouping(.never)
                .locale(locale)
        )

        guard minutes != 0 else { return "UTC\(sign)\(hourText)" }

        let minuteText = minutes.formatted(
            .number
                .precision(.integerLength(2))
                .grouping(.never)
                .locale(locale)
        )
        return "UTC\(sign)\(hourText):\(minuteText)"
    }

}
