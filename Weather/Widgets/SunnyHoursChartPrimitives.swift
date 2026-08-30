//
//  SunnyHoursChartPrimitives.swift
//  Weather
//
//  Purpose: Renders the shared sunny-hours chart shapes used by the app and
//  Home Screen widgets. Each surface adapts its weather data and container,
//  while the capsule geometry, colours, and exposed rounded ends stay unified.
//

import SwiftUI

// MARK: - Shared Chart Inputs

/// The small set of visual track colors. It controls only capsule tint; the
/// current-condition icons keep rendering WeatherKit's original symbol.
enum SunnyHoursChartCondition: Hashable {
    case sun
    case partlySunny
    case rain
    case drizzle
    case noSun

    init(weatherCondition: AppWeatherCondition?) {
        guard let weatherCondition else {
            self = .noSun
            return
        }

        switch weatherCondition.iconTone {
        case .clear:
            self = .sun
        case .partlySunny:
            self = .partlySunny
        case .rain:
            self = .rain
        case .drizzle:
            self = .drizzle
        case .cloudy:
            self = .noSun
        }
    }
}

/// One daylight forecast hour reduced to the presentation values required by
/// both the app and widget chart renderers.
struct SunnyHoursChartHour: Identifiable {
    /// Absolute forecast instant, including distinction across DST repeats.
    let date: Date
    /// City-local hour used to position the cell in the chart domain.
    let hour: Int
    /// Presentation-only track color selected from the API condition.
    let condition: SunnyHoursChartCondition

    init(date: Date, hour: Int, condition: SunnyHoursChartCondition) {
        self.date = date
        self.hour = hour
        self.condition = condition
    }

    init(date: Date, hour: Int, condition: AppWeatherCondition?) {
        self.init(
            date: date,
            hour: hour,
            condition: SunnyHoursChartCondition(weatherCondition: condition)
        )
    }

    var id: Date { date }
}

/// The semantic colours required by the shared timeline shapes. Containers own
/// their palette policy, including WidgetKit's tinted and monochrome modes.
struct SunnyHoursChartColors {
    let primary: Color
    let secondary: Color
    let sun: Color
    let partlySunny: Color
    let rain: Color
    let drizzle: Color
    let noSun: Color

    /// Matches the app's sunny-hours policy: clear and mostly-clear hours use
    /// their distinct sunny colors, rain and drizzle retain their own colors,
    /// and all other conditions are neutral daylight.
    func color(for condition: SunnyHoursChartCondition) -> Color {
        switch condition {
        case .sun:
            sun
        case .partlySunny:
            partlySunny
        case .rain:
            rain
        case .drizzle:
            drizzle
        case .noSun:
            noSun
        }
    }
}

// MARK: - Daily Discrete Capsule Timeline

/// Shared current-day timeline used by the app's Daily Sunny Hours card and
/// the Medium Home Screen widget. The callers provide only data, colour policy,
/// and their outer chrome; every capsule, gap, marker, and axis position comes
/// from this one view.
struct SunnyHoursDiscreteCapsuleTimeline: View {
    // MARK: - Configuration

    /// Surface-specific space constraints without changing chart geometry.
    struct Configuration {
        let capsuleSpacing: CGFloat
        /// Optional cap for a single vertical capsule. Extra horizontal room is
        /// distributed between capsules so the timeline still fills its track.
        let maximumCapsuleWidth: CGFloat?
        let minimumTrackHeight: CGFloat
        let axisHeight: CGFloat

        static let appAndHome = Configuration(
            capsuleSpacing: 7,
            maximumCapsuleWidth: nil,
            minimumTrackHeight: 44,
            axisHeight: 14
        )

    }

    // MARK: - Inputs

    /// One visible daylight capsule per source hour.
    let hours: [SunnyHoursChartHour]
    /// Inclusive-start, exclusive-end local-hour domain.
    let bounds: SunnyHoursChartBounds
    /// Timeline entry time, used only for a current-time marker.
    let currentDate: Date
    /// The app hides the marker when the user has selected a non-current day.
    let showsCurrentTimeMarker: Bool
    /// Family-specific vertical space and axis treatment.
    let configuration: Configuration
    /// Surface-owned semantic colour policy.
    let colors: SunnyHoursChartColors

    private static let maximumPhoneTimelineWidth: CGFloat = 360

