import SwiftUI
import Charts

enum WeatherChartMetric: Hashable {
    case temperature, feelsLike, cloudCover, precipitation
    case windSpeed, uvIndex, humidity, visibility
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

    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue

    private var tempUnit: TemperatureUnit { TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius }
    private var distUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers }
    private var indicatorLineColor: Color { colorScheme == .dark ? .white : AppTheme.shared.colors.listCardFill.mix(with: .black, by: 0.25) }
    private var totalHeight: CGFloat { compactLayout ? 230 : 250 }
    private var chartHeight: CGFloat { compactLayout ? 132 : 146 }
    private var labelSpacing: CGFloat { compactLayout ? 6 : 10 }

    private var currentCityHour: Int? {
        guard dayOffset == 0 || dayOffset == -1 else { return nil }
        if let previewCurrentHour { return previewCurrentHour }
        var calendar = Calendar.current
        calendar.timeZone = cityTimeZone
        return calendar.component(.hour, from: Date())
    }

    private var dataPoints: [HourlyForecast] {
        showAllHours ? hourlyForecasts.sorted { $0.hour < $1.hour } : hourlyForecasts.filter { [7, 9, 11, 13, 15, 17, 19].contains($0.hour) }
    }

    private var chartPoints: [ChartPoint] {
        dataPoints.enumerated().map { index, forecast in
            ChartPoint(
                id: forecast.id.uuidString,
                index: index,
                label: forecast.shortFormattedHour(locale: locale),
                icon: forecast.weatherIcon,
                value: value(for: forecast),
                valueText: chartValueText(for: forecast),
                isPast: isPastHour(forecast.hour)
            )
        }
    }

    private var chartDomain: ClosedRange<Double> {
        let values = chartPoints.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let padding = max((maxValue - minValue) * (compactLayout ? 0.55 : 0.35), compactLayout ? 4.0 : 2.0)
        return (minValue - padding)...(maxValue + padding)
    }

    private var currentHourIndex: Double? {
        guard let currentCityHour else { return nil }
        let hours = dataPoints.map(\.hour)
        guard let lastIndex = hours.lastIndex(where: { $0 <= currentCityHour }), lastIndex < hours.count - 1 else { return nil }
        let h0 = Double(hours[lastIndex])
        let h1 = Double(hours[lastIndex + 1])
        let fraction = h1 > h0 ? Double(currentCityHour - hours[lastIndex]) / (h1 - h0) : 0
        return Double(lastIndex) + fraction
    }

    private func isPastHour(_ hour: Int) -> Bool {
        guard let currentCityHour else { return false }
        return hour < currentCityHour
    }

    private func chartValueText(for forecast: HourlyForecast) -> String {
        switch chartMetric {
        case .temperature: return tempUnit.display(forecast.temperature)
        case .feelsLike: return forecast.apparentTemperature.map { tempUnit.display($0) } ?? "-"
        case .cloudCover: return forecast.cloudCoverPercent.map { "\($0)%" } ?? "-"
        case .precipitation: return forecast.precipitationChance.map { "\(Int($0 * 100))%" } ?? "-"
        case .windSpeed: return forecast.windSpeed.map { distUnit == .miles ? "\(Int($0 * 0.621371))" : "\(Int($0))" } ?? "-"
        case .uvIndex: return forecast.uvIndex.map { "\($0)" } ?? "-"
        case .humidity: return forecast.humidity.map { "\(Int($0 * 100))%" } ?? "-"
        case .visibility: return forecast.visibility.map { distUnit == .miles ? "\(Int($0 * 0.621371))" : "\(Int($0))" } ?? "-"
        }
    }

    private func value(for forecast: HourlyForecast) -> Double {
        switch chartMetric {
        case .temperature: return forecast.temperature
        case .feelsLike: return forecast.apparentTemperature ?? forecast.temperature
        case .cloudCover: return Double(forecast.cloudCoverPercent ?? 0)
        case .precipitation: return (forecast.precipitationChance ?? 0) * 100
        case .windSpeed: return forecast.windSpeed ?? 0
        case .uvIndex: return Double(forecast.uvIndex ?? 0)
        case .humidity: return (forecast.humidity ?? 0) * 100
        case .visibility: return forecast.visibility ?? 10
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
            emptyTitle: "No hourly data"
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
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue

    private var tempUnit: TemperatureUnit { TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius }
    private var distUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers }
    private var indicatorLineColor: Color { colorScheme == .dark ? .white : AppTheme.shared.colors.listCardFill.mix(with: .black, by: 0.25) }
    private var totalHeight: CGFloat { compactLayout ? 230 : 250 }
    private var chartHeight: CGFloat { compactLayout ? 132 : 146 }
    private var labelSpacing: CGFloat { compactLayout ? 6 : 10 }
    private var dataPoints: [DailyForecast] { dailyForecasts.sorted { $0.dayOffset < $1.dayOffset } }

    private var chartPoints: [ChartPoint] {
        dataPoints.enumerated().map { index, forecast in
            ChartPoint(
                id: forecast.id.uuidString,
                index: index,
                label: dayLabel(for: forecast),
                icon: forecast.weatherIcon,
                value: value(for: forecast),
                valueText: chartValueText(for: forecast),
                isPast: false
            )
        }
    }

    private var selectedIndex: Double? {
        dataPoints.firstIndex(where: { $0.dayOffset == (selectedDayOffset == -1 ? 0 : selectedDayOffset) }).map(Double.init)
    }

    private var chartDomain: ClosedRange<Double> {
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

    private func value(for forecast: DailyForecast) -> Double {
        switch chartMetric {
        case .temperature: return forecast.dailyHigh
        case .feelsLike: return forecast.feelsLikeHigh ?? forecast.dailyHigh
        case .cloudCover: return (forecast.cloudCover ?? 0) * 100
        case .precipitation: return (forecast.precipitationChance ?? 0) * 100
        case .windSpeed: return forecast.windSpeed ?? 0
        case .uvIndex: return Double(forecast.uvIndex ?? 0)
        case .humidity: return (forecast.maxHumidity ?? 0) * 100
        case .visibility: return forecast.maxVisibility ?? 10
        }
    }

    private func chartValueText(for forecast: DailyForecast) -> String {
        switch chartMetric {
        case .temperature: return tempUnit.display(forecast.dailyHigh)
        case .feelsLike: return forecast.feelsLikeHigh.map { tempUnit.display($0) } ?? "-"
        case .cloudCover: return forecast.cloudCover.map { "\(Int($0 * 100))%" } ?? "-"
        case .precipitation: return forecast.precipitationChance.map { "\(Int($0 * 100))%" } ?? "-"
        case .windSpeed: return forecast.windSpeed.map { distUnit == .miles ? "\(Int($0 * 0.621371))" : "\(Int($0))" } ?? "-"
        case .uvIndex: return forecast.uvIndex.map { "\($0)" } ?? "-"
        case .humidity: return forecast.maxHumidity.map { "\(Int($0 * 100))%" } ?? "-"
        case .visibility: return forecast.maxVisibility.map { distUnit == .miles ? "\(Int($0 * 0.621371))" : "\(Int($0))" } ?? "-"
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
            emptyTitle: "No daily data"
        )
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
            VStack(spacing: labelSpacing) {
                labelRow
                chart
                valueRow
            }
            .frame(height: totalHeight)
            .animation(.smooth(duration: 0.3), value: points.map(\.value))
        }
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
                        .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                }
                .opacity(point.isPast ? 0.3 : 1.0)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var chart: some View {
        GeometryReader { geometry in
            let chartPoints = positionedPoints(in: geometry.size)
            let selectedX = selectedIndex.map { chartX(for: $0, width: geometry.size.width) }

            ZStack {
                if let selectedX {
                    Rectangle()
                        .fill(indicatorColor.opacity(0.5))
                        .frame(width: compactLayout ? 1.5 : 2)
                        .position(x: selectedX, y: geometry.size.height / 2)
                }

                Path { path in
                    guard let first = chartPoints.first else { return }
                    path.move(to: first)
                    chartPoints.dropFirst().forEach { point in
                        path.addLine(to: point)
                    }
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: compactLayout ? 3 : 4, lineCap: .round, lineJoin: .round))

                ForEach(Array(chartPoints.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(lineColor)
                        .frame(width: compactLayout ? 8.5 : 10.5, height: compactLayout ? 8.5 : 10.5)
                        .position(point)
                }
            }
        }
        .frame(height: chartHeight)
    }

    private func positionedPoints(in size: CGSize) -> [CGPoint] {
        points.map { point in
            CGPoint(
                x: chartX(for: Double(point.index), width: size.width),
                y: chartY(for: point.value, height: size.height)
            )
        }
    }

    private func chartX(for index: Double, width: CGFloat) -> CGFloat {
        guard !points.isEmpty else { return 0 }
        return (CGFloat(index) + 0.5) * width / CGFloat(points.count)
    }

    private func chartY(for value: Double, height: CGFloat) -> CGFloat {
        let lower = domain.lowerBound
        let upper = domain.upperBound
        guard upper > lower else { return height / 2 }
        let progress = (value - lower) / (upper - lower)
        return height * (1 - CGFloat(progress))
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
