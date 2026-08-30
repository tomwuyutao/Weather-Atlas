//
//  SunnyHoursTimeline.swift
//  Weather
//
//  Purpose: Defines the shared single-day sunny-hour timeline used in current
//  and saved-location reports.
//

import SwiftUI

/// One quiet, centered footer style for local-time and timezone context.
/// Screens supply their own factual sentence; this view keeps its presentation
/// identical across Your Location, detail, and Saved Places.
struct WeatherTimeZoneFootnote: View {
    let text: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(theme.colors.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }
}

// MARK: - Daily Sunny-Hours Timeline

/// Shared daily chart UI for both location reports. Your Location supplies
/// location-recovery actions, while a saved-place Detail supplies weather only.
struct SunnyHoursTimeline: View {
    // MARK: - Inputs

    let weather: CityWeather?
    let selectedDate: Date
    private let locationStatus: LocationProviderStatus?
    private let isLoading: Bool
    private let unavailableMessage: String?
    private let requestLocation: (() -> Void)?
    private let openSettings: (() -> Void)?
    private let retry: (() -> Void)?

    @Environment(\.appTheme) private var theme
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var horizontalTimelinePadding: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var verticalTimelinePadding: CGFloat = 14

    // MARK: - Initialization and Forecast Selection

    /// Your Location includes recovery actions because its forecast depends on
    /// Core Location authorization and a fresh physical coordinate.
    init(
        weather: CityWeather?,
        selectedDate: Date,
        locationStatus: LocationProviderStatus,
        isLoading: Bool,
        requestLocation: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        retry: @escaping () -> Void
    ) {
        self.weather = weather
        self.selectedDate = selectedDate
        self.locationStatus = locationStatus
        self.isLoading = isLoading
        unavailableMessage = nil
        self.requestLocation = requestLocation
        self.openSettings = openSettings
        self.retry = retry
    }

    /// Saved and discovered place reports use this initializer to keep the
    /// card in the report while their forecast is loading or unavailable.
    /// Device-location permission recovery remains exclusive to the
    /// current-location initializer above.
    init(
        weather: CityWeather?,
        selectedDate: Date,
        isLoading: Bool,
        unavailableMessage: String?,
        retry: (() -> Void)?
    ) {
        self.weather = weather
        self.selectedDate = selectedDate
        locationStatus = nil
        self.isLoading = isLoading
        self.unavailableMessage = unavailableMessage
        requestLocation = nil
        openSettings = nil
        self.retry = retry
    }

    private var selectedForecast: DailyForecast? {
        // Match by the shared calendar day rather than array position. The
        // current location's local time zone can differ from the device's.
        weather?.forecastIfAvailable(
            on: selectedDate,
            selectionCalendar: calendar
        )
    }

    // MARK: - Presentation and Availability States

