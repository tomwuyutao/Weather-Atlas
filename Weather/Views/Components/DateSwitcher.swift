//
//  DateSwitcher.swift
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
    // MARK: Inputs and Local Presentation State

    /// The root owns the selected forecast day; this compact toolbar control
    /// merely mutates that binding when the person steps or picks a date.
    @Binding var selection: Date
    let availableDates: [Date]

    @State private var showsDatePicker = false

    @Environment(\.appTheme) private var theme
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    // The toolbar's date label and hit targets must grow with the surrounding
    // body text instead of remaining a fixed, harder-to-read control.
    @ScaledMetric(relativeTo: .body) private var dateLabelWidth: CGFloat = 104
    @ScaledMetric(relativeTo: .body) private var dateLabelHeight: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var controlHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var stepperWidth: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var stepperHeight: CGFloat = 36

    // MARK: Normalized Date Navigation

    private var dates: [Date] {
        // Date values may include different times. Normalize them to calendar
        // days, de-duplicate, and sort before calculating neighbours.
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
        // The toolbar itself supplies the native glass material. This view
        // only lays out its three controls inside that system-provided shell.
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
                    // The wider label fits ordinary localized dates at the
                    // standard text style. If a longer date still needs more
                    // room, reduce its size before truncating its contents.
                    .minimumScaleFactor(0.65)
                    .allowsTightening(true)
                    .frame(
                        minWidth: dateLabelWidth,
                        minHeight: dateLabelHeight
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Forecast Date"))
            .accessibilityValue(dateText(for: normalizedSelection))
            .accessibilityHint(Text("Open Forecast Date Picker"))
            .popover(isPresented: $showsDatePicker) {
                datePicker
                    // On iPhone retain the anchored calendar instead of
                    // adapting this short choice into a full-screen sheet.
                    .presentationCompactAdaptation(.popover)
            }

            stepperButton(
                systemImage: "chevron.right",
                targetDate: nextDate
            )
        }
        .padding(.horizontal, 2)
        // The native toolbar provides this control's glass container. Adding
        // a second custom glass background here creates a nested capsule.
        .frame(minHeight: controlHeight)
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
                .frame(width: stepperWidth, height: stepperHeight)
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
            systemImage == "chevron.left"
                ? Text("Previous Forecast Date")
                : Text("Next Forecast Date")
        )
        .accessibilityValue(targetDate.map(dateText(for:)) ?? "")
    }

    // MARK: Calendar Picker

    @ViewBuilder
    private var datePicker: some View {
        if let firstDate = dates.first, let lastDate = dates.last {
            DatePicker(
                "Forecast Date",
                selection: Binding(
                    // The graphical picker works with any day in its range;
                    // the setter below snaps that choice to an actual forecast.
                    get: { normalizedSelection },
                    set: selectNearestAvailableDate
                ),
                in: firstDate...lastDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .frame(minWidth: 320)
            .presentationCompactAdaptation(.popover)
        } else {
            ContentUnavailableView("No Forecast Dates", systemImage: "calendar")
                .padding()
        }
    }

    private func selectNearestAvailableDate(_ date: Date) {
        // Forecasts can have missing days. Choose the closest available day
        // rather than leaving the shared selection on an unrenderable one.
        guard let nearestDate = dates.min(by: {
            abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date))
        }) else {
            return
        }
        selection = nearestDate
        showsDatePicker = false
    }

    private func dateText(for date: Date) -> String {
        return date.formatted(
            Date.FormatStyle.dateTime
                .weekday(.abbreviated)
                .month(.abbreviated)
                .day()
                .locale(locale)
        )
    }
}

// MARK: - Shared Forecast Horizon

/// One literal forecast horizon shared by Your Location, Map, Places, and chart sheets.
enum ForecastDateHorizon {
    static func dates(in calendar: Calendar) -> [Date] {
        // Build local calendar days rather than adding fixed 24-hour intervals,
        // which would be wrong across daylight-saving-time changes.
        let today = calendar.startOfDay(for: Date())
        return (0..<10).compactMap {
            calendar.date(byAdding: .day, value: $0, to: today)
        }
    }

    /// Default only for previews and isolated callers. App destinations pass
    /// the current-location calendar explicitly.
    static var dates: [Date] {
        dates(in: .current)
    }
}
