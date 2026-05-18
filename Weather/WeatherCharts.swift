import SwiftUI

enum WeatherChartMetric: Hashable {
    case temperature, feelsLike, cloudCover, precipitation
    case windSpeed, uvIndex, humidity, visibility
}

enum WeatherChartTimeRange: Hashable {
    case daytime, entireDay, tenDay
}

struct AnimatablePointList: VectorArithmetic {
    var values: [Double]

    static var zero: AnimatablePointList { .init(values: []) }

    static func + (lhs: AnimatablePointList, rhs: AnimatablePointList) -> AnimatablePointList {
        let count = max(lhs.values.count, rhs.values.count)
        var result = [Double](repeating: 0, count: count)
        for index in 0..<count {
            result[index] = (index < lhs.values.count ? lhs.values[index] : 0) + (index < rhs.values.count ? rhs.values[index] : 0)
        }
        return .init(values: result)
    }

    static func - (lhs: AnimatablePointList, rhs: AnimatablePointList) -> AnimatablePointList {
        let count = max(lhs.values.count, rhs.values.count)
        var result = [Double](repeating: 0, count: count)
        for index in 0..<count {
            result[index] = (index < lhs.values.count ? lhs.values[index] : 0) - (index < rhs.values.count ? rhs.values[index] : 0)
        }
        return .init(values: result)
    }

    mutating func scale(by rhs: Double) {
        for index in values.indices { values[index] *= rhs }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }
}

struct HourlyChartLineShape: Shape {
    var pointYValues: AnimatablePointList
    let pointXPositions: [CGFloat]
    let gapRadius: CGFloat

