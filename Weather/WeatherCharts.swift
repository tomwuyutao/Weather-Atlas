import SwiftUI
import Charts

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

private struct ChartPoint: Identifiable {
    let id: String
    let index: Int
    let label: String
    let icon: String
    let value: Double
    let valueText: String
    let isPast: Bool
}

struct HourlyTimelineChart: View {
    let hourlyForecasts: [HourlyForecast]
    var chartMetric: WeatherChartMetric = .temperature
    var dayOffset: Int = 0
    var cityTimeZone: TimeZone = .current
    var previewCurrentHour: Int? = nil
    var lineColor: Color = AppTheme.shared.colors.accent
    var showAllHours: Bool = false
    var compactLayout: Bool = false
    var transitionDirection: Int = 1
    var onHorizontalSwipe: ((Int) -> Void)? = nil

    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.defaultRawValue

    private var tempUnit: TemperatureUnit { TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic }
    private var distUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .automatic }
    private var indicatorLineColor: Color { colorScheme == .dark ? .white : AppTheme.shared.colors.listCardFill.compatMix(with: .black, by: 0.25) }
    private var totalHeight: CGFloat { compactLayout ? 230 : 250 }
    private var chartHeight: CGFloat { compactLayout ? 132 : 146 }
    private var labelSpacing: CGFloat { compactLayout ? 6 : 10 }

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
            emptyTitle: missingDataTitle,
            transitionID: "hourly-\(dayOffset)-\(chartMetric)-\(showAllHours)",
            transitionDirection: transitionDirection,
            onHorizontalSwipe: onHorizontalSwipe
        )
    }
}

struct DailyTimelineChart: View {
    let dailyForecasts: [DailyForecast]
    var chartMetric: WeatherChartMetric = .temperature
    var selectedDayOffset: Int = 0
    var cityTimeZone: TimeZone = .current
    var lineColor: Color = AppTheme.shared.colors.accent
    var compactLayout: Bool = false

    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.defaultRawValue

    private var tempUnit: TemperatureUnit { TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic }
    private var distUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .automatic }
    private var indicatorLineColor: Color { colorScheme == .dark ? .white : AppTheme.shared.colors.listCardFill.compatMix(with: .black, by: 0.25) }
    private var totalHeight: CGFloat { compactLayout ? 230 : 250 }
    private var chartHeight: CGFloat { compactLayout ? 132 : 146 }
    private var labelSpacing: CGFloat { compactLayout ? 6 : 10 }
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
    let emptyTitle: String
    let transitionID: String
    let transitionDirection: Int
    let onHorizontalSwipe: ((Int) -> Void)?

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
                    labelRow
                    chart
                    valueRow
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
            ForEach(points) { point in
                VStack(spacing: compactLayout ? 4 : 7) {
                    Text(point.label)
                        .font(compactLayout ? .caption.weight(.medium) : .avenir(.subheadline))
                        .foregroundStyle(AppTheme.shared.colors.primaryText)
                    Image(systemName: point.icon)
                        .font(.system(size: compactLayout ? 14 : 17))
                        .weatherIconStyle(for: point.icon)
                        .compatSymbolReplaceTransition()
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

    private var chartContent: some View {
        Chart {
            if let selectedIndex {
                RuleMark(x: .value("Selected", selectedIndex))
                    .foregroundStyle(indicatorColor.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: compactLayout ? 1.5 : 2))
            }

            ForEach(points) { point in
                LineMark(
                    x: .value("Index", Double(point.index)),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(lineColor)
                .lineStyle(StrokeStyle(lineWidth: compactLayout ? 3 : 4, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("Index", Double(point.index)),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(lineColor)
                .symbolSize(compactLayout ? 72 : 110)
            }
        }
        .chartXScale(domain: -0.5...(Double(points.count) - 0.5))
        .chartYScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { plotArea in
            plotArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
                    .font(compactLayout ? .caption.weight(.semibold) : .avenir(.footnote, weight: .semibold))
                    .foregroundStyle(AppTheme.shared.colors.primaryText)
                    .contentTransition(.numericText())
                    .opacity(point.isPast ? 0.3 : 1.0)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
