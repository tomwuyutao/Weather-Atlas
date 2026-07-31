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
    case temperature
    case feelsLike
    case cloudCover
    case rainChance
    case visibility
    case uvIndex

    var id: String { rawValue }

    /// SF Symbol shared by the Detail card and chart title.
    var systemImage: String {
        switch self {
        case .temperature: "thermometer.medium"
        case .feelsLike: "thermometer.variable"
        case .cloudCover: "cloud"
        case .rainChance: "drop.fill"
        case .visibility: "eye"
        case .uvIndex: "sun.max.trianglebadge.exclamationmark"
        }
    }

    /// Localized user-facing metric title.
    func title(locale: Locale) -> String {
        switch self {
        case .temperature: localizedString("Temperature", locale: locale)
        case .feelsLike: localizedString("Feels Like", locale: locale)
        case .cloudCover: localizedString("Cloud Cover", locale: locale)
        case .rainChance: localizedString("Rain Chance", locale: locale)
        case .visibility: localizedString("Visibility", locale: locale)
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

/// Stable icon identity derived from the represented forecast instant.
private struct ChartConditionIcon: Identifiable {
    let id: Date
    let symbolName: String
    let condition: AppWeatherCondition?
}

// MARK: - Detail Metric Grid

/// Six-card Detail selector that presents the chart sheet at the tapped metric.
struct DetailMetricGrid: View {
    let city: CityWeather
    let forecast: DailyForecast
    let temperatureUnit: TemperatureUnit
    let usesLandscapeIPadLayout: Bool
    /// App-wide forecast date shared with the Detail screen and chart sheet.
    let selectedForecastDate: Binding<Date>

    /// Persisted display unit for visibility values.
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.defaultRawValue

    @State private var presentedMetric: DetailChartMetric?

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        metricCards(selectedMetric: nil) { metric in
            presentedMetric = metric
        }
        .sheet(item: $presentedMetric) { metric in
            DetailChartView(
                city: city,
                initialForecast: forecast,
                initialMetric: metric,
                temperatureUnit: temperatureUnit,
                selectedForecastDate: selectedForecastDate
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
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [
                GridItem(
                    .adaptive(
                        minimum: usesLandscapeIPadLayout ? 200 : 150
                    ),
                    spacing: 10
                )
            ]

        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(DetailChartMetric.allCases) { metric in
                DetailMetricCard(
                    metric: metric,
                    value: metric.summary(
                        for: forecast,
                        city: city,
                        temperatureUnit: temperatureUnit,
                        distanceUnit: DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers,
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
            HStack(spacing: 10) {
                Image(systemName: metric.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(metricTint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.title(locale: locale))
                        .font(.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                    Text(value)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
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
                    .stroke(theme.colors.accent, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(metric.title(locale: locale))
        .accessibilityValue(value)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var metricTint: Color {
        switch metric {
        case .temperature, .feelsLike:
            theme.colors.sunForeground
        case .cloudCover:
            theme.colors.cloudyForeground
        case .rainChance:
            theme.colors.drizzleForeground
        case .visibility:
            theme.colors.accent
        case .uvIndex:
            theme.colors.destructive
        }
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
    /// Keeps Chart View synchronized with Detail View's selected forecast day.
    @Binding private var selectedForecastDate: Date

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Persisted display unit for visibility values.
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.defaultRawValue

    init(
        city: CityWeather,
        initialForecast: DailyForecast,
        initialMetric: DetailChartMetric,
        temperatureUnit: TemperatureUnit,
        selectedForecastDate: Binding<Date>
    ) {
        self.city = city
        self.initialForecast = initialForecast
        self.initialMetric = initialMetric
        self.temperatureUnit = temperatureUnit
        _selectedMetric = State(initialValue: initialMetric)
        _selectedForecastDate = selectedForecastDate
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    ForecastDateStrip(
                        selection: $selectedForecastDate,
                        availableDates: chartSelectionDates
                    )
                    .padding(.horizontal, -16)

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
                    temperatureSeriesLegend
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .tint(theme.colors.accent)
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

            Text(chartDateLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.colors.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var temperatureSeriesLegend: some View {
        if selectedRange == .forecast && selectedMetric.usesTemperatureLines {
            HStack(spacing: 18) {
                Label("High", systemImage: "circle.fill")
                    .foregroundStyle(metricColor)
                Label("Low", systemImage: "diamond.fill")
                    .foregroundStyle(dailyLowTemperatureColor)
            }
            .font(.caption.weight(.semibold))
            .accessibilityElement(children: .combine)
        }
    }

    /// Weather symbols aligned in the same cadence as the plot below.
    private var conditionIcons: some View {
        let symbols: [ChartConditionIcon] = {
            switch selectedRange {
            case .day:
                return stride(from: 0, to: chartForecast.hourlyForecasts.count, by: 3).map {
                    let forecast = chartForecast.hourlyForecasts[$0]
                    return ChartConditionIcon(
                        id: forecast.id,
                        symbolName: forecast.symbolName,
                        condition: SunninessScoring.condition(for: forecast)
                    )
                }
            case .forecast:
                return availableForecasts.map {
                    ChartConditionIcon(
                        id: $0.id,
                        symbolName: $0.symbolName,
                        condition: SunninessScoring.condition(for: $0)
                    )
                }
            }
        }()

        return HStack(spacing: 0) {
            ForEach(symbols) { symbol in
                let icon = symbol.condition?.displayIcon ?? symbol.symbolName
                Image(systemName: icon)
                    .weatherIconStyle(for: icon)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 44 : 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Forecast conditions")
        .accessibilityValue(conditionAccessibilitySummary(for: symbols))
    }

    /// Selects an hourly or multi-day Swift Charts rendering.
    ///
    /// Day charts use SwiftUI's page-style `TabView`, giving the plot its
    /// native interactive swipe transition while keeping the rest of the sheet
    /// vertically scrollable and stationary.
    @ViewBuilder
    private var metricChart: some View {
        switch selectedRange {
        case .day:
            TabView(selection: $selectedForecastDate) {
                ForEach(chartSelectionDates, id: \.self) { date in
                    hourlyChart(
                        for: city.forecastIfAvailable(on: date) ?? initialForecast
                    )
                    .tag(date)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // A paged TabView inside ScrollView needs an explicit height;
            // otherwise SwiftUI gives it no vertical proposal and the chart
            // pages appear blank.
            .frame(height: chartHeight)
        case .forecast:
            forecastChart
        }
    }

    /// Hourly line chart for one forecast page in the native date pager.
    private func hourlyChart(for forecast: DailyForecast) -> some View {
        let points = forecast.hourlyForecasts.compactMap {
            DetailChartPoint.hourly(
                $0,
                metric: selectedMetric,
                distanceUnit: DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
            )
        }
        let domain = yAxisDomain(for: points)

        return Chart {
            if selectedMetric.usesTemperatureLines {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value(
                            selectedMetric.title(locale: locale),
                            point.value
                        )
                    )
                    .foregroundStyle(metricColor)

                    PointMark(
                        x: .value("Time", point.date),
                        y: .value(
                            selectedMetric.title(locale: locale),
                            point.value
                        )
                    )
                    .foregroundStyle(metricColor)
                    .symbolSize(24)
                    .symbol(.circle)
                }
            } else {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value(
                            selectedMetric.title(locale: locale),
                            point.value
                        )
                    )
                    .foregroundStyle(metricColor)

                    PointMark(
                        x: .value("Time", point.date),
                        y: .value(
                            selectedMetric.title(locale: locale),
                            point.value
                        )
                    )
                    .foregroundStyle(metricColor)
                    .symbolSize(24)
                    .symbol(.circle)
                }
            }
        }
        // The scale's real upper bound is also the uppermost native axis grid
        // line. Do not add a separate cap mark, which can drift from the plot.
        .chartYScale(domain: domain, range: .plotDimension(startPadding: 0, endPadding: 0))
        // Keep endpoint symbols and the trailing scale clear of the plot edges.
        .chartXScale(range: .plotDimension(startPadding: 12, endPadding: 18))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                AxisGridLine().foregroundStyle(theme.colors.secondaryText.opacity(0.16))
                // Extend each vertical division below the plot before its label.
                AxisTick(
                    centered: true,
                    length: 10,
                    stroke: StrokeStyle(lineWidth: 1)
                )
                .foregroundStyle(theme.colors.secondaryText.opacity(0.28))
                AxisValueLabel(format: hourlyAxisFormat)
                    .foregroundStyle(theme.colors.secondaryText)
                    .offset(y: 7)
            }
        }
        .chartYAxis {
            AxisMarks(preset: .aligned, position: .trailing, values: yAxisValues(for: domain)) { value in
                AxisGridLine().foregroundStyle(theme.colors.secondaryText.opacity(0.16))
                AxisValueLabel {
                    if let numericValue = value.as(Double.self) {
                        Text(
                            selectedMetric.axisLabel(
                                for: numericValue,
                                locale: locale
                            )
                        )
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }
                .offset(y: 7)
            }
        }
        .frame(height: chartHeight)
        .accessibilityLabel(selectedMetric.title(locale: locale))
    }

    /// Available-days chart using every real forecast returned for the city.
    private var forecastChart: some View {
        let points = availableForecasts.compactMap {
            DetailChartPoint.daily(
                $0,
                metric: selectedMetric,
                distanceUnit: DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
            )
        }
        let domain = yAxisDomain(for: points)

        return Chart {
            if selectedMetric.usesTemperatureLines {
                ForEach(points) { point in
                    if let lower = point.lowerValue, let upper = point.upperValue {
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("High", upper),
                            series: .value("Series", "High")
                        )
                        .foregroundStyle(metricColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("High", upper)
                        )
                        .foregroundStyle(metricColor)
                        .symbolSize(28)
                        .symbol(.circle)

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Low", lower),
                            series: .value("Series", "Low")
                        )
                        // The 10-day low series uses the palette's rain blue,
                        // distinct from the sunny high series.
                        .foregroundStyle(dailyLowTemperatureColor)
                        .lineStyle(
                            StrokeStyle(
                                lineWidth: 2,
                                dash: [6, 4]
                            )
                        )

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Low", lower)
                        )
                        .foregroundStyle(dailyLowTemperatureColor)
                        .symbolSize(28)
                        .symbol(.diamond)
                    }
                }
            } else {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(
                            selectedMetric.title(locale: locale),
                            point.value
                        )
                    )
                    .foregroundStyle(metricColor)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value(
                            selectedMetric.title(locale: locale),
                            point.value
                        )
                    )
                    .foregroundStyle(metricColor)
                    .symbolSize(28)
                    .symbol(.circle)
                }
            }
        }
        .chartYScale(domain: domain, range: .plotDimension(startPadding: 0, endPadding: 0))
        .chartXScale(range: .plotDimension(startPadding: 12, endPadding: 18))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisGridLine().foregroundStyle(theme.colors.secondaryText.opacity(0.16))
                AxisTick(
                    centered: true,
                    length: 10,
                    stroke: StrokeStyle(lineWidth: 1)
                )
                .foregroundStyle(theme.colors.secondaryText.opacity(0.28))
                AxisValueLabel(format: weekdayAxisFormat)
                    .foregroundStyle(theme.colors.secondaryText)
                    .offset(y: 7)
            }
        }
        .chartYAxis {
            AxisMarks(preset: .aligned, position: .trailing, values: yAxisValues(for: domain)) { value in
                AxisGridLine().foregroundStyle(theme.colors.secondaryText.opacity(0.16))
                AxisValueLabel {
                    if let numericValue = value.as(Double.self) {
                        Text(
                            selectedMetric.axisLabel(
                                for: numericValue,
                                locale: locale
                            )
                        )
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }
                .offset(y: 7)
            }
        }
        .frame(height: chartHeight)
        .accessibilityLabel(selectedMetric.title(locale: locale))
    }

    /// The same six cards become an in-sheet metric switcher.
    private var chartMetricCards: some View {
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : UIDevice.current.userInterfaceIdiom == .pad
            ? [GridItem(.adaptive(minimum: 200), spacing: 10)]
            : [GridItem(.flexible()), GridItem(.flexible())]

        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(DetailChartMetric.allCases) { metric in
                DetailMetricCard(
                    metric: metric,
                    value: metric.summary(
                        for: chartForecast,
                        city: city,
                        temperatureUnit: temperatureUnit,
                        distanceUnit: DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers,
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
                for: chartForecast,
                city: city,
                temperatureUnit: temperatureUnit,
                distanceUnit: DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers,
                locale: locale
            )
        case .forecast:
            return selectedMetric.forecastSummary(
                availableForecasts,
                city: city,
                temperatureUnit: temperatureUnit,
                distanceUnit: DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers,
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
            return chartForecast.date.formatted(style)
        case .forecast:
            guard let first = availableForecasts.first, let last = availableForecasts.last else {
                return ""
            }
            return "\(first.date.formatted(style)) – \(last.date.formatted(style))"
        }
    }

    private var hourlyAxisFormat: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime
            .hour()
            .locale(locale)
        style.timeZone = city.timeZone
        return style
    }

    private var weekdayAxisFormat: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime
            .weekday(.abbreviated)
            .locale(locale)
        style.timeZone = city.timeZone
        return style
    }

    /// Gives VoiceOver the same time-varying condition sequence represented by
    /// the otherwise image-only symbol strip.
    private func conditionAccessibilitySummary(
        for symbols: [ChartConditionIcon]
    ) -> String {
        var timeStyle = Date.FormatStyle.dateTime
            .hour()
            .locale(locale)
        timeStyle.timeZone = city.timeZone
        var dayStyle = Date.FormatStyle.dateTime
            .weekday(.abbreviated)
            .locale(locale)
        dayStyle.timeZone = city.timeZone

        return symbols.map { symbol in
            let condition = (
                symbol.condition
                    ?? AppWeatherCondition.fromWeatherSymbol(symbol.symbolName)
            )?.localizedDisplayName(locale: locale)
                ?? localizedString("Forecast unavailable", locale: locale)
            let dateLabel = symbol.id.formatted(
                selectedRange == .day ? timeStyle : dayStyle
            )
            return "\(dateLabel), \(condition)"
        }
        .joined(separator: "; ")
    }

    /// Reuses only Weather Atlas palette colors and follows the resolved theme.
    private var metricColor: Color {
        switch selectedMetric {
        case .temperature, .feelsLike: theme.colors.sunForeground
        case .cloudCover: theme.colors.rainForeground
        case .rainChance: theme.colors.drizzleForeground
        case .visibility: theme.colors.secondaryText
        case .uvIndex: theme.colors.destructive
        }
    }

    /// Shared low-temperature color for Temperature and Feels Like 10-day lines.
    private var dailyLowTemperatureColor: Color {
        theme.colors.rainForeground
    }

    /// Forecast matching the app-wide selected day, with the opening day as a
    /// safe fallback while a forecast refresh temporarily changes its date range.
    private var chartForecast: DailyForecast {
        city.forecastIfAvailable(on: selectedForecastDate) ?? initialForecast
    }

    /// Device-calendar dates that this city's real forecast can display.
    private var chartSelectionDates: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return Array(
            Set(city.dailyForecasts.compactMap {
                city.selectionDate(for: $0)
            })
            .filter { $0 >= today }
        )
        .sorted()
    }

    /// Keeps percentages fixed and rounds other bounds outward for readable headroom.
    private func yAxisDomain(for points: [DetailChartPoint]) -> ClosedRange<Double> {
        if selectedMetric.usesPercentageScale {
            return 0...100
        }
        guard !points.isEmpty else { return 0...1 }
        let minimum = points.map { $0.lowerValue ?? $0.value }.min() ?? 0
        let maximum = points.map { $0.upperValue ?? $0.value }.max() ?? 1
        let span = max(maximum - minimum, 1)
        // Add a small, rounded margin without letting the axis dominate the
        // data. This keeps values legible near the chart edge while avoiding
        // the overly broad ranges caused by the earlier half-step padding.
        let step = roundedAxisStep(for: span / 5)
        let roundedLower = floor((minimum - step * 0.15) / step) * step
        // Visibility, UV, and percentage values have no meaningful negative
        // range. Temperature and feels-like temperature remain unrestricted.
        let lower = selectedMetric.usesNonNegativeScale ? max(0, roundedLower) : roundedLower
        let upper = ceil((maximum + step * 0.15) / step) * step
        return lower...max(upper, lower + step)
    }

    /// Compact shared height for hourly and available-days charts.
    private var chartHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 260 : 200
    }

    /// Includes both domain boundaries, making the uppermost native gridline
    /// the visible chart cap rather than relying on a separate RuleMark.
    private func yAxisValues(for domain: ClosedRange<Double>) -> [Double] {
        if selectedMetric.usesPercentageScale {
            return [0, 25, 50, 75, 100]
        }

        let interval = (domain.upperBound - domain.lowerBound) / 4
        return (0...4).map { domain.lowerBound + Double($0) * interval }
    }

    /// Chooses a familiar 1–2–5 axis interval at the required magnitude.
    private func roundedAxisStep(for rawStep: Double) -> Double {
        let magnitude = pow(10, floor(log10(max(rawStep, 0.000_001))))
        let normalized = rawStep / magnitude
        let multiplier: Double
        switch normalized {
        case ...1: multiplier = 1
        case ...2: multiplier = 2
        case ...5: multiplier = 5
        default: multiplier = 10
        }
        return multiplier * magnitude
    }
}

// MARK: - Metric Formatting

private extension DetailChartMetric {
    var usesTemperatureLines: Bool {
        self == .temperature || self == .feelsLike
    }

    var usesPercentageScale: Bool {
        self == .cloudCover || self == .rainChance
    }

    /// Metrics that represent a physical quantity with zero as their floor.
    var usesNonNegativeScale: Bool {
        self == .cloudCover || self == .rainChance || self == .visibility || self == .uvIndex
    }

    /// Formats the explicit axis ticks without introducing values outside the
    /// chart's real scale domain.
    func axisLabel(for value: Double, locale: Locale) -> String {
        if usesPercentageScale {
            return (value / 100).formatted(
                .percent
                    .precision(.fractionLength(0))
                    .locale(locale)
            )
        }

        let roundedValue = value.rounded()
        if abs(value - roundedValue) < 0.001 {
            return Int(roundedValue).formatted(
                .number.locale(locale)
            )
        }
        return value.formatted(
            .number
                .precision(.fractionLength(1))
                .locale(locale)
        )
    }

    /// Card value for one selected day.
    func summary(
        for forecast: DailyForecast,
        city: CityWeather,
        temperatureUnit: TemperatureUnit,
        distanceUnit: DistanceUnit,
        locale: Locale
    ) -> String {
        switch self {
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
        case .cloudCover:
            return forecast.cloudCoverPercent.map { "\($0)%" } ?? "—"
        case .rainChance:
            return forecast.precipitationChance.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
        case .visibility:
            return forecast.averageVisibilityKilometers.map(distanceUnit.display) ?? "—"
        case .uvIndex:
            return forecast.uvIndex.map(String.init) ?? "—"
        }
    }

    /// Aggregate value range across the actual available forecast horizon.
    func forecastSummary(
        _ forecasts: [DailyForecast],
        city: CityWeather,
        temperatureUnit: TemperatureUnit,
        distanceUnit: DistanceUnit,
        locale: Locale
    ) -> String {
        guard !forecasts.isEmpty else { return "—" }
        switch self {
        case .temperature:
            guard let low = forecasts.map(\.dailyLow).min(),
                  let high = forecasts.map(\.dailyHigh).max() else { return "—" }
            return temperatureRange(low: low, high: high, unit: temperatureUnit)
        case .feelsLike:
            // WeatherKit provides no daily apparent-temperature aggregate, but
            // each forecast day retains its own real hourly readings. Keep the
            // 10-day headline consistent with the plotted daily low/high data.
            let dailyRanges = forecasts.compactMap { forecast -> (Double, Double)? in
                let values = forecast.hourlyForecasts.compactMap(\.apparentTemperature)
                guard let low = values.min(), let high = values.max() else { return nil }
                return (low, high)
            }
            guard let low = dailyRanges.map(\.0).min(),
                  let high = dailyRanges.map(\.1).max() else { return "—" }
            return temperatureRange(low: low, high: high, unit: temperatureUnit)
        case .cloudCover:
            return numericRange(forecasts.compactMap { $0.cloudCover.map { $0 * 100 } }, suffix: "%")
        case .rainChance:
            return numericRange(
                forecasts.compactMap { $0.precipitationChance.map { $0 * 100 } },
                suffix: "%"
            )
        case .visibility:
            return visibilityRange(
                forecasts.compactMap(\.averageVisibilityKilometers),
                unit: distanceUnit
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

    func visibilityRange(_ values: [Double], unit: DistanceUnit) -> String {
        guard let low = values.min(), let high = values.max() else { return "—" }
        return "\(unit.display(low)) – \(unit.display(high))"
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
        distanceUnit: DistanceUnit
    ) -> DetailChartPoint? {
        let value: Double?
        switch metric {
        case .temperature: value = hour.temperature
        case .feelsLike: value = hour.apparentTemperature
        case .cloudCover: value = hour.cloudCover.map { $0 * 100 }
        case .rainChance: value = hour.precipitationChance.map { $0 * 100 }
        case .visibility: value = hour.visibilityKilometers.map(distanceUnit.value(fromKilometers:))
        case .uvIndex: value = hour.uvIndex.map(Double.init)
        }
        guard let value else { return nil }
        return DetailChartPoint(date: hour.date, value: value, lowerValue: nil, upperValue: nil)
    }

    static func daily(
        _ forecast: DailyForecast,
        metric: DetailChartMetric,
        distanceUnit: DistanceUnit
    ) -> DetailChartPoint? {
        switch metric {
        case .temperature:
            return DetailChartPoint(
                date: forecast.date,
                value: forecast.dailyHigh,
                lowerValue: forecast.dailyLow,
                upperValue: forecast.dailyHigh
            )
        case .feelsLike:
            // WeatherKit has no daily apparent-temperature aggregate. Use only
            // the actual hourly apparent-temperature readings belonging to this
            // day; do not fabricate a value when its hourly data is absent.
            let values = forecast.hourlyForecasts.compactMap(\.apparentTemperature)
            guard let low = values.min(), let high = values.max() else { return nil }
            return DetailChartPoint(
                date: forecast.date,
                value: high,
                lowerValue: low,
                upperValue: high
            )
        case .cloudCover:
            guard let value = forecast.cloudCover else { return nil }
            return DetailChartPoint(date: forecast.date, value: value * 100, lowerValue: nil, upperValue: nil)
        case .rainChance:
            guard let value = forecast.precipitationChance else { return nil }
            return DetailChartPoint(date: forecast.date, value: value * 100, lowerValue: nil, upperValue: nil)
        case .visibility:
            guard let value = forecast.averageVisibilityKilometers else { return nil }
            return DetailChartPoint(
                date: forecast.date,
                value: distanceUnit.value(fromKilometers: value),
                lowerValue: nil,
                upperValue: nil
            )
        case .uvIndex:
            guard let value = forecast.uvIndex.map(Double.init) else { return nil }
            return DetailChartPoint(date: forecast.date, value: value, lowerValue: nil, upperValue: nil)
        }
    }
}
