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
    /// Raw values provide a stable identity for `ForEach`, Picker tags, and
    /// the item-driven sheet; localized titles are computed separately.
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

// MARK: - Chart Annotation Model

/// Stable icon identity derived from the represented forecast instant.
private struct ChartConditionIcon: Identifiable {
    let id: Date
    let symbolName: String
    let condition: AppWeatherCondition?
}

// MARK: - Detail Metric Grid

/// Six-card Detail selector that presents the chart sheet at the tapped metric.
struct DetailMetricGrid: View {
    // MARK: Inputs and Local Sheet State

    /// Optional inputs let report screens preserve all six card shells before
    /// weather arrives or after a request fails.
    let city: CityWeather?
    /// Report-owned place name, including any saved custom name.
    let placeDisplayName: String
    let forecast: DailyForecast?
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

    /// Loaded Detail reports retain their existing call shape.
    init(
        city: CityWeather,
        placeDisplayName: String,
        forecast: DailyForecast,
        temperatureUnit: TemperatureUnit,
        usesLandscapeIPadLayout: Bool,
        selectedForecastDate: Binding<Date>
    ) {
        self.city = city
        self.placeDisplayName = placeDisplayName
        self.forecast = forecast
        self.temperatureUnit = temperatureUnit
        self.usesLandscapeIPadLayout = usesLandscapeIPadLayout
        self.selectedForecastDate = selectedForecastDate
    }

    /// Persistent report surfaces can pass unavailable values without removing
    /// the grid; each metric then renders an explicit unavailable state.
    init(
        city: CityWeather?,
        placeDisplayName: String,
        forecast: DailyForecast?,
        temperatureUnit: TemperatureUnit,
        usesLandscapeIPadLayout: Bool,
        selectedForecastDate: Binding<Date>
    ) {
        self.city = city
        self.placeDisplayName = placeDisplayName
        self.forecast = forecast
        self.temperatureUnit = temperatureUnit
        self.usesLandscapeIPadLayout = usesLandscapeIPadLayout
        self.selectedForecastDate = selectedForecastDate
    }

    var body: some View {
        let presentation = valuePresentation

        // The optional metric is both the chosen card and the sheet payload.
        // `.sheet(item:)` clears it automatically when the user dismisses.
        metricCards(
            selectedMetric: nil,
            presentation: presentation
        ) { metric in
            presentedMetric = metric
        }
        .sheet(item: $presentedMetric) { metric in
            if let city {
                DetailChartView(
                    city: city,
                    placeDisplayName: placeDisplayName,
                    initialMetric: metric,
                    temperatureUnit: temperatureUnit,
                    selectedForecastDate: selectedForecastDate
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        // The parent report owns the request outcome. Missing metric values
        // remain blank rather than presenting a second alert for the city.
    }

    private var valuePresentation: DetailMetricValuePresentation? {
        guard let city, let forecast else { return nil }
        return DetailMetricValuePresentation(
            city: city,
            forecast: forecast,
            now: .now
        )
    }

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    private func missingDataReport(
        for presentation: DetailMetricValuePresentation?
    ) -> MissingDataAlertReport? {
        guard let city, let forecast, let presentation else { return nil }
        let issues = DetailChartMetric.allCases.compactMap { metric in
            presentation.summary(
                for: metric,
                temperatureUnit: temperatureUnit,
                distanceUnit: distanceUnit,
                locale: locale
            ) == nil
                ? presentation.missingDataIssue(for: metric)
                : nil
        }
        guard !issues.isEmpty else { return nil }
        let uniqueIssues = Array(Set(issues)).sorted {
            $0.kind.rawValue < $1.kind.rawValue
        }
        return MissingDataAlertReport(
            key: "metric-grid:\(city.id.uuidString):\(forecast.date.timeIntervalSinceReferenceDate):\(presentation.identity):\(uniqueIssues.map(\.kind.rawValue).joined(separator: ","))",
            title: localizedString("Weather Data Missing", locale: locale),
            message: Array(Set(uniqueIssues.map {
                weatherDataIssueMessage(
                    $0,
                    cityName: placeDisplayName,
                    locale: locale
                )
            })).sorted().joined(separator: "\n")
        )
    }

    /// Keeps the card order and appearance identical in Detail and the sheet.
    private func metricCards(
        selectedMetric: DetailChartMetric?,
        presentation: DetailMetricValuePresentation?,
        action: @escaping (DetailChartMetric) -> Void
    ) -> some View {
        // Larger text sizes receive a single column so neither metric
        // names nor values have to shrink below a readable size.
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
                let value = presentation?.summary(
                    for: metric,
                    temperatureUnit: temperatureUnit,
                    distanceUnit: distanceUnit,
                    locale: locale
                )
                DetailMetricCard(
                    metric: metric,
                    value: value,
                    // Missing values remain selectable when the city itself
                    // is known: the chart sheet can now explain that field's
                    // unavailable state instead of leaving a dead card.
                    isEnabled: city != nil,
                    isSelected: selectedMetric == metric,
                    action: { action(metric) }
                )
            }
        }
    }
}

/// Chooses the value semantics for the six Detail metric cards. A selected
/// forecast whose day is today in its own location's time zone uses the one
/// WeatherKit hourly sample that represents the current local clock hour.
/// Other selected days retain their existing daily summaries.
private struct DetailMetricValuePresentation {
    let city: CityWeather
    let forecast: DailyForecast
    let usesCurrentHourlyValue: Bool
    private let currentHourlyForecast: HourlyForecast?

