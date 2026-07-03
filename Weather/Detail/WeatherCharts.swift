//
//  WeatherCharts.swift
//  Weather
//
//  Purpose: Draws reusable hourly and daily weather charts for detail cards,
//  including metric switching, time ranges, and swipe navigation.
//

import SwiftUI
import Charts

// MARK: - Chart Configuration

enum WeatherChartMetric: Hashable {
    case temperature, feelsLike, cloudCover, precipitation
    case windSpeed, uvIndex, humidity, visibility

    var fixedDomain: ClosedRange<Double>? {
        switch self {
        case .cloudCover, .precipitation, .humidity:
            return 0...100
        case .uvIndex:
            return 0...11
        case .temperature, .feelsLike, .windSpeed, .visibility:
            return nil
        }
    }
}

enum WeatherChartTimeRange: Hashable {
    case daytime, entireDay, tenDay
}

// MARK: - Internal Chart Point

private struct ChartPoint: Identifiable {
    let id: String
    let index: Int
    let label: String
    let icon: String
    let value: Double
    let valueText: String
    let isPast: Bool
}

private struct ChartLineSegment: Identifiable {
    let id: String
    let start: ChartPoint
    let end: ChartPoint

    var points: [ChartPoint] { [start, end] }
    var isFutureSegment: Bool { !start.isPast && !end.isPast }
}

// MARK: - Hourly Chart

struct HourlyTimelineChart: View {
    let hourlyForecasts: [HourlyForecast]
    var chartMetric: WeatherChartMetric = .temperature
    var dayOffset: Int = 0
    var cityTimeZone: TimeZone = .current
    var previewCurrentHour: Int? = nil
    var lineColor: Color = AppTheme.shared.colors.accent
    var showAllHours: Bool = false
    var compactLayout: Bool = false
    var placesLabelsBelowChart: Bool = false
    var showsPointValueLabels: Bool = false
    var showsSelectedIndicator: Bool = true
    var showsValueRow: Bool = true
    var labelStride: Int = 1
    var showsYAxis: Bool = false
    var showsChartBackground: Bool = false
    var chartBottomSpacing: CGFloat? = nil
    var transitionDirection: Int = 1
    var onHorizontalSwipe: ((Int) -> Void)? = nil

    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.defaultRawValue

