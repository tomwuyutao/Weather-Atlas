//
//  SunnyWindowLargeWidget.swift
//  WeatherWidgets
//
//  Purpose: Renders the Large Home Screen multi-day sunny-window chart.
//

import SwiftUI
import WidgetKit

// MARK: - Large Sunny-Window Presentation

/// Header, ten-day chart, and missing-data state for the large widget.
struct SunnyWindowLargeWidgetView: View {
  /// Locale published by the main app.
  @Environment(\.locale) private var locale
  /// Widget appearance used by the shared palette.
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast
  @Environment(\.widgetRenderingMode) private var widgetRenderingMode
  /// Timeline entry supplied by the shared provider.
  let entry: SunnyHoursLockScreenEntry

  /// Builds available chart content or a visible unavailable placeholder.
  var body: some View {
    if let city = entry.city {
      let windowIssue = city.widgetSunnyWindowIssue
      let summaryText = widgetSunnyHoursTotalText(for: city, locale: locale)
      VStack(alignment: .leading, spacing: 9) {
        SunnyHoursHeader(
          cityName: city.cityName,
          summaryText: summaryText,
          font: .headline.weight(.semibold)
        )

        // Validation is intentionally checked before layout. A short
        // forecast is valid and renders all of its available rows; an
        // unavailable state is reserved for missing forecast structure
        // or an unsafe city identity.
        if windowIssue != nil {
          WidgetDataUnavailablePlaceholder()
        } else if let timeZone = city.timeZoneIdentifier.flatMap(
          TimeZone.init(identifier:)
        ),
          let chartBounds = { () -> SunnyHoursChartBounds? in
            let bounds = Array(
              (city.sunnyWindowDays ?? []).prefix(10)
            )
            .map { day -> SunnyHoursChartBounds in
              let hours = (day.hourlyConditions ?? [])
                .filter { $0.weather != nil }
                .map(\.hour)
              guard let firstHour = hours.min(),
                let lastHour = hours.max()
              else {
                return .fullDay
              }
              return SunnyHoursChartBounds(
                startHour: firstHour,
                endHour: lastHour + 1
              )
            }
            guard let first = bounds.map(\.startHour).min(),
              let last = bounds.map(\.endHour).max()
            else {
              return nil
            }
            return SunnyHoursChartBounds(
              startHour: first,
              endHour: last
            )
          }()
        {
          SunnyWindowLargeChart(
            days: Array((city.sunnyWindowDays ?? []).prefix(10)),
            currentDate: entry.date,
            locale: locale,
            timeZone: timeZone,
            chartBounds: chartBounds
          )
          .padding(.top, 7)
          .frame(maxHeight: .infinity, alignment: .top)
        }
      }
      .padding(.horizontal, 6)
      .padding(.top, 4)
      .padding(.bottom, 2)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .foregroundStyle(
        widgetRenderingMode == .fullColor
          ? AppPalette.values(
            for: colorScheme,
            contrast: colorSchemeContrast
          ).titleText
          : Color.primary
      )
      // `widgetURL` makes the entire noninteractive widget a deep link;
      // WidgetKit does not support arbitrary in-widget navigation here.
      .widgetURL(widgetPlaceURL(for: city, issue: windowIssue))
    } else {
      WidgetDataUnavailablePlaceholder()
    }
  }
}

/// Height-adaptive ten-day widget timeline using real daylight bounds.
/// The chart is custom SwiftUI layout rather than Swift Charts because every
/// row needs the same solar-time x-axis while WidgetKit supplies tight sizes.
private struct SunnyWindowLargeChart: View {
  /// Available current/future day rows extracted from WeatherKit.
  let days: [WidgetSunnyWindowDay]
  /// Timeline entry date used for the current-time marker.
  let currentDate: Date
  /// Main-app locale used by date labels.
  let locale: Locale
  /// Selected city timezone.
  let timeZone: TimeZone
  /// Merged real daylight domain across visible rows.
  let chartBounds: SunnyHoursChartBounds
  // MARK: - Rendering Environment

  /// Contrast preference strengthening chart guides and tracks.
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast
  /// Rendering mode used to replace colors in tinted/vibrant widgets.
  @Environment(\.widgetRenderingMode) private var widgetRenderingMode
  /// Widget appearance selecting the shared palette.
  @Environment(\.colorScheme) private var colorScheme