    var body: some View {
        cardContent
            .padding(.horizontal, horizontalTimelinePadding)
            .padding(.vertical, verticalTimelinePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        // The capsules intentionally sit directly on the report background.
        // Availability remains in this space without adding a second card.
    }

    @ViewBuilder
    private var cardContent: some View {
        // The forecast's available daylight rows are enough to render a
        // timeline; an empty result is an ordinary zero-sun day.
        if let weather,
           let forecast = selectedForecast {
            let data = SunnyHoursCalculation.sunnyHoursData(
                for: forecast,
                timeZone: weather.timeZone
            )
            loadedTimeline(weather: weather, data: data)
        } else if isLoading || locationStatus?.isActivelyLocating == true {
            HStack(spacing: WeatherCardLayout.headerSpacing) {
                ProgressView()
                    .frame(
                        width: WeatherCardLayout.leadingIconWidth,
                        alignment: .leading
                    )

                Text(
                    locationStatus == nil
                        ? "Loading forecast…"
                        : "Loading weather at current location…"
                )
                    .font(.callout)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: WeatherCardFallbackLayout.dailyTimelineContentHeight,
                alignment: .leading
            )

        } else if locationStatus != nil {
            locationUnavailableContent
        } else {
            genericUnavailableContent
        }
    }

    // MARK: - Unavailable-State Copy

    private var resolvedUnavailableMessage: String {
        let message = unavailableMessage?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let message, !message.isEmpty else {
            return localizedString(
                "Daily sunny hours are unavailable for the selected date.",
                locale: locale
            )
        }
        return message
    }

    private var genericUnavailableContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(resolvedUnavailableMessage)
                .font(.callout)
                .foregroundStyle(theme.colors.secondaryText)

            if let retry {
                Button("Try Again", systemImage: "arrow.clockwise") {
                    retry()
                }
                .weatherGlassActionStyle()
            }
        }
            .frame(
                maxWidth: .infinity,
                minHeight: WeatherCardFallbackLayout.dailyTimelineContentHeight,
                alignment: .leading
            )
    }

    // MARK: - Loaded Timeline

    private func loadedTimeline(
        weather: CityWeather,
        data: SunnyHoursCalculation.SunnyHoursData
    ) -> some View {
        return DailySunnyHoursTrack(
            data: data,
            selectedDate: selectedDate,
            timeZone: weather.timeZone
        )
    }

    // MARK: - Location Recovery

    @ViewBuilder
    private var locationUnavailableContent: some View {
        // LocationProviderStatus distinguishes permission problems from a
        // transient weather request, allowing the action to match the cause.
        if let locationStatus,
           let requestLocation,
           let openSettings,
           let retry {
            switch locationStatus {
            case .denied:
                locationMessage(
                    "Location access is off. Allow it in Settings to show your local timeline and nearest sunny place.",
                    buttonTitle: "Open Settings",
                    systemImage: "gearshape",
                    action: openSettings
                )
            case .restricted, .servicesDisabled:
                locationMessage(
                    "Current location is unavailable on this device.",
                    buttonTitle: "Open Settings",
                    systemImage: "gearshape",
                    action: openSettings
                )
            case .failed:
                locationMessage(
                    "Current location is unavailable on this device.",
                    buttonTitle: "Try Again",
                    systemImage: "arrow.clockwise",
                    action: retry
                )
            case .resolvingPlace, .ready, .readyWithoutMetadata:
                locationMessage(
                    "Weather is temporarily unavailable.",
                    buttonTitle: "Try Again",
                    systemImage: "arrow.clockwise",
                    action: retry
                )
            case .idle, .checkingAvailability, .requestingAuthorization,
                    .locating:
                locationMessage(
                    "Use your location to see the day's sunny-hour timeline.",
                    buttonTitle: "Use Current Location",
                    systemImage: "location",
                    action: requestLocation
                )
            }
        } else {
            EmptyView()
        }
    }

    private func locationMessage(
        _ message: LocalizedStringKey,
        buttonTitle: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        // All recovery states share one readable message-and-button layout.
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.callout)
                .foregroundStyle(theme.colors.secondaryText)

            Button(action: action) {
                Label(buttonTitle, systemImage: systemImage)
            }
            .weatherGlassActionStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

}

// MARK: - Hourly Track

/// Low-level graphical track shared by the daily card in both report types.
/// It adapts app forecast values to the shared app/widget capsule renderer.
private struct DailySunnyHoursTrack: View {
    let data: SunnyHoursCalculation.SunnyHoursData
    let selectedDate: Date
    let timeZone: TimeZone

    @Environment(\.appTheme) private var theme
    @Environment(\.calendar) private var calendar
    @ScaledMetric(relativeTo: .caption) private var capsuleSpacing: CGFloat = 7
    @ScaledMetric(relativeTo: .caption) private var maximumCapsuleWidth: CGFloat = 16
    @ScaledMetric(relativeTo: .caption) private var timelineMinimumHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var axisHeight: CGFloat = 14

    /// Converts app-owned hourly values into the target-neutral timeline input
    /// also used by the widget extension.
    private var chartHours: [SunnyHoursChartHour] {
        data.hours.map { forecast in
            SunnyHoursChartHour(
                date: forecast.date,
                hour: forecast.hour(in: timeZone),
                condition: forecast.condition
            )
        }
    }

    /// Uses the shared warm neutral so daily and 10-day cloudy marks match.
    private var noSunTimelineColor: Color {
        theme.colors.noSunTimelineFill
    }

    var body: some View {
        SunnyHoursDiscreteCapsuleTimeline(
            hours: chartHours,
            bounds: data.bounds,
            currentDate: .now,
            showsCurrentTimeMarker: selectedDateIsToday,
            configuration: .init(
                capsuleSpacing: capsuleSpacing,
                maximumCapsuleWidth: maximumCapsuleWidth,
                minimumTrackHeight: timelineMinimumHeight,
                axisHeight: axisHeight
            ),
            colors: SunnyHoursChartColors(
                primary: theme.colors.primaryText,
                secondary: theme.colors.secondaryText,
                sun: theme.colors.dotSun,
                partlySunny: theme.colors.dotPartlyCloudy,
                rain: theme.colors.dotRain,
                drizzle: theme.colors.dotDrizzle,
                noSun: noSunTimelineColor
            )
        )
    }

    private var selectedDateIsToday: Bool {
        var cityCalendar = calendar
        cityCalendar.timeZone = timeZone
        return cityCalendar.isDateInToday(selectedDate)
    }

}

// MARK: - Location Status Helpers

/// Presentation-only grouping used by the timeline's loading branch.
private extension LocationProviderStatus {
    var isActivelyLocating: Bool {
        switch self {
        case .checkingAvailability, .requestingAuthorization, .locating:
            true
        case .idle, .resolvingPlace, .ready, .readyWithoutMetadata, .denied,
                .restricted, .servicesDisabled, .failed:
            false
        }
    }
}
