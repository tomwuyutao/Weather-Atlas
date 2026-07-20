//
//  WidgetDataStore.swift
//  Weather
//
//  Purpose: Shares city weather data with the WidgetKit extension.
//

import Foundation
import WidgetKit

func widgetLocalizedString(_ key: String.LocalizationValue, locale: Locale) -> String {
    var resource = LocalizedStringResource(key)
    resource.locale = locale
    return String(localized: resource)
}

// MARK: - Shared Weather Symbols

/// Canonical SF Symbols for weather conditions, shared by the app and widgets.
enum WeatherIconSymbol {
    static let clear = "sun.max.fill"
    static let partlyCloudy = "cloud.sun"
    static let cloudy = "cloud"
    static let rain = "cloud.rain"
    static let drizzle = "cloud.drizzle"
    static let snow = "cloud.snow"
    static let fog = "cloud.fog"
    static let wind = "wind"
    static let night = "moon.fill"
}

// MARK: - Shared Weather Data Validation

/// A missing input that makes weather-derived content unsafe to display.
/// These states are persisted with widget snapshots so the extension never
/// replaces absent source data with plausible-looking hours or conditions.
struct WeatherDataIssue: Error, Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case missingSunriseOrSunset
        case missingSunriseData
        case missingSunsetData
        case missingHourlyData
        case missingForecastData
        case missingCloudCoverData
        case missingPrecipitationData
        case missingUVIndexData
        case missingTimeZone
        case unknownWeatherSymbol
    }

    let kind: Kind
    let detail: String?

    static let missingSunriseOrSunset = WeatherDataIssue(
        kind: .missingSunriseOrSunset,
        detail: nil
    )
    static let missingSunriseData = WeatherDataIssue(
        kind: .missingSunriseData,
        detail: nil
    )
    static let missingSunsetData = WeatherDataIssue(
        kind: .missingSunsetData,
        detail: nil
    )
    static let missingHourlyData = WeatherDataIssue(
        kind: .missingHourlyData,
        detail: nil
    )
    static let missingForecastData = WeatherDataIssue(
        kind: .missingForecastData,
        detail: nil
    )
    static let missingCloudCoverData = WeatherDataIssue(
        kind: .missingCloudCoverData,
        detail: nil
    )
    static let missingPrecipitationData = WeatherDataIssue(
        kind: .missingPrecipitationData,
        detail: nil
    )
    static let missingUVIndexData = WeatherDataIssue(
        kind: .missingUVIndexData,
        detail: nil
    )
    static let missingTimeZone = WeatherDataIssue(
        kind: .missingTimeZone,
        detail: nil
    )

    static func unknownWeatherSymbol(_ symbolName: String) -> WeatherDataIssue {
        WeatherDataIssue(kind: .unknownWeatherSymbol, detail: symbolName)
    }

    /// Names the absent solar event when WeatherKit supplies only one side of
    /// the daylight interval. The combined case is reserved for both missing.
    static func missingSunEvent(sunrise: Date?, sunset: Date?) -> WeatherDataIssue? {
        switch (sunrise, sunset) {
        case (nil, nil): .missingSunriseOrSunset
        case (nil, _): .missingSunriseData
        case (_, nil): .missingSunsetData
        case (.some, .some): nil
        }
    }
}

/// Recognizes every condition family used by the app and widget. An unknown
/// symbol stays unknown so callers can stop rendering dependent content.
enum WeatherSymbolClassification {
    case clear
    case partlySunny
    case partlyCloudy
    case cloudy
    case rain
    case drizzle
    case snow
    case fog
    case wind
    case night

    static func resolve(_ symbolName: String) -> WeatherSymbolClassification? {
        let symbol = symbolName.lowercased()

        if symbol.contains("drizzle") { return .drizzle }
        if symbol.contains("rain") || symbol.contains("thunderstorm") || symbol.contains("storm") { return .rain }
        if symbol.contains("snow") || symbol.contains("sleet") || symbol.contains("flurr") { return .snow }
        if symbol.contains("wind") || symbol.contains("hurricane") || symbol.contains("tropicalstorm") { return .wind }
        if symbol.contains("fog") || symbol.contains("haze") || symbol.contains("smoke") { return .fog }
        if symbol.contains("moon") { return .night }
        if symbol.contains("cloud") && symbol.contains("sun") { return .partlySunny }
        if symbol.contains("sun.max") || symbol == "sun" || symbol == "sun.fill" { return .clear }
        if symbol.contains("partly") && symbol.contains("cloud") { return .partlyCloudy }
        if symbol.contains("cloud") { return .cloudy }
        return nil
    }
}