    init(
        city: CityWeather,
        forecast: DailyForecast,
        now: Date
    ) {
        self.city = city
        self.forecast = forecast

        var localCalendar = Calendar.autoupdatingCurrent
        localCalendar.timeZone = city.timeZone
        let isCurrentLocalDay = localCalendar.isDate(
            forecast.date,
            inSameDayAs: now
        )
        usesCurrentHourlyValue = isCurrentLocalDay

        guard isCurrentLocalDay,
              let currentHourInterval = localCalendar.dateInterval(
                of: .hour,
                for: now
              ) else {
            currentHourlyForecast = nil
            return
        }

        // Hourly forecast timestamps identify the beginning of their local
        // hour. Matching the half-open hour interval handles DST boundaries
        // without comparing device-local hour numbers.
        currentHourlyForecast = forecast.hourlyForecasts.first {
            currentHourInterval.contains($0.date)
        }
    }

    /// Stable alert identity for a daily summary or its live hourly sample.
    var identity: String {
        guard usesCurrentHourlyValue else { return "daily" }
        guard let currentHourlyForecast else {
            return "current-hour-unavailable"
        }
        return String(
            Int(currentHourlyForecast.date.timeIntervalSinceReferenceDate)
        )
    }

    func summary(
        for metric: DetailChartMetric,
        temperatureUnit: TemperatureUnit,
        distanceUnit: DistanceUnit,
        locale: Locale
    ) -> String? {
        if usesCurrentHourlyValue {
            return metric.currentHourlySummary(
                for: currentHourlyForecast,
                temperatureUnit: temperatureUnit,
                distanceUnit: distanceUnit
            )
        }

        return metric.summary(
            for: forecast,
            city: city,
            temperatureUnit: temperatureUnit,
            distanceUnit: distanceUnit,
            locale: locale
        )
    }

