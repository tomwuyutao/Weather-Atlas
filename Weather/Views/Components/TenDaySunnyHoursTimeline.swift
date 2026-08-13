//
//  TenDaySunnyHoursTimeline.swift
//  Weather
//
//  Purpose: Presents the compact ten-day sunny-hours detail card using the
//  current place-owned data model.
//

import SwiftUI

// MARK: - Ten-Day Sunny-Hours Overview

/// Shared Home/Detail ten-day chart. It turns each available daily forecast
/// into a row of hourly weather conditions and writes taps to the root-selected
/// day.
struct TenDaySunnyHoursTimeline: View {
    /// Optional for report surfaces that must preserve the card while their
    /// forecast request is still loading or has failed.
    let city: CityWeather?
    /// The name already chosen by the owning report (including a saved alias).
    let placeDisplayName: String
    /// Shared Detail selection; every chart row can change the active day.
    @Binding var selectedDate: Date
    private let isLoading: Bool
    private let unavailableMessage: String?
    private let retry: (() -> Void)?

    @Environment(\.accessibilityDifferentiateWithoutColor)
    private var differentiateWithoutColor
    @Environment(\.appTheme) private var theme
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    /// Existing Detail callers already own loaded weather and keep their
    /// original concise initializer.
    init(
        city: CityWeather,
        placeDisplayName: String,
        selectedDate: Binding<Date>
    ) {
        self.city = city
        self.placeDisplayName = placeDisplayName
        _selectedDate = selectedDate
        isLoading = false
        unavailableMessage = nil
        retry = nil
    }

    /// Your Location uses this state-aware initializer so the ten-day card has
    /// stable identity through loading, failure, and retry episodes.
    init(
        city: CityWeather?,
        placeDisplayName: String,
        selectedDate: Binding<Date>,
        isLoading: Bool,
        unavailableMessage: String?,
        retry: (() -> Void)?
    ) {
        self.city = city
        self.placeDisplayName = placeDisplayName
        _selectedDate = selectedDate
        self.isLoading = isLoading
        self.unavailableMessage = unavailableMessage
        self.retry = retry
    }

    // MARK: Chart Data Preparation

    private struct PreparedChart {
        let rows: [SunnyHoursDayRow]
        let issues: [WeatherDataIssue]
    }

    private var preparedChart: PreparedChart {
        var rows: [SunnyHoursDayRow] = []
        var issues: [WeatherDataIssue] = []

        // A missing city is a request-level presentation state, not malformed
        // forecast content. The owning report supplies its loading/error copy.
        guard let city else {
            return PreparedChart(rows: [], issues: [])
        }

        let horizon: ForecastValidation.TenDayForecastData
        switch ForecastValidation.tenDayForecastData(
            for: city,
            selectionCalendar: calendar
        ) {
        case .success(let validatedHorizon):
            horizon = validatedHorizon
        case .failure(let issue):
            return PreparedChart(
                rows: [],
                issues: [issue]
            )
        }

        // Validate every eligible row before drawing any of them. A shortened
        // chart can otherwise make missing source weather look like a shorter
        // forecast horizon.
        for forecast in horizon.forecasts {
            guard let selectionDate = city.selectionDate(
                for: forecast,
                selectionCalendar: calendar
            ) else {
                issues.append(
                    .invalidValue(
                        "Unable to convert a forecast into the app calendar",
                        at: forecast.date
                    )
                )
                continue
            }

            let result = SunnyHoursCalculation.sunnyHoursData(
                for: forecast,
                timeZone: city.timeZone
            )
            guard case .success(let data) = result else {
                if case .failure(let issue) = result {
                    issues.append(issue)
                }
                continue
            }

            var cells: [SunnyHoursDayCell] = []
            var conditionIssue: WeatherDataIssue?
            for hour in data.hours {
                guard let condition = hour.condition else {
                    let symbol = hour.symbolName.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    conditionIssue = symbol.isEmpty
                        ? .missing(.missingConditionData, at: hour.date)
                        : .unknownWeatherSymbol(symbol, at: hour.date)
                    break
                }
                cells.append(
                    SunnyHoursDayCell(
                        id: hour.date,
                        hour: hour.hour(in: city.timeZone),
                        condition: condition
                    )
                )
            }
            if let conditionIssue {
                issues.append(conditionIssue)
                continue
            }

            rows.append(SunnyHoursDayRow(
                selectionDate: selectionDate,
                forecastDate: forecast.date,
                hours: cells,
                bounds: data.bounds
            ))
        }

        if rows.isEmpty, issues.isEmpty {
            issues.append(.missingForecastData(at: selectedDate))
        }
        return PreparedChart(
            rows: rows,
            issues: issues
        )
    }

