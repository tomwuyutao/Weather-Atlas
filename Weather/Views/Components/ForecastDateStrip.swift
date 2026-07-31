//
//  ForecastDateStrip.swift
//  Weather
//
//  Purpose: Provides the shared, horizontally scrolling forecast-date context
//  used directly below native navigation titles.
//

import SwiftUI

struct ForecastDateStrip: View {
    @Binding var selection: Date

    let availableDates: [Date]

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentedCalendar: CalendarPresentation?
    @State private var scrolledDate: Date?

    private var dates: [Date] {
        let normalized = availableDates.map { calendar.startOfDay(for: $0) }
        return Array(Set(normalized)).sorted()
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 2) {
                ForEach(dates, id: \.self) { date in
                    ForecastDateButton(
                        date: date,
                        isSelected: calendar.isDate(date, inSameDayAs: selection),
                        locale: locale
                    ) {
                        selection = date
                    }
                    .id(date)
                }

                Button {
                    presentedCalendar = CalendarPresentation()
                } label: {
                    Label("Choose Date", systemImage: "calendar")
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows a calendar for choosing another forecast date.")
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolledDate, anchor: .center)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        // Horizontal ScrollView otherwise accepts all proposed vertical space
        // when it sits above Places content. Its content owns the natural
        // height, including larger Dynamic Type categories.
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            scrollToSelection()
        }
        .onChange(of: selection) {
            scrollToSelection()
        }
        .sheet(item: $presentedCalendar) { _ in
            ForecastCalendarSheet(
                selection: $selection,
                availableDates: dates
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Forecast date")
    }

    private func scrollToSelection() {
        let normalizedSelection = calendar.startOfDay(for: selection)
        guard dates.contains(normalizedSelection) else { return }
        withAnimation(reduceMotion ? nil : .smooth) {
            scrolledDate = normalizedSelection
        }
    }
}

private struct CalendarPresentation: Identifiable {
    let id = "forecast-calendar"
}

private struct ForecastDateButton: View {
    let date: Date
    let isSelected: Bool
    let locale: Locale
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(date, format: .dateTime.weekday(.abbreviated).locale(locale))
                    .font(.caption)
                Text(date, format: .dateTime.day().locale(locale))
                    .font(.headline)
            }
            .padding(.horizontal, 4)
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(
                isSelected ? theme.colors.background : theme.colors.primaryText
            )
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(theme.colors.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text(date, format: .dateTime.weekday(.wide).month(.wide).day().locale(locale))
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ForecastCalendarSheet: View {
    @Binding var selection: Date

    let availableDates: [Date]

    @Environment(\.calendar) private var calendar
    @Environment(\.dismiss) private var dismiss
    @State private var draftDate: Date

    init(selection: Binding<Date>, availableDates: [Date]) {
        _selection = selection
        self.availableDates = availableDates
        _draftDate = State(initialValue: selection.wrappedValue)
    }

    private var selectableRange: ClosedRange<Date> {
        let today = calendar.startOfDay(for: Date())
        let lowerBound = availableDates.first ?? today
        let upperBound = availableDates.last
            ?? calendar.date(byAdding: .day, value: 9, to: today)
            ?? today
        return lowerBound...max(lowerBound, upperBound)
    }

    var body: some View {
        NavigationStack {
            DatePicker(
                "Forecast Date",
                selection: $draftDate,
                in: selectableRange,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("Choose Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        selection = nearestAvailableDate(to: draftDate)
                        dismiss()
                    }
                }
            }
        }
        .presentationSizing(.form)
    }

    private func nearestAvailableDate(to date: Date) -> Date {
        availableDates.min {
            abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date))
        } ?? calendar.startOfDay(for: date)
    }
}