    func missingDataIssue(for metric: DetailChartMetric) -> WeatherDataIssue? {
        if usesCurrentHourlyValue {
            guard let currentHourlyForecast else {
                return .missingHourlyData(at: forecast.date)
            }
            return metric.currentHourlySummaryIssue(for: currentHourlyForecast)
        }

        return metric.dailySummaryIssue(
            for: forecast,
            timeZone: city.timeZone
        )
    }
}

/// One tappable metric card shared verbatim between Detail and Chart View.
private struct DetailMetricCard: View {
    let metric: DetailChartMetric
    let value: String?
    let isEnabled: Bool
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // A plain button preserves the custom glass card while retaining native
        // button semantics and a single full-card hit target. A card remains
        // actionable for a known city even when its selected metric is missing,
        // because the chart sheet now shows a matching explicit state.
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: metric.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .frame(width: 24)
                    // The card's text already names the metric. Keeping this
                    // symbol out of the chart header avoids a duplicate
                    // weather/thermometer announcement before every value.


                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.title(locale: locale))
                        .font(.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                    if let value {
                        Text(value)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(
                                dynamicTypeSize.isAccessibilitySize ? nil : 1
                            )
                            .minimumScaleFactor(
                                dynamicTypeSize.isAccessibilitySize ? 1 : 0.65
                            )
                            .frame(minHeight: 20, alignment: .leading)
                    } else {
                        // A literal em dash looked like a loading artifact.
                        // Keep the unavailable card disabled, but make the
                        // missing-data state clear in the card itself.
                        Label(
                            localizedString(
                                "Weather Data Missing",
                                locale: locale
                            ),
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(
                            dynamicTypeSize.isAccessibilitySize ? nil : 2
                        )
                        .frame(minHeight: 20, alignment: .leading)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(WeatherCardLayout.padding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        // Treat the title and value as one native control. The full card is the
        // action that opens its chart, so the card does not create a competing
        // secondary interaction target.


        // Match Daily and 10-Day Sunny Hours exactly. The Button still owns
        // the full hit target; using the regular report surface prevents the
        // interactive glass variant from introducing a brighter card tint.
        .detailTranslucentCard(
            colorScheme: colorScheme,
            in: RoundedRectangle(
                cornerRadius: WeatherCardLayout.cornerRadius,
                style: .continuous
            )
        )
        .overlay {
            if isSelected {
                // The sheet's metric picker uses this outline; Detail passes
                // `nil` because it has no selected metric before presentation.
                RoundedRectangle(
                    cornerRadius: WeatherCardLayout.cornerRadius,
                    style: .continuous
                )
                    .stroke(theme.colors.primaryText.opacity(0.75), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
    }

}

// MARK: - Chart Sheet

/// Almost-full-screen Detail sheet with native range switching and metric cards.
struct DetailChartView: View {
    // MARK: Immutable Inputs

    let city: CityWeather
    let placeDisplayName: String
    let initialMetric: DetailChartMetric
    let temperatureUnit: TemperatureUnit

    // MARK: View-Owned Selection State

    /// Starts at the card tapped in Detail, then changes inside the sheet.
    @State private var selectedMetric: DetailChartMetric
    /// Segmented control chooses hourly data for one day or daily data across
    /// the real forecast horizon.
    @State private var selectedRange: DetailChartRange = .day
    /// Keeps Chart View synchronized with Detail View's selected forecast day.
    @Binding private var selectedForecastDate: Date

    @Environment(\.appTheme) private var theme
    @Environment(\.calendar) private var forecastCalendar
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Persisted display unit for visibility values.
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.defaultRawValue

    init(
        city: CityWeather,
        placeDisplayName: String,
        initialMetric: DetailChartMetric,
        temperatureUnit: TemperatureUnit,
        selectedForecastDate: Binding<Date>
    ) {
        // `@State` must be initialized through its backing storage so the
        // opening metric becomes persistent local sheet state after creation.
        self.city = city
        self.placeDisplayName = placeDisplayName
        self.initialMetric = initialMetric
        self.temperatureUnit = temperatureUnit
        _selectedMetric = State(initialValue: initialMetric)
        _selectedForecastDate = selectedForecastDate
    }

    var body: some View {
        // The sheet owns an inner navigation stack only for its compact title
        // and standard Close action; it does not push additional destinations.
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

                    // Header, legend, and plot react to both local selectors;
                    // cards below offer a second way to change only the metric.
                    chartHeader
                    temperatureSeriesLegend
                    metricChart

                    // The six cards summarize one selected day. Hiding them in
                    // 10-day mode prevents those day values from appearing to
                    // contradict the aggregate chart heading.
                    if selectedRange == .day {
                        chartMetricCards
                    }
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

                ToolbarItem(placement: .topBarTrailing) {
                    // This binding is shared with the parent Detail report,
                    // keeping chart and report on the exact same calendar day.
                    TopForecastDateSwitcher(
                        selection: $selectedForecastDate,
                        availableDates: chartSelectionDates
                    )
                }
            }
            .tint(theme.colors.accent)
        }
        // A chart can expose a narrower missing field than its parent report;
        // keep that field blank and avoid a second modal error.
    }

    private var chartDataIssue: WeatherDataIssue? {
        switch selectedRange {
        case .day:
            guard let chartForecast else {
                return .missingForecastData(at: selectedForecastDate)
            }
            return selectedMetric.hourlyChartIssue(
                for: chartForecast,
                timeZone: city.timeZone
            )
        case .forecast:
            if let forecastHorizonIssue {
                return forecastHorizonIssue
            }
            guard !availableForecasts.isEmpty else {
                return .missingForecastData(at: selectedForecastDate)
            }
            return availableForecasts.lazy.compactMap {
                selectedMetric.dailyChartIssue(
                    for: $0,
                    timeZone: city.timeZone
                )
            }.first
        }
    }

    /// Current-hour card diagnostics are separate from chart diagnostics: the
    /// hourly chart can be valid even when the one city-local current sample
    /// is absent or missing one metric.
    private var metricCardDataIssues: [WeatherDataIssue] {
        guard selectedRange == .day,
              let metricPresentation else {
            return []
        }

        return DetailChartMetric.allCases.compactMap { metric in
            metricPresentation.summary(
                for: metric,
                temperatureUnit: temperatureUnit,
                distanceUnit: distanceUnit,
                locale: locale
            ) == nil
                ? metricPresentation.missingDataIssue(for: metric)
                : nil
        }
    }

    private var chartConditionIssue: WeatherDataIssue? {
        switch selectedRange {
        case .day:
            guard let chartForecast,
                  let forecast = chartForecast.hourlyForecasts.first(where: {
                      $0.condition == nil
                  }) else { return nil }
            return conditionIssue(
                symbolName: forecast.symbolName,
                date: forecast.date
            )
        case .forecast:
            guard let forecast = availableForecasts.first(where: {
                $0.condition == nil
            }) else { return nil }
            return conditionIssue(
                symbolName: forecast.symbolName,
                date: forecast.date
            )
        }
    }

    private func conditionIssue(
        symbolName: String,
        date: Date
    ) -> WeatherDataIssue {
        let symbol = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        return symbol.isEmpty
            ? .missing(.missingConditionData, at: date)
            : .unknownWeatherSymbol(symbol, at: date)
    }

    private var missingDataReport: MissingDataAlertReport? {
        let issues = Array(
            Set(
                [chartDataIssue, chartConditionIssue].compactMap { $0 }
                    + metricCardDataIssues
            )
        )
            .sorted { $0.kind.rawValue < $1.kind.rawValue }
        guard !issues.isEmpty else { return nil }
        return MissingDataAlertReport(
            key: "detail-chart:\(city.id.uuidString):\(selectedForecastDate.timeIntervalSinceReferenceDate):\(selectedRange.rawValue):\(selectedMetric.rawValue):\(metricPresentation?.identity ?? "no-metric-presentation"):\(issues.map(\.kind.rawValue).joined(separator: ","))",
            title: localizedString("Weather Data Missing", locale: locale),
            message: Array(Set(issues.map {
                weatherDataIssueMessage(
                    $0,
                    cityName: placeDisplayName,
                    locale: locale
                )
            })).sorted().joined(separator: "\n")
        )
    }

    /// Title, selected range value, and literal date context above the plot.
    private var chartHeader: some View {
        // The headline is a formatted value/range; the line below prevents
        // ambiguity about whether it refers to the selected day or ten days.
        VStack(alignment: .leading, spacing: 4) {
            Label(selectedMetric.title(locale: locale), systemImage: selectedMetric.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.colors.secondaryText)

            Text(
                chartSummary
                    ?? localizedString("Forecast Unavailable", locale: locale)
            )
                .font(.system(.title, design: .rounded).weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)

            Text(chartDateLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.colors.secondaryText)
        }
    }

    @ViewBuilder
    private var temperatureSeriesLegend: some View {
        if selectedRange == .forecast,
           selectedMetric.usesTemperatureLines,
           chartDataIssue == nil {
            HStack(spacing: 18) {
                Label("High", systemImage: "circle.fill")
                    .foregroundStyle(metricColor)
                Label("Low", systemImage: "diamond.fill")
                    .foregroundStyle(dailyLowTemperatureColor)
            }
            .font(.caption.weight(.semibold))
        }
    }

    /// Selects an hourly or multi-day Swift Charts rendering.
    ///
    /// The shared bottom date slider is the sole date-changing control, so the
    /// chart itself remains a stable rendering of that selection.
    @ViewBuilder
    private var metricChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            if chartDataIssue == nil {
                switch selectedRange {
                case .day:
                    if let chartForecast {
                        hourlyChart(for: chartForecast)
                    }
                case .forecast:
                    forecastChart
                }
            } else {
                chartUnavailableContent
            }

        }
    }

    /// Uses the same explicit missing-data language as report cards instead of
    /// reserving a blank plot-sized area when a metric cannot be charted.
    private var chartUnavailableContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.title2)
                .foregroundStyle(theme.colors.secondaryText)


            Text("Forecast Unavailable")
                .font(.callout.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)

            Text(chartUnavailableMessage)
                .font(.caption)
                .foregroundStyle(theme.colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: chartHeight)



    }

