//
//  SunnyHoursMediumWidget.swift
//  WeatherWidgets
//
//  Purpose: Renders the Medium Home Screen daily sunny-hours timeline.
//

import Foundation
import SwiftUI
import WeatherKit
import WidgetKit

// MARK: - Medium Daily Presentation

/// Medium Home Screen widget content for one city's current local day.
/// The medium view reuses the same entry/provider as the large widget but draws
/// the compact single-day timeline instead of independently fetching weather.
struct SunnyHoursHomeWidgetView: View {
    /// Main-app locale used by the sunny-window summary.
    @Environment(\.locale) private var locale
    /// Widget appearance selecting the shared palette.
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    /// Timeline entry supplied by the shared provider.
    let entry: SunnyHoursLockScreenEntry

    /// Builds configured city content or remains empty before catalog publication.
    var body: some View {
        if let city = entry.city {
            // The city payload is validated within content, while the outer view
            // owns the shared full-widget deep-link destination.
            content(city)
                .widgetURL(widgetPlaceURL(for: city, issue: city.widgetCurrentIssue))
        } else {
            WidgetDataUnavailablePlaceholder()
        }
    }

    /// Builds header, current-day timeline, or missing-data state.
    private func content(_ city: WidgetDataCity) -> some View {
        let issue = city.widgetCurrentIssue
        let summaryText = widgetSunnyHoursTotalText(for: city, locale: locale)
        return VStack(alignment: .leading, spacing: 9) {
            SunnyHoursHeader(
                cityName: city.cityName,
                summaryText: summaryText,
                font: .headline.weight(.semibold)
            )

            if issue != nil {
                WidgetDataUnavailablePlaceholder()
            } else {
                WidgetDailySunnyHoursTimeline(
                    city: city,
                    currentDate: entry.date
                )
                    .padding(.top, 12)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 7)
        .padding(.top, 12)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(
            widgetRenderingMode == .fullColor
                ? AppPalette.values(
                    for: colorScheme,
                    contrast: colorSchemeContrast
                ).titleText
                : Color.primary
        )
    }
}

/// Widget-only adapter for the current-day chart. The actual capsule rendering
/// is shared with the app's Daily Sunny Hours card.
private struct WidgetDailySunnyHoursTimeline: View {
    // MARK: - Rendering Environment and Inputs

    /// Contrast preference selecting the app's higher-contrast colors.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// Rendering mode controlling system monochrome/tinted colors.
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    /// Widget appearance selecting the shared palette.
    @Environment(\.colorScheme) private var colorScheme
    /// Configured city with current-day chart data.
    let city: WidgetDataCity
    /// Entry time used by the city-local current-time marker.
    let currentDate: Date

    // MARK: - Shared Timeline

    var body: some View {
        SunnyHoursDiscreteCapsuleTimeline(
            hours: chartHours,
            bounds: city.widgetCurrentDaylightBounds,
            currentDate: currentDate,
            showsCurrentTimeMarker: true,
            configuration: .appAndHome,
            colors: sharedChartColors
        )
    }

    // MARK: - Timeline Rendering

    /// Resolves the widget's colour policy before passing it to the shared
    /// renderer. WidgetKit can enforce monochrome or accented colours.
    private func timelineColor(for tone: WeatherIconTone) -> Color {
        if usesSystemColors {
            return monochromeColor(for: tone)
        }

        if colorSchemeContrast == .increased {
            let colors = AppPalette.increasedContrastValues(for: colorScheme)
            return chartColor(for: tone, colors: colors)
        }

        return chartColor(for: tone, colors: palette)
    }

    private var sharedChartColors: SunnyHoursChartColors {
        SunnyHoursChartColors(
            primary: renderedPrimary,
            secondary: renderedSecondary,
            sun: timelineColor(for: .clear),
            partlySunny: timelineColor(for: .partlySunny),
            rain: timelineColor(for: .rain),
            drizzle: timelineColor(for: .drizzle),
            noSun: timelineColor(for: .cloudy)
        )
    }