    private var rows: [SunnyHoursDayRow] {
        preparedChart.issues.isEmpty ? preparedChart.rows : []
    }

    private var chartBounds: SunnyHoursChartBounds? {
        // A merged domain makes the time axis identical across every row even
        // if an individual forecast starts later or ends earlier.
        SunnyHoursChartBounds.merged(rows.map(\.bounds))
    }

    /// The whole report follows the selected day, so inactive chart segments
    /// use that same subtle canvas tint rather than a fixed gray fill.
    private var screenTone: WeatherIconTone? {
        city?.forecastIfAvailable(
            on: selectedDate,
            selectionCalendar: calendar
        )?.condition?.iconTone
    }

    private var missingDataReport: MissingDataAlertReport? {
        guard let city else { return nil }
        let issues = Array(Set(preparedChart.issues)).sorted {
            $0.kind.rawValue < $1.kind.rawValue
        }
        guard !issues.isEmpty else { return nil }
        let issueIdentity = issues.map(\.kind.rawValue).joined(separator: ",")
        let messages = issues.map {
            weatherDataIssueMessage(
                $0,
                cityName: placeDisplayName,
                locale: locale
            )
        }
        return MissingDataAlertReport(
            key: "ten-day-sunny-hours:\(city.id.uuidString):\(issueIdentity)",
            title: localizedString("Weather Data Missing", locale: locale),
            message: Array(Set(messages)).sorted().joined(separator: "\n")
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WeatherCardHeader(
                icon: "calendar",
                title: "10-Day Sunny Hours"
            )

            if let chartBounds, !rows.isEmpty {
                SunnyHoursAxis(bounds: chartBounds)

                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        let isSelected = calendar.isDate(
                            row.selectionDate,
                            inSameDayAs: selectedDate
                        )
                        // Each graphical row is a button. Its selection state
                        // draws an outline and synchronizes the app-wide date.
                        Button {
                            withAnimation(.smooth(duration: 0.2)) {
                                selectedDate = calendar.startOfDay(
                                    for: row.selectionDate
                                )
                            }
                        } label: {
                            SunnyHoursDayTrack(
                                row: row,
                                bounds: chartBounds,
                                selected: isSelected,
                                label: dayLabel(for: row.forecastDate),
                                theme: theme.colors,
                                noSunColor: theme.colors.weatherNoSunTimelineColor(
                                    for: screenTone
                                ),
                                differentiateWithoutColor:
                                    differentiateWithoutColor
                            )
                        }
                        .buttonStyle(.plain)
                        .contentShape(.rect)
                        .accessibilityLabel(dayLabel(for: row.forecastDate))
                        .accessibilityValue(accessibilityValue(for: row))
                        .accessibilityHint("Select this forecast date")
                        .accessibilityAddTraits(
                            isSelected ? .isSelected : []
                        )
                    }
                }

                legend
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                    // Every selectable row already names the precise
                    // destination-local weather states. The color key would
                    // otherwise repeat those values as an extra focus stop.
                    .accessibilityHidden(true)
            } else {
                unavailableContent
            }
        }
        .padding(WeatherCardLayout.padding)
        .detailTranslucentCard(
            colorScheme: colorScheme,
            in: RoundedRectangle(
                cornerRadius: WeatherCardLayout.cornerRadius,
                style: .continuous
            )
        )
        // Availability belongs to the enclosing report. This card renders an
        // honest blank/unavailable state, but never presents a duplicate alert.
    }

    private func dayLabel(for date: Date) -> String {
        var localCalendar = calendar
        localCalendar.timeZone = city?.timeZone ?? .autoupdatingCurrent
        if localCalendar.isDateInToday(date) {
            return localizedString("Today", locale: locale)
        }
        var style = Date.FormatStyle.dateTime
            .month(.abbreviated)
            .day()
            .locale(locale)
        style.timeZone = city?.timeZone ?? .autoupdatingCurrent
        return date.formatted(style)
    }

    /// The selected forecast instant supplies the date-sensitive UTC offset.
    private var localTimeDisclosure: String? {
        guard let city,
              let referenceDate = city.forecastIfAvailable(
            on: selectedDate,
            selectionCalendar: calendar
        )?.date ?? rows.first?.forecastDate else {
            return nil
        }
        return SunnyHoursFormatting.localTimeDisclosure(
            placeName: placeDisplayName,
            timeZone: city.timeZone,
            at: referenceDate,
            locale: locale
        )
    }

    /// Replaces color-only chart exploration with explicit city-local clock
    /// values. Every time is already converted from its forecast instant using
    /// `city.timeZone`, so VoiceOver never falls back to the device time zone.
    private func accessibilityValue(for row: SunnyHoursDayRow) -> String {
        let hourlyDetails = row.hours.map { cell in
            let hour = SunnyHoursFormatting.chartHourLabel(cell.hour)
            return "\(hour):00 \(cell.condition.localizedDisplayName(locale: locale))"
        }
        .joined(separator: ", ")

        guard !hourlyDetails.isEmpty else {
            return localTimeDisclosure ?? ""
        }
        guard let localTimeDisclosure else { return hourlyDetails }
        return "\(localTimeDisclosure). \(hourlyDetails)"
    }

    @ViewBuilder
    private var unavailableContent: some View {
        if isLoading {
            HStack(spacing: WeatherCardLayout.headerSpacing) {
                ProgressView()
                    .frame(
                        width: WeatherCardLayout.leadingIconWidth,
                        alignment: .leading
                    )
                    .accessibilityHidden(true)
                Text("Loading 10-day forecast…")
                    .font(.callout)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            VStack(spacing: 12) {
                Text(resolvedUnavailableMessage)
                    .font(.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .multilineTextAlignment(.center)

                if let retry {
                    Button("Try Again", systemImage: "arrow.clockwise") {
                        retry()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .center)
        }
    }

    private var resolvedUnavailableMessage: String {
        let message = unavailableMessage?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let message, !message.isEmpty else {
            return localizedString(
                "10-day sunny hours are unavailable.",
                locale: locale
            )
        }
        return message
    }

    private var legend: some View {
        // Prefer one line, then fall back to two only when space or Dynamic
        // Type makes the complete legend too wide for the card.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                legendItem("Sunny", color: theme.colors.dotSun)
                legendItem(
                    "Partly Sunny",
                    color: theme.colors.dotPartlyCloudy
                )
                legendItem(
                    "No Sun",
                    color: theme.colors.weatherNoSunTimelineColor(
                        for: screenTone
                    )
                )
                legendItem("Rain", color: theme.colors.dotRain)
                legendItem("Drizzle", color: theme.colors.dotDrizzle)
            }

            VStack(spacing: 6) {
                HStack(spacing: 14) {
                    legendItem("Sunny", color: theme.colors.dotSun)
                    legendItem(
                        "Partly Sunny",
                        color: theme.colors.dotPartlyCloudy
                    )
                    legendItem(
                        "No Sun",
                        color: theme.colors.weatherNoSunTimelineColor(
                            for: screenTone
                        )
                    )
                }
                HStack(spacing: 14) {
                    legendItem("Rain", color: theme.colors.dotRain)
                    legendItem("Drizzle", color: theme.colors.dotDrizzle)
                }
            }
        }
    }

    private func legendItem(
        _ title: LocalizedStringKey,
        color: Color
    ) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
        }
    }
}

