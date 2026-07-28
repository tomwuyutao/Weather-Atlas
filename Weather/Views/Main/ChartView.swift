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

// MARK: - Detail Metric Grid

/// Six-card Detail selector that presents the chart sheet at the tapped metric.
struct DetailMetricGrid: View {
    let city: CityWeather
    let forecast: DailyForecast
    let temperatureUnit: TemperatureUnit
    let usesLandscapeIPadLayout: Bool
    /// App-wide forecast date shared with the Detail screen and chart sheet.
    let selectedForecastDate: Binding<Date>

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
    /// Controls the native Calendar popover in the chart-specific bottom bar.
    @State private var showingChartDatePopover = false
    /// Keeps Chart View synchronized with Detail View's selected forecast day.
    @Binding private var selectedForecastDate: Date

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

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
                        // Date swiping belongs to the plotted data only, leaving
                        // the sheet's vertical scroll and metric-card taps intact.
                        .contentShape(Rectangle())
                        .simultaneousGesture(chartDateSwipeGesture)

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                // A sheet has its own toolbar hierarchy, so provide the same
                // native date affordance here instead of hiding it behind Detail.
                ToolbarItem(placement: .bottomBar) {
                    chartDateToolbar
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
                return stride(from: 0, to: chartForecast.hourlyForecasts.count, by: 3).map {
                    chartForecast.hourlyForecasts[$0].symbolName
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

    /// Hourly line chart for the selected daily forecast.
    private var hourlyChart: some View {
        let points = chartForecast.hourlyForecasts.compactMap {
            DetailChartPoint.hourly(
                $0,
                metric: selectedMetric,
                forecast: chartForecast,
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
                    .foregroundStyle(metricColor)

                    PointMark(
                        x: .value("Time", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(metricColor)
                    .symbolSize(24)
                    .symbol {
                        Circle()
                            .fill(metricColor)
                            .frame(width: 7, height: 7)
                    }
                }
            } else {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Value", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(metricColor)

                    PointMark(
                        x: .value("Time", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(metricColor)
                    .symbolSize(24)
                    .symbol {
                        Circle()
                            .fill(metricColor)
                            .frame(width: 7, height: 7)
                    }
                }
            }
        }
        .chartYScale(domain: yAxisDomain(for: points))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                AxisGridLine().foregroundStyle(theme.colors.secondaryText.opacity(0.16))
                AxisValueLabel(format: .dateTime.hour())
                    .foregroundStyle(theme.colors.secondaryText)
            }
        }
        .chartYAxis {
            if selectedMetric.usesPercentageScale {
                AxisMarks(position: .trailing, values: [0.0, 25.0, 50.0, 75.0, 100.0]) { value in
                    AxisGridLine().foregroundStyle(theme.colors.secondaryText.opacity(0.16))
                    AxisValueLabel {
                        if let percentage = value.as(Double.self) {
                            Text("\(Int(percentage))%")
                                .foregroundStyle(theme.colors.secondaryText)
                        }
                    }
                }
            } else {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(theme.colors.secondaryText.opacity(0.16))
                    AxisValueLabel()
                        .foregroundStyle(theme.colors.secondaryText)
                }
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
                        .foregroundStyle(metricColor)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("High", upper)
                        )
                        .foregroundStyle(metricColor)
                        .symbolSize(28)
                        .symbol {
                            Circle()
                                .fill(metricColor)
                                .frame(width: 8, height: 8)
                        }

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
                        .foregroundStyle(theme.colors.secondaryText)
                        .symbolSize(28)
                        .symbol {
                            Circle()
                                .fill(theme.colors.secondaryText)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            } else {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(metricColor)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(metricColor)
                    .symbolSize(28)
                    .symbol {
                        Circle()
                            .fill(metricColor)
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
        .chartYScale(domain: yAxisDomain(for: points))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisGridLine().foregroundStyle(theme.colors.secondaryText.opacity(0.16))
                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    .foregroundStyle(theme.colors.secondaryText)
            }
        }
        .chartYAxis {
            if selectedMetric.usesPercentageScale {
                AxisMarks(position: .trailing, values: [0.0, 25.0, 50.0, 75.0, 100.0]) { value in
                    AxisGridLine().foregroundStyle(theme.colors.secondaryText.opacity(0.16))
                    AxisValueLabel {
                        if let percentage = value.as(Double.self) {
                            Text("\(Int(percentage))%")
                                .foregroundStyle(theme.colors.secondaryText)
                        }
                    }
                }
            } else {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(theme.colors.secondaryText.opacity(0.16))
                    AxisValueLabel()
                        .foregroundStyle(theme.colors.secondaryText)
                }
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
                        for: chartForecast,
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
                for: chartForecast,
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
            return chartForecast.date.formatted(style)
        case .forecast:
            guard let first = availableForecasts.first, let last = availableForecasts.last else {
                return ""
            }
            return "\(first.date.formatted(style)) – \(last.date.formatted(style))"
        }
    }

    /// Reuses only Weather Atlas palette colors and follows the resolved theme.
    private var metricColor: Color {
        switch selectedMetric {
        case .temperature: theme.colors.dotSun
        case .feelsLike: theme.colors.dotPartlyCloudy
        case .cloudCover: theme.colors.dotCloudy
        case .rainChance: theme.colors.dotRain
        case .visibility: theme.colors.dotDrizzle
        case .uvIndex: theme.colors.primaryText
        }
    }

    /// Forecast matching the app-wide selected day, with the opening day as a
    /// safe fallback while a list refresh temporarily changes its date range.
    private var chartForecast: DailyForecast {
        city.forecastIfAvailable(on: selectedForecastDate) ?? initialForecast
    }

    /// Device-calendar dates that this city's real forecast can display.
    private var chartSelectionDates: [Date] {
        Array(Set(city.dailyForecasts.compactMap {
            city.selectionDate(for: $0)
        })).sorted()
    }

    /// Native bottom toolbar for changing the chart's selected day.
    private var chartDateToolbar: some View {
        HStack(spacing: 6) {
            chartDateStepButton(systemImage: "chevron.left", forward: false)

            Button {
                Haptics.lightImpact()
                showingChartDatePopover = true
            } label: {
                Text(chartDateSwitcherText(for: selectedForecastDate))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
                    .frame(minWidth: 72, minHeight: 32)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingChartDatePopover) {
                chartDatePickerPopover
            }

            chartDateStepButton(systemImage: "chevron.right", forward: true)
        }
        .padding(.horizontal, 3)
        .frame(width: 165)
    }

    /// One adjacent-day control, disabled when no forecast exists that way.
    private func chartDateStepButton(systemImage: String, forward: Bool) -> some View {
        let isEnabled = forward
            ? chartSelectionDates.contains { $0 > selectedForecastDate }
            : chartSelectionDates.contains { $0 < selectedForecastDate }

        return Button {
            selectAdjacentChartDate(forward: forward)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    isEnabled ? theme.colors.primaryText : theme.colors.primaryText.opacity(0.35)
                )
                .frame(minWidth: 30, minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    /// Moves one literal app-calendar day through this city's forecast range.
    private func selectAdjacentChartDate(forward: Bool) {
        let nextDate = forward
            ? chartSelectionDates.first(where: { $0 > selectedForecastDate })
            : chartSelectionDates.last(where: { $0 < selectedForecastDate })
        guard let nextDate else { return }
        Haptics.lightImpact()
        withAnimation(.smooth(duration: 0.2)) {
            selectedForecastDate = nextDate
        }
    }

    /// Handles a deliberate horizontal chart swipe without affecting the sheet.
    private var chartDateSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                guard selectedRange == .day,
                      abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) >= 50 else {
                    return
                }
                selectAdjacentChartDate(forward: value.translation.width < 0)
            }
    }

    /// Mirrors the app's compact date text in Chart View's own toolbar.
    private func chartDateSwitcherText(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return localizedString("Today", locale: locale)
        }
        return date.formatted(
            Date.FormatStyle.dateTime
                .weekday(.abbreviated)
                .month(.abbreviated)
                .day()
                .locale(locale)
        )
    }