    private var tempUnit: TemperatureUnit { TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic }
    private var distUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .automatic }
    private var indicatorLineColor: Color { colorScheme == .dark ? .white : AppTheme.shared.colors.listCardFill.compatMix(with: .black, by: 0.25) }
    private var totalHeight: CGFloat {
        compactLayout ? 230 : 250
    }
    private var chartHeight: CGFloat {
        compactLayout ? 132 : 146
    }
    private var labelSpacing: CGFloat {
        compactLayout ? 6 : 10
    }

    private var currentCityHour: Double? {
        guard dayOffset == 0 || dayOffset == -1 else { return nil }
        if let previewCurrentHour { return Double(previewCurrentHour) }
        var calendar = Calendar.current
        calendar.timeZone = cityTimeZone
        let components = calendar.dateComponents([.hour, .minute], from: Date())
        return Double(components.hour ?? 0) + (Double(components.minute ?? 0) / 60)
    }

    private var dataPoints: [HourlyForecast] {
        let sortedForecasts = hourlyForecasts.sorted { $0.hour < $1.hour }
        guard !showAllHours else { return sortedForecasts }
        let daytimeForecasts = sortedForecasts.filter { [7, 9, 11, 13, 15, 17, 19].contains($0.hour) }
        return daytimeForecasts
    }

    private var chartPoints: [ChartPoint] {
        dataPoints.enumerated().compactMap { index, forecast in
            guard let value = value(for: forecast) else { return nil }
            return ChartPoint(
                id: forecast.id.uuidString,
                index: index,
                label: forecast.shortFormattedHour(locale: locale),
                icon: forecast.weatherIcon,
                value: value,
                valueText: chartValueText(for: forecast),
                isPast: isPastHour(forecast.hour)
            )
        }
    }

    private var chartDomain: ClosedRange<Double> {
        if let fixedDomain = chartMetric.fixedDomain {
            return fixedDomain
        }

        let values = chartPoints.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let padding = max((maxValue - minValue) * (compactLayout ? 0.55 : 0.35), compactLayout ? 4.0 : 2.0)
        return (minValue - padding)...(maxValue + padding)
    }

    private var currentHourIndex: Double? {
        guard let currentCityHour else { return nil }
        let hours = dataPoints.map(\.hour)
        guard let lastIndex = hours.lastIndex(where: { Double($0) <= currentCityHour }), lastIndex < hours.count - 1 else { return nil }
        let h0 = Double(hours[lastIndex])
        let h1 = Double(hours[lastIndex + 1])
        let fraction = h1 > h0 ? (currentCityHour - h0) / (h1 - h0) : 0
        return Double(lastIndex) + fraction
    }

    private func isPastHour(_ hour: Int) -> Bool {
        guard let currentCityHour else { return false }
        return Double(hour) < currentCityHour
    }

    private func chartValueText(for forecast: HourlyForecast) -> String {
        switch chartMetric {
        case .temperature: return tempUnit.display(forecast.temperature)
        case .feelsLike: return forecast.apparentTemperature.map { tempUnit.display($0) } ?? "-"
        case .cloudCover: return forecast.cloudCoverPercent.map { "\($0)%" } ?? "-"
        case .precipitation: return forecast.precipitationChance.map { "\(Int($0 * 100))%" } ?? "-"
        case .windSpeed: return forecast.windSpeed.map { distUnit.resolved == .miles ? "\(Int($0 * 0.621371))" : "\(Int($0))" } ?? "-"
        case .uvIndex: return forecast.uvIndex.map { "\($0)" } ?? "-"
        case .humidity: return forecast.humidity.map { "\(Int($0 * 100))%" } ?? "-"
        case .visibility: return forecast.visibility.map { distUnit.resolved == .miles ? "\(Int($0 * 0.621371))" : "\(Int($0))" } ?? "-"
        }
    }

    private func value(for forecast: HourlyForecast) -> Double? {
        switch chartMetric {
        case .temperature: return forecast.temperature
        case .feelsLike: return forecast.apparentTemperature
        case .cloudCover: return forecast.cloudCoverPercent.map(Double.init)
        case .precipitation: return forecast.precipitationChance.map { $0 * 100 }
        case .windSpeed: return forecast.windSpeed
        case .uvIndex: return forecast.uvIndex.map(Double.init)
        case .humidity: return forecast.humidity.map { $0 * 100 }
        case .visibility: return forecast.visibility
        }
    }

    private var missingDataTitle: String {
        localizedString("Missing \(metricName) data", locale: locale)
    }

    private var metricName: String {
        switch chartMetric {
        case .temperature: return localizedString("temperature", locale: locale)
        case .feelsLike: return localizedString("feels-like", locale: locale)
        case .cloudCover: return localizedString("cloud cover", locale: locale)
        case .precipitation: return localizedString("precipitation", locale: locale)
        case .windSpeed: return localizedString("wind speed", locale: locale)
        case .uvIndex: return localizedString("UV index", locale: locale)
        case .humidity: return localizedString("humidity", locale: locale)
        case .visibility: return localizedString("visibility", locale: locale)
        }
    }

    var body: some View {
        TimelineChartBody(
            points: chartPoints,
            domain: chartDomain,
            selectedIndex: currentHourIndex,
            lineColor: lineColor,
            indicatorColor: indicatorLineColor,
            totalHeight: totalHeight,
            chartHeight: chartHeight,
            labelSpacing: labelSpacing,
            compactLayout: compactLayout,
            placesLabelsBelowChart: placesLabelsBelowChart,
            showsPointValueLabels: showsPointValueLabels,
            showsSelectedIndicator: showsSelectedIndicator,
            showsValueRow: showsValueRow,
            labelStride: labelStride,
            showsYAxis: showsYAxis,
            showsChartBackground: showsChartBackground,
            chartBottomSpacing: chartBottomSpacing,
            emptyTitle: missingDataTitle,
            transitionID: "hourly-\(dayOffset)-\(chartMetric)-\(showAllHours)",
            transitionDirection: transitionDirection,
            onHorizontalSwipe: onHorizontalSwipe
        )
    }
}

