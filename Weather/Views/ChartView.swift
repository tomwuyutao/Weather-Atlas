//
//  ChartView.swift
//  Weather
//
//  Purpose: Provides the reusable Detail metric cards and the interactive
//  hourly/forecast chart sheet opened from those cards.
//

import Charts
import SwiftUI

// MARK: - Detail Metrics

/// Metrics exposed by the six-card Detail selector and chart sheet.
enum DetailChartMetric: String, CaseIterable, Identifiable {
    case sunnyHours
    case cloudCover
    case temperature
    case feelsLike
    case rainChance
    case uvIndex

    var id: String { rawValue }

    /// SF Symbol shared by the Detail card and chart title.
    var systemImage: String {
        switch self {
        case .sunnyHours: "sun.max.fill"
        case .cloudCover: "cloud"
        case .temperature: "thermometer.medium"
        case .feelsLike: "thermometer.variable"
        case .rainChance: "drop.fill"
        case .uvIndex: "sun.max.trianglebadge.exclamationmark"
        }
    }

    /// Localized user-facing metric title.
    func title(locale: Locale) -> String {
        switch self {
        case .sunnyHours: localizedString("Sunny Hours", locale: locale)
        case .cloudCover: localizedString("Cloud Cover", locale: locale)
        case .temperature: localizedString("Temperature", locale: locale)
        case .feelsLike: localizedString("Feels Like", locale: locale)
        case .rainChance: localizedString("Rain Chance", locale: locale)
        case .uvIndex: localizedString("UV Index", locale: locale)
        }
    }
}

/// Native chart-range choices: one selected day or every available forecast day.
private enum DetailChartRange: String, CaseIterable, Identifiable {
    case day
    case forecast

    var id: String { rawValue }

    func title(locale: Locale) -> String {
        switch self {
        case .day: localizedString("Day", locale: locale)
        case .forecast: localizedString("10 Days", locale: locale)
        }
    }
}

// MARK: - Detail Metric Grid

/// Six-card Detail selector that presents the chart sheet at the tapped metric.
struct DetailMetricGrid: View {
    let city: CityWeather
    let forecast: DailyForecast
    let temperatureUnit: TemperatureUnit
    let usesLandscapeIPadLayout: Bool