// MARK: - Widget Weather Models

struct WidgetDataCity: Codable, Hashable, Identifiable {
    let id: String
    let cityName: String
    let timeZoneIdentifier: String?
    let latitude: Double?
    let longitude: Double?
    let daytimeHours: [Int]
    let sunnyHours: [Int]
    let partlySunnyHours: [Int]
    var currentConditionSymbolName: String? = nil
    var daylightBounds: SunnyHoursChartBounds? = nil
    var sunnyWindowDays: [WidgetSunnyWindowDay]? = nil
    var dataIssue: WeatherDataIssue? = nil
}

struct WidgetSunnyWindowDay: Codable, Hashable, Identifiable {
    let date: Date
    let sunnyHours: [Int]
    let partlySunnyHours: [Int]
    var daylightBounds: SunnyHoursChartBounds? = nil
    var dataIssue: WeatherDataIssue? = nil

    var id: Date { date }
}

struct WidgetWeatherSnapshot: Codable, Hashable {
    let fetchedAt: Date
    let timeZoneIdentifier: String?
    var currentConditionSymbolName: String? = nil
    let daytimeHours: [Int]
    let sunnyHours: [Int]
    let partlySunnyHours: [Int]
    var daylightBounds: SunnyHoursChartBounds? = nil
    var sunnyWindowDays: [WidgetSunnyWindowDay]? = nil
    var dataIssue: WeatherDataIssue? = nil
}

extension WidgetWeatherSnapshot {
    init(fetchedAt: Date, city: WidgetDataCity) {
        self.init(
            fetchedAt: fetchedAt,
            timeZoneIdentifier: city.timeZoneIdentifier,
            currentConditionSymbolName: city.currentConditionSymbolName,
            daytimeHours: city.daytimeHours,
            sunnyHours: city.sunnyHours,
            partlySunnyHours: city.partlySunnyHours,
            daylightBounds: city.daylightBounds,
            sunnyWindowDays: city.sunnyWindowDays,
            dataIssue: city.dataIssue
        )
    }
}

// MARK: - Sunny-Hour Chart Models

struct SunnyHoursChartBounds: Codable, Hashable {
    let startHour: Int
    let endHour: Int

    init(startHour: Int, endHour: Int) {
        self.startHour = max(0, min(startHour, 23))
        self.endHour = max(self.startHour + 1, min(endHour, 24))
    }

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

        // MARK: Cross-Midnight Daylight

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

    /// Returns whether the local hourly cell intersects the actual daylight
    /// interval, including daylight that wraps across local midnight.
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

        let hourEnd = hour + 1
        if sunsetHour < sunriseHour {
            return hour < sunsetHour || hourEnd > sunriseHour
        }
        return hourEnd > sunriseHour && hour < sunsetHour
    }

    private static func fractionalHour(for date: Date, timeZone: TimeZone) -> Double? {
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

    static func merged(_ bounds: [SunnyHoursChartBounds]) -> SunnyHoursChartBounds? {
        guard let earliestStart = bounds.map(\.startHour).min(),
              let latestEnd = bounds.map(\.endHour).max() else {
            return nil
        }
        return SunnyHoursChartBounds(startHour: earliestStart, endHour: latestEnd)
    }

    static func covering(hours: [Int]) -> SunnyHoursChartBounds? {
        guard let firstHour = hours.min(), let lastHour = hours.max() else { return nil }
        return SunnyHoursChartBounds(startHour: firstHour, endHour: lastHour + 1)
    }

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

        var result = Array(stride(from: startHour, through: endHour, by: step))
        if result.last != endHour {
            result.append(endHour)
        }
        return result
    }

    func contains(_ hour: Int) -> Bool {
        hour >= startHour && hour < endHour
    }

    func xPosition(for hour: Double, width: CGFloat) -> CGFloat {
        let clampedHour = min(max(hour, Double(startHour)), Double(endHour))
        let fraction = (clampedHour - Double(startHour)) / Double(endHour - startHour)
        return CGFloat(fraction) * width
    }

    /// Positions an absolute instant using the selected city's real local time.
    /// Returning nil outside the chart bounds prevents a misleading edge marker.
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

