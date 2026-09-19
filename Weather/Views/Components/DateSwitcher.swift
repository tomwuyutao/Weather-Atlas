//
//  DateSwitcher.swift
//  Weather
//
//  Purpose: Provides the compact previous/date/next forecast control in the
//  trailing navigation area.
//

import SwiftUI

// MARK: - Shared Forecast Date Labels

/// Produces the compact, locale-aware date wording shared by forecast controls
/// and cards that describe the app-wide selected day.
enum ForecastDateLabel {
  static func compact(
    for date: Date,
    calendar: Calendar,
    locale: Locale
  ) -> String {
    if calendar.isDateInToday(date) {
      return localizedString("Today", locale: locale)
    }

    if calendar.isDateInTomorrow(date) {
      return localizedString("Tomorrow", locale: locale)
    }

    var style = Date.FormatStyle.dateTime
      .weekday(.abbreviated)
      .month(.abbreviated)
      .day()
      .locale(locale)
    style.timeZone = calendar.timeZone
    return date.formatted(style)
  }

  /// Formats an inclusive forecast-day span without assuming field order or
  /// punctuation. A one-day range stays compact rather than repeating the
  /// same date twice.
  static func compactRange(
    from start: Date,
    through end: Date,
    calendar: Calendar,
    locale: Locale
  ) -> String {
    let startDay = calendar.startOfDay(for: min(start, end))
    let endDay = calendar.startOfDay(for: max(start, end))

    var oneDayStyle = Date.FormatStyle.dateTime
      .month(.abbreviated)
      .day()
      .locale(locale)
    oneDayStyle.timeZone = calendar.timeZone

    guard startDay != endDay else {
      return startDay.formatted(oneDayStyle)
    }

    let rangeStyle = Date.IntervalFormatStyle(
      locale: locale,
      calendar: calendar,
      timeZone: calendar.timeZone
    )
    .month(.abbreviated)
    .day()
    return (startDay..<endDay).formatted(rangeStyle)
  }
}

/// A compact, native date stepper with an anchored system calendar picker.
///
/// The control owns no app-wide state: every main destination receives the
/// same binding from the root, so switching tabs never resets the chosen day.
struct TopForecastDateSwitcher: View {
  /// Saved Places can preserve the control's position while showing a
  /// noninteractive time span for modes that are not driven by one day.
  enum Display: Equatable {
    case selectedDate
    case staticRange(start: Date, end: Date)
  }

  // MARK: - Inputs and Local Presentation State

  /// The root owns the selected forecast day; this compact toolbar control
  /// merely mutates that binding when the person steps or picks a date.
  @Binding var selection: Date
  let availableDates: [Date]
  let display: Display
  let staticRangeHorizontalPadding: CGFloat

  @State private var showsDatePicker = false

  @Environment(\.appTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.calendar) private var calendar
  @Environment(\.locale) private var locale
  // The toolbar's date label and hit targets must grow with the surrounding
  // body text instead of remaining a fixed, harder-to-read control.
  @ScaledMetric(relativeTo: .body) private var dateLabelWidth: CGFloat = 96
  @ScaledMetric(relativeTo: .body) private var dateLabelHeight: CGFloat = 32
  @ScaledMetric(relativeTo: .body) private var controlHeight: CGFloat = 44
  @ScaledMetric(relativeTo: .body) private var stepperWidth: CGFloat = 28
  @ScaledMetric(relativeTo: .body) private var stepperHeight: CGFloat = 36

  /// Dynamic Type may shrink scaled metrics below their base value at the
  /// smallest text sizes. Keep the artwork scalable, but never let an
  /// individual toolbar control fall below Apple's 44-point tap target.
  private var minimumTapDimension: CGFloat {
    max(44, controlHeight)
  }

  /// Keep the visual chevrons tucked toward the date while their invisible
  /// 44-point button frames continue to extend into the outer toolbar space.
  private let chevronVisualInset: CGFloat = 9

  init(
    selection: Binding<Date>,
    availableDates: [Date],
    display: Display = .selectedDate,
    staticRangeHorizontalPadding: CGFloat = 0
  ) {
    self._selection = selection
    self.availableDates = availableDates
    self.display = display
    self.staticRangeHorizontalPadding = staticRangeHorizontalPadding
  }

  // MARK: - Body and Controls