  // MARK: - Fixed Layout Constants

  /// Width reserved for compact day labels.
  private let labelWidth: CGFloat = 52
  /// Height reserved for hour-axis labels.
  private let axisHeight: CGFloat = 18
  /// Visible track and segment thickness.
  private let capsuleHeight: CGFloat = 10

  // MARK: - Derived Chart Inputs

  /// Rows already capped at the large widget's ten-row presentation limit.
  private var visibleDays: [WidgetSunnyWindowDay] {
    days
  }

  // MARK: - Adaptive Chart Layout

  /// Divides actual WidgetKit height among rows so the forecast fills the widget.
  var body: some View {
    // GeometryReader exposes the size proposed by WidgetKit at render time.
    // It is appropriate here because row allocation genuinely depends on
    // the container's final height rather than a fixed device dimension.
    GeometryReader { geometry in
      let timelineWidth = max(geometry.size.width - labelWidth, 1)
      // Reserve two points between the axis and the first forecast row.
      let availableRowsHeight = max(
        geometry.size.height - axisHeight - 2,
        0
      )
      // WidgetKit can give the same family different usable heights on
      // iPhone and iPad. Divide the actual proposal exactly so every
      // available point is used by the forecast rows.
      let rowHeight =
        visibleDays.isEmpty
        ? 0
        : availableRowsHeight / CGFloat(visibleDays.count)
      let rowsHeight = CGFloat(visibleDays.count) * rowHeight

      VStack(spacing: 2) {
        (HStack(spacing: 0) {
          Color.clear.frame(width: labelWidth)
          ZStack(alignment: .leading) {
            // Hours are unique integers, so `\.self` is a stable identity
            // for SwiftUI's lightweight axis-label ForEach.
            ForEach((chartBounds.axisHours(maximumTickCount: 8)), id: \.self) { hour in
              Text(
                hour == 24
                  ? "24"
                  : String(format: "%02d", ((hour % 24) + 24) % 24)
              )
              .font(.caption2.weight(.semibold))
              .foregroundStyle(
                ((widgetRenderingMode != .fullColor)
                  ? .secondary
                  : (AppPalette.values(for: colorScheme, contrast: colorSchemeContrast))
                    .secondaryText)
              )
              .position(
                x: chartBounds.xPosition(for: Double(hour), width: (timelineWidth)),
                y: axisHeight / 2
              )
            }
          }
          .frame(width: (timelineWidth), height: axisHeight)
        })
        // Overlay independent layers on the same chart coordinate space:
        // content capsules first, then noninteractive guides and marker.
        ZStack {
          rowsView(
            visibleDays,
            timelineWidth: timelineWidth,
            rowHeight: rowHeight
          )
          gridLines(
            rowCount: visibleDays.count,
            timelineWidth: timelineWidth,
            rowHeight: rowHeight
          )
          // Decorative overlays must never absorb the widget tap
          // used by the widgetURL deep link.
          .allowsHitTesting(false)
          currentTimeMarker(
            rowCount: visibleDays.count,
            timelineWidth: timelineWidth,
            rowHeight: rowHeight
          )
          .allowsHitTesting(false)
        }
        .frame(height: rowsHeight)
        .clipped()
      }
    }
  }

  // MARK: - Chart Layers

  /// Positions hour labels over the shared timeline width.

