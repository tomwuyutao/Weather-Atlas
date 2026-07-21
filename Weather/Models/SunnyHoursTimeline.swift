//
//  SunnyHoursTimeline.swift
//  Weather
//
//  Purpose: Defines shared sunny-hour chart bounds, segments, layout, and formatting.
//

import Foundation

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

}
