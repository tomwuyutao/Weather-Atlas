//
//  TopForecastDateSwitcher.swift
//  Weather
//
//  Purpose: Provides the compact previous/date/next forecast control in the
//  trailing navigation area, replacing the experimental scrolling date strip.
//

import SwiftUI

/// A compact, native date stepper with an anchored system calendar picker.
///
/// The control owns no app-wide state: every main destination receives the
/// same binding from the root, so switching tabs never resets the chosen day.
struct TopForecastDateSwitcher: View {
    @Binding var selection: Date
    let availableDates: [Date]

    @State private var showsDatePicker = false

    @Environment(\.appTheme) private var theme
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    private var dates: [Date] {
        Array(Set(availableDates.map(calendar.startOfDay(for:))).sorted())
    }

    private var normalizedSelection: Date {
        calendar.startOfDay(for: selection)
    }

    private var previousDate: Date? {
        dates.last(where: { $0 < normalizedSelection })
    }

    private var nextDate: Date? {
        dates.first(where: { $0 > normalizedSelection })
    }

    var body: some View {
        HStack(spacing: 0) {
            stepperButton(
                systemImage: "chevron.left",
                targetDate: previousDate
            )

            Button {
                showsDatePicker = true
            } label: {
                Text(dateText(for: normalizedSelection))
                    // Match the Saved Places recommendation rows so the
                    // shared forecast control reads at the same hierarchy.
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(minWidth: 62, minHeight: 32)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Forecast date")
            .accessibilityValue(dateText(for: normalizedSelection))
            .popover(isPresented: $showsDatePicker) {
                datePicker
            }

            stepperButton(
                systemImage: "chevron.right",
                targetDate: nextDate
            )
        }
        .padding(.horizontal, 2)
        .frame(height: 36)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(theme.colors.primaryText.opacity(0.16), lineWidth: 1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func stepperButton(
        systemImage: String,
        targetDate: Date?
    ) -> some View {
        Button {
            guard let targetDate else { return }
            withAnimation(.smooth(duration: 0.2)) {
                selection = targetDate
            }
        } label: {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 28, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            targetDate == nil
                ? theme.colors.primaryText.opacity(0.28)
                : theme.colors.primaryText
        )
        .disabled(targetDate == nil)
        .accessibilityLabel(
            targetDate == previousDate ? "Previous Date" : "Next Date"
        )
    }

    @ViewBuilder
    private var datePicker: some View {
        if let firstDate = dates.first, let lastDate = dates.last {
            DatePicker(
                "Forecast Date",
                selection: Binding(
                    get: { normalizedSelection },
                    set: selectNearestAvailableDate
                ),
                in: firstDate...lastDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .frame(minWidth: 320)
        } else {
            ContentUnavailableView("No Forecast Dates", systemImage: "calendar")
                .padding()
        }
    }

    private func selectNearestAvailableDate(_ date: Date) {
        guard let nearestDate = dates.min(by: {
            abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date))
        }) else {
            return
        }
        selection = nearestDate
        showsDatePicker = false
    }

    private func dateText(for date: Date) -> String {
        if calendar.isDateInToday(date) {
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
}

/// One literal forecast horizon shared by Home, Map, Places, and chart sheets.
enum ForecastDateHorizon {
    static var dates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<10).compactMap {
            calendar.date(byAdding: .day, value: $0, to: today)
        }
    }
}