  /// Builds date labels and contiguous hourly-weather capsules.
  private func rowsView(
    _ visibleDays: [WidgetSunnyWindowDay],
    timelineWidth: CGFloat,
    rowHeight: CGFloat
  ) -> some View {
    VStack(spacing: 0) {
      ForEach(visibleDays) { day in
        // `let` declarations inside a ViewBuilder are recomputed from
        // immutable entry data on each render; they are not stored state.
        let isCurrentDay =
          ({ (date: Date) -> Bool in

            // Use the city zone rather than device zone for both dates. This keeps
            // the marker on the row the city itself calls "today".
            var calendar = Calendar.current
            calendar.timeZone = timeZone
            return calendar.isDate(date, inSameDayAs: currentDate)
          })(day.date)
        HStack(spacing: 0) {
          // Format Today or a compact localized month/day label.
          Text(
            {
              if isCurrentDay {
                return widgetLocalizedString("Today")
              }
              // Format dates in the selected city's timezone. A Date
              // is absolute, so device-local formatting could label a
              // forecast row as the previous/next calendar day.
              var format = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(locale)
              format.timeZone = timeZone
              return day.date.formatted(format)
            }()
          )
          .font(.caption2.weight(isCurrentDay ? .bold : .medium))
          .foregroundStyle(
            isCurrentDay
              ? ((widgetRenderingMode != .fullColor)
                ? .primary
                : (AppPalette.values(for: colorScheme, contrast: colorSchemeContrast)).titleText)
              : ((widgetRenderingMode != .fullColor)
                ? .secondary
                : (AppPalette.values(for: colorScheme, contrast: colorSchemeContrast)).secondaryText)
          )
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .frame(width: labelWidth, alignment: .leading)

          SunnyHoursContinuousCapsuleTrack(
            hours: (day.hourlyConditions ?? [])
              .filter { $0.weather != nil }
              .compactMap {
                guard let weather = $0.weather else { return nil }
                return SunnyHoursChartHour(
                  date: $0.date,
                  hour: $0.hour,
                  condition: weather.condition
                )
              },
            bounds: chartBounds,
            colors: (SunnyHoursChartColors(
              primary: ((widgetRenderingMode != .fullColor)
                ? .primary
                : (AppPalette.values(for: colorScheme, contrast: colorSchemeContrast)).titleText),
              secondary: ((widgetRenderingMode != .fullColor)
                ? .secondary
                : (AppPalette.values(for: colorScheme, contrast: colorSchemeContrast)).secondaryText),
              sun: segmentColor(for: .clear),
              partlySunny: segmentColor(for: .partlySunny),
              rain: segmentColor(for: .rain),
              drizzle: segmentColor(for: .drizzle),
              noSun: segmentColor(for: .cloudy)
            )),
            height: capsuleHeight
          )
          // Give each shared capsule track a stable 16-point lane.
          .frame(width: timelineWidth, height: 16)
        }
        .frame(height: rowHeight)
      }
    }
  }

  /// Draws vertical hour guides across the visible row region.
  private func gridLines(
    rowCount: Int,
    timelineWidth: CGFloat,
    rowHeight: CGFloat
  ) -> some View {
    let rowsHeight = CGFloat(rowCount) * rowHeight
    let verticalInset = (16 - capsuleHeight) / 2
    let gridHeight = max(rowsHeight - verticalInset * 2, 0)

    return HStack(spacing: 0) {
      Color.clear.frame(width: labelWidth)
      // Build one vector path instead of a view per guide. Path coordinates
      // are local to this timeline rectangle and therefore share the axis.
      Path { path in
        for hour in (chartBounds.axisHours(maximumTickCount: 8)) {
          let x = chartBounds.xPosition(for: Double(hour), width: timelineWidth)
          path.move(to: CGPoint(x: x, y: verticalInset))
          path.addLine(to: CGPoint(x: x, y: verticalInset + gridHeight))
        }
      }
      // Keep vertical guides subordinate in every rendering mode.
      .stroke(
        ((widgetRenderingMode != .fullColor)
          ? .secondary
          : (AppPalette.values(for: colorScheme, contrast: colorSchemeContrast)).secondaryText)
          .opacity(0.08),
        lineWidth: 1
      )
      .frame(width: timelineWidth, height: rowsHeight)
    }
    .frame(height: rowsHeight)
  }

