//
//  SunnyHoursLockScreenWidget.swift
//  WeatherWidgets
//
//  Purpose: Defines and renders the rectangular Lock Screen widget.
//

import SwiftUI
import WidgetKit

// MARK: - Lock-Screen Widget

/// Rectangular Lock Screen widget showing one city's current-day timeline.
/// Lock Screen families use system-controlled rendering, so this configuration
/// shares data/provider behavior but intentionally chooses a transparent canvas.
struct SunnyHoursLockScreenWidget: Widget {
    /// Stable WidgetKit registration kind.
    static let kind = "SunnyHoursLockScreenWidget"

    /// Registers the accessory widget with the shared configuration/provider.
    var body: some WidgetConfiguration {
        // The same intent/provider guarantees a selected city shows consistent
        // forecast data across Home and Lock Screen widget families.
        AppIntentConfiguration(
            kind: Self.kind,
            intent: SunnyHoursLockScreenConfigurationIntent.self,
            provider: SunnyHoursLockScreenProvider()
        ) { entry in
            SunnyHoursLockScreenWidgetView(entry: entry)
                .environment(\.locale, WidgetDataStore.appLocale)
                .modifier(WidgetTextSizePolicyModifier())
                // Let the person's Lock Screen data-access setting redact city
                // and forecast details while the device is locked.
                .privacySensitive()
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName(
            WidgetDataStore.localizedText(for: "Sunny Hours")
        )
        .description(
            WidgetDataStore.localizedText(
                for: "Track sunny daytime hours for a chosen city."
            )
        )
        .supportedFamilies([.accessoryRectangular])
    }
}

/// Height-specific rectangular Lock Screen presentation. The accessory family
/// is much shorter than a Small Home widget, so its information is arranged in
/// one compact row instead of inheriting the taller icon/status/city stack.
private struct SunnyHoursLockScreenWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    @Environment(\.locale) private var locale
    /// Timeline entry supplied by the shared provider.
    let entry: SunnyHoursLockScreenEntry

    /// Keeps city and condition/status visible without clipping at the system's
    /// fixed accessory-rectangular height.
    var body: some View {
        if let city = entry.city {
            let issue = city.widgetCurrentIssue
            let status = issue == nil
                ? widgetSunStatusText(for: city, at: entry.date, locale: locale)
                : nil

            HStack(alignment: .center, spacing: 8) {
                if issue == nil,
                   let weather = widgetWeatherPresentation(
                       for: city,
                       at: entry.date
                   ) {
                    WidgetConditionIcon(weather: weather, size: 24)
                } else {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(renderedSecondary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(city.cityName)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(status ?? widgetLocalizedString("Weather unavailable."))
                        .font(.caption2)
                        .foregroundStyle(renderedSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .leading
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

#if DEBUG
#Preview("Sun Status - Lock Screen", as: .accessoryRectangular) {
    SunnyHoursLockScreenWidget()
} timeline: {
    SunnyHoursLockScreenEntry.preview
}
#endif