enum SunnyHourKind: String, Hashable {
    case sunny
    case partlySunny = "partly"
}

struct SunnyHoursTimelineSegment: Identifiable, Hashable {
    let id: String
    let range: ClosedRange<Int>
    let kind: SunnyHourKind

    var isPartlySunny: Bool { kind == .partlySunny }
}

struct SunnyHoursTimelineSpan: Identifiable, Hashable {
    let id: String
    let range: ClosedRange<Int>
    let segments: [SunnyHoursTimelineSegment]
}

enum SunnyHoursTimelineLayout {
    static func spans(
        sunnyRanges: [ClosedRange<Int>],
        partlySunnyRanges: [ClosedRange<Int>]
    ) -> [SunnyHoursTimelineSpan] {
        let segments = makeSegments(ranges: partlySunnyRanges, kind: .partlySunny)
            + makeSegments(ranges: sunnyRanges, kind: .sunny)
        return mergeContiguousSegments(segments.sorted(by: segmentSort))
    }

    static func spans(
        sunnyHours: [Int],
        partlySunnyHours: [Int],
        boundedBy bounds: SunnyHoursChartBounds
    ) -> [SunnyHoursTimelineSpan] {
        spans(
            sunnyRanges: SunnyHoursFormatting.contiguousRanges(in: sunnyHours, boundedBy: bounds),
            partlySunnyRanges: SunnyHoursFormatting.contiguousRanges(in: partlySunnyHours, boundedBy: bounds)
        )
    }

    private static func makeSegments(
        ranges: [ClosedRange<Int>],
        kind: SunnyHourKind
    ) -> [SunnyHoursTimelineSegment] {
        ranges.enumerated().map { index, range in
            SunnyHoursTimelineSegment(
                id: "\(kind.rawValue)-\(index)-\(range.lowerBound)-\(range.upperBound)",
                range: range,
                kind: kind
            )
        }
    }

    nonisolated private static func segmentSort(
        _ lhs: SunnyHoursTimelineSegment,
        _ rhs: SunnyHoursTimelineSegment
    ) -> Bool {
        if lhs.range.lowerBound == rhs.range.lowerBound {
            return lhs.range.upperBound < rhs.range.upperBound
        }
        return lhs.range.lowerBound < rhs.range.lowerBound
    }

    private static func mergeContiguousSegments(
        _ segments: [SunnyHoursTimelineSegment]
    ) -> [SunnyHoursTimelineSpan] {
        guard let firstSegment = segments.first else { return [] }

        var spans: [SunnyHoursTimelineSpan] = []
        var currentSegments = [firstSegment]
        var currentStart = firstSegment.range.lowerBound
        var currentEnd = firstSegment.range.upperBound

        for segment in segments.dropFirst() {
            if segment.range.lowerBound <= currentEnd + 1 {
                currentSegments.append(segment)
                currentEnd = max(currentEnd, segment.range.upperBound)
            } else {
                spans.append(
                    makeSpan(
                        index: spans.count,
                        start: currentStart,
                        end: currentEnd,
                        segments: currentSegments
                    )
                )
                currentSegments = [segment]
                currentStart = segment.range.lowerBound
                currentEnd = segment.range.upperBound
            }
        }

        spans.append(
            makeSpan(
                index: spans.count,
                start: currentStart,
                end: currentEnd,
                segments: currentSegments
            )
        )
        return spans
    }

    private static func makeSpan(
        index: Int,
        start: Int,
        end: Int,
        segments: [SunnyHoursTimelineSegment]
    ) -> SunnyHoursTimelineSpan {
        SunnyHoursTimelineSpan(
            id: "\(start)-\(end)-\(index)",
            range: start...end,
            segments: segments
        )
    }
}

// MARK: - Sunny-Hour Formatting