    /// Graphical calendar limited to days with a real forecast for this city.
    @ViewBuilder
    private var chartDatePickerPopover: some View {
        if let firstDate = chartSelectionDates.first, let lastDate = chartSelectionDates.last {
            DatePicker(
                chartDateSwitcherText(for: selectedForecastDate),
                selection: $selectedForecastDate,
                in: firstDate...lastDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .frame(width: 280, height: 300)
            .padding(8)
            .presentationCompactAdaptation(.popover)
            .themedPopoverBackground()
        }
    }

    /// Keeps percentage metrics fixed while retaining useful automatic-like ranges elsewhere.
    private func yAxisDomain(for points: [DetailChartPoint]) -> ClosedRange<Double> {
        if selectedMetric.usesPercentageScale {
            return 0...100
        }
        guard !points.isEmpty else { return 0...1 }
        if selectedMetric.usesTemperatureLines {
            let minimum = points.map { $0.lowerValue ?? $0.value }.min() ?? 0
            let maximum = points.map { $0.upperValue ?? $0.value }.max() ?? 1
            let padding = max((maximum - minimum) * 0.12, 1)
            return (minimum - padding)...(maximum + padding)
        }
        let maximum = points.map(\.value).max() ?? 1
        return 0...max(maximum * 1.08, 1)
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

    /// Card value for one selected day.
    func summary(
        for forecast: DailyForecast,
        city: CityWeather,
        temperatureUnit: TemperatureUnit,
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
            return visibilityRange(forecast.hourlyForecasts.compactMap(\.visibilityKilometers))
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
        case .temperature:
            guard let low = forecasts.map(\.dailyLow).min(),
                  let high = forecasts.map(\.dailyHigh).max() else { return "—" }
            return temperatureRange(low: low, high: high, unit: temperatureUnit)
        case .feelsLike:
            let values = forecasts.flatMap(\.hourlyForecasts).compactMap(\.apparentTemperature)
            guard let low = values.min(), let high = values.max() else { return "—" }
            return temperatureRange(low: low, high: high, unit: temperatureUnit)
        case .cloudCover:
            return numericRange(forecasts.compactMap { $0.cloudCover.map { $0 * 100 } }, suffix: "%")
        case .rainChance:
            return numericRange(
                forecasts.compactMap { $0.precipitationChance.map { $0 * 100 } },
                suffix: "%"
            )
        case .visibility:
            return visibilityRange(forecasts.flatMap(\.hourlyForecasts).compactMap(\.visibilityKilometers))
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

    func visibilityRange(_ values: [Double]) -> String {
        guard let low = values.min(), let high = values.max() else { return "—" }
        return "\(Int(low.rounded())) – \(Int(high.rounded())) km"
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
        case .temperature: value = hour.temperature
        case .feelsLike: value = hour.apparentTemperature
        case .cloudCover:
            value = (hour.cloudCover ?? forecast.cloudCover).map { $0 * 100 }
        case .rainChance:
            value = (hour.precipitationChance ?? forecast.precipitationChance).map { $0 * 100 }
        case .visibility:
            value = hour.visibilityKilometers ?? forecast.hourlyForecasts
                .compactMap(\.visibilityKilometers)
                .average
        case .uvIndex:
            value = hour.uvIndex.map(Double.init) ?? forecast.uvIndex.map(Double.init)
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
        case .cloudCover:
            let value = forecast.cloudCover
                ?? forecast.hourlyForecasts.compactMap(\.cloudCover).average
            guard let value else { return nil }
            return DetailChartPoint(date: forecast.date, value: value * 100, lowerValue: nil, upperValue: nil)
        case .rainChance:
            let value = forecast.precipitationChance
                ?? forecast.hourlyForecasts.compactMap(\.precipitationChance).max()
            guard let value else { return nil }
            return DetailChartPoint(date: forecast.date, value: value * 100, lowerValue: nil, upperValue: nil)
        case .visibility:
            let values = forecast.hourlyForecasts.compactMap(\.visibilityKilometers)
            guard let value = values.average else { return nil }
            return DetailChartPoint(
                date: forecast.date,
                value: value,
                lowerValue: nil,
                upperValue: nil
            )
        case .uvIndex:
            let value = forecast.uvIndex.map(Double.init)
                ?? forecast.hourlyForecasts.compactMap(\.uvIndex).map(Double.init).max()
            guard let value else { return nil }
            return DetailChartPoint(date: forecast.date, value: value, lowerValue: nil, upperValue: nil)
        }
    }
}

private extension Collection where Element == Double {
    /// Arithmetic mean used as a faithful fallback when WeatherKit omits a daily aggregate.
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}
