//
//  SunnyHoursCard.swift
//  Weather
//
//  Purpose: Presents the compact ten-day sunny-hours detail card using the
//  current place-owned data model.
//

import SwiftUI

struct SunnyHoursOverviewCard: View {
    let city: CityWeather
    /// Shared Detail selection; every chart row can change the active day.
    @Binding var selectedDate: Date

    @Environment(\.accessibilityDifferentiateWithoutColor)
    private var differentiateWithoutColor
    @Environment(\.appTheme) private var theme
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    private var rows: [SunnyHoursDayRow] {
        city.dailyForecasts.prefix(10).compactMap { forecast in
            guard let selectionDate = city.selectionDate(
                for: forecast,
                selectionCalendar: calendar
            ),
                  selectionDate >= calendar.startOfDay(for: Date()),
                  case .success(let data) = SunninessScoring.sunnyHoursData(
                for: forecast,
                timeZone: city.timeZone
                  ) else {
                return nil
            }

            return SunnyHoursDayRow(
                date: selectionDate,
                hours: data.hours.compactMap { hour in
                    guard let condition = SunninessScoring.condition(for: hour)
                    else {
                        return nil
                    }
                    return SunnyHoursDayCell(
                        id: hour.date,
                        hour: hour.hour(in: city.timeZone),
                        condition: condition
                    )
                },
                bounds: data.bounds
            )
        }
    }

    private var chartBounds: SunnyHoursChartBounds? {
        SunnyHoursChartBounds.merged(rows.map(\.bounds))
    }

    var body: some View {
        if let chartBounds, !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.day.timeline.left")
                        .frame(width: 24, alignment: .leading)
                    Text("Sunny Hours")
                    Spacer(minLength: 8)
                    Text(selectedSunnyWindow)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                }
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)

                SunnyHoursAxis(bounds: chartBounds)

                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        Button {
                            withAnimation(.smooth(duration: 0.2)) {
                                selectedDate = calendar.startOfDay(for: row.date)
                            }
                        } label: {
                            SunnyHoursDayTrack(
                                row: row,
                                bounds: chartBounds,
                                selected: calendar.isDate(
                                    row.date,
                                    inSameDayAs: selectedDate
                                ),
                                label: dayLabel(for: row.date),
                                theme: theme.colors,
                                differentiateWithoutColor:
                                    differentiateWithoutColor
                            )
                        }
                        .buttonStyle(.plain)
                        .contentShape(.rect)
                        .accessibilityLabel(
                            "\(dayLabel(for: row.date)), \(row.accessibilitySummary(locale: locale))"
                        )
                        .accessibilityAddTraits(
                            calendar.isDate(
                                row.date,
                                inSameDayAs: selectedDate
                            ) ? .isSelected : []
                        )
                    }
                }

                legend
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
            .padding(14)
            .detailTranslucentCard(
                colorScheme: colorScheme,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
        }
    }

    private var selectedSunnyWindow: String {
        guard let forecast = city.forecastIfAvailable(
            on: selectedDate,
            selectionCalendar: calendar
        ),
              case .success(let data) = SunninessScoring.sunnyHoursData(
                for: forecast,
                timeZone: city.timeZone
              ),
              let range = SunninessScoring.longestSunnyHourRange(
                in: data.hours,
                timeZone: city.timeZone
              ) else {
            return localizedString("No Sun", locale: locale)
        }

        return "\(SunninessScoring.compactHourLabel(range.lowerBound, locale: locale)) – \(SunninessScoring.compactHourLabel(range.upperBound + 1, locale: locale))"
    }

    private func dayLabel(for date: Date) -> String {
        if calendar.isDateInToday(date) {
            return localizedString("Today", locale: locale)
        }
        return date.formatted(
            .dateTime
                .month(.abbreviated)
                .day()
                .locale(locale)
        )
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                legendItem("Sunny", color: theme.colors.dotSun)
                legendItem(
                    "Partly Sunny",
                    color: theme.colors.dotPartlyCloudy
                )
                legendItem("No Sun", color: theme.colors.settingsRowFill)
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
                    legendItem("No Sun", color: theme.colors.settingsRowFill)
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

private struct SunnyHoursAxis: View {
    let bounds: SunnyHoursChartBounds

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: SunnyHoursDayTrack.labelWidth)

            GeometryReader { proxy in
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
                                y: 8
                            )
                    }
                }
            }
        }
        .frame(height: 18)
    }
}

private struct SunnyHoursDayTrack: View {
    static let labelWidth: CGFloat = 58

    let row: SunnyHoursDayRow
    let bounds: SunnyHoursChartBounds
    let selected: Bool
    let label: String
    let theme: ThemeColors
    let differentiateWithoutColor: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.caption.weight(selected ? .bold : .medium))
                .foregroundStyle(
                    selected ? theme.primaryText : theme.secondaryText
                )
                .lineLimit(1)
                .frame(width: Self.labelWidth, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.settingsRowFill)

                    ForEach(row.hours) { cell in
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
            .frame(height: 13)
        }
        .frame(height: 27)
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
            theme.settingsRowFill
        }
    }
}

private struct SunnyHoursDayRow: Identifiable {
    let date: Date
    let hours: [SunnyHoursDayCell]
    let bounds: SunnyHoursChartBounds

    var id: Date { date }

    func accessibilitySummary(locale: Locale) -> String {
        let sunnyCount = hours.filter {
            $0.condition.isSunnyOrPartlySunny
        }.count
        if sunnyCount == 0 {
            return localizedString("No Sun", locale: locale)
        }
        return localizedString("\(sunnyCount) sunny hours", locale: locale)
    }
}

private struct SunnyHoursDayCell: Identifiable {
    let id: Date
    let hour: Int
    let condition: AppWeatherCondition
}