    // MARK: - Layout Types

    /// An x-axis label mapped to an actual displayed capsule index.
    private struct AxisMarker: Identifiable {
        let hour: Int
        let capsuleIndex: Int

        var id: Int { hour }
    }

    /// Shared dimensions for the capsule row and its axis.
    private struct TimelineMetrics {
        let capsuleWidth: CGFloat
        let spacing: CGFloat
    }

    // MARK: - Rendering

    var body: some View {
        if let startHour = hours.first?.hour {
            VStack(spacing: 4) {
                GeometryReader { proxy in
                    let capsuleHeight = proxy.size.height
                    let metrics = timelineMetrics(
                        for: hours.count,
                        availableWidth: proxy.size.width
                    )

                    ZStack(alignment: .leading) {
                        HStack(spacing: metrics.spacing) {
                            ForEach(hours) { hour in
                                Capsule()
                                    .fill(colors.color(for: hour.condition))
                                    .frame(width: metrics.capsuleWidth)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if let slotPosition = currentTimeSlotPosition() {
                            Rectangle()
                                .fill(colors.primary.opacity(0.9))
                                .frame(width: 2, height: capsuleHeight)
                                .position(
                                    x: currentTimeMarkerX(
                                        for: slotPosition,
                                        capsuleWidth: metrics.capsuleWidth,
                                        slotCount: hours.count,
                                        spacing: metrics.spacing
                                    ),
                                    y: capsuleHeight / 2
                                )
                        }
                    }
                    .frame(height: capsuleHeight, alignment: .top)
                }
                .frame(minHeight: configuration.minimumTrackHeight)

                axis(for: startHour)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            EmptyView()
        }
    }

    // MARK: - Axis

    @ViewBuilder
    private func axis(for startHour: Int) -> some View {
        let markers = timelineAxisMarkers(from: startHour)
        GeometryReader { proxy in
            let metrics = timelineMetrics(
                for: hours.count,
                availableWidth: proxy.size.width
            )

            ZStack(alignment: .leading) {
                ForEach(markers) { marker in
                    Text(SunnyHoursFormatting.chartHourLabel(marker.hour))
                        .position(
                            x: CGFloat(marker.capsuleIndex)
                                * (metrics.capsuleWidth + metrics.spacing)
                                + metrics.capsuleWidth / 2,
                            y: proxy.size.height / 2
                        )
                }
            }
        }
        .frame(height: configuration.axisHeight)
        .font(.caption2.weight(.medium))
        .foregroundStyle(colors.secondary)
        .lineLimit(1)
    }

    // MARK: - Current-Time Marker

    /// Finds the exact fractional position within the covering hourly capsule,
    /// clamping times outside the daylight window to its leading/trailing edge.
    private func currentTimeSlotPosition() -> Double? {
        guard showsCurrentTimeMarker,
              !hours.isEmpty,
              let firstDate = hours.first?.date,
              let lastDate = hours.last?.date else {
            return nil
        }

        if currentDate < firstDate {
            return 0
        }
        if currentDate >= lastDate.addingTimeInterval(60 * 60) {
            return Double(hours.count)
        }

        if let currentIndex = hours.firstIndex(where: {
            $0.date <= currentDate
                && currentDate < $0.date.addingTimeInterval(60 * 60)
        }) {
            let elapsed = currentDate.timeIntervalSince(hours[currentIndex].date)
            return Double(currentIndex) + min(max(elapsed / 3600, 0), 1)
        }

        // A missing source hour remains a gap, not a fabricated capsule. Place
        // the marker at the boundary before the first later source record.
        return Double(hours.firstIndex(where: { $0.date > currentDate }) ?? hours.count)
    }

    /// Interpolates between capsule boundaries so minutes advance smoothly.
    private func currentTimeMarkerX(
        for slotPosition: Double,
        capsuleWidth: CGFloat,
        slotCount: Int,
        spacing: CGFloat
    ) -> CGFloat {
        func boundaryX(_ boundaryIndex: Int) -> CGFloat {
            if boundaryIndex <= 0 { return 0 }
            if boundaryIndex >= slotCount {
                return CGFloat(slotCount) * capsuleWidth
                    + CGFloat(max(slotCount - 1, 0)) * spacing
            }
            return CGFloat(boundaryIndex) * capsuleWidth
                + (CGFloat(boundaryIndex) - 0.5) * spacing
        }

        let clamped = min(max(slotPosition, 0), Double(slotCount))
        let lower = Int(floor(clamped))
        let upper = Int(ceil(clamped))
        guard lower != upper else { return boundaryX(lower) }
        let fraction = CGFloat(clamped - Double(lower))
        let lowerX = boundaryX(lower)
        return lowerX + (boundaryX(upper) - lowerX) * fraction
    }

    // MARK: - Layout Calculation

    /// Scales capsule widths and gaps to fill the offered width. A caller may
    /// cap the capsule width; any remaining width becomes inter-capsule space.
    private func timelineMetrics(
        for slotCount: Int,
        availableWidth: CGFloat
    ) -> TimelineMetrics {
        guard slotCount > 0, availableWidth > 0 else {
            return TimelineMetrics(capsuleWidth: 0, spacing: 0)
        }

        let compactWidth = min(
            availableWidth,
            Self.maximumPhoneTimelineWidth
        )
        let compactSpacing = slotCount > 1
            ? min(
                configuration.capsuleSpacing,
                compactWidth / CGFloat(slotCount - 1)
            )
            : 0
        let compactCapsuleWidth = max(
            0,
            (
                compactWidth
                    - compactSpacing * CGFloat(slotCount - 1)
            ) / CGFloat(slotCount)
        )
        let scale = availableWidth / compactWidth
        let uncappedCapsuleWidth = compactCapsuleWidth * scale
        let capsuleWidth = min(
            uncappedCapsuleWidth,
            configuration.maximumCapsuleWidth ?? uncappedCapsuleWidth
        )
        let spacing: CGFloat
        if slotCount > 1 {
            spacing = max(
                0,
                (availableWidth - capsuleWidth * CGFloat(slotCount))
                    / CGFloat(slotCount - 1)
            )
        } else {
            spacing = 0
        }
        return TimelineMetrics(
            capsuleWidth: capsuleWidth,
            spacing: spacing
        )
    }

    // MARK: - Axis Calculation

    /// Maps four evenly-spaced desired labels to actual capsule centers.
    private func timelineAxisMarkers(from startHour: Int) -> [AxisMarker] {
        guard !hours.isEmpty else { return [] }

        let span = max(bounds.endHour - startHour, 0)
        let axisHours = (0...3).reduce(into: [Int]()) { values, index in
            let hour = startHour
                + Int((Double(span) * Double(index) / 3).rounded())
            if values.last != hour {
                values.append(hour)
            }
        }

        return axisHours.enumerated().map { axisIndex, hour in
            let capsuleIndex: Int
            if axisIndex == 0 {
                capsuleIndex = 0
            } else if axisIndex == axisHours.count - 1 {
                capsuleIndex = hours.count - 1
            } else {
                capsuleIndex = hours.enumerated().min {
                    abs($0.element.hour - hour) < abs($1.element.hour - hour)
                }?.offset ?? 0
            }
            return AxisMarker(hour: hour, capsuleIndex: capsuleIndex)
        }
    }
}

// MARK: - Multi-Day Continuous Capsule Track

/// Shared one-row ten-day chart. It keeps joins square between adjacent weather
/// runs but rounds each exposed end, so app and Large Home Screen widget rows
/// cannot drift into different capsule shapes.
struct SunnyHoursContinuousCapsuleTrack: View {
    // MARK: - Inputs

    /// Source hour cells for one city-local day.
    let hours: [SunnyHoursChartHour]
    /// Shared local-hour domain for all rows.
    let bounds: SunnyHoursChartBounds
    /// Surface-owned colours.
    let colors: SunnyHoursChartColors
    /// Visible lane thickness.
    let height: CGFloat
    /// Optional app-only selection outline.
    var outlineColor: Color? = nil
    /// Optional app-only selection outline width.
    var outlineLineWidth: CGFloat = 1.5

    // MARK: - Segment Model

    private struct ColorSegment: Identifiable {
        let id: Date
        let startPosition: Double
        var endPosition: Double
        let condition: SunnyHoursChartCondition
        var leadingNeighborCondition: SunnyHoursChartCondition?
        var trailingNeighborCondition: SunnyHoursChartCondition?
    }

    /// A local clock-hour lane after repeated DST hours have been divided into
    /// equal sub-slots. Both occurrences remain visible without drawing two
    /// forecast records on top of each other.
    private struct PositionedHour {
        let id: Date
        let startPosition: Double
        let endPosition: Double
        let condition: SunnyHoursChartCondition
    }

    // MARK: - Rendering

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(colors.noSun)

                ForEach(colorSegments) { segment in
                    segmentShape(for: segment)
                        .fill(colors.color(for: segment.condition))
                        .frame(
                            width: max(
                                bounds.xPosition(
                                    for: segment.endPosition,
                                    width: proxy.size.width
                                ) - bounds.xPosition(
                                    for: segment.startPosition,
                                    width: proxy.size.width
                                ),
                                1
                            )
                        )
                        .offset(
                            x: bounds.xPosition(
                                for: segment.startPosition,
                                width: proxy.size.width
                            )
                        )
                }
            }
            .overlay {
                if let outlineColor {
                    Capsule()
                        .stroke(outlineColor, lineWidth: outlineLineWidth)
                }
            }
        }
        .frame(height: height)
    }