  var body: some View {
    // The toolbar itself supplies the native glass material. This view
    // only lays out its three controls inside that system-provided shell.
    HStack(spacing: 0) {
      switch display {
      case .selectedDate:
        stepperButton(
          systemImage: "chevron.left",
          targetDate: ((
            // Date values may include different times. Normalize them to calendar
            // days, de-duplicate, and sort before calculating neighbours.
            Array(Set(availableDates.map(calendar.startOfDay(for:))).sorted())).last(where: {
              $0 < (calendar.startOfDay(for: selection))
            }))
        )

        Button {
          showsDatePicker = true
        } label: {
          (Text(
            ((ForecastDateLabel.compact(
              for: (calendar.startOfDay(for: selection)),
              calendar: calendar,
              locale: locale
            )))
          )
          // Match the Saved Places recommendation rows so the shared
          // forecast control reads at the same hierarchy.
          .font(.body.weight(.medium))
          .foregroundStyle((theme.colors.primaryText))
          .lineLimit(1)
          // The wider label fits ordinary localized dates at the standard
          // text style. Longer ranges shrink before truncating.
          .minimumScaleFactor(0.65)
          .allowsTightening(true)
          .frame(minWidth: dateLabelWidth, minHeight: dateLabelHeight))
          .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // The visual date label remains compact, but this independent
        // toolbar button keeps the standard 44-point minimum hit area.
        .frame(
          minWidth: dateLabelWidth,
          minHeight: minimumTapDimension
        )
        .contentShape(Rectangle())
        .popover(isPresented: $showsDatePicker) {
          Group {
            if let firstDate = Array(
              Set(availableDates.map(calendar.startOfDay(for:)))
            ).sorted().first,
              let lastDate = Array(
                Set(availableDates.map(calendar.startOfDay(for:)))
              ).sorted().last
            {
              DatePicker(
                "Forecast Date",
                selection: Binding(
                  get: { calendar.startOfDay(for: selection) },
                  set: { date in
                    guard
                      let nearestDate = Array(
                        Set(availableDates.map(calendar.startOfDay(for:)))
                      ).sorted().min(by: {
                        abs($0.timeIntervalSince(date))
                          < abs($1.timeIntervalSince(date))
                      })
                    else {
                      return
                    }
                    selection = nearestDate
                    showsDatePicker = false
                  }
                ),
                in: firstDate...lastDate,
                displayedComponents: .date
              )
              .datePickerStyle(.graphical)
              .tint(theme.colors.dotSun)
              .padding()
              .frame(minWidth: 320)
              .presentationCompactAdaptation(.popover)
            } else {
              ContentUnavailableView("No Forecast Dates", systemImage: "calendar")
                .padding()
            }
          }
          // On iPhone retain the anchored calendar instead of
          // adapting this short choice into a full-screen sheet.
          .presentationCompactAdaptation(.popover)
        }

        stepperButton(
          systemImage: "chevron.right",
          targetDate: ((
            // Date values may include different times. Normalize them to calendar
            // days, de-duplicate, and sort before calculating neighbours.
            Array(Set(availableDates.map(calendar.startOfDay(for:))).sorted())).first(where: {
              $0 > (calendar.startOfDay(for: selection))
            }))
        )

      case .staticRange:
        (Text(
          (({
            guard case .staticRange(let start, let end) = display else {
              return nil
            }
            return ForecastDateLabel.compactRange(
              from: start,
              through: end,
              calendar: calendar,
              locale: locale
            )
          })()
            ?? (ForecastDateLabel.compact(
              for: (calendar.startOfDay(for: selection)),
              calendar: calendar,
              locale: locale
            )))
        )
        // Match the Saved Places recommendation rows so the shared
        // forecast control reads at the same hierarchy.
        .font(.body.weight(.medium))
        .foregroundStyle((theme.colors.secondaryText))
        .lineLimit(1)
        // The wider label fits ordinary localized dates at the standard
        // text style. Longer ranges shrink before truncating.
        .minimumScaleFactor(0.65)
        .allowsTightening(true)
        .frame(minWidth: dateLabelWidth, minHeight: dateLabelHeight))
        .padding(.horizontal, staticRangeHorizontalPadding)
        .frame(
          minWidth: dateLabelWidth,
          minHeight: minimumTapDimension
        )
      }
    }
    .padding(.horizontal, 2)
    // The native toolbar provides this control's glass container. Adding
    // a second custom glass background here creates a nested capsule.
    .frame(minHeight: minimumTapDimension)
    .fixedSize(horizontal: true, vertical: false)
    .onChange(of: display) {
      if case .staticRange = display {
        showsDatePicker = false
      }
    }
  }

  private func stepperButton(
    systemImage: String,
    targetDate: Date?
  ) -> some View {
    Color.clear
      .frame(width: stepperWidth, height: stepperHeight)
      .overlay {
        Button {
          guard let targetDate else { return }
          withAnimation(
            reduceMotion ? nil : .smooth(duration: 0.2)
          ) {
            selection = targetDate
          }
        } label: {
          Image(systemName: systemImage)
            .font(.caption.weight(.semibold))
            .frame(width: stepperWidth, height: stepperHeight)
            .offset(
              x: systemImage == "chevron.left"
                ? chevronVisualInset
                : -chevronVisualInset
            )
        }
        .buttonStyle(.plain)
        // Keep the visual spacing compact while each
        // chevron's real hit target expands away from the date label.
        .frame(width: minimumTapDimension, height: minimumTapDimension)
        .contentShape(Rectangle())
        .offset(
          x: systemImage == "chevron.left"
            ? -(max(0, (minimumTapDimension - stepperWidth) / 2))
            : (max(0, (minimumTapDimension - stepperWidth) / 2))
        )
        .foregroundStyle(
          targetDate == nil
            ? theme.colors.primaryText.opacity(0.28)
            : theme.colors.primaryText
        )
        .disabled(targetDate == nil)

      }
  }

}