    var animatableData: AnimatablePointList {
        get { pointYValues }
        set { pointYValues = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = zip(pointXPositions, pointYValues.values).map { CGPoint(x: $0, y: $1) }
        guard points.count >= 2 else { return path }

        let segmentSteps = 40
        var allPoints: [CGPoint] = []
        for index in 0..<(points.count - 1) {
            let p0 = index > 0 ? points[index - 1] : CGPoint(x: 2 * points[index].x - points[index + 1].x, y: 2 * points[index].y - points[index + 1].y)
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = index + 2 < points.count ? points[index + 2] : CGPoint(x: 2 * p2.x - p1.x, y: 2 * p2.y - p1.y)

            for step in 0...segmentSteps {
                let t = CGFloat(step) / CGFloat(segmentSteps)
                allPoints.append(CGPoint(
                    x: catmullRom(t: t, p0: p0.x, p1: p1.x, p2: p2.x, p3: p3.x),
                    y: catmullRom(t: t, p0: p0.y, p1: p1.y, p2: p2.y, p3: p3.y)
                ))
            }
        }

        var drawing = false
        for point in allPoints {
            let nearDataPoint = points.contains { abs(point.x - $0.x) < gapRadius }
            if nearDataPoint {
                drawing = false
            } else if drawing {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                drawing = true
            }
        }
        return path
    }

    private func catmullRom(t: CGFloat, p0: CGFloat, p1: CGFloat, p2: CGFloat, p3: CGFloat) -> CGFloat {
        let t2 = t * t
        let t3 = t2 * t
        return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
    }
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

    private var currentCityHour: Int? {
        guard dayOffset == 0 || dayOffset == -1 else { return nil }
        if let previewCurrentHour { return previewCurrentHour }
        var calendar = Calendar.current
        calendar.timeZone = cityTimeZone
        return calendar.component(.hour, from: Date())
    }

    private func isPastHour(_ hour: Int) -> Bool {
        guard let currentCityHour else { return false }
        return hour < currentCityHour
    }

    private var totalHeight: CGFloat { compactLayout ? 230 : 250 }
    private var hourLabelHeight: CGFloat { compactLayout ? 14 : 20 }
    private var topPadding: CGFloat { compactLayout ? 0 : 4 }
    private var iconHeight: CGFloat { compactLayout ? 16 : 26 }
    private var iconBottomPadding: CGFloat { compactLayout ? 6 : 20 }
    private var valueHeight: CGFloat { compactLayout ? 14 : 20 }
    private var chartTop: CGFloat { hourLabelHeight + topPadding + iconHeight + iconBottomPadding }
    private var chartBottom: CGFloat { totalHeight - valueHeight - 14 }
    private var chartZone: CGFloat { chartBottom - chartTop }

    private var dataPoints: [HourlyForecast] {
        showAllHours ? hourlyForecasts.sorted { $0.hour < $1.hour } : hourlyForecasts.filter { [7, 9, 11, 13, 15, 17, 19].contains($0.hour) }
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

    private var valueRange: (min: Double, max: Double) {
        switch chartMetric {
        case .cloudCover, .precipitation, .humidity: return (0, 100)
        case .uvIndex: return (0, 11)
        case .windSpeed: return (0, 100)
        case .visibility:
            let maxValue = dataPoints.map { value(for: $0) }.max() ?? 30
            return (0, max(30, maxValue + 5))
        case .temperature, .feelsLike:
            let values = dataPoints.map { value(for: $0) }
            let minValue = values.min() ?? 10
            let maxValue = values.max() ?? 20
            let padding = max((maxValue - minValue) * (compactLayout ? 0.7 : 0.25), compactLayout ? 5.0 : 2.0)
            return (minValue - padding, maxValue + padding)
        }
    }

    private func lineY(for value: Double) -> CGFloat {
        let range = valueRange.max - valueRange.min
        guard range > 0 else { return chartTop + chartZone * 0.5 }
        return chartTop + (1.0 - CGFloat((value - valueRange.min) / range)) * chartZone
    }

    var body: some View {
        if dataPoints.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary.opacity(0.5))
                Text("No hourly data")
                    .font(.avenir(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(height: totalHeight)
            .frame(maxWidth: .infinity)
        } else {
            GeometryReader { geometry in
                let width = geometry.size.width
                let count = CGFloat(dataPoints.count)
                let columnWidth = count > 0 ? width / count : width
                let xPositions = dataPoints.indices.map { (CGFloat($0) + 0.5) * columnWidth }
                let lineYPositions = dataPoints.map { lineY(for: value(for: $0)) }

                ZStack(alignment: .topLeading) {
                    HourlyChartLineShape(pointYValues: AnimatablePointList(values: lineYPositions.map { Double($0) }), pointXPositions: xPositions, gapRadius: 0)
                        .stroke(AppTheme.shared.colors.accent, style: StrokeStyle(lineWidth: compactLayout ? 3 : 4, lineCap: .round, lineJoin: .round))

                    ForEach(Array(dataPoints.enumerated()), id: \.element.id) { index, _ in
                        Circle()
                            .fill(AppTheme.shared.colors.accent)
                            .frame(width: compactLayout ? 9 : 12, height: compactLayout ? 9 : 12)
                            .position(x: xPositions[index], y: lineYPositions[index])
                    }

                    if let currentCityHour {
                        let hours = dataPoints.map { $0.hour }
                        let lineTop = chartTop - 4
                        let lineBottom = chartBottom + valueHeight
                        let lineHeight = lineBottom - lineTop
                        let lineCenterY = lineTop + lineHeight / 2
                        if let lastIndex = hours.lastIndex(where: { $0 <= currentCityHour }), lastIndex < hours.count - 1 {
                            let h0 = CGFloat(hours[lastIndex])
                            let h1 = CGFloat(hours[lastIndex + 1])
                            let fraction = h1 > h0 ? CGFloat(currentCityHour - hours[lastIndex]) / (h1 - h0) : 0
                            let nowX = xPositions[lastIndex] + fraction * (xPositions[lastIndex + 1] - xPositions[lastIndex])
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .fill(indicatorLineColor)
                                .frame(width: 1.5, height: lineHeight)
                                .position(x: nowX, y: lineCenterY)
                                .opacity(0.5)
                        }
                    }

                    HStack(spacing: 0) {
                        ForEach(Array(dataPoints.enumerated()), id: \.element.id) { index, forecast in
                            let pointY = lineYPositions[index]
                            let pastHour = isPastHour(forecast.hour)
                            let iconY = hourLabelHeight + topPadding + iconHeight / 2 + 10
                            ZStack {
                                Text(forecast.shortFormattedHour(locale: locale))
                                    .font(compactLayout ? .caption.weight(.medium) : .avenir(.subheadline))
                                    .foregroundStyle(AppTheme.shared.colors.primaryText)
                                    .frame(height: hourLabelHeight)
                                    .position(x: columnWidth / 2, y: hourLabelHeight / 2 + (compactLayout ? 4 : 10))
                                    .opacity(pastHour ? 0.3 : 1.0)

                                Image(systemName: forecast.weatherIcon)
                                    .font(.system(size: compactLayout ? 14 : 17))
                                    .weatherIconStyle(for: forecast.weatherIcon)
                                    .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                                    .frame(height: iconHeight)
                                    .position(x: columnWidth / 2, y: iconY)
                                    .opacity(pastHour ? 0.3 : 1.0)

                                Text(chartValueText(for: forecast))
                                    .font(compactLayout ? .caption.weight(.semibold) : .avenir(.footnote, weight: .semibold))
                                    .foregroundStyle(AppTheme.shared.colors.primaryText)
                                    .contentTransition(.numericText())
                                    .frame(height: valueHeight)
                                    .position(x: columnWidth / 2 + 2, y: pointY + valueHeight * 0.85 + 2)
                                    .opacity(pastHour ? 0.3 : 1.0)
                            }
                            .frame(width: columnWidth, height: totalHeight)
                        }
                    }
                }
            }
            .frame(height: totalHeight)
            .animation(.smooth(duration: 0.3), value: chartMetric)
        }
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
    private var dayLabelHeight: CGFloat { compactLayout ? 14 : 20 }
    private var topPadding: CGFloat { compactLayout ? 0 : 4 }
    private var iconHeight: CGFloat { compactLayout ? 16 : 26 }
    private var iconBottomPadding: CGFloat { compactLayout ? 6 : 20 }
    private var valueHeight: CGFloat { compactLayout ? 14 : 20 }
    private var chartTop: CGFloat { dayLabelHeight + topPadding + iconHeight + iconBottomPadding }
    private var chartBottom: CGFloat { totalHeight - valueHeight - 14 }
    private var chartZone: CGFloat { chartBottom - chartTop }
    private var dataPoints: [DailyForecast] { dailyForecasts.sorted { $0.dayOffset < $1.dayOffset } }

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

    private var valueRange: (min: Double, max: Double) {
        switch chartMetric {
        case .cloudCover, .precipitation, .humidity: return (0, 100)
        case .uvIndex: return (0, 11)
        case .windSpeed: return (0, 100)
        case .visibility:
            let maxValue = dataPoints.map { value(for: $0) }.max() ?? 30
            return (0, max(30, maxValue + 5))
        case .temperature, .feelsLike:
            let values = dataPoints.map { value(for: $0) }
            let minValue = values.min() ?? 10
            let maxValue = values.max() ?? 20
            let padding = max((maxValue - minValue) * (compactLayout ? 0.7 : 0.25), compactLayout ? 5.0 : 2.0)
            return (minValue - padding, maxValue + padding)
        }
    }

    private func lineY(for value: Double) -> CGFloat {
        let range = valueRange.max - valueRange.min
        guard range > 0 else { return chartTop + chartZone * 0.5 }
        return chartTop + (1.0 - CGFloat((value - valueRange.min) / range)) * chartZone
    }

    var body: some View {
        if dataPoints.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary.opacity(0.5))
                Text("No daily data")
                    .font(.avenir(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(height: totalHeight)
            .frame(maxWidth: .infinity)
        } else {
            GeometryReader { geometry in
                let width = geometry.size.width
                let count = CGFloat(dataPoints.count)
                let columnWidth = count > 0 ? width / count : width
                let xPositions = dataPoints.indices.map { (CGFloat($0) + 0.5) * columnWidth }
                let lineYPositions = dataPoints.map { lineY(for: value(for: $0)) }

                ZStack(alignment: .topLeading) {
                    HourlyChartLineShape(pointYValues: AnimatablePointList(values: lineYPositions.map { Double($0) }), pointXPositions: xPositions, gapRadius: 0)
                        .stroke(AppTheme.shared.colors.accent, style: StrokeStyle(lineWidth: compactLayout ? 3 : 4, lineCap: .round, lineJoin: .round))

                    ForEach(Array(dataPoints.enumerated()), id: \.element.id) { index, _ in
                        Circle()
                            .fill(AppTheme.shared.colors.accent)
                            .frame(width: compactLayout ? 9 : 12, height: compactLayout ? 9 : 12)
                            .position(x: xPositions[index], y: lineYPositions[index])
                    }

                    if let selectedIndex = dataPoints.firstIndex(where: { $0.dayOffset == (selectedDayOffset == -1 ? 0 : selectedDayOffset) }) {
                        let lineTop = chartTop - 4
                        let lineBottom = chartBottom + valueHeight
                        let lineHeight = lineBottom - lineTop
                        Rectangle()
                            .fill(indicatorLineColor)
                            .frame(width: 3, height: lineHeight)
                            .position(x: xPositions[selectedIndex], y: lineTop + lineHeight / 2)
                            .opacity(0.5)
                    }

                    HStack(spacing: 0) {
                        ForEach(Array(dataPoints.enumerated()), id: \.element.id) { index, forecast in
                            let pointY = lineYPositions[index]
                            let iconY = dayLabelHeight + topPadding + iconHeight / 2 + 10
                            ZStack {
                                Text(dayLabel(for: forecast))
                                    .font(compactLayout ? .caption.weight(.medium) : .avenir(.subheadline))
                                    .foregroundStyle(AppTheme.shared.colors.primaryText)
                                    .frame(height: dayLabelHeight)
                                    .position(x: columnWidth / 2, y: dayLabelHeight / 2 + (compactLayout ? 4 : 10))

                                Image(systemName: forecast.weatherIcon)
                                    .font(.system(size: compactLayout ? 14 : 17))
                                    .weatherIconStyle(for: forecast.weatherIcon)
                                    .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                                    .frame(height: iconHeight)
                                    .position(x: columnWidth / 2, y: iconY)

                                Text(chartValueText(for: forecast))
                                    .font(compactLayout ? .caption.weight(.semibold) : .avenir(.footnote, weight: .semibold))
                                    .foregroundStyle(AppTheme.shared.colors.primaryText)
                                    .contentTransition(.numericText())
                                    .frame(height: valueHeight)
                                    .position(x: columnWidth / 2 + 2, y: pointY + valueHeight * 0.85 + 2)
                            }
                            .frame(width: columnWidth, height: totalHeight)
                        }
                    }
                }
            }
            .frame(height: totalHeight)
            .animation(.smooth(duration: 0.3), value: chartMetric)
        }
    }
}
