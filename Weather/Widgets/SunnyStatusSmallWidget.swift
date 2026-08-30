//
//  SunnyStatusSmallWidget.swift
//  WeatherWidgets
//
//  Purpose: Renders the Small Home Screen current sun-status card.
//

import Foundation
import SwiftUI
import WidgetKit

// MARK: - Small Sun-Status Presentation

/// Compact status presentation for the Small Home Screen widget.
struct SunnyStatusWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    @Environment(\.locale) private var locale
    let entry: SunnyHoursLockScreenEntry

    var body: some View {
        if let city = entry.city {
            let issue = city.widgetCurrentIssue
            let status = issue == nil
                ? widgetSunStatusText(for: city, at: entry.date, locale: locale)
                : nil

            VStack(alignment: .leading, spacing: 8) {
                if issue == nil,
                   let weather = widgetWeatherPresentation(
                       for: city,
                       at: entry.date
                   ) {
                    WidgetConditionIcon(weather: weather, size: 34)
                } else {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(renderedSecondary)
                }
                Text(status ?? widgetLocalizedString("Weather unavailable."))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(renderedSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                Text(city.cityName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .padding(.bottom, 12)
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .foregroundStyle(renderedPrimary)
            .widgetURL(widgetPlaceURL(for: city, issue: issue))
        } else {
            WidgetDataUnavailablePlaceholder()
        }
    }

    private var widgetPalette: AppPalette.Values {
        AppPalette.values(for: colorScheme, contrast: colorSchemeContrast)
    }

    private var usesSystemColors: Bool {
        widgetRenderingMode != .fullColor
    }

    private var renderedPrimary: Color {
        usesSystemColors ? .primary : widgetPalette.titleText
    }

    private var renderedSecondary: Color {
        usesSystemColors ? .secondary : widgetPalette.secondaryText
    }
}

// MARK: - Compact Shared Condition Helpers

/// Reusable weather symbol for compact widgets. Home Screen widgets retain the
/// app's semantic condition tint; WidgetKit-controlled Lock Screen rendering
/// remains system monochrome or tinted as required.
struct WidgetConditionIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    let weather: WidgetWeatherPresentation
    let size: CGFloat

    var body: some View {
        Image(systemName: weather.symbolName)
            .font(.system(size: size, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(iconColor)
    }

    private var iconColor: Color {
        guard widgetRenderingMode == .fullColor else { return .primary }
        return widgetConditionIconColor(
            for: weather,
            colors: AppPalette.values(
                for: colorScheme,
                contrast: colorSchemeContrast
            )
        )
    }
}

/// Chooses the hourly condition that covers a timeline entry. WidgetKit can
/// render these entries long after the extension was suspended, so compact
/// icons must advance from persisted hourly data rather than freezing the
/// fetch-time current observation.
func widgetWeatherPresentation(
    for city: WidgetDataCity,
    at date: Date
) -> WidgetWeatherPresentation? {
    if let currentWeather = city.currentWeather,
       let fetchedAt = city.weatherFetchedAt,
       let timeZone = city.widgetTimeZone {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        if calendar.isDate(date, equalTo: fetchedAt, toGranularity: .hour) {
            return currentWeather
        }
    }
    if let weather = city.hourlyWeatherConditions?.first(where: {
        $0.date <= date && date < $0.date.addingTimeInterval(60 * 60)
    })?.weather {
        return weather
    }
    return city.currentWeather
}

/// Uses the same current-day sun-status wording as the Detail hero. Widgets
/// only display today, so the non-today "Sunny for … hours" branch is not
/// needed here.
func widgetSunStatusText(
    for city: WidgetDataCity,
    at referenceDate: Date,
    locale: Locale
) -> String? {
    guard city.widgetCurrentIssue == nil,
          let timeZone = city.widgetTimeZone else {
        return nil
    }

    guard let conditions = city.hourlyConditions else { return nil }
    var calendar = Calendar.current
    calendar.timeZone = timeZone
    let representedConditions = conditions
        .filter { calendar.isDate($0.date, inSameDayAs: referenceDate) }
        .sorted { $0.date < $1.date }
    let sunnyConditions = representedConditions.filter {
        $0.weather?.condition.countsAsSunnyHour == true
    }

    // Solar events refine live copy at their exact instant. HourWeather's
    // daylight flag remains the sole source for chart totals and colors.
    if let sunset = city.sunset, referenceDate >= sunset {
        return sunnyConditions.isEmpty
            ? widgetLocalizedString("No Sun Today")
            : widgetLocalizedString("No More Sun Today")
    }
    if let sunrise = city.sunrise, sunrise > referenceDate,
       sunnyConditions.contains(where: {
           $0.date <= sunrise
               && sunrise < $0.date.addingTimeInterval(60 * 60)
       }) {
        return String(
            format: widgetLocalizedString("Sun Out in %@"),
            locale: locale,
            widgetCountdownText(
                to: sunrise,
                from: referenceDate,
                locale: locale
            )
        )
    }

    // An empty daylight array is valid during polar night. The snapshot still
    // has a current condition and daily forecast, so this means zero daylight
    // rather than a failed WeatherKit request.
    guard !sunnyConditions.isEmpty else {
        return widgetLocalizedString("No Sun Today")
    }

    if let current = representedConditions.last(where: {
        $0.date <= referenceDate
            && referenceDate < $0.date.addingTimeInterval(60 * 60)
    }), current.weather?.condition.countsAsSunnyHour == true {
        return widgetLocalizedString("Sun Out Now")
    }
    if let next = sunnyConditions.first(where: { $0.date > referenceDate }) {
        let nextSunnyInstant: Date
        if let sunrise = city.sunrise,
           sunrise > next.date,
           sunrise < next.date.addingTimeInterval(60 * 60) {
            nextSunnyInstant = sunrise
        } else {
            nextSunnyInstant = next.date
        }
        return String(
            format: widgetLocalizedString("Sun Out in %@"),
            locale: locale,
            widgetCountdownText(
                to: nextSunnyInstant,
                from: referenceDate,
                locale: locale
            )
        )
    }
    return widgetLocalizedString("No More Sun Today")
}

/// Formats the Detail-compatible duration without depending on the app process.
private func widgetCountdownText(
    to date: Date,
    from referenceDate: Date,
    locale: Locale
) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute]
    formatter.unitsStyle = .full
    formatter.maximumUnitCount = 2
    formatter.zeroFormattingBehavior = .dropAll
    var calendar = Calendar.autoupdatingCurrent
    calendar.locale = locale
    formatter.calendar = calendar
    return formatter.string(
        from: max(0, date.timeIntervalSince(referenceDate))
    ) ?? widgetLocalizedString("less than one minute")
}

/// Returns the exact semantic Map-dot color for a widget condition icon.
///
/// Full-color widgets use one color for every layer of a condition symbol, just
/// like the main app. WidgetKit's tinted and monochrome modes retain their
/// platform-controlled rendering outside this helper.
private func widgetConditionIconColor(
    for weather: WidgetWeatherPresentation,
    colors: AppPalette.Values
) -> Color {
    if weather.symbolName.localizedCaseInsensitiveContains("moon") {
        return colors.moonIcon
    }
    switch weather.condition.iconTone {
    case .clear:
        return colors.dotSun
    case .partlySunny:
        return colors.dotPartlyCloudy
    case .cloudy:
        return colors.dotCloudy
    case .rain:
        return colors.dotRain
    case .drizzle:
        return colors.dotDrizzle
    }
}

#if DEBUG
#Preview("Sun Status - Small", as: .systemSmall) {
    BestSunnyPlacesWidget()
} timeline: {
    SunnyHoursLockScreenEntry.preview
}
#endif