    @State private var presentedMetric: DetailChartMetric?

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    var body: some View {
        metricCards(selectedMetric: nil) { metric in
            presentedMetric = metric
        }
        .sheet(item: $presentedMetric) { metric in
            DetailChartView(
                city: city,
                initialForecast: forecast,
                initialMetric: metric,
                temperatureUnit: temperatureUnit
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    /// Keeps the card order and appearance identical in Detail and the sheet.
    private func metricCards(
        selectedMetric: DetailChartMetric?,
        action: @escaping (DetailChartMetric) -> Void
    ) -> some View {
        let columns = usesLandscapeIPadLayout
            ? [GridItem(.adaptive(minimum: 200), spacing: 10)]
            : [GridItem(.flexible()), GridItem(.flexible())]

        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(DetailChartMetric.allCases) { metric in
                DetailMetricCard(
                    metric: metric,
                    value: metric.summary(
                        for: forecast,
                        city: city,
                        temperatureUnit: temperatureUnit,
                        locale: locale
                    ),
                    isSelected: selectedMetric == metric,
                    action: { action(metric) }
                )
            }
        }
    }
}

/// One tappable metric card shared verbatim between Detail and Chart View.
private struct DetailMetricCard: View {
    let metric: DetailChartMetric
    let value: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: action) {
            HStack(spacing: CityListLayout.columnSpacing) {
                Image(systemName: metric.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    // Every metric icon uses the same primary semantic color.
                    .foregroundStyle(theme.colors.primaryText)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.title(locale: locale))
                        .font(.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                    Text(value)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(minHeight: 20, alignment: .leading)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: 18))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(theme.colors.primaryText.opacity(0.75), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(metric.title(locale: locale))
        .accessibilityValue(value)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Chart Sheet

/// Almost-full-screen Detail sheet with native range switching and metric cards.
struct DetailChartView: View {
    let city: CityWeather
    let initialForecast: DailyForecast
    let initialMetric: DetailChartMetric
    let temperatureUnit: TemperatureUnit

    @State private var selectedMetric: DetailChartMetric
    @State private var selectedRange: DetailChartRange = .day

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    init(
        city: CityWeather,
        initialForecast: DailyForecast,
        initialMetric: DetailChartMetric,
        temperatureUnit: TemperatureUnit
    ) {
        self.city = city
        self.initialForecast = initialForecast
        self.initialMetric = initialMetric
        self.temperatureUnit = temperatureUnit
        _selectedMetric = State(initialValue: initialMetric)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Picker(
                        localizedString("Chart Range", locale: locale),
                        selection: $selectedRange
                    ) {
                        ForEach(DetailChartRange.allCases) { range in
                            Text(range.title(locale: locale)).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)

                    chartHeader
                    conditionIcons
                    metricChart

                    chartMetricCards
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle(selectedMetric.title(locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localizedString("Done", locale: locale)) {
                        dismiss()
                    }
                }
            }
            .tint(theme.colors.primaryText)
        }
    }

    /// Title, selected range value, and literal date context above the plot.
    private var chartHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(selectedMetric.title(locale: locale), systemImage: selectedMetric.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.colors.secondaryText)

            Text(chartSummary)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(chartDateLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.colors.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    /// Weather symbols aligned in the same cadence as the plot below.
    private var conditionIcons: some View {
        let symbols: [String] = {
            switch selectedRange {
            case .day:
                return stride(from: 0, to: initialForecast.hourlyForecasts.count, by: 3).map {
                    initialForecast.hourlyForecasts[$0].symbolName
                }
            case .forecast:
                return availableForecasts.map(\.symbolName)
            }
        }()

        return HStack(spacing: 0) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                let icon = AppWeatherCondition.fromWeatherSymbol(symbol)?.displayIcon ?? symbol
                Image(systemName: icon)
                    .weatherIconStyle(for: icon)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 24)
        .accessibilityHidden(true)
    }

    /// Selects an hourly or multi-day Swift Charts rendering.
    @ViewBuilder
    private var metricChart: some View {
        switch selectedRange {
        case .day:
            hourlyChart
        case .forecast:
            forecastChart
        }
    }

    /// Hourly bar or line chart for the selected daily forecast.
    private var hourlyChart: some View {
        let points = initialForecast.hourlyForecasts.compactMap {
            DetailChartPoint.hourly(
                $0,
                metric: selectedMetric,
                forecast: initialForecast,
                timeZone: city.timeZone
            )
        }

        return Chart {
            if selectedMetric.usesTemperatureLines {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Value", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(theme.colors.primaryText)

                    PointMark(
                        x: .value("Time", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(theme.colors.background)
                    .symbolSize(24)
                }
            } else {
                ForEach(points) { point in
                    BarMark(
                        x: .value("Time", point.date),
                        y: .value("Value", point.value),
                        width: .ratio(0.55)
                    )
                    .foregroundStyle(barColor(for: point.value))
                    .clipShape(Capsule())
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                AxisGridLine().foregroundStyle(theme.colors.secondaryText.opacity(0.16))
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine().foregroundStyle(theme.colors.secondaryText.opacity(0.16))
                AxisValueLabel()
            }
        }
        .frame(height: 280)
        .accessibilityLabel(selectedMetric.title(locale: locale))
    }

    /// Available-days chart using every real forecast returned for the city.
    private var forecastChart: some View {
        let points = availableForecasts.compactMap {
            DetailChartPoint.daily($0, metric: selectedMetric, timeZone: city.timeZone)
        }

        return Chart {
            if selectedMetric.usesTemperatureLines {
                ForEach(points) { point in
                    if let lower = point.lowerValue, let upper = point.upperValue {
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("High", upper),
                            series: .value("Series", "High")
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(theme.colors.primaryText)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("High", upper)
                        )
                        .foregroundStyle(theme.colors.background)
                        .symbolSize(28)

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Low", lower),
                            series: .value("Series", "Low")
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(theme.colors.secondaryText)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Low", lower)
                        )
                        .foregroundStyle(theme.colors.background)
                        .symbolSize(28)
                    }
                }
            } else {
                ForEach(points) { point in
                    BarMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value),
                        width: .ratio(0.38)
                    )
                    .foregroundStyle(barColor(for: point.value))
                    .clipShape(Capsule())
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisGridLine().foregroundStyle(theme.colors.secondaryText.opacity(0.16))
                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine().foregroundStyle(theme.colors.secondaryText.opacity(0.16))
                AxisValueLabel()
            }
        }
        .frame(height: 280)
        .accessibilityLabel(selectedMetric.title(locale: locale))
    }

    /// The same six cards become an in-sheet metric switcher.
    private var chartMetricCards: some View {
        let columns = UIDevice.current.userInterfaceIdiom == .pad
            ? [GridItem(.adaptive(minimum: 200), spacing: 10)]
            : [GridItem(.flexible()), GridItem(.flexible())]

        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(DetailChartMetric.allCases) { metric in
                DetailMetricCard(
                    metric: metric,
                    value: metric.summary(
                        for: initialForecast,
                        city: city,
                        temperatureUnit: temperatureUnit,
                        locale: locale
                    ),
                    isSelected: selectedMetric == metric,
                    action: {
                        withAnimation(.smooth(duration: 0.2)) {
                            selectedMetric = metric
                        }
                    }
                )
            }
        }
    }

    /// Real forecast horizon, capped at Weather Atlas's ten-day presentation.
    private var availableForecasts: [DailyForecast] {
        Array(city.dailyForecasts.prefix(10))
    }

    /// Value range printed above the selected chart.
    private var chartSummary: String {
        switch selectedRange {
        case .day:
            return selectedMetric.summary(
                for: initialForecast,
                city: city,
                temperatureUnit: temperatureUnit,
                locale: locale
            )
        case .forecast:
            return selectedMetric.forecastSummary(
                availableForecasts,
                city: city,
                temperatureUnit: temperatureUnit,
                locale: locale
            )
        }
    }

    /// Literal selected date or the actual available forecast range.
    private var chartDateLabel: String {
        var style = Date.FormatStyle.dateTime.day().month(.wide).weekday(.wide).locale(locale)
        style.timeZone = city.timeZone
        switch selectedRange {
        case .day:
            return initialForecast.date.formatted(style)
        case .forecast:
            guard let first = availableForecasts.first, let last = availableForecasts.last else {
                return ""
            }
            return "\(first.date.formatted(style)) – \(last.date.formatted(style))"
        }
    }

    /// Semantic chart color with UV risk bands and otherwise primary styling.
    private func barColor(for value: Double) -> Color {
        if selectedMetric == .sunnyHours {
            return value >= 1 ? theme.colors.dotSun : theme.colors.dotPartlyCloudy
        }
        return theme.colors.primaryText
    }
}

// MARK: - Metric Formatting

private extension DetailChartMetric {
    var usesTemperatureLines: Bool {
        self == .temperature || self == .feelsLike
    }