    private var chartUnavailableMessage: String {
        guard let chartDataIssue else {
            return localizedString(
                "Forecast data is unavailable for the selected date.",
                locale: locale
            )
        }
        return weatherDataIssueMessage(
            chartDataIssue,
            cityName: placeDisplayName,
            locale: locale
        )
    }

    /// Hourly line chart for one forecast page in the native date pager.
    private func hourlyChart(for forecast: DailyForecast) -> some View {
        // Convert domain forecasts to lightweight numeric points once before
        // entering `Chart`; absent metric values simply do not plot a point.
        let points = forecast.hourlyForecasts.compactMap {
            DetailChartPoint.hourly(
                $0,
                metric: selectedMetric,
                distanceUnit: DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
            )
        }
        let domain = yAxisDomain(for: points)
        let icons = hourlyConditionIcons(for: forecast, at: points.map(\.date))

        return Chart {
            if let currentTime = currentTimeIndicator(for: forecast) {
                RuleMark(x: .value("Current time", currentTime))
                    .foregroundStyle(theme.colors.primaryText.opacity(0.72))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))

            }

            if selectedMetric.usesTemperatureLines {
                // Hourly temperature and feels-like plots are one series. The
                // separate high/low treatment applies only to daily forecasts.
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
            // Symbols occupy the top axis, leaving bottom labels free for time
            // while sharing the same x values as their plotted points.
            conditionIconAxisMarks(for: icons)

            AxisMarks(position: .bottom, values: .stride(by: .hour, count: 6)) { value in
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
    }

    /// A live-time rule is meaningful only for the forecast page that is
    /// today in this city's local time. Keeping it inside the represented
    /// hourly range prevents an out-of-range rule from expanding the chart.
    private func currentTimeIndicator(
        for forecast: DailyForecast
    ) -> Date? {
        var cityCalendar = Calendar.autoupdatingCurrent
        cityCalendar.timeZone = city.timeZone
        let now = Date.now

        guard cityCalendar.isDate(forecast.date, inSameDayAs: now),
              let firstHour = forecast.hourlyForecasts.map(\.date).min(),
              let lastHour = forecast.hourlyForecasts.map(\.date).max(),
              now >= firstHour,
              now <= lastHour else {
            return nil
        }

        return now
    }

    /// Available-days chart using every real forecast returned for the city.
    private var forecastChart: some View {
        // Forecast-range points use one point per real daily forecast. For
        // temperature-like metrics each point also carries low/high values.
        let points = availableForecasts.compactMap {
            DetailChartPoint.daily(
                $0,
                metric: selectedMetric,
                distanceUnit: DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
            )
        }
        let domain = yAxisDomain(for: points)
        let icons = dailyConditionIcons(at: points.map(\.date))

        return Chart {
            if selectedMetric.usesTemperatureLines {
                ForEach(points) { point in
                    if let lower = point.lowerValue, let upper = point.upperValue {
                        // Two named series let Swift Charts keep the high and
                        // low lines continuous across forecast days.
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
            conditionIconAxisMarks(for: icons)

            // Use the plotted forecast instants themselves. A calendar stride
            // can resolve in a different time zone from the city's forecasts,
            // which offsets grid lines and labels from their dots.
            AxisMarks(position: .bottom, values: points.map(\.date)) { value in
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
    }

    /// The same six cards become an in-sheet metric switcher.
    private var chartMetricCards: some View {
        // iPad has room for wider adaptive cards; iPhone uses two columns until
        // larger text sizing requests the single-column fallback.
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : UIDevice.current.userInterfaceIdiom == .pad
            ? [GridItem(.adaptive(minimum: 200), spacing: 10)]
            : [GridItem(.flexible()), GridItem(.flexible())]

        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(DetailChartMetric.allCases) { metric in
                let value = metricPresentation?.summary(
                    for: metric,
                    temperatureUnit: temperatureUnit,
                    distanceUnit: distanceUnit,
                    locale: locale
                )
                DetailMetricCard(
                    metric: metric,
                    value: value,
                    isEnabled: true,
                    isSelected: selectedMetric == metric,
                    action: {
                        // Animate only the local metric switch. The selected
                        // date remains untouched so the user's context stays.
                        withAnimation(.smooth(duration: 0.2)) {
                            selectedMetric = metric
                        }
                    }
                )
            }
        }
    }

    /// Valid multi-day source horizon after any explicit timezone-edge omission.
    private var availableForecasts: [DailyForecast] {
        validatedForecastHorizon?.forecasts ?? []
    }

    private var validatedForecastHorizon: ForecastValidation.TenDayForecastData? {
        guard case .success(let horizon) = forecastHorizonResult else {
            return nil
        }
        return horizon
    }

    private var forecastHorizonIssue: WeatherDataIssue? {
        guard case .failure(let issue) = forecastHorizonResult else {
            return nil
        }
        return issue
    }

    private var forecastHorizonResult: Result<
        ForecastValidation.TenDayForecastData,
        WeatherDataIssue
    > {
        ForecastValidation.tenDayForecastData(
            for: city,
            selectionCalendar: forecastCalendar
        )
    }

    private var metricPresentation: DetailMetricValuePresentation? {
        chartForecast.map {
            DetailMetricValuePresentation(
                city: city,
                forecast: $0,
                now: .now
            )
        }
    }

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    /// Value range printed above the selected chart.
    private var chartSummary: String? {
        switch selectedRange {
        case .day:
            return chartForecast.flatMap {
                selectedMetric.summary(
                    for: $0,
                    city: city,
                    temperatureUnit: temperatureUnit,
                    distanceUnit: DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers,
                    locale: locale
                )
            }
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
        // Force the city's time zone so a forecast near midnight never prints
        // as the neighboring device-calendar day.
        var style = Date.FormatStyle.dateTime.day().month(.wide).weekday(.wide).locale(locale)
        style.timeZone = city.timeZone
        switch selectedRange {
        case .day:
            return chartForecast?.date.formatted(style) ?? ""
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

    /// Places weather symbols on the chart's top axis so their centers share
    /// the exact x-coordinate of their associated point marks.
    @AxisContentBuilder
    private func conditionIconAxisMarks(
        for icons: [ChartConditionIcon]
    ) -> some AxisContent {
        // Axis values supply dates rather than indexes, which ensures weather
        // icons stay aligned if some missing readings were filtered out.
        AxisMarks(position: .top, values: icons.map(\.id)) { value in
            AxisValueLabel {
                if let date = value.as(Date.self),
                   let icon = icons.first(where: { $0.id == date }) {
                    if let condition = icon.condition {
                        let symbolName = condition.displayIcon
                        Image(systemName: symbolName)
                            // Axis symbols use the same condition color as
                            // cards and Map markers.
                            .weatherIconStyle(for: condition.iconTone)
                            .font(.caption2.weight(.semibold))
                            // These symbols are a visual annotation for the
                            // chart. The chart descriptor exposes the same
                            // forecast samples through Chart Detail and Audio
                            // Graph without duplicating every icon.

                    }
                }
            }
        }
    }

    /// One symbol for every other plotted hourly point, excluding missing
    /// readings that have no corresponding dot in the chart. This keeps the
    /// Day chart's top axis legible without changing its plotted data.
    private func hourlyConditionIcons(
        for forecast: DailyForecast,
        at dates: [Date]
    ) -> [ChartConditionIcon] {
        let plottedDates = Set(dates)
        return forecast.hourlyForecasts.compactMap { forecast in
            guard plottedDates.contains(forecast.id) else { return nil }
            return ChartConditionIcon(
                id: forecast.id,
                symbolName: forecast.symbolName,
                condition: forecast.condition
            )
        }
        .enumerated()
        // Draw alternate symbols only: hourly data can have 24 points and a
        // symbol on every point would make the chart header unreadable.
        .compactMap { index, icon in
            index.isMultiple(of: 2) ? icon : nil
        }
    }

    /// One symbol for every plotted daily point, excluding unavailable metric
    /// values that do not produce a dot.
    private func dailyConditionIcons(at dates: [Date]) -> [ChartConditionIcon] {
        let plottedDates = Set(dates)
        return availableForecasts.compactMap { forecast in
            guard plottedDates.contains(forecast.id) else { return nil }
            return ChartConditionIcon(
                id: forecast.id,
                symbolName: forecast.symbolName,
                condition: forecast.condition
            )
        }
    }

    /// Reuses only Weather Atlas palette colors and follows the resolved theme.
    private var metricColor: Color {
        // Temperature uses the same sunny yellow as the app's clear-weather
        // dot, keeping it visually connected to the weather palette.
        switch selectedMetric {
        case .temperature, .feelsLike: theme.colors.dotSun
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

    /// Forecast matching the app-wide selected day. A vanished day remains nil
    /// so the chart can blank and report missing forecast data.
    private var chartForecast: DailyForecast? {
        city.forecastIfAvailable(
            on: selectedForecastDate,
            selectionCalendar: forecastCalendar
        )
    }

    /// Device-calendar dates that this city's real forecast can display.
    private var chartSelectionDates: [Date] {
        // Convert each forecast instant through CityWeather before using it in
        // the date stepper: the city may live in another time zone.
        let today = forecastCalendar.startOfDay(for: Date())
        return Array(
            Set(city.dailyForecasts.compactMap {
                city.selectionDate(for: $0, selectionCalendar: forecastCalendar)
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
        // Integer tick intervals keep every visible y-axis label free of
        // decimal fractions, including narrow temperature ranges.
        let step = max(roundedAxisStep(for: span / 5), 1)
        let roundedLower = floor((minimum - step * 0.15) / step) * step
        // Visibility, UV, and percentage values have no meaningful negative
        // range. Temperature and feels-like temperature remain unrestricted.
        let lower = selectedMetric.requiresZeroBaseline ? 0 :
            (selectedMetric.usesNonNegativeScale ? max(0, roundedLower) : roundedLower)
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

        let lower = Int(domain.lowerBound.rounded(.up))
        let upper = Int(domain.upperBound.rounded(.down))
        guard lower < upper else { return [domain.lowerBound, domain.upperBound] }

        let interval = max(1, Int(ceil(Double(upper - lower) / 4)))
        var values = stride(from: lower, through: upper, by: interval).map(Double.init)
        if values.last != Double(upper) {
            values.append(Double(upper))
        }
        return values
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

/// Conversion and display rules kept next to the metric enum so cards, chart
/// headlines, axis labels, and plotted point construction agree on each unit.
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

    /// Visibility and UV charts should always communicate their natural zero
    /// baseline, even when all currently displayed readings are higher.
    var requiresZeroBaseline: Bool {
        self == .visibility || self == .uvIndex
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

        return Int(value.rounded()).formatted(.number.locale(locale))
    }

    /// Card value for one selected day.
    func summary(
        for forecast: DailyForecast,
        city: CityWeather,
        temperatureUnit: TemperatureUnit,
        distanceUnit: DistanceUnit,
        locale: Locale
    ) -> String? {
        // Missing fields remain an empty value in the card; the owning grid
        // reports their structured issue through the native alert queue.
        switch self {
        case .temperature:
            guard forecast.dailyLow.isFinite, forecast.dailyHigh.isFinite else {
                return nil
            }
            return temperatureRange(
                low: forecast.dailyLow,
                high: forecast.dailyHigh,
                unit: temperatureUnit
            )
        case .feelsLike:
            guard let values = completeHourlyValues(
                from: forecast.hourlyForecasts,
                transform: \.apparentTemperature,
                isValid: \.isFinite
            ) else { return nil }
            return hourlyTemperatureRange(
                values,
                unit: temperatureUnit
            )
        case .cloudCover:
            guard let values = completeHourlyValues(
                from: forecast.hourlyForecasts,
                transform: { $0.cloudCover.map { $0 * 100 } },
                isValid: { $0.isFinite && (0...100).contains($0) }
            ) else { return nil }
            return hourlyNumericRange(values, suffix: "%")
        case .rainChance:
            guard let values = completeHourlyValues(
                from: forecast.hourlyForecasts,
                transform: { $0.precipitationChance.map { $0 * 100 } },
                isValid: { $0.isFinite && (0...100).contains($0) }
            ) else { return nil }
            return hourlyNumericRange(values, suffix: "%")
        case .visibility:
            guard let values = completeHourlyValues(
                from: forecast.hourlyForecasts,
                transform: \.visibilityKilometers,
                isValid: { $0.isFinite && $0 >= 0 }
            ) else { return nil }
            return hourlyVisibilityRange(values, unit: distanceUnit)
        case .uvIndex:
            guard let values = completeHourlyValues(
                from: forecast.hourlyForecasts,
                transform: { $0.uvIndex.map(Double.init) },
                isValid: { $0.isFinite && $0 >= 0 }
            ) else { return nil }
            return hourlyNumericRange(values, suffix: "")
        }
    }

    /// Spot value for the current city-local forecast hour. It deliberately
    /// accepts no daily fallback: a missing live reading stays unavailable
    /// instead of being replaced with a plausible daily aggregate.
    func currentHourlySummary(
        for hour: HourlyForecast?,
        temperatureUnit: TemperatureUnit,
        distanceUnit: DistanceUnit
    ) -> String? {
        guard let hour else { return nil }

        switch self {
        case .temperature:
            guard let value = hour.temperature, value.isFinite else { return nil }
            return temperatureUnit.display(value)
        case .feelsLike:
            guard let value = hour.apparentTemperature, value.isFinite else {
                return nil
            }
            return temperatureUnit.display(value)
        case .cloudCover:
            guard let value = hour.cloudCover,
                  value.isFinite,
                  (0...1).contains(value) else {
                return nil
            }
            return "\(Int((value * 100).rounded()))%"
        case .rainChance:
            guard let value = hour.precipitationChance,
                  value.isFinite,
                  (0...1).contains(value) else {
                return nil
            }
            return "\(Int((value * 100).rounded()))%"
        case .visibility:
            guard let value = hour.visibilityKilometers,
                  value.isFinite,
                  value >= 0 else {
                return nil
            }
            return distanceUnit.display(value)
        case .uvIndex:
            guard let value = hour.uvIndex, value >= 0 else { return nil }
            return String(value)
        }
    }

    /// Field-specific reason the current city-local hour cannot render.
    func currentHourlySummaryIssue(
        for hour: HourlyForecast
    ) -> WeatherDataIssue? {
        switch self {
        case .temperature:
            guard let value = hour.temperature else {
                return .missing(.missingTemperatureData, at: hour.date)
            }
            return value.isFinite
                ? nil
                : .invalidValue("hourly temperature", at: hour.date)
        case .feelsLike:
            guard let value = hour.apparentTemperature else {
                return .missing(.missingApparentTemperatureData, at: hour.date)
            }
            return value.isFinite
                ? nil
                : .invalidValue("hourly apparent temperature", at: hour.date)
        case .cloudCover:
            guard let value = hour.cloudCover else {
                return .missing(.missingCloudCoverData, at: hour.date)
            }
            return value.isFinite && (0...1).contains(value)
                ? nil
                : .invalidValue("hourly cloud cover", at: hour.date)
        case .rainChance:
            guard let value = hour.precipitationChance else {
                return .missing(.missingPrecipitationChanceData, at: hour.date)
            }
            return value.isFinite && (0...1).contains(value)
                ? nil
                : .invalidValue("hourly precipitation chance", at: hour.date)
        case .visibility:
            guard let value = hour.visibilityKilometers else {
                return .missing(.missingVisibilityData, at: hour.date)
            }
            return value.isFinite && value >= 0
                ? nil
                : .invalidValue("hourly visibility", at: hour.date)
        case .uvIndex:
            return hour.uvIndex == nil
                ? .missing(.missingUVIndexData, at: hour.date)
                : hour.uvIndex! >= 0
                ? nil
                : .invalidValue("hourly UV index", at: hour.date)
        }
    }

    /// Non-today cards are daily ranges. Require a complete selected-day
    /// hourly set for every metric so a partial rolling feed cannot imply a
    /// trustworthy min–max range.
    private func completeHourlyValues(
        from hours: [HourlyForecast],
        transform: (HourlyForecast) -> Double?,
        isValid: (Double) -> Bool
    ) -> [Double]? {
        guard !hours.isEmpty else { return nil }
        let values = hours.compactMap(transform)
        guard values.count == hours.count,
              values.allSatisfy(isValid) else {
            return nil
        }
        return values
    }

    private func hourlyTemperatureRange(
        _ values: [Double],
        unit: TemperatureUnit
    ) -> String? {
        guard !values.isEmpty,
              let low = values.min(),
              let high = values.max() else {
            return nil
        }
        return temperatureRange(low: low, high: high, unit: unit)
    }

    private func hourlyNumericRange(
        _ values: [Double],
        suffix: String
    ) -> String? {
        guard !values.isEmpty,
              let low = values.min(),
              let high = values.max() else {
            return nil
        }
        return "\(Int(low.rounded())) – \(Int(high.rounded()))\(suffix)"
    }

    private func hourlyVisibilityRange(
        _ values: [Double],
        unit: DistanceUnit
    ) -> String? {
        guard !values.isEmpty,
              let low = values.min(),
              let high = values.max() else {
            return nil
        }
        return unit.displayRange(low, high)
    }

    /// Aggregate value range across the actual available forecast horizon.
    func forecastSummary(
        _ forecasts: [DailyForecast],
        city: CityWeather,
        temperatureUnit: TemperatureUnit,
        distanceUnit: DistanceUnit,
        locale: Locale
    ) -> String? {
        // Forecast summaries summarize only available values, never substitute
        // zero for missing weather readings.
        guard !forecasts.isEmpty else { return nil }
        switch self {
        case .temperature:
            guard let low = forecasts.map(\.dailyLow).min(),
                  let high = forecasts.map(\.dailyHigh).max() else { return nil }
            return temperatureRange(low: low, high: high, unit: temperatureUnit)
        case .feelsLike:
            // WeatherKit provides no daily apparent-temperature aggregate, but
            // each forecast day retains its own real hourly readings. Keep the
            // 10-day headline consistent with the plotted daily low/high data.
            guard forecasts.allSatisfy({ forecast in
                !forecast.hourlyForecasts.isEmpty
                    && forecast.hourlyForecasts.allSatisfy {
                        $0.apparentTemperature != nil
                    }
            }) else { return nil }
            let dailyRanges = forecasts.compactMap { forecast -> (Double, Double)? in
                let values = forecast.hourlyForecasts.compactMap(\.apparentTemperature)
                guard let low = values.min(), let high = values.max() else { return nil }
                return (low, high)
            }
            guard let low = dailyRanges.map(\.0).min(),
                  let high = dailyRanges.map(\.1).max() else { return nil }
            return temperatureRange(low: low, high: high, unit: temperatureUnit)
        case .cloudCover:
            guard forecasts.allSatisfy({ $0.cloudCover != nil }) else {
                return nil
            }
            return numericRange(forecasts.compactMap { $0.cloudCover.map { $0 * 100 } }, suffix: "%")
        case .rainChance:
            guard forecasts.allSatisfy({ $0.precipitationChance != nil }) else {
                return nil
            }
            return numericRange(
                forecasts.compactMap { $0.precipitationChance.map { $0 * 100 } },
                suffix: "%"
            )
        case .visibility:
            guard forecasts.allSatisfy({ forecast in
                forecast.averageVisibilityKilometers != nil
            }) else {
                return nil
            }
            return visibilityRange(
                forecasts.compactMap(\.averageVisibilityKilometers),
                unit: distanceUnit
            )
        case .uvIndex:
            guard forecasts.allSatisfy({ $0.uvIndex != nil }) else {
                return nil
            }
            return numericRange(forecasts.compactMap { $0.uvIndex.map(Double.init) }, suffix: "")
        }
    }

    func dailySummaryIssue(
        for forecast: DailyForecast,
        timeZone: TimeZone
    ) -> WeatherDataIssue? {
        // Temperature has authoritative daily low/high values. The remaining
        // cards now display min–max ranges derived from hourly readings, so
        // their diagnostics must validate that same source instead of the
        // older single daily aggregate.
        self == .temperature
            ? nil
            : hourlyChartIssue(for: forecast, timeZone: timeZone)
    }

    func hourlyChartIssue(
        for forecast: DailyForecast,
        timeZone: TimeZone
    ) -> WeatherDataIssue? {
        guard !forecast.hourlyForecasts.isEmpty else {
            return .missingHourlyData(at: forecast.date)
        }
        let missingHour = forecast.hourlyForecasts.first { hour in
            switch self {
            case .temperature: hour.temperature == nil
            case .feelsLike: hour.apparentTemperature == nil
            case .cloudCover: hour.cloudCover == nil
            case .rainChance: hour.precipitationChance == nil
            case .visibility: hour.visibilityKilometers == nil
            case .uvIndex: hour.uvIndex == nil
            }
        }
        guard let missingHour else { return nil }
        return .missing(missingKind, at: missingHour.date)
    }

    func dailyChartIssue(
        for forecast: DailyForecast,
        timeZone: TimeZone
    ) -> WeatherDataIssue? {
        switch self {
        case .temperature:
            return nil
        case .feelsLike:
            guard !forecast.hourlyForecasts.isEmpty else {
                return .missingHourlyData(at: forecast.date)
            }
            guard let hour = forecast.hourlyForecasts.first(where: {
                $0.apparentTemperature == nil
            }) else { return nil }
            return .missing(.missingApparentTemperatureData, at: hour.date)
        case .cloudCover:
            return forecast.cloudCover == nil
                ? .missing(.missingCloudCoverData, at: forecast.date)
                : nil
        case .rainChance:
            return forecast.precipitationChance == nil
                ? .missing(.missingPrecipitationChanceData, at: forecast.date)
                : nil
        case .visibility:
            guard !forecast.hourlyForecasts.isEmpty else {
                return .missingHourlyData(at: forecast.date)
            }
            guard let hour = forecast.hourlyForecasts.first(where: {
                $0.visibilityKilometers == nil
            }) else { return nil }
            return .missing(.missingVisibilityData, at: hour.date)
        case .uvIndex:
            return forecast.uvIndex == nil
                ? .missing(.missingUVIndexData, at: forecast.date)
                : nil
        }
    }

    private var missingKind: WeatherDataIssue.Kind {
        switch self {
        case .temperature: .missingTemperatureData
        case .feelsLike: .missingApparentTemperatureData
        case .cloudCover: .missingCloudCoverData
        case .rainChance: .missingPrecipitationChanceData
        case .visibility: .missingVisibilityData
        case .uvIndex: .missingUVIndexData
        }
    }

    func temperatureRange(low: Double, high: Double, unit: TemperatureUnit) -> String {
        "\(unit.display(low)) – \(unit.display(high))"
    }

    func numericRange(_ values: [Double], suffix: String) -> String? {
        guard let low = values.min(), let high = values.max() else { return nil }
        return "\(Int(low.rounded())) – \(Int(high.rounded()))\(suffix)"
    }

    func visibilityRange(_ values: [Double], unit: DistanceUnit) -> String? {
        guard let low = values.min(), let high = values.max() else { return nil }
        return unit.displayRange(low, high)
    }
}

// MARK: - Chart Data

/// Normalized point consumed by both hourly and available-days charts.
private struct DetailChartPoint: Identifiable {
    /// `value` drives single-series metrics; lower/upper hold the two daily
    /// temperature values used to plot high and low lines together.
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
        // Keep source-unit conversion at the boundary between forecast models
        // and Charts, so chart scales and formatted values use the same unit.
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
        // Daily temperature returns a range. Other metrics return one daily
        // value, with optional WeatherKit fields omitted rather than guessed.
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