// MARK: - Shared Time Axis

/// Axis labels positioned by the same chart bounds as all daily tracks.
private struct SunnyHoursAxis: View {
    let bounds: SunnyHoursChartBounds

    @Environment(\.appTheme) private var theme
    @ScaledMetric(relativeTo: .caption) private var labelColumnWidth: CGFloat = 58
    @ScaledMetric(relativeTo: .caption) private var axisHeight: CGFloat = 18

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: labelColumnWidth)

            GeometryReader { proxy in
                // `GeometryReader` is limited to the time scale: its width is
                // needed to turn hour values into exact label positions.
                ZStack(alignment: .topLeading) {
                    ForEach(bounds.axisHours(), id: \.self) { hour in
                        Text(SunnyHoursFormatting.chartHourLabel(hour))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(theme.colors.secondaryText)
                            .position(
                                x: bounds.xPosition(
                                    for: Double(hour),
                                    width: proxy.size.width
                                ),
                                y: proxy.size.height / 2
                            )
                    }
                }
            }
        }
        .frame(height: axisHeight)
        // Axis labels are visual anchors only; each adjacent button exposes
        // the full hourly value in a concise VoiceOver summary.
        .accessibilityHidden(true)
    }
}

// MARK: - One Daily Track

/// A single selectable day. Its label sits in a fixed column and its colored
/// hourly cells fill the remaining width according to shared chart bounds.
private struct SunnyHoursDayTrack: View {
    let row: SunnyHoursDayRow
    let bounds: SunnyHoursChartBounds
    let selected: Bool
    let label: String
    let theme: ThemeColors
    let noSunColor: Color
    let differentiateWithoutColor: Bool