// MARK: - Daily Chart

struct DailyTimelineChart: View {
    let dailyForecasts: [DailyForecast]
    var chartMetric: WeatherChartMetric = .temperature
    var selectedDayOffset: Int = 0
    var cityTimeZone: TimeZone = .current
    var lineColor: Color = AppTheme.shared.colors.accent
    var compactLayout: Bool = false
    var placesLabelsBelowChart: Bool = false
    var showsPointValueLabels: Bool = false
    var showsSelectedIndicator: Bool = true
    var showsValueRow: Bool = true
    var labelStride: Int = 1
    var showsYAxis: Bool = false
    var showsChartBackground: Bool = false
    var chartBottomSpacing: CGFloat? = nil

    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.defaultRawValue

    private var tempUnit: TemperatureUnit { TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic }
    private var distUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .automatic }
    private var indicatorLineColor: Color { colorScheme == .dark ? .white : AppTheme.shared.colors.listCardFill.compatMix(with: .black, by: 0.25) }
    private var totalHeight: CGFloat {
        compactLayout ? 230 : 250
    }
    private var chartHeight: CGFloat {
        compactLayout ? 132 : 146
    }
    private var labelSpacing: CGFloat {
        compactLayout ? 6 : 10
    }
    private var dataPoints: [DailyForecast] { dailyForecasts.sorted { $0.dayOffset < $1.dayOffset } }

    private var chartPoints: [ChartPoint] {
        dataPoints.enumerated().compactMap { index, forecast in
            guard let value = value(for: forecast) else { return nil }
            return ChartPoint(
                id: forecast.id.uuidString,
                index: index,
                label: dayLabel(for: forecast),
                icon: forecast.weatherIcon,
                value: value,
                valueText: chartValueText(for: forecast),
                isPast: false
            )
        }
    }

    private var selectedIndex: Double? {
        dataPoints.firstIndex(where: { $0.dayOffset == (selectedDayOffset == -1 ? 0 : selectedDayOffset) }).map(Double.init)
    }

    private var chartDomain: ClosedRange<Double> {
        if let fixedDomain = chartMetric.fixedDomain {
            return fixedDomain
        }

        let values = chartPoints.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let padding = max((maxValue - minValue) * (compactLayout ? 0.55 : 0.35), compactLayout ? 4.0 : 2.0)
        return (minValue - padding)...(maxValue + padding)
    }

    private func dayLabel(for forecast: DailyForecast) -> String {
        var cityCalendar = Calendar.current
        cityCalendar.timeZone = cityTimeZone
        let cityToday = cityCalendar.startOfDay(for: Date())
        guard let date = cityCalendar.date(byAdding: .day, value: forecast.dayOffset, to: cityToday) else { return "" }
        if forecast.dayOffset == 0 { return localizedString("Today", locale: locale) }
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "EEE", options: 0, locale: locale)
        formatter.locale = locale
        formatter.timeZone = cityTimeZone
        return formatter.string(from: date)
    }

    private func value(for forecast: DailyForecast) -> Double? {
        switch chartMetric {
        case .temperature: return forecast.dailyHigh
        case .feelsLike: return forecast.feelsLikeHigh
        case .cloudCover: return forecast.cloudCover.map { $0 * 100 }
        case .precipitation: return forecast.precipitationChance.map { $0 * 100 }
        case .windSpeed: return forecast.windSpeed
        case .uvIndex: return forecast.uvIndex.map(Double.init)
        case .humidity: return forecast.maxHumidity.map { $0 * 100 }
        case .visibility: return forecast.maxVisibility
        }
    }

    private func chartValueText(for forecast: DailyForecast) -> String {
        switch chartMetric {
        case .temperature: return tempUnit.display(forecast.dailyHigh)
        case .feelsLike: return forecast.feelsLikeHigh.map { tempUnit.display($0) } ?? "-"
        case .cloudCover: return forecast.cloudCover.map { "\(Int($0 * 100))%" } ?? "-"
        case .precipitation: return forecast.precipitationChance.map { "\(Int($0 * 100))%" } ?? "-"
        case .windSpeed: return forecast.windSpeed.map { distUnit.resolved == .miles ? "\(Int($0 * 0.621371))" : "\(Int($0))" } ?? "-"
        case .uvIndex: return forecast.uvIndex.map { "\($0)" } ?? "-"
        case .humidity: return forecast.maxHumidity.map { "\(Int($0 * 100))%" } ?? "-"
        case .visibility: return forecast.maxVisibility.map { distUnit.resolved == .miles ? "\(Int($0 * 0.621371))" : "\(Int($0))" } ?? "-"
        }
    }

    var body: some View {
        TimelineChartBody(
            points: chartPoints,
            domain: chartDomain,
            selectedIndex: selectedIndex,
            lineColor: lineColor,
            indicatorColor: indicatorLineColor,
            totalHeight: totalHeight,
            chartHeight: chartHeight,
            labelSpacing: labelSpacing,
            compactLayout: compactLayout,
            placesLabelsBelowChart: placesLabelsBelowChart,
            showsPointValueLabels: showsPointValueLabels,
            showsSelectedIndicator: showsSelectedIndicator,
            showsValueRow: showsValueRow,
            labelStride: labelStride,
            showsYAxis: showsYAxis,
            showsChartBackground: showsChartBackground,
            chartBottomSpacing: chartBottomSpacing,
            emptyTitle: missingDataTitle,
            transitionID: "daily-\(selectedDayOffset)-\(chartMetric)",
            transitionDirection: 1,
            onHorizontalSwipe: nil
        )
    }

    private var missingDataTitle: String {
        localizedString("Missing \(metricName) data", locale: locale)
    }

    private var metricName: String {
        switch chartMetric {
        case .temperature: return localizedString("temperature", locale: locale)
        case .feelsLike: return localizedString("feels-like", locale: locale)
        case .cloudCover: return localizedString("cloud cover", locale: locale)
        case .precipitation: return localizedString("precipitation", locale: locale)
        case .windSpeed: return localizedString("wind speed", locale: locale)
        case .uvIndex: return localizedString("UV index", locale: locale)
        case .humidity: return localizedString("humidity", locale: locale)
        case .visibility: return localizedString("visibility", locale: locale)
        }
    }
}

