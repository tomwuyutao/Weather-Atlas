//
//  LocalSunCard.swift
//  Weather
//
//  Purpose: Brings the medium widget's single-day sunny-hour timeline into
//  Home using live current-location weather.
//

import SwiftUI

struct CurrentLocationTimelineCard: View {
    let weather: CityWeather?
    let selectedDate: Date
    /// Reverse-geocoded locality shown in the card header as soon as it arrives.
    let locationName: String?
    let locationStatus: LocationProviderStatus
    let isLoading: Bool
    let requestLocation: () -> Void
    let openSettings: () -> Void
    let retry: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    private var selectedForecast: DailyForecast? {
        weather?.forecastIfAvailable(
            on: selectedDate,
            selectionCalendar: calendar
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WeatherCardHeader(
                icon: "location.fill",
                title: displayLocationName
            ) {
                if let forecast = selectedForecast {
                    let icon = SunninessScoring.condition(for: forecast)?.displayIcon
                        ?? forecast.symbolName
                    Image(systemName: icon)
                        .font(.title2.weight(.medium))
                        .weatherIconStyle(for: icon)
                }
            }

            cardContent
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

    @ViewBuilder
    private var cardContent: some View {
        if let weather,
           let forecast = selectedForecast,
           case .success(let data) = SunninessScoring.sunnyHoursData(
            for: forecast,
            timeZone: weather.timeZone
           ) {
            loadedTimeline(weather: weather, forecast: forecast, data: data)
        } else if isLoading || locationStatus.isActivelyLocating {
            HStack(spacing: 12) {
                ProgressView()
                Text("Loading current-location weather…")
                    .font(.callout)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 18)
        } else {
            locationUnavailableContent
        }
    }

    private func loadedTimeline(
        weather: CityWeather,
        forecast: DailyForecast,
        data: SunninessScoring.SunnyHoursData
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            CurrentLocationHourTrack(
                data: data,
                selectedDate: selectedDate,
                timeZone: weather.timeZone
            )

            // The location and condition symbol belong in the shared card
            // header; the selected day's plain-language sun window follows the
            // timeline as supporting information.
            Text(sunStatus(for: weather, forecast: forecast, data: data))
                .font(.body)
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var locationUnavailableContent: some View {
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
                "Weather Atlas could not update your current location.",
                buttonTitle: "Try Again",
                systemImage: "arrow.clockwise",
                action: retry
            )
        case .ready, .readyWithoutMetadata:
            locationMessage(
                "Forecast data is unavailable for the selected date.",
                buttonTitle: "Try Again",
                systemImage: "arrow.clockwise",
                action: retry
            )
        case .idle, .checkingAvailability, .requestingAuthorization,
                .locating, .resolvingPlace:
            locationMessage(
                "Use your location to see the day's sunny-hour timeline.",
                buttonTitle: "Use Current Location",
                systemImage: "location",
                action: requestLocation
            )
        }
    }

    private func locationMessage(
        _ message: LocalizedStringKey,
        buttonTitle: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.callout)
                .foregroundStyle(theme.colors.secondaryText)

            Button(action: action) {
                Label(buttonTitle, systemImage: systemImage)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var displayLocationName: LocalizedStringKey {
        let name = locationName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return LocalizedStringKey(name?.isEmpty == false ? name! : "Current Location")
    }

    /// Explains the selected day in terms of the next fully clear hour. The
    /// countdown deliberately uses a duration rather than an absolute clock
    /// time, so Home answers how long the user has to wait for sun.
    private func sunStatus(
        for weather: CityWeather,
        forecast: DailyForecast,
        data: SunninessScoring.SunnyHoursData
    ) -> String {
        var cityCalendar = calendar
        cityCalendar.timeZone = weather.timeZone

        guard cityCalendar.isDateInToday(selectedDate) else {
            return sunnyHoursText(data: data, timeZone: weather.timeZone)
        }

        let clearHours = data.hours.filter {
            SunninessScoring.condition(for: $0) == .clear
        }
        let now = Date()
        if cityCalendar.isDateInToday(selectedDate),
           let currentHour = data.hours.last(where: { $0.date <= now }),
           SunninessScoring.condition(for: currentHour) == .clear {
            return localizedString("Clear Now", locale: locale)
        }
        if let nextClearHour = clearHours.first(where: { $0.date > now }) {
            return String(
                format: localizedString("Sun coming out in %@", locale: locale),
                locale: locale,
                countdownText(to: nextClearHour.date, from: now)
            )
        }
        return localizedString("No Sun on this day", locale: locale)
    }

    private func sunnyHoursText(
        data: SunninessScoring.SunnyHoursData,
        timeZone: TimeZone
    ) -> String {
        guard let range = SunninessScoring.longestSunnyHourRange(
            in: data.hours,
            timeZone: timeZone
        ) else {
            return localizedString("No Sun on this day", locale: locale)
        }
        let start = SunninessScoring.compactHourLabel(range.lowerBound, locale: locale)
        let end = SunninessScoring.compactHourLabel(range.upperBound + 1, locale: locale)
        return "\(localizedString("Sunny Hours", locale: locale)): \(start) – \(end)"
    }

    /// Produces a concise, localized duration such as "2 hours, 15 minutes".
    private func countdownText(to date: Date, from referenceDate: Date) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        formatter.calendar = calendar
        return formatter.string(
            from: max(0, date.timeIntervalSince(referenceDate))
        ) ?? localizedString("less than one minute", locale: locale)
    }
}

private struct CurrentLocationHourTrack: View {
    let data: SunninessScoring.SunnyHoursData
    let selectedDate: Date
    let timeZone: TimeZone