    /// Adapts exact persisted API conditions to the presentation-only shared
    /// track. No missing source value is replaced by a fabricated condition.
    private var chartHours: [SunnyHoursChartHour] {
        let daylightHours = city.hourlyConditions ?? []
        if !daylightHours.isEmpty {
            return daylightHours.compactMap { source in
                guard let weather = source.weather else { return nil }
                return SunnyHoursChartHour(
                    date: source.date,
                    hour: source.hour,
                    condition: weather.condition
                )
            }
        }

        // A fully covered polar-night response legitimately contains no
        // daylight records. Draw its available hours as neutral no-sun cells
        // instead of leaving the medium widget's timeline blank.
        let noSun = AppWeatherCondition(
            weatherKit: WeatherKit.WeatherCondition.cloudy
        )
        return (city.hourlyWeatherConditions ?? []).map { source in
            SunnyHoursChartHour(
                date: source.date,
                hour: source.hour,
                condition: noSun
            )
        }
    }

    /// Neutral no-sun color shared by non-sunny chart slots.
    private var noSunColor: Color {
        if usesSystemColors {
            return .primary.opacity(0.14)
        }
        return widgetNoSunTimelineColor(
            colorScheme: colorScheme,
            contrast: colorSchemeContrast
        )
    }

    /// WidgetKit may enforce monochrome/tinted rendering, where custom colors
    /// are unavailable. Preserve condition differences with distinct weights.
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
            noSunColor
        }
    }

    /// Uses the widget's full-color timeline mapping: clear, rain, drizzle,
    /// and the neutral no-sun treatment.
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
            widgetNoSunTimelineColor(
                colorScheme: colorScheme,
                contrast: colorSchemeContrast
            )
        }
    }

    /// Shared primitive palette for the widget appearance.
    private var palette: AppPalette.Values {
        AppPalette.values(for: colorScheme, contrast: colorSchemeContrast)
    }

    /// Whether WidgetKit requires semantic system foregrounds.
    private var usesSystemColors: Bool {
        widgetRenderingMode != .fullColor
    }

    /// Effective primary foreground.
    private var renderedPrimary: Color {
        usesSystemColors ? .primary : palette.titleText
    }

    /// Effective secondary foreground.
    private var renderedSecondary: Color {
        usesSystemColors ? .secondary : palette.secondaryText
    }
}

// MARK: - Shared Home-Screen Chart Presentation

/// Shared city-name and sunny-hours summary used by Home Screen widgets.
struct SunnyHoursHeader: View {
    /// Widget appearance selecting the summary-text palette.
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// Rendering mode determining full-color versus monochrome symbols.
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    /// Localized configured city name.
    let cityName: String
    /// Optional current-day total. Missing-data states leave this slot empty.
    let summaryText: String?
    /// Family-specific header font.
    let font: Font
    /// Builds the city title and its compact current-day total.
    var body: some View {
        HStack(spacing: 6) {
            Text(cityName)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 6)
            if let summaryText {
                Text(summaryText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        widgetRenderingMode == .fullColor
                            ? widgetPalette.secondaryText
                            : Color.secondary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .font(font)
    }

    private var widgetPalette: AppPalette.Values {
        AppPalette.values(for: colorScheme, contrast: colorSchemeContrast)
    }
}

/// Formats the full current-day favorable total for widget headers.
func widgetSunnyHoursTotalText(
    for city: WidgetDataCity,
    locale: Locale
) -> String? {
    guard city.widgetCurrentIssue == nil else { return nil }
    // Count source forecast records rather than distinct clock labels. A local
    // hour repeats when daylight saving time ends, and both real hours belong
    // in the day's total.
    let favorableHourCount = (city.hourlyConditions ?? []).count { hour in
        hour.weather?.condition.countsAsSunnyHour == true
    }
    guard favorableHourCount > 0 else {
        return widgetLocalizedString("No Sun")
    }
    return SunnyHoursFormatting.hourCountLabel(
        Double(favorableHourCount),
        locale: locale
    )
}

/// Uses the same untinted cloudy/no-sun fill as the app's daily and ten-day
/// timelines. Increase Contrast changes only this color, preserving the normal
/// gray recipe and darkening it by the app's deliberately small amount.
func widgetNoSunTimelineColor(
    colorScheme: ColorScheme,
    contrast: ColorSchemeContrast
) -> Color {
    switch (colorScheme, contrast) {
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

#if DEBUG
#Preview("Sunny Hours (Daily) - Medium", as: .systemMedium) {
    BestSunnyPlacesWidget()
} timeline: {
    SunnyHoursLockScreenEntry.preview
}
#endif