private struct TimelineChartBody: View {
    let points: [ChartPoint]
    let domain: ClosedRange<Double>
    let selectedIndex: Double?
    let lineColor: Color
    let indicatorColor: Color
    let totalHeight: CGFloat
    let chartHeight: CGFloat
    let labelSpacing: CGFloat
    let compactLayout: Bool
    let placesLabelsBelowChart: Bool
    let showsPointValueLabels: Bool
    let showsSelectedIndicator: Bool
    let showsValueRow: Bool
    let labelStride: Int
    let showsYAxis: Bool
    let showsChartBackground: Bool
    let chartBottomSpacing: CGFloat?
    let emptyTitle: String
    let transitionID: String
    let transitionDirection: Int
    let onHorizontalSwipe: ((Int) -> Void)?

    private var labelFont: Font {
        compactLayout ? .caption.weight(.medium) : .avenir(.subheadline)
    }

    private var valueFont: Font {
        compactLayout ? .caption.weight(.semibold) : .avenir(.footnote, weight: .semibold)
    }

    private var iconSize: CGFloat {
        compactLayout ? 14 : 17
    }

    private var pointSize: CGFloat {
        compactLayout ? 72 : 110
    }

    private var yAxisLabelWidth: CGFloat {
        showsYAxis ? 34 : 0
    }