enum SunnyHoursFormatting {
    static func contiguousRanges(
        in sourceHours: [Int],
        boundedBy bounds: SunnyHoursChartBounds? = nil
    ) -> [ClosedRange<Int>] {
        let hours = Array(Set(sourceHours.filter { bounds?.contains($0) ?? true })).sorted()
        guard let firstHour = hours.first else { return [] }

        var ranges: [ClosedRange<Int>] = []
        var start = firstHour
        var end = firstHour

        for hour in hours.dropFirst() {
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

    /// Fixed-width 24-hour label used on compact chart axes.
    nonisolated static func chartHourLabel(_ hour: Int) -> String {
        // Keep the right edge of a full local-day chart distinct from its 00
        // start. This is a boundary label, not another midnight forecast cell.
        hour == 24 ? "24" : String(format: "%02d", ((hour % 24) + 24) % 24)
    }

    static func chartRangeText(for hours: [Int]) -> String {
        rangeText(for: hours, hourLabel: chartHourLabel)
    }

    static func localizedRangeText(for hours: [Int], locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)

        return rangeText(for: hours) { hour in
            var components = DateComponents()
            components.calendar = Calendar(identifier: .gregorian)
            components.hour = hour % 24
            components.minute = 0
            guard let date = components.date else { return chartHourLabel(hour) }
            return formatter.string(from: date)
        }
    }

    private static func rangeText(
        for hours: [Int],
        hourLabel: (Int) -> String
    ) -> String {
        contiguousRanges(in: hours)
            .map { range in
                "\(hourLabel(range.lowerBound))–\(hourLabel(range.upperBound + 1))"
            }
            .joined(separator: ", ")
    }
}

// MARK: - Widget Catalog Models

struct WidgetDataList: Codable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let cities: [WidgetDataCity]
}

struct WidgetDataCatalog: Codable, Hashable {
    let lists: [WidgetDataList]
    var appLanguageIdentifier: String? = nil
}

// MARK: - Shared Widget Persistence

enum WidgetDataStore {
    static let appGroupIdentifier = "group.Yutao-Wu.Weather"
    static let catalogKey = "bestSunnyPlacesWidgetCatalog"
    static let kind = "BestSunnyPlacesWidget"
    static let weatherCacheKeyPrefix = "widgetWeatherSnapshot."
    static let weatherCacheDuration: TimeInterval = 30 * 60

    static func cityIdentifier(country: String, latitude: Double, longitude: Double, listID: String) -> String {
        let latitude = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), latitude)
        let longitude = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), longitude)
        return "\(listID)|\(country)|\(latitude)|\(longitude)"
    }

    static func catalog() -> WidgetDataCatalog? {
        guard let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: catalogKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetDataCatalog.self, from: data)
    }

    static var appLocale: Locale {
        guard let identifier = catalog()?.appLanguageIdentifier, !identifier.isEmpty else {
            return .autoupdatingCurrent
        }
        return Locale(identifier: identifier)
    }

    static func save(_ catalog: WidgetDataCatalog) {
        guard let data = try? JSONEncoder().encode(catalog) else { return }
        UserDefaults(suiteName: appGroupIdentifier)?.set(data, forKey: catalogKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func weatherSnapshot(for cityID: String, now: Date = .now) -> WidgetWeatherSnapshot? {
        guard let snapshot = latestWeatherSnapshot(for: cityID),
              now.timeIntervalSince(snapshot.fetchedAt) < weatherCacheDuration else {
            return nil
        }
        return snapshot
    }

    /// Returns the last real WeatherKit result even when it is older than the
    /// normal widget freshness window. The provider can display it while asking
    /// WidgetKit for a short retry instead of replacing it with invented data.
    static func latestWeatherSnapshot(for cityID: String) -> WidgetWeatherSnapshot? {
        guard let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: weatherCacheKey(for: cityID)) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetWeatherSnapshot.self, from: data)
    }

    static func saveWeatherSnapshot(_ snapshot: WidgetWeatherSnapshot, for cityID: String) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: appGroupIdentifier)?.set(data, forKey: weatherCacheKey(for: cityID))
    }

    private static func weatherCacheKey(for cityID: String) -> String {
        "\(weatherCacheKeyPrefix)\(cityID)"
    }
}
