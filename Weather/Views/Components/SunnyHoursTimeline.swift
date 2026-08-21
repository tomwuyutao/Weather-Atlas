//
//  SunnyHoursTimeline.swift
//  Weather
//
//  Purpose: Brings the medium widget's single-day sunny-hour timeline into
//  Your Location using live current-location weather.
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
    // MARK: Inputs

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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    // MARK: Selected Forecast

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

    /// The trailing header value reports the selected day's total sunny hours,
    /// matching the compact value used by nearby and saved-place rankings.
    /// The chart itself still exposes the hours' positions within the day.
    private var selectedSunnyHours: String? {
        guard let weather,
              let forecast = selectedForecast,
              case .success(let data) = SunnyHoursCalculation.sunnyHoursData(
                for: forecast,
                timeZone: weather.timeZone
              ) else {
            return nil
        }

        return SunnyHoursFormatting.hourCountLabel(
            SunnyHoursCalculation.sunnyHourCount(in: data),
            locale: locale
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeatherCardLayout.contentSpacing) {
            WeatherCardHeader(
                icon: "calendar.day.timeline.left",
                title: "Daily Sunny Hours"
            ) {
                if let selectedSunnyHours {
                    Text(selectedSunnyHours)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
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
        // Availability belongs to the enclosing report. This card renders an
        // honest blank/unavailable state, but never presents a duplicate alert.
    }

    @ViewBuilder
    private var cardContent: some View {
        // `sunnyHoursData` validates that hourly data is coherent before the
        // timeline is drawn. Every other state explains how to recover.
        if let weather,
           let forecast = selectedForecast,
           case .success(let data) = SunnyHoursCalculation.sunnyHoursData(
            for: forecast,
            timeZone: weather.timeZone
           ) {
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

    private func loadedTimeline(
        weather: CityWeather,
        data: SunnyHoursCalculation.SunnyHoursData
    ) -> some View {
        return DailySunnyHoursTrack(
            data: data,
            selectedDate: selectedDate,
            timeZone: weather.timeZone,
            screenTone: selectedForecast?.condition?.iconTone
        )
    }

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
            case .ready, .readyWithoutMetadata:
                locationMessage(
                    "Weather is temporarily unavailable.",
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
/// It aligns hourly segments, the current-time marker, and sparse axis labels.
private struct DailySunnyHoursTrack: View {
    /// The daily chart deliberately stops growing once it reaches the width of
    /// a phone report. On a landscape iPad, stretching each hourly capsule
    /// across the entire card made the compact timeline read as large dots
    /// rather than the vertical, discrete hour marks used on phone and widget.
    private static let maximumPhoneTimelineWidth: CGFloat = 360
    /// One data-backed hourly capsule in the discrete daily timeline.
    private struct TimelineSlot: Identifiable {
        enum ID: Hashable {
            case forecast(Date)
        }

        let id: ID
        let hour: Int
        let condition: AppWeatherCondition?
    }

    /// A sparse x-axis label mapped to one concrete capsule index. Keeping the
    /// displayed hour and its capsule position together prevents labels from
    /// drifting into the gaps between cells on a nonuniform daylight domain.
    private struct AxisMarker: Identifiable {
        let hour: Int
        let capsuleIndex: Int

        var id: Int { hour }
    }

    let data: SunnyHoursCalculation.SunnyHoursData
    let selectedDate: Date
    let timeZone: TimeZone
    /// The selected report condition also tints inactive timeline slots.
    let screenTone: WeatherIconTone?

    @Environment(\.appTheme) private var theme
    @Environment(\.calendar) private var calendar
    @ScaledMetric(relativeTo: .caption) private var capsuleSpacing: CGFloat = 7
    @ScaledMetric(relativeTo: .caption) private var timelineMinimumHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var axisHeight: CGFloat = 14

    /// Converts validated daylight forecasts into the same data-backed
    /// discrete capsule sequence used by the medium widget.
    private var displayedSlots: [TimelineSlot] {
        data.hours.map { forecast in
            TimelineSlot(
                id: .forecast(forecast.date),
                hour: forecast.hour(in: timeZone),
                condition: forecast.condition
            )
        }
    }

    var body: some View {
        // Both rows derive their positions from this single slot sequence. The
        // chart is therefore visually identical to the medium widget below its
        // header, while the app can retain its own card chrome above it.
        let slots = displayedSlots
        if let startHour = slots.first?.hour, !slots.isEmpty {
            let endHour = data.bounds.endHour
            VStack(spacing: 4) {
                GeometryReader { proxy in
                    let capsuleHeight = proxy.size.height
                    // The widget divides the available width after reserving
                    // inter-capsule gaps; reuse that calculation verbatim so
                    // the axis and live marker share the same coordinates.
                    let capsuleWidth = (
                        proxy.size.width
                            - capsuleSpacing * CGFloat(slots.count - 1)
                    ) / CGFloat(slots.count)

                    ZStack(alignment: .leading) {
                        HStack(spacing: capsuleSpacing) {
                            ForEach(slots) { slot in
                                Capsule()
                                    .fill(color(for: slot.condition))
                            }
                        }

                        if selectedDateIsToday,
                           let boundaryIndex = currentTimeBoundaryIndex(in: slots) {
                            Rectangle()
                                .fill(theme.colors.primaryText.opacity(0.9))
                                .frame(width: 2)
                                .frame(height: capsuleHeight)
                                .position(
                                    // Match the widget's marker: it falls at the
                                    // nearest clock-hour boundary between capsules.
                                    x: currentTimeMarkerX(
                                        for: boundaryIndex,
                                        capsuleWidth: capsuleWidth,
                                        slotCount: slots.count
                                    ),
                                    y: capsuleHeight / 2
                                )
                        }
                    }
                    .frame(height: capsuleHeight, alignment: .top)
                }
                .frame(minHeight: timelineMinimumHeight)

                // Four labels remain readable in the app card. Each desired
                // hour is anchored to its nearest visible capsule center, as
                // in the medium widget, rather than a continuous solar-time x.
                let axisMarkers = timelineAxisMarkers(
                    for: slots,
                    from: startHour,
                    through: endHour
                )
                GeometryReader { proxy in
                    let capsuleWidth = (
                        proxy.size.width
                            - capsuleSpacing * CGFloat(slots.count - 1)
                    ) / CGFloat(slots.count)

                    ZStack(alignment: .leading) {
                        ForEach(axisMarkers) { marker in
                            Text(SunnyHoursFormatting.chartHourLabel(marker.hour))
                                .position(
                                    // Put every label directly under a real
                                    // capsule center, including each endpoint.
                                    x: CGFloat(marker.capsuleIndex)
                                        * (capsuleWidth + capsuleSpacing)
                                        + capsuleWidth / 2,
                                    y: proxy.size.height / 2
                                )
                        }
                    }
                }
                .frame(height: axisHeight)
                .font(.caption2.weight(.medium))
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
            }



            .frame(
                maxWidth: Self.maximumPhoneTimelineWidth,
                alignment: .leading
            )
        } else {
            EmptyView()
        }
    }

    private var selectedDateIsToday: Bool {
        var cityCalendar = calendar
        cityCalendar.timeZone = timeZone
        return cityCalendar.isDateInToday(selectedDate)
    }

    /// Finds the boundary after the capsule nearest the city's current hour.
    /// This mirrors the widget's discrete marker policy instead of placing a
    /// continuous marker at a point that could sit between unequal slot widths.
    private func currentTimeBoundaryIndex(in slots: [TimelineSlot]) -> Int? {
        guard slots.count > 1,
              let firstHour = slots.first?.hour,
              let lastHour = slots.last?.hour else {
            return nil
        }

        var cityCalendar = calendar
        cityCalendar.timeZone = timeZone
        let currentHour = cityCalendar.component(.hour, from: .now)

        guard currentHour >= firstHour,
              currentHour <= lastHour,
              let currentIndex = slots.enumerated().min(by: {
                  abs($0.element.hour - currentHour)
                      < abs($1.element.hour - currentHour)
              })?.offset else {
            return nil
        }

        return currentIndex + 1
    }

    /// Places a marker between data cells, or at the trailing edge when the
    /// current hour is the final represented forecast interval.
    private func currentTimeMarkerX(
        for boundaryIndex: Int,
        capsuleWidth: CGFloat,
        slotCount: Int
    ) -> CGFloat {
        if boundaryIndex >= slotCount {
            return CGFloat(slotCount) * capsuleWidth
                + CGFloat(max(slotCount - 1, 0)) * capsuleSpacing
        }
        return CGFloat(boundaryIndex) * capsuleWidth
            + (CGFloat(boundaryIndex) - 0.5) * capsuleSpacing
    }

    /// Maps four evenly spaced clock labels back to actual capsule centers.
    /// Rounding can land between real daylight-hour cells, so the nearest
    /// displayed slot gives the user an honest visual anchor for every label.
    private func timelineAxisMarkers(
        for slots: [TimelineSlot],
        from startHour: Int,
        through endHour: Int
    ) -> [AxisMarker] {
        guard !slots.isEmpty else { return [] }

        let span = max(endHour - startHour, 0)
        let axisHours = (0...3).reduce(into: [Int]()) { hours, index in
            let hour = startHour
                + Int((Double(span) * Double(index) / 3).rounded())
            if hours.last != hour {
                hours.append(hour)
            }
        }

        return axisHours.enumerated().map { axisIndex, hour in
            let capsuleIndex: Int
            if axisIndex == 0 {
                capsuleIndex = 0
            } else if axisIndex == axisHours.count - 1 {
                capsuleIndex = slots.count - 1
            } else {
                capsuleIndex = slots.enumerated().min {
                    abs($0.element.hour - hour) < abs($1.element.hour - hour)
                }?.offset ?? 0
            }
            return AxisMarker(hour: hour, capsuleIndex: capsuleIndex)
        }
    }

    /// Uses the same five semantic chart colors as the ten-day chart and
    /// widgets. Non-precipitation conditions retain the neutral no-sun track,
    /// while rain and drizzle stay visible as their own forecast states.
    private func color(for condition: AppWeatherCondition?) -> Color {
        switch condition {
        case .clear:
            theme.colors.dotSun
        case .partlySunny:
            theme.colors.dotPartlyCloudy
        case .rain:
            theme.colors.dotRain
        case .drizzle:
            theme.colors.dotDrizzle
        case .partlyCloudy, .cloudy, .snow, .fog, .wind, .none:
            theme.colors.weatherNoSunTimelineColor(for: screenTone)
        }
    }

}

// MARK: - Location Status Helpers

/// Presentation-only grouping used by the timeline's loading branch.
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