    // MARK: - Segment Construction

    /// Groups adjacent equal conditions into a single visual run.
    private var colorSegments: [ColorSegment] {
        var segments = positionedHours.reduce(into: [ColorSegment]()) { segments, hour in
            if let previous = segments.last,
               previous.condition == hour.condition,
               approximatelyEqual(hour.startPosition, previous.endPosition) {
                segments[segments.count - 1].endPosition = hour.endPosition
            } else {
                segments.append(
                    ColorSegment(
                        id: hour.id,
                        startPosition: hour.startPosition,
                        endPosition: hour.endPosition,
                        condition: hour.condition,
                        leadingNeighborCondition: nil,
                        trailingNeighborCondition: nil
                    )
                )
            }
        }

        for index in segments.indices {
            if index > segments.startIndex,
               approximatelyEqual(
                   segments[index - 1].endPosition,
                   segments[index].startPosition
               ) {
                segments[index].leadingNeighborCondition = segments[index - 1].condition
            }
            if index < segments.index(before: segments.endIndex),
               approximatelyEqual(
                   segments[index].endPosition,
                   segments[index + 1].startPosition
               ) {
                segments[index].trailingNeighborCondition = segments[index + 1].condition
            }
        }
        return segments
    }

    /// Converts repeated local hours on a daylight-saving fall-back day into
    /// non-overlapping fractions of that clock-hour lane. Normal days retain
    /// the exact integer-hour geometry used throughout the app.
    private var positionedHours: [PositionedHour] {
        let sortedHours = hours.sorted { $0.date < $1.date }
        let occurrenceCounts = Dictionary(
            grouping: sortedHours,
            by: \.hour
        ).mapValues(\.count)
        var occurrenceIndices: [Int: Int] = [:]

        return sortedHours.map { hour in
            let count = max(occurrenceCounts[hour.hour] ?? 1, 1)
            let index = occurrenceIndices[hour.hour, default: 0]
            occurrenceIndices[hour.hour] = index + 1
            let slotWidth = 1 / Double(count)
            let startPosition = Double(hour.hour) + Double(index) * slotWidth
            return PositionedHour(
                id: hour.date,
                startPosition: startPosition,
                endPosition: startPosition + slotWidth,
                condition: hour.condition
            )
        }
    }

    /// Only exposed ends round; adjoining coloured weather runs retain their
    /// square shared edge and read as a continuous hourly forecast.
    private func segmentShape(for segment: ColorSegment) -> UnevenRoundedRectangle {
        let squaresLeadingEdge = segment.leadingNeighborCondition.map(isColoredCondition) == true
        let squaresTrailingEdge = segment.trailingNeighborCondition.map(isColoredCondition) == true
        let radius = height / 2
        return UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: squaresLeadingEdge ? 0 : radius,
                bottomLeading: squaresLeadingEdge ? 0 : radius,
                bottomTrailing: squaresTrailingEdge ? 0 : radius,
                topTrailing: squaresTrailingEdge ? 0 : radius
            ),
            style: .continuous
        )
    }

    private func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.000_001
    }

    private func isColoredCondition(_ condition: SunnyHoursChartCondition) -> Bool {
        switch condition {
        case .sun, .partlySunny, .rain, .drizzle:
            true
        case .noSun:
            false
        }
    }
}