    @ScaledMetric(relativeTo: .caption) private var labelWidth: CGFloat = 58
    @ScaledMetric(relativeTo: .caption) private var trackHeight: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 27

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.caption.weight(selected ? .bold : .medium))
                .foregroundStyle(
                    selected ? theme.primaryText : theme.secondaryText
                )
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(noSunColor)

                    ForEach(row.hours) { cell in
                        // Use one rectangle per actual hourly reading. The
                        // offset and width map the cell's hour into the domain.
                        Rectangle()
                            .fill(color(for: cell.condition))
                            .frame(
                                width: bounds.width(
                                    for: cell.hour...cell.hour,
                                    timelineWidth: proxy.size.width,
                                    minimumWidth: 1
                                )
                            )
                            .overlay {
                                if differentiateWithoutColor,
                                   cell.condition == .partlySunny
                                    || cell.condition == .drizzle {
                                    Rectangle()
                                        .stroke(
                                            theme.primaryText.opacity(0.75),
                                            style: StrokeStyle(
                                                lineWidth: 0.7,
                                                dash: [2, 2]
                                            )
                                        )
                                }
                            }
                            .offset(
                                x: bounds.xPosition(
                                    for: Double(cell.hour),
                                    width: proxy.size.width
                                )
                            )
                    }
                }
                .clipShape(Capsule())
                .overlay {
                    if selected {
                        Capsule()
                            .stroke(theme.primaryText, lineWidth: 1.5)
                    }
                }
            }
            .frame(height: trackHeight)
        }
        .frame(height: rowHeight)
        .contentShape(.rect)
    }

    private func color(for condition: AppWeatherCondition) -> Color {
        switch condition {
        case .clear:
            theme.dotSun
        case .partlySunny:
            theme.dotPartlyCloudy
        case .rain:
            theme.dotRain
        case .drizzle:
            theme.dotDrizzle
        case .partlyCloudy, .cloudy, .snow, .fog, .wind:
            noSunColor
        }
    }
}

// MARK: - Chart Row Models

/// Prepared data for one daily track. Keeping it value-based makes `ForEach`
/// identity stable while chart selection and theme colors change.
private struct SunnyHoursDayRow: Identifiable {
    /// Literal root-selector day used when the row is tapped.
    let selectionDate: Date
    /// Original destination-local forecast instant used for display formatting.
    let forecastDate: Date
    let hours: [SunnyHoursDayCell]
    let bounds: SunnyHoursChartBounds

    var id: Date { forecastDate }
}

/// One hour's condition after it has been converted to the city's local hour.
private struct SunnyHoursDayCell: Identifiable {
    let id: Date
    let hour: Int
    let condition: AppWeatherCondition
}
