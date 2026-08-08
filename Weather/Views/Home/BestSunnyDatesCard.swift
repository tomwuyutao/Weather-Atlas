//
//  BestSunnyDatesCard.swift
//  Weather
//
//  Purpose: Summarizes the strongest upcoming sunny days across Saved Places.
//

import SwiftUI

/// A weighted sunlight summary for one forecast date across Saved Places.
struct BestSunnyDateSummary: Identifiable {
    let date: Date
    let sunnyScore: Double
    let availableCityCount: Int

    var id: Date { date }
}

/// Compact planning control for choosing a high-sun day across Saved Places.
struct BestSunnyDatesCard: View {
    let summaries: [BestSunnyDateSummary]
    @Binding var selectedDate: Date

    @Environment(\.appTheme) private var theme
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 7), count: 7)
    }

    /// The forecast horizon rendered as complete calendar weeks. Dates with no
    /// saved-place forecast stay visible but inert, preserving the heatmap's
    /// calendar rhythm without implying that weather data exists for them.
    private var calendarDates: [BestSunnyCalendarDate] {
        let summariesByDate = Dictionary(
            uniqueKeysWithValues: summaries.map {
                (calendar.startOfDay(for: $0.date), $0)
            }
        )
        let forecastDates = summariesByDate.keys.sorted()

        guard let firstForecastDate = forecastDates.first,
              let lastForecastDate = forecastDates.last else {
            return []
        }

        let leadingCount = leadingCalendarCellCount(for: firstForecastDate)
        let leadingDates = (0..<leadingCount).compactMap { index in
            calendar.date(
                byAdding: .day,
                value: index - leadingCount,
                to: firstForecastDate
            )
        }

        let forecastRange = dates(from: firstForecastDate, through: lastForecastDate)
        let trailingCount = (
            7 - ((leadingDates.count + forecastRange.count) % 7)
        ) % 7
        let trailingDates = (0..<trailingCount).compactMap { index in
            calendar.date(
                byAdding: .day,
                value: index + 1,
                to: lastForecastDate
            )
        }

        return (leadingDates + forecastRange + trailingDates).map { date in
            let normalizedDate = calendar.startOfDay(for: date)
            return BestSunnyCalendarDate(
                date: normalizedDate,
                summary: summariesByDate[normalizedDate]
            )
        }
    }

    private var weekdayLabels: [String] {
        var localizedCalendar = calendar
        localizedCalendar.locale = locale
        let symbols = localizedCalendar.shortStandaloneWeekdaySymbols
        let firstWeekdayIndex = localizedCalendar.firstWeekday - 1

        guard symbols.count == 7,
              symbols.indices.contains(firstWeekdayIndex) else {
            return []
        }

        return Array(symbols[firstWeekdayIndex...])
            + Array(symbols[..<firstWeekdayIndex])
    }

    private var hasAvailableForecast: Bool {
        calendarDates.contains { $0.isForecastDate }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WeatherCardHeader(
                icon: "calendar",
                title: "Best Sunny Dates",
                subtitle: localizedString("Across Saved Places", locale: locale)
            )

            if !hasAvailableForecast {
                Text("No saved-place forecasts are available yet.")
                    .font(.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .padding(.vertical, 4)
            } else {
                calendarHeatmap
            }
        }
        .padding(WeatherCardLayout.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .detailTranslucentCard(
            colorScheme: colorScheme,
            in: RoundedRectangle(
                cornerRadius: WeatherCardLayout.cornerRadius,
                style: .continuous
            )
        )
    }

    private var calendarHeatmap: some View {
        VStack(spacing: 7) {
            LazyVGrid(columns: calendarColumns, spacing: 0) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(theme.colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }

            LazyVGrid(columns: calendarColumns, spacing: 7) {
                ForEach(calendarDates) { day in
                    calendarDayView(day)
                }
            }
        }
    }

    @ViewBuilder
    private func calendarDayView(_ day: BestSunnyCalendarDate) -> some View {
        if let summary = day.summary, day.isForecastDate {
            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    selectedDate = calendar.startOfDay(for: summary.date)
                }
            } label: {
                calendarDayCell(
                    day,
                    isSelected: calendar.isDate(
                        summary.date,
                        inSameDayAs: selectedDate
                    )
                )
            }
            .buttonStyle(.plain)
        } else {
            calendarDayCell(day, isSelected: false)
        }
    }

    private func calendarDayCell(
        _ day: BestSunnyCalendarDate,
        isSelected: Bool
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        return ZStack {
            shape.fill(heatmapFill(for: day))

            Text(
                day.date.formatted(
                    .dateTime.day().locale(locale)
                )
            )
            .font(
                .system(
                    size: 16,
                    weight: isSelected ? .semibold : .medium,
                    design: .default
                )
                .monospacedDigit()
            )
            .foregroundStyle(
                day.isForecastDate
                    ? (isSelected ? theme.colors.accent : theme.colors.primaryText)
                    : theme.colors.secondaryText
            )
            .lineLimit(1)
        }
        .overlay {
            shape.stroke(
                isSelected
                    ? theme.colors.accent
                    : theme.colors.primaryText.opacity(0.16),
                lineWidth: isSelected ? 1.65 : 0.7
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(2)
        .contentShape(shape)
    }

    private func heatmapFill(for day: BestSunnyCalendarDate) -> Color {
        guard day.isForecastDate,
              let summary = day.summary else {
            return theme.colors.secondaryText.opacity(
                colorScheme == .dark ? 0.18 : 0.10
            )
        }

        guard summary.sunnyScore > 0,
              summary.availableCityCount > 0 else {
            return theme.colors.glassFill.opacity(
                colorScheme == .dark ? 0.34 : 0.56
            )
        }

        let fraction = max(
            0,
            min(1, summary.sunnyScore / Double(summary.availableCityCount))
        )
        let curvedFraction = pow(fraction, 1.55)
        return theme.colors.dotSun.opacity(0.16 + 0.79 * curvedFraction)
    }

    private func leadingCalendarCellCount(for date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private func dates(from firstDate: Date, through lastDate: Date) -> [Date] {
        var dates: [Date] = []
        var date = firstDate

        while date <= lastDate {
            dates.append(date)
            guard let nextDate = calendar.date(
                byAdding: .day,
                value: 1,
                to: date
            ) else {
                break
            }
            date = nextDate
        }

        return dates
    }
}

private struct BestSunnyCalendarDate: Identifiable {
    let date: Date
    let summary: BestSunnyDateSummary?

    var id: Date { date }

    var isForecastDate: Bool {
        (summary?.availableCityCount ?? 0) > 0
    }
}