  // `@ViewBuilder` lets this helper intentionally emit no view when today is
  // absent. Off-window times clamp to the chart's leading or trailing edge.
  @ViewBuilder
  /// Draws selected-city local time on today's row, clamped to daylight.
  private func currentTimeMarker(
    rowCount: Int,
    timelineWidth: CGFloat,
    rowHeight: CGFloat
  ) -> some View {
    let rowsHeight = CGFloat(rowCount) * rowHeight
    if let todayRowIndex = visibleDays.firstIndex(where: {
      ({ (date: Date) -> Bool in

        // Use the city zone rather than device zone for both dates. This keeps
        // the marker on the row the city itself calls "today".
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar.isDate(date, inSameDayAs: currentDate)
      })($0.date)
    }),
      let markerX = { () -> CGFloat? in
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
          [.hour, .minute, .second],
          from: currentDate
        )
        guard let hour = components.hour,
          let minute = components.minute,
          let second = components.second
        else {
          return nil
        }
        let fractionalHour =
          Double(hour)
          + Double(minute) / 60
          + Double(second) / 3_600
        return chartBounds.xPosition(
          for: fractionalHour,
          width: timelineWidth
        )
      }()
    {
      // Offset the marker into today's row while keeping its x coordinate
      // relative to the day-label-free timeline area.
      HStack(spacing: 0) {
        Color.clear.frame(width: labelWidth)
        ZStack(alignment: .topLeading) {
          ZStack(alignment: .leading) {
            Rectangle()
              .fill(
                ((widgetRenderingMode != .fullColor)
                  ? .primary
                  : (AppPalette.values(for: colorScheme, contrast: colorSchemeContrast)).titleText)
                  .opacity(0.82)
              )
              .frame(width: 2, height: capsuleHeight)
              // Keep the complete two-point marker visible when
              // an off-window time clamps to either chart edge.
              .offset(
                x: min(
                  max(markerX - 1, 0),
                  max(timelineWidth - 2, 0)
                )
              )
          }
          .frame(
            width: timelineWidth,
            height: capsuleHeight,
            alignment: .leading
          )
          .clipShape(Capsule())
          .offset(
            y: CGFloat(todayRowIndex) * rowHeight
              + (rowHeight - capsuleHeight) / 2
          )
        }
        .frame(width: timelineWidth, height: rowsHeight, alignment: .topLeading)
      }
      .frame(height: rowsHeight)
    }
  }

  // MARK: - Rendering Colors and Local Time

  /// Returns the shared timeline color for one API-derived tint family.
  /// This changes only the track color; current-condition symbols always use
  /// the original WeatherKit `symbolName`.
  private func segmentColor(for tone: WeatherIconTone) -> Color {
    if widgetRenderingMode != .fullColor {
      return monochromeColor(for: tone)
    }
    if colorSchemeContrast == .increased {
      let colors = AppPalette.increasedContrastValues(
        for: colorScheme == .dark ? AppPalette.dark : AppPalette.light,
        colorScheme: colorScheme
      )
      return chartColor(for: tone, colors: colors)
    }
    return chartColor(
      for: tone, colors: (AppPalette.values(for: colorScheme, contrast: colorSchemeContrast)))
  }

  /// Adapter-only colour policy for the shared app/widget capsule renderer.

  /// Retains clear, precipitation, and neutral no-sun weights when WidgetKit
  /// enforces a monochrome or tinted rendering mode.
  private func monochromeColor(for tone: WeatherIconTone) -> Color {
    switch tone {
    case .clear:
      .primary.opacity(1)
    case .partlySunny:
      .primary.opacity(0.92)
    case .rain:
      .primary.opacity(0.82)
    case .drizzle:
      .primary.opacity(0.38)
    case .cloudy:
      .primary.opacity(0.14)
    }
  }

  /// Maps only tint families to the timeline palette.
  private func chartColor(
    for tone: WeatherIconTone,
    colors: AppPalette.Values
  ) -> Color {
    switch tone {
    case .clear:
      colors.dotSun
    case .partlySunny:
      colors.dotPartlyCloudy
    case .rain:
      colors.dotRain
    case .drizzle:
      colors.dotDrizzle
    case .cloudy:
      switch (colorScheme, colorSchemeContrast) {
      case (.dark, .increased):
        ThemeColors.increasedContrastDark.noSunTimelineFill
      case (.dark, _):
        ThemeColors.dark.noSunTimelineFill
      case (_, .increased):
        ThemeColors.increasedContrastLight.noSunTimelineFill
      default:
        ThemeColors.light.noSunTimelineFill
      }
    }
  }

}

#if DEBUG
  #Preview("Sunny Hours — Large", as: .systemLarge) {
    BestSunnyPlacesWidget()
  } timeline: {
    SunnyHoursLockScreenEntry.preview
  }
#endif