    private var lineSegments: [ChartLineSegment] {
        guard points.count > 1 else { return [] }
        return points.indices.dropLast().map { index in
            ChartLineSegment(
                id: "\(points[index].id)-\(points[index + 1].id)",
                start: points[index],
                end: points[index + 1]
            )
        }
    }

    var body: some View {
        if points.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary.opacity(0.5))
                Text(emptyTitle)
                    .font(.avenir(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(height: totalHeight)
            .frame(maxWidth: .infinity)
        } else {
            ZStack {
                VStack(spacing: labelSpacing) {
                    if placesLabelsBelowChart {
                        chartWithBelowLabels
                    } else {
                        labelRow
                        chart
                    }

                    if showsValueRow {
                        valueRow
                    }
                }
                .id(transitionID)
                .transition(chartSwipeTransition)
            }
            .frame(height: totalHeight)
            .clipped()
            .animation(.snappy(duration: 0.28), value: transitionID)
        }
    }

    private var chartSwipeTransition: AnyTransition {
        let insertionEdge: Edge = transitionDirection >= 0 ? .trailing : .leading
        let removalEdge: Edge = transitionDirection >= 0 ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private var labelRow: some View {
        HStack(spacing: 0) {
            if yAxisLabelWidth > 0 {
                Color.clear
                    .frame(width: yAxisLabelWidth)
            }

            ForEach(points) { point in
                VStack(spacing: compactLayout ? 2 : 7) {
                    if point.index % max(labelStride, 1) != 0 {
                        Color.clear
                            .frame(height: compactLayout ? 34 : 44)
                    } else if placesLabelsBelowChart {
                        Image(systemName: point.icon)
                            .font(.system(size: iconSize))
                            .weatherIconStyle(for: point.icon)
                            .compatSymbolReplaceTransition()
                        Text(point.label)
                            .font(labelFont)
                            .foregroundStyle(AppTheme.shared.colors.primaryText)
                    } else {
                        Text(point.label)
                            .font(labelFont)
                            .foregroundStyle(AppTheme.shared.colors.primaryText)
                        Image(systemName: point.icon)
                            .font(.system(size: iconSize))
                            .weatherIconStyle(for: point.icon)
                            .compatSymbolReplaceTransition()
                    }
                }
                .opacity(point.isPast ? 0.3 : 1.0)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        if let onHorizontalSwipe {
            chartContent
                .contentShape(Rectangle())
                .gesture(horizontalSwipeGesture(action: onHorizontalSwipe))
                .frame(height: chartHeight)
        } else {
            chartContent
                .frame(height: chartHeight)
        }
    }

    private var chartWithBelowLabels: some View {
        VStack(spacing: 0) {
            chart
            if let chartBottomSpacing {
                Color.clear.frame(height: chartBottomSpacing)
            }
            labelRow
        }
        .chartBackgroundIfNeeded(showsChartBackground)
    }

    private var chartContent: some View {
        Chart {
            if showsSelectedIndicator, let selectedIndex {
                RuleMark(x: .value("Selected", selectedIndex))
                    .foregroundStyle(indicatorColor.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: compactLayout ? 1.5 : 2))
            }

            ForEach(lineSegments) { segment in
                ForEach(segment.points) { point in
                    LineMark(
                        x: .value("Index", Double(point.index)),
                        y: .value("Value", point.value),
                        series: .value("Segment", segment.id)
                    )
                    .foregroundStyle(lineSegmentColor(for: segment))
                    .lineStyle(StrokeStyle(lineWidth: compactLayout ? 3 : 4, lineCap: .round, lineJoin: .round))
                }
            }

            ForEach(points) { point in
                if showsPointValueLabels {
                    PointMark(
                        x: .value("Index", Double(point.index)),
                        y: .value("Value Label", point.value)
                    )
                    .annotation(position: .top, spacing: 9) {
                        Text(point.valueText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(pointValueLabelColor(for: point))
                    }
                    .foregroundStyle(.clear)
                    .symbolSize(1)
                }

                PointMark(
                    x: .value("Index", Double(point.index)),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(pointMarkerColor(for: point))
                .symbolSize(pointSize)
            }
        }
        .chartXScale(domain: -0.5...(Double(points.count) - 0.5))
        .chartYScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis {
            if showsYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                    AxisGridLine()
                        .foregroundStyle(.secondary.opacity(0.16))
                    AxisValueLabel {
                        if let intValue = value.as(Int.self) {
                            Text("\(intValue)%")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartPlotStyle { plotArea in
            plotArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func pointValueLabelColor(for point: ChartPoint) -> Color {
        point.isPast ? .secondary.opacity(0.38) : .secondary
    }

    private func pointMarkerColor(for point: ChartPoint) -> Color {
        point.isPast ? .secondary.opacity(0.36) : lineColor
    }

    private func lineSegmentColor(for segment: ChartLineSegment) -> Color {
        segment.isFutureSegment ? lineColor : .secondary.opacity(0.28)
    }

    private func horizontalSwipeGesture(action: @escaping (Int) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontalDistance = value.translation.width
                let verticalDistance = value.translation.height
                guard abs(horizontalDistance) > max(abs(verticalDistance) * 1.5, 36) else { return }
                action(horizontalDistance < 0 ? 1 : -1)
            }
    }

    private var valueRow: some View {
        HStack(spacing: 0) {
            ForEach(points) { point in
                Text(point.valueText)
                    .font(valueFont)
                    .foregroundStyle(AppTheme.shared.colors.primaryText)
                    .contentTransition(.numericText())
                    .opacity(point.isPast ? 0.3 : 1.0)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func chartBackgroundIfNeeded(_ enabled: Bool) -> some View {
        if enabled {
            self
                .padding(.top, 34)
                .padding(.bottom, 12)
                .padding(.horizontal, 10)
                .background(
                    AppTheme.shared.colors.secondaryText.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        } else {
            self
        }
    }
}

// MARK: - Expanded Detail Card Chart Controls

extension ContentView {

    @ViewBuilder
    func chartContent(for cityWeather: CityWeather, forecast: DailyForecast, availableSize: CGSize) -> some View {
        let refreshKey = hourlyRefreshKey(for: cityWeather, dayOffset: forecast.dayOffset)
        let isRefreshingHourlyData = hourlyRefreshKeys.contains(refreshKey)

        if shouldRefreshHourlyData(for: cityWeather, forecast: forecast), isRefreshingHourlyData {
            ProgressView()
                .controlSize(.regular)
                .frame(width: availableSize.width, height: availableSize.height)
        } else if expandedWeatherCardChartRange == .tenDay {
            ScrollView(.horizontal, showsIndicators: false) {
                DailyTimelineChart(
                    dailyForecasts: cityWeather.dailyForecasts,
                    chartMetric: expandedWeatherCardChartMetric,
                    selectedDayOffset: selectedDayOffset,
                    cityTimeZone: cityWeather.timeZone,
                    lineColor: expandedWeatherCardChartLineColor(expandedWeatherCardChartMetric),
                    compactLayout: true
                )
                .frame(width: max(availableSize.width * 1.1, 270), height: availableSize.height)
            }
        } else if expandedWeatherCardChartRange == .entireDay {
            let chartWidth = entireDayChartWidth(for: forecast, availableWidth: availableSize.width)
            let scrollTargetID = "entire-day-current-\(cityWeather.id.uuidString)-\(forecast.dayOffset)"
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .leading) {
                        HourlyTimelineChart(
                            hourlyForecasts: forecast.hourlyForecasts,
                            chartMetric: expandedWeatherCardChartMetric,
                            dayOffset: max(0, selectedDayOffset),
                            cityTimeZone: cityWeather.timeZone,
                            previewCurrentHour: nil,
                            lineColor: expandedWeatherCardChartLineColor(expandedWeatherCardChartMetric),
                            showAllHours: true,
                            compactLayout: true,
                            transitionDirection: detailChartSwipeDirection
                        )
                        .frame(width: chartWidth, height: availableSize.height)

                        if let targetX = entireDayCurrentTimeScrollTargetX(for: cityWeather, chartWidth: chartWidth) {
                            Color.clear
                                .frame(width: 1, height: 1)
                                .padding(.leading, targetX)
                                .id(scrollTargetID)
                        }
                    }
                }
                .task(id: "\(refreshKey)-\(chartWidth)-\(expandedWeatherCardChartRange)") {
                    await refreshHourlyDataIfNeeded(for: cityWeather, forecast: forecast)
                    guard entireDayCurrentTimeScrollTargetX(for: cityWeather, chartWidth: chartWidth) != nil else { return }
                    try? await Task.sleep(for: .milliseconds(80))
                    scrollEntireDayChart(proxy, targetID: scrollTargetID)
                    try? await Task.sleep(for: .milliseconds(220))
                    scrollEntireDayChart(proxy, targetID: scrollTargetID)
                }
                .onChange(of: expandedWeatherCardChartRange) { _, range in
                    guard range == .entireDay else { return }
                    Task {
                        try? await Task.sleep(for: .milliseconds(120))
                        scrollEntireDayChart(proxy, targetID: scrollTargetID)
                    }
                }
            }
        } else {
            HourlyTimelineChart(
                hourlyForecasts: forecast.hourlyForecasts,
                chartMetric: expandedWeatherCardChartMetric,
                dayOffset: max(0, selectedDayOffset),
                cityTimeZone: cityWeather.timeZone,
                previewCurrentHour: nil,
                lineColor: expandedWeatherCardChartLineColor(expandedWeatherCardChartMetric),
                compactLayout: true,
                transitionDirection: detailChartSwipeDirection,
                onHorizontalSwipe: { direction in
                    shiftExpandedCardChartDate(by: direction)
                }
            )
            .frame(width: availableSize.width, height: availableSize.height)
            .task(id: refreshKey) {
                await refreshHourlyDataIfNeeded(for: cityWeather, forecast: forecast)
            }
        }
    }

    private func entireDayChartWidth(for forecast: DailyForecast, availableWidth: CGFloat) -> CGFloat {
        let hourCount = max(forecast.hourlyForecasts.count, 24)
        return max(availableWidth * 2.4, CGFloat(hourCount) * 46)
    }

    private func entireDayCurrentTimeScrollTargetX(for cityWeather: CityWeather, chartWidth: CGFloat) -> CGFloat? {
        guard selectedDayOffset == -1 || selectedDayOffset == 0 else { return nil }
        var calendar = Calendar.current
        calendar.timeZone = cityWeather.timeZone
        let components = calendar.dateComponents([.hour, .minute], from: Date())
        let hour = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
        return max(0, min(chartWidth, chartWidth * CGFloat(hour / 23)))
    }

    @MainActor
    private func scrollEntireDayChart(_ proxy: ScrollViewProxy, targetID: String) {
        withAnimation(.smooth(duration: 0.28)) {
            proxy.scrollTo(targetID, anchor: .center)
        }
    }
    func expandedWeatherCardChartMetricMenu() -> some View {
        Menu {
            ForEach(expandedWeatherCardChartMetrics, id: \.0) { metric, icon, label in
                Button {
                    expandedWeatherCardChartMetric = metric
                } label: {
                    HStack {
                        if expandedWeatherCardChartMetric == metric {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.primary)
                                .frame(width: 14)
                        } else {
                            Color.clear.frame(width: 14)
                        }
                        Text(label)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: expandedWeatherCardChartMetricIcon(expandedWeatherCardChartMetric))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(expandedWeatherCardChartMetricLabel(expandedWeatherCardChartMetric))
                    .font(Font.callout.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 30)
            .padding(.horizontal, 11)
            .background(Color.primary.opacity(0.07), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    func expandedWeatherCardChartRangeMenu() -> some View {
        Menu {
            ForEach(expandedWeatherCardChartRanges, id: \.0) { range, label in
                Button {
                    expandedWeatherCardChartRange = range
                } label: {
                    HStack {
                        if expandedWeatherCardChartRange == range {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.primary)
                                .frame(width: 14)
                        } else {
                            Color.clear.frame(width: 14)
                        }
                        Text(label)
                    }
                }
            }
        } label: {
            Text(expandedWeatherCardChartRangeLabel(expandedWeatherCardChartRange))
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
                .frame(height: 30)
                .padding(.horizontal, 11)
                .background(Color.primary.opacity(0.07), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var expandedWeatherCardChartRanges: [(WeatherChartTimeRange, String)] {
        [
            (.daytime, localizedString("Daytime", locale: locale)),
            (.entireDay, localizedString("Entire Day", locale: locale)),
            (.tenDay, localizedString("10 Days", locale: locale))
        ]
    }
    private var expandedWeatherCardChartMetrics: [(WeatherChartMetric, String, String)] {
        [
            (.temperature, "thermometer.medium", localizedString("Temperature", locale: locale)),
            (.feelsLike, "thermometer.variable.and.figure", localizedString("Feels Like", locale: locale)),
            (.cloudCover, "cloud", localizedString("Cloud Cover", locale: locale)),
            (.precipitation, "drop.fill", localizedString("Precipitation", locale: locale)),
            (.windSpeed, "wind", localizedString("Wind Speed", locale: locale)),
            (.uvIndex, "sun.max.fill", localizedString("UV Index", locale: locale)),
            (.humidity, "humidity.fill", localizedString("Humidity", locale: locale)),
            (.visibility, "eye", localizedString("Visibility", locale: locale))
        ]
    }

    private func expandedWeatherCardChartMetricIcon(_ metric: WeatherChartMetric) -> String {
        expandedWeatherCardChartMetrics.first(where: { $0.0 == metric })?.1 ?? "chart.xyaxis.line"
    }

    private func expandedWeatherCardChartMetricLabel(_ metric: WeatherChartMetric) -> String {
        expandedWeatherCardChartMetrics.first(where: { $0.0 == metric })?.2 ?? localizedString("Forecast", locale: locale)
    }

    private func expandedWeatherCardChartRangeLabel(_ range: WeatherChartTimeRange) -> String {
        switch range {
        case .daytime: return localizedString("Daytime", locale: locale)
        case .entireDay: return localizedString("Entire Day", locale: locale)
        case .tenDay: return localizedString("10 Days", locale: locale)
        }
    }

    private func expandedWeatherCardChartLineColor(_ metric: WeatherChartMetric) -> Color {
        theme.colors.dotRain
    }

    private func shiftExpandedCardChartDate(by direction: Int) {
        let currentDay = max(0, selectedDayOffset)
        let nextDay = min(9, max(0, currentDay + direction))
        guard nextDay != selectedDayOffset else { return }
        detailChartSwipeDirection = direction
        dateSwitcherForward = direction > 0
        PlatformFeedback.lightImpact()
        withAnimation(.snappy(duration: 0.28)) {
            selectedDayOffset = nextDay
        }
    }
}
