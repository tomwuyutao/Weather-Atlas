//
//  TenDaySunnyHoursTimeline.swift
//  Weather
//
//  Purpose: Presents the compact ten-day sunny-hours detail card using the
//  current place-owned data model.
//

import SwiftUI

// MARK: - Ten-Day Sunny-Hours Overview

/// Shared current-location/saved-place ten-day chart. It turns each available
/// daily forecast into a row of hourly weather conditions and writes taps to
/// the root-selected day.
struct TenDaySunnyHoursTimeline: View {
    // MARK: - Inputs

    /// Optional for report surfaces that must preserve the card while their
    /// forecast request is still loading or has failed.
    let city: CityWeather?
    /// Shared Detail selection; every chart row can change the active day.
    @Binding var selectedDate: Date
    private let isLoading: Bool
    private let unavailableMessage: String?
    private let retry: (() -> Void)?

    @Environment(\.appTheme) private var theme
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    /// Your Location uses this state-aware initializer so the ten-day card has
    /// stable identity through loading, failure, and retry episodes.
    init(
        city: CityWeather?,
        selectedDate: Binding<Date>,
        isLoading: Bool,
        unavailableMessage: String?,
        retry: (() -> Void)?
    ) {
        self.city = city
        _selectedDate = selectedDate
        self.isLoading = isLoading
        self.unavailableMessage = unavailableMessage
        self.retry = retry
    }

    // MARK: - Chart Data Preparation

    private var rows: [SunnyHoursDayRow] {
        // Render every real WeatherKit daily forecast independently. A short
        // (for example, nine-day) horizon simply produces the same number of
        // rows; an incomplete daylight slice stays a neutral row instead of
        // hiding that forecast date.
        guard let city else { return [] }

        return city.dailyForecasts
            .sorted { $0.date < $1.date }
            .prefix(10)
            .map { forecast in
                let data = SunnyHoursCalculation.sunnyHoursData(
                    for: forecast,
                    timeZone: city.timeZone
                )
                let selectionDate = city.selectionDate(
                    for: forecast,
                    selectionCalendar: calendar
                ) ?? calendar.startOfDay(for: forecast.date)

                return SunnyHoursDayRow(
                    selectionDate: selectionDate,
                    forecastDate: forecast.date,
                    hours: data.hours.map { hour in
                        SunnyHoursDayCell(
                            id: hour.date,
                            hour: hour.hour(in: city.timeZone),
                            // The track keeps only its color role. It never
                            // substitutes a different WeatherKit condition
                            // when a cached source condition is unavailable.
                            condition: SunnyHoursChartCondition(
                                weatherCondition: hour.condition
                            )
                        )
                    },
                    bounds: data.bounds
                )
            }
    }

    private var chartBounds: SunnyHoursChartBounds? {
        // A merged domain makes the time axis identical across every row even
        // if an individual forecast starts later or ends earlier.
        SunnyHoursChartBounds.merged(rows.map(\.bounds))
    }

    /// Uses the shared warm neutral so daily and 10-day cloudy marks match.
    private var noSunTimelineColor: Color {
        theme.colors.noSunTimelineFill
    }

    // MARK: - Presentation

    var body: some View {
        VStack(alignment: .leading, spacing: WeatherCardLayout.contentSpacing) {
            WeatherCardHeader(
                icon: "calendar",
                title: "10-Day Sunny Hours"
            )

            if let chartBounds {
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
                                noSunColor: noSunTimelineColor
                            )
                        }
                        .buttonStyle(.plain)
                        // Keep the compact 27-point row rhythm: the
                        // chart is primarily a dense visual forecast, with
                        // selection as a secondary interaction.
                        .contentShape(.rect)

                    }
                }

                legend
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)

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

    // MARK: - Labels and Availability

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

    @ViewBuilder
    private var unavailableContent: some View {
        if isLoading {
            HStack(spacing: WeatherCardLayout.headerSpacing) {
                ProgressView()
                    .frame(
                        width: WeatherCardLayout.leadingIconWidth,
                        alignment: .leading
                    )

                Text("Loading 10-day forecast…")
                    .font(.callout)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .leading)

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
                    .weatherGlassActionStyle()
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: WeatherCardFallbackLayout.tenDayTimelineContentHeight,
                alignment: .center
            )
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

    // MARK: - Legend

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
                    color: noSunTimelineColor
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
                        color: noSunTimelineColor
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
        // the full hourly value in a concise local-time summary.

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

            SunnyHoursContinuousCapsuleTrack(
                hours: row.hours.map {
                    SunnyHoursChartHour(
                        date: $0.id,
                        hour: $0.hour,
                        condition: $0.condition
                    )
                },
                bounds: bounds,
                colors: SunnyHoursChartColors(
                    primary: theme.primaryText,
                    secondary: theme.secondaryText,
                    sun: theme.dotSun,
                    partlySunny: theme.dotPartlyCloudy,
                    rain: theme.dotRain,
                    drizzle: theme.dotDrizzle,
                    noSun: noSunColor
                ),
                height: trackHeight,
                outlineColor: selected ? theme.primaryText : nil
            )
        }
        .frame(height: rowHeight)
        .contentShape(.rect)
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

/// One available daylight hour after conversion to the city's local hour.
/// The chart condition is presentation-only and derives directly from the
/// source condition's tint role without replacing its API value.
private struct SunnyHoursDayCell: Identifiable {
    let id: Date
    let hour: Int
    let condition: SunnyHoursChartCondition
}
