//
//  SunnyHoursTimeline.swift
//  Weather
//
//  Purpose: Defines shared sunny-hour chart bounds, segments, layout, and formatting.
//

import Foundation

// MARK: - Sunny-Hour Chart Models

/// Integer-hour chart domain derived exclusively from real solar-event times.
struct SunnyHoursChartBounds: Codable, Hashable {
    /// Inclusive first hour represented by the chart.
    let startHour: Int
    /// Exclusive upper hour boundary represented by the chart.
    let endHour: Int

    /// Creates a valid nonempty domain, clamping the end after the start.
    init(startHour: Int, endHour: Int) {
        self.startHour = max(0, min(startHour, 23))
        self.endHour = max(self.startHour + 1, min(endHour, 24))
    }

    /// Derives chart bounds from sunrise and sunset in the city's timezone.
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
    /// Tests whether a forecast's one-hour interval intersects actual daylight.
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

    /// Converts an instant into a decimal clock hour in the requested timezone.
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

    /// Returns the smallest domain containing every supplied nonempty bound.
    static func merged(_ bounds: [SunnyHoursChartBounds]) -> SunnyHoursChartBounds? {
        guard let earliestStart = bounds.map(\.startHour).min(),
              let latestEnd = bounds.map(\.endHour).max() else {
            return nil
        }
        return SunnyHoursChartBounds(startHour: earliestStart, endHour: latestEnd)
    }

    /// Chooses evenly spaced integer tick hours within the real domain.
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

    /// Whether an integer clock hour begins inside this chart domain.
    func contains(_ hour: Int) -> Bool {
        hour >= startHour && hour < endHour
    }

    /// Maps a decimal clock hour into a clamped horizontal chart coordinate.
    func xPosition(for hour: Double, width: CGFloat) -> CGFloat {
        let clampedHour = min(max(hour, Double(startHour)), Double(endHour))
        let fraction = (clampedHour - Double(startHour)) / Double(endHour - startHour)
        return CGFloat(fraction) * width
    }

    /// Positions an absolute instant using the selected city's real local time.
    /// Returning nil outside the chart bounds prevents a misleading edge marker.
    /// Maps current city-local time to the chart, or hides it outside daylight.
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

    /// Returns the rendered width of an inclusive integer-hour range.
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

/// Visual classification for a favorable hourly forecast segment.
enum SunnyHourKind: String, Hashable {
    case sunny
    case partlySunny = "partly"
}

/// Contiguous run of sunny or partly sunny integer hours.
struct SunnyHoursTimelineSegment: Identifiable, Hashable {
    /// Deterministic range-and-kind identity for SwiftUI diffing.
    let id: String
    /// Inclusive clock-hour range covered by the segment.
    let range: ClosedRange<Int>
    /// Condition treatment used to render the segment.
    let kind: SunnyHourKind

    /// Convenience flag used by chart fill and accessibility styling.
    var isPartlySunny: Bool { kind == .partlySunny }
}

/// Outer contiguous capsule containing one or more condition segments.
struct SunnyHoursTimelineSpan: Identifiable, Hashable {
    /// Deterministic range identity for SwiftUI diffing.
    let id: String
    /// Inclusive hours covered without an unfavorable gap.
    let range: ClosedRange<Int>
    /// Ordered sunny/partly-sunny runs clipped into this capsule.
    let segments: [SunnyHoursTimelineSegment]
}

/// Pure transformations from classified hours into renderable chart spans.
enum SunnyHoursTimelineLayout {
    /// Builds spans from separate sunny and partly-sunny hour collections.
    static func spans(
        sunnyRanges: [ClosedRange<Int>],
        partlySunnyRanges: [ClosedRange<Int>]
    ) -> [SunnyHoursTimelineSpan] {
        let segments = makeSegments(ranges: partlySunnyRanges, kind: .partlySunny)
            + makeSegments(ranges: sunnyRanges, kind: .sunny)
        // Order by start hour, giving the shorter segment precedence on ties.
        return mergeContiguousSegments(segments.sorted {
            if $0.range.lowerBound == $1.range.lowerBound {
                return $0.range.upperBound < $1.range.upperBound
            }
            return $0.range.lowerBound < $1.range.lowerBound
        })
    }

    /// Builds spans from precomputed segments after sorting and merging them.
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

    /// Converts integer hours of one kind into normalized contiguous segments.
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

    /// Coalesces touching equal-kind segments without bridging real gaps.
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

    /// Wraps a connected segment collection in its enclosing capsule range.
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

/// Shared deterministic formatting for chart ranges and axis labels.
enum SunnyHoursFormatting {
    /// Converts integer hours into maximal contiguous inclusive ranges.
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
    /// Formats a 24-hour integer as a compact fixed English chart tick.
    nonisolated static func chartHourLabel(_ hour: Int) -> String {
        // Keep the right edge of a full local-day chart distinct from its 00
        // start. This is a boundary label, not another midnight forecast cell.
        hour == 24 ? "24" : String(format: "%02d", ((hour % 24) + 24) % 24)
    }

}
