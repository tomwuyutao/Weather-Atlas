//
//  BestSunnyDatesCard.swift
//  Weather
//
//  Purpose: Summarizes the strongest upcoming sunny days across Saved Places.
//

import SwiftUI

// MARK: - Date Summary Model

/// An average sunny-hours summary for one forecast date across Saved Places.
struct BestSunnyDateSummary: Identifiable {
    let date: Date
    /// Mean selected-day sunny hours across concrete recommendations.
    let averageSunnyHours: Double

    var id: Date { date }
}

/// Compact planning control for choosing a high-sun day across Saved Places.
struct BestSunnyDatesCard: View {
    // MARK: Inputs and Environment

    let summaries: [BestSunnyDateSummary]
    /// Shared root selection. Tapping a heatmap cell updates every tab's date
    /// control and any report currently shown in its navigation stack.
    @Binding var selectedDate: Date
    /// Describes why the heatmap may not yet contain a usable date.
    let presentationState: SavedPlacesForecastPresentationState

    @Environment(\.appTheme) private var theme
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    // MARK: Calendar Layout

    private var calendarColumns: [GridItem] {
        // Seven equal-width columns mirror the user's locale-aware week.
        Array(repeating: GridItem(.flexible(), spacing: 7), count: 7)
    }

    /// The supplied forecast range rendered as complete calendar weeks. Dates
    /// with no saved-place forecast stay visible but inert, preserving the
    /// heatmap's calendar rhythm without implying that weather data exists.
    private var calendarDates: [BestSunnyCalendarDate] {
        // Associate forecasts with normalized local days before filling the
        // leading/trailing cells required to complete calendar weeks.
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

        // The real forecast range sits between inert cells from adjacent weeks.
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
        // Localize the weekday names without replacing the system calendar's
        // First Day of Week preference. The same value also positions dates.
        let firstWeekdayIndex = calendar.firstWeekday - 1
        var localizedCalendar = calendar
        localizedCalendar.locale = locale
        let symbols = localizedCalendar.shortStandaloneWeekdaySymbols

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
        // Every planning card uses the same shared header, padding, corner
        // radius, and translucent material as the rest of the app.
        VStack(
            alignment: .leading,
            spacing: WeatherCardLayout.contentSpacing
        ) {
            WeatherCardHeader(
                icon: "calendar",
                title: "Best Sunny Dates"
            )

            if hasAvailableForecast {
                calendarHeatmap
            } else {
                statusContent
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

    /// Keeps the card informative without inventing heatmap values while the
    /// library is empty, loading, or unavailable.
    private var statusContent: some View {
        HStack(spacing: 8) {
            if presentationState == .loading {
                ProgressView()
                    .controlSize(.small)

            }

            Text(statusMessage)
        }
        .font(.callout)
        .foregroundStyle(theme.colors.secondaryText)
        .frame(
            maxWidth: .infinity,
            minHeight: WeatherCardFallbackLayout.savedDatesContentHeight,
            alignment: .leading
        )

    }

    private var statusMessage: LocalizedStringKey {
        switch presentationState {
        case .emptyLibrary:
            "Save a place to compare upcoming sunny dates."
        case .loading:
            "Loading saved-place forecasts…"
        case .unavailable:
            "Saved-place forecasts are unavailable."
        case .ready:
            "No saved-place forecasts are available for this period."
        }
    }

    private var calendarHeatmap: some View {
        VStack(spacing: 7) {
            LazyVGrid(columns: calendarColumns, spacing: 0) {
                // `enumerated` gives the static labels stable positional IDs;
                // weekday strings themselves can repeat in some locales.
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
            let isSelected = calendar.isDate(
                summary.date,
                inSameDayAs: selectedDate
            )
            // Only dates with forecasts are buttons. Empty adjacent-week cells
            // retain the grid's geometry but cannot choose a missing forecast.
            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    selectedDate = calendar.startOfDay(for: summary.date)
                }
            } label: {
                calendarDayCell(
                    day,
                    isSelected: isSelected
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
        // The cell is always rendered once. Only its fill, outline, and text
        // color change, keeping the heatmap's grid visually stable.
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        return ZStack {
            shape.fill(heatmapFill(for: day))

            // A calendar cell should contain the day number only. Date
            // formatting appends locale-specific units such as Japanese 日,
            // which makes the compact grid visually inconsistent.
            Text(
                calendar.component(.day, from: day.date),
                format: .number.locale(locale)
            )
            .font(.body.weight(isSelected ? .semibold : .medium).monospacedDigit())
            .foregroundStyle(
                day.isForecastDate
                    ? (isSelected ? theme.colors.accent : theme.colors.primaryText)
                    : theme.colors.secondaryText
            )
            .lineLimit(1)
            .minimumScaleFactor(0.65)
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

        return theme.colors.sunnyHoursColor(
            for: summary.averageSunnyHours,
            colorScheme: colorScheme
        )
    }

    private func leadingCalendarCellCount(for date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private func dates(from firstDate: Date, through lastDate: Date) -> [Date] {
        // Advance by calendar days, rather than 86,400-second durations, to
        // keep the forecast grid correct around daylight-saving transitions.
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

// MARK: - Calendar Cell State

/// A visual day cell combines a calendar date with an optional saved-place
/// summary. `nil` means an adjacent-week filler rather than unavailable data.
private struct BestSunnyCalendarDate: Identifiable {
    let date: Date
    let summary: BestSunnyDateSummary?

    var id: Date { date }

    var isForecastDate: Bool {
        summary != nil
    }
}