    /// Card value for one selected day.
    func summary(
        for forecast: DailyForecast,
        city: CityWeather,
        temperatureUnit: TemperatureUnit,
        locale: Locale
    ) -> String {
        switch self {
        case .sunnyHours:
            guard case .success(let data) = SunninessScoring.sunnyHoursData(
                for: forecast,
                timeZone: city.timeZone
            ) else {
                return "—"
            }
            guard let range = SunninessScoring.longestSunnyHourRange(
                in: data.hours,
                timeZone: city.timeZone
            ) else {
                return localizedString("No Sun", locale: locale)
            }
            return "\(SunninessScoring.compactHourLabel(range.lowerBound, locale: locale)) – \(SunninessScoring.compactHourLabel(range.upperBound + 1, locale: locale))"
        case .cloudCover:
            return forecast.cloudCoverPercent.map { "\($0)%" } ?? "—"
        case .temperature:
            return temperatureRange(
                low: forecast.dailyLow,
                high: forecast.dailyHigh,
                unit: temperatureUnit
            )
        case .feelsLike:
            let values = forecast.hourlyForecasts.compactMap(\.apparentTemperature)
            guard let low = values.min(), let high = values.max() else { return "—" }
            return temperatureRange(low: low, high: high, unit: temperatureUnit)
        case .rainChance:
            return forecast.precipitationChance.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
        case .uvIndex:
            return forecast.uvIndex.map(String.init) ?? "—"
        }
    }

    /// Aggregate value range across the actual available forecast horizon.
    func forecastSummary(
        _ forecasts: [DailyForecast],
        city: CityWeather,
        temperatureUnit: TemperatureUnit,
        locale: Locale
    ) -> String {
        guard !forecasts.isEmpty else { return "—" }
        switch self {
        case .sunnyHours:
            let totals = forecasts.compactMap {
                DetailChartPoint.daily($0, metric: self, timeZone: city.timeZone)?.value
            }
            return numericRange(totals, suffix: "h")
        case .cloudCover:
            return numericRange(forecasts.compactMap { $0.cloudCover.map { $0 * 100 } }, suffix: "%")
        case .temperature:
            guard let low = forecasts.map(\.dailyLow).min(),
                  let high = forecasts.map(\.dailyHigh).max() else { return "—" }
            return temperatureRange(low: low, high: high, unit: temperatureUnit)
        case .feelsLike:
            let values = forecasts.flatMap(\.hourlyForecasts).compactMap(\.apparentTemperature)
            guard let low = values.min(), let high = values.max() else { return "—" }
            return temperatureRange(low: low, high: high, unit: temperatureUnit)
        case .rainChance:
            return numericRange(
                forecasts.compactMap { $0.precipitationChance.map { $0 * 100 } },
                suffix: "%"
            )
        case .uvIndex:
            return numericRange(forecasts.compactMap { $0.uvIndex.map(Double.init) }, suffix: "")
        }
    }