    @Environment(\.accessibilityDifferentiateWithoutColor)
    private var differentiateWithoutColor
    @Environment(\.appTheme) private var theme
    @Environment(\.calendar) private var calendar

    private var axisHours: [Int] {
        data.bounds.axisHours(maximumTickCount: 4)
    }

    private let axisLabelWidth: CGFloat = 24

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    HStack(spacing: 7) {
                        ForEach(data.hours, id: \.date) { hour in
                            let condition = SunninessScoring.condition(for: hour)
                            Capsule()
                                .fill(color(for: condition))
                                .overlay {
                                    if differentiateWithoutColor,
                                       condition == .partlySunny {
                                        Capsule().strokeBorder(
                                            theme.colors.primaryText.opacity(0.8),
                                            style: StrokeStyle(
                                                lineWidth: 1,
                                                dash: [2, 2]
                                            )
                                        )
                                    }
                                }
                        }
                    }

                    if selectedDateIsToday,
                       let markerX = data.bounds.currentTimeXPosition(
                        at: Date(),
                        timeZone: timeZone,
                        width: proxy.size.width
                       ) {
                        Rectangle()
                            .fill(theme.colors.primaryText.opacity(0.9))
                            .frame(width: 2)
                            .position(x: markerX, y: proxy.size.height / 2)
                    }
                }
            }
            .frame(height: 44)

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    ForEach(axisHours, id: \.self) { hour in
                        Text(SunnyHoursFormatting.chartHourLabel(hour))
                            .frame(width: axisLabelWidth)
                            .position(
                                // Keep the first and last labels inside the
                                // same horizontal bounds as the hour track.
                                x: min(
                                    max(
                                        axisLabelWidth / 2,
                                        data.bounds.xPosition(
                                            for: Double(hour),
                                            width: proxy.size.width
                                        )
                                    ),
                                    proxy.size.width - axisLabelWidth / 2
                                ),
                                y: 7
                            )
                    }
                }
            }
            .frame(height: 14)
            .font(.caption2.weight(.medium))
            .foregroundStyle(theme.colors.secondaryText)
            .lineLimit(1)
        }
    }

    private var selectedDateIsToday: Bool {
        var cityCalendar = calendar
        cityCalendar.timeZone = timeZone
        return cityCalendar.isDateInToday(selectedDate)
    }

    private func color(for condition: AppWeatherCondition?) -> Color {
        condition?.dotColor(for: theme.colors) ?? theme.colors.dotCloudy
    }
}

private extension LocationProviderStatus {
    var isActivelyLocating: Bool {
        switch self {
        case .checkingAvailability, .requestingAuthorization, .locating,
                .resolvingPlace:
            true
        case .idle, .ready, .readyWithoutMetadata, .denied, .restricted,
                .servicesDisabled, .failed:
            false
        }
    }
}