    func temperatureRange(low: Double, high: Double, unit: TemperatureUnit) -> String {
        "\(unit.display(low)) – \(unit.display(high))"
    }

    func numericRange(_ values: [Double], suffix: String) -> String {
        guard let low = values.min(), let high = values.max() else { return "—" }
        return "\(Int(low.rounded())) – \(Int(high.rounded()))\(suffix)"
    }
}

// MARK: - Chart Data

/// Normalized point consumed by both hourly and available-days charts.
private struct DetailChartPoint: Identifiable {
    let date: Date
    let value: Double
    let lowerValue: Double?
    let upperValue: Double?

    var id: Date { date }

    static func hourly(
        _ hour: HourlyForecast,
        metric: DetailChartMetric,
        forecast: DailyForecast,
        timeZone: TimeZone
    ) -> DetailChartPoint? {
        let value: Double?
        switch metric {
        case .sunnyHours:
            guard case .success(let data) = SunninessScoring.sunnyHoursData(
                for: forecast,
                timeZone: timeZone
            ) else {
                return nil
            }
            guard data.hours.contains(where: { $0.date == hour.date }) else {
                return DetailChartPoint(
                    date: hour.date,
                    value: 0,
                    lowerValue: nil,
                    upperValue: nil
                )
            }
            switch SunninessScoring.condition(for: hour.symbolName) {
            case .clear: value = 1
            case .partlySunny: value = 0.5
            case .partlyCloudy, .cloudy, .rain, .drizzle, .snow, .fog, .wind: value = 0
            case nil: value = nil
            }
        case .cloudCover: value = hour.cloudCover.map { $0 * 100 }
        case .temperature: value = hour.temperature
        case .feelsLike: value = hour.apparentTemperature
        case .rainChance: value = hour.precipitationChance.map { $0 * 100 }
        case .uvIndex: value = hour.uvIndex.map(Double.init)
        }
        guard let value else { return nil }
        return DetailChartPoint(date: hour.date, value: value, lowerValue: nil, upperValue: nil)
    }

    static func daily(
        _ forecast: DailyForecast,
        metric: DetailChartMetric,
        timeZone: TimeZone
    ) -> DetailChartPoint? {
        switch metric {
        case .sunnyHours:
            guard case .success(let data) = SunninessScoring.sunnyHoursData(
                for: forecast,
                timeZone: timeZone
            ) else {
                return nil
            }
            let value = data.hours.reduce(into: 0.0) { total, hour in
                switch SunninessScoring.condition(for: hour.symbolName) {
                case .clear: total += 1
                case .partlySunny: total += 0.5
                default: break
                }
            }
            return DetailChartPoint(date: forecast.date, value: value, lowerValue: nil, upperValue: nil)
        case .cloudCover:
            guard let value = forecast.cloudCover.map({ $0 * 100 }) else { return nil }
            return DetailChartPoint(date: forecast.date, value: value, lowerValue: nil, upperValue: nil)
        case .temperature:
            return DetailChartPoint(
                date: forecast.date,
                value: forecast.dailyHigh,
                lowerValue: forecast.dailyLow,
                upperValue: forecast.dailyHigh
            )
        case .feelsLike:
            let values = forecast.hourlyForecasts.compactMap(\.apparentTemperature)
            guard let low = values.min(), let high = values.max() else { return nil }
            return DetailChartPoint(date: forecast.date, value: high, lowerValue: low, upperValue: high)
        case .rainChance:
            guard let value = forecast.precipitationChance.map({ $0 * 100 }) else { return nil }
            return DetailChartPoint(date: forecast.date, value: value, lowerValue: nil, upperValue: nil)
        case .uvIndex:
            guard let value = forecast.uvIndex.map(Double.init) else { return nil }
            return DetailChartPoint(date: forecast.date, value: value, lowerValue: nil, upperValue: nil)
        }
    }
}
