//
//  NearbySunnyPlacesCard.swift
//  Weather
//
//  Purpose: Presents nearby World Cities recommendations using the same
//  ranking as Best Sunny Places, with each city's distance from the user.
//

import SwiftUI

// MARK: - Nearby Sunny Recommendations

/// Fallback card shown when the selected day is not sunny at the person's
/// location. It displays already-fetched recommendations; it does not search.
struct NearbySunnyPlacesCard: View {
    /// Your Location is a quick local scan, not a second full results screen.
    private static let maxRecommendations = 3

    // MARK: Inputs and User Preferences

    /// Pre-ranked results supplied by `WeatherModel` for the selected day.
    let recommendations: [NearestSunnyPlaceResult]
    let locationStatus: LocationProviderStatus
    let isLoading: Bool
    let hasCompletedSearch: Bool
    let errorMessage: String?
    let requestLocation: () -> Void
    let openSettings: () -> Void
    let retry: () -> Void
    let viewOnMap: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit")
    private var distanceUnitRaw = DistanceUnit.defaultRawValue

    // MARK: Display Formatting

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .systemDefault
    }

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    private var shownRecommendations: [NearestSunnyPlaceResult] {
        // Your Location is a preview. Map receives the full result list through the
        // action closure when the person wants to explore more choices.
        Array(recommendations.prefix(Self.maxRecommendations))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WeatherCardHeader(
                icon: "location.magnifyingglass",
                title: "Nearby Sunny Places"
            )

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
        if !shownRecommendations.isEmpty {
            // Render each discovery as native value navigation. Unlike saved
            // places, no bookmark action appears: these are suggestion rows.
            VStack(spacing: 0) {
                ForEach(shownRecommendations) { recommendation in
                    resultRow(recommendation)
                    if recommendation.id != shownRecommendations.last?.id {
                        Divider()
                            .padding(
                                .leading,
                                WeatherCardLayout.leadingIconWidth
                                    + WeatherCardLayout.headerSpacing
                            )
                    }
                }
            }

            // A nearby batch may retain useful cities even when one candidate
            // fails. Keep those rows, but surface the partial failure and its
            // recovery action inside this same card instead of hiding it.
            if let errorMessage {
                messageWithAction(
                    errorMessage,
                    actionTitle: "Try Again",
                    systemImage: "arrow.clockwise",
                    action: retry
                )
                .padding(.top, 4)
            }

            Button(action: viewOnMap) {
                Label("View on Map", systemImage: "map")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        } else if isLoading {
            // Loading is separate from an empty completed search, avoiding a
            // misleading “no sunny city” message while WeatherKit is working.
            HStack(spacing: WeatherCardLayout.headerSpacing) {
                ProgressView()
                    .frame(
                        width: WeatherCardLayout.leadingIconWidth,
                        alignment: .leading
                    )
                    .accessibilityHidden(true)
                Text("Loading nearby sunny places…")
                    .font(.callout)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .accessibilityElement(children: .combine)
        } else if let errorMessage {
            messageWithAction(
                errorMessage,
                actionTitle: "Try Again",
                systemImage: "arrow.clockwise",
                action: retry
            )
        } else if locationStatus.requiresSettings {
            messageWithAction(
                locationStatus == .denied
                    ? localizedString(
                        "Location access is off. Allow it in Settings to show your local timeline and nearest sunny place.",
                        locale: locale
                    )
                    : localizedString(
                        "Current location is unavailable on this device.",
                        locale: locale
                    ),
                actionTitle: "Open Settings",
                systemImage: "gearshape",
                action: openSettings
            )
        } else if !locationStatus.hasResolvedCoordinate {
            messageWithAction(
                localizedString(
                    "Use your location to find the nearest fully sunny city.",
                    locale: locale
                ),
                actionTitle: "Use Current Location",
                systemImage: "location",
                action: requestLocation
            )
        } else if hasCompletedSearch {
            Text(
                localizedString(
                    "No sunny city was found on this date.",
                    locale: locale
                )
            )
            .font(.callout)
            .foregroundStyle(theme.colors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } else {
            messageWithAction(
                localizedString(
                    "Find nearby World Cities with sunny conditions.",
                    locale: locale
                ),
                actionTitle: "Find Sunny Place",
                systemImage: "sun.max",
                action: retry
            )
        }
    }

    private func resultRow(
        _ recommendation: NearestSunnyPlaceResult
    ) -> some View {
        // The row mirrors `SavedPlacesSunnyPlaceRow`: fixed icon column, regular city
        // name, trailing temperature. Its one extra line is the local distance.
        NavigationLink(value: AppRoute.place(id: recommendation.id)) {
            HStack(spacing: WeatherCardLayout.headerSpacing) {
                let icon = recommendation.recommendation.condition.displayIcon
                Image(systemName: icon)
                    // Preserve the exact weather category color used by Map.
                    .weatherIconStyle(for: recommendation.recommendation.condition.iconTone)
                    .font(.callout.weight(.medium))
                    .frame(
                        width: WeatherCardLayout.leadingIconWidth,
                        alignment: .leading
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(recommendation.cityWeather.city.displayName)
                        .font(.body)
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(2)

                    Text(
                        "\(distanceUnit.display(recommendation.distanceKilometers)) from your location"
                    )
                        .font(.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text(temperatureUnit.display(recommendation.forecast.dailyHigh))
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recommendation.cityWeather.city.displayName)
        .accessibilityValue(
            accessibilityValue(for: recommendation)
        )
    }

    private func accessibilityValue(
        for recommendation: NearestSunnyPlaceResult
    ) -> String {
        let distance = String(
            format: localizedString("%@ from your location", locale: locale),
            locale: locale,
            distanceUnit.display(recommendation.distanceKilometers)
        )
        return [
            recommendation.recommendation.condition.localizedDisplayName(
                locale: locale
            ),
            temperatureUnit.display(recommendation.forecast.dailyHigh),
            distance
        ]
        .joined(separator: ", ")
    }

    private func messageWithAction(
        _ message: String,
        actionTitle: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        // Permission, error, and empty-search states share the same recovery
        // layout; callers vary only the explanatory text and action.
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.callout)
                .foregroundStyle(theme.colors.secondaryText)

            Button(action: action) {
                Label(actionTitle, systemImage: systemImage)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

// MARK: - Search Readiness

/// A coordinate is enough to search nearby cities even if reverse-geocoded
/// place metadata has not arrived yet.
private extension LocationProviderStatus {
    /// Authorization or service restrictions cannot be repaired by issuing
    /// another Core Location request, so route the person to system Settings.
    var requiresSettings: Bool {
        switch self {
        case .denied, .restricted, .servicesDisabled:
            true
        case .idle, .checkingAvailability, .requestingAuthorization,
                .locating, .resolvingPlace, .ready,
                .readyWithoutMetadata, .failed:
            false
        }
    }

    var hasResolvedCoordinate: Bool {
        switch self {
        case .ready, .readyWithoutMetadata:
            true
        case .idle, .checkingAvailability, .requestingAuthorization,
                .locating, .resolvingPlace, .denied, .restricted,
                .servicesDisabled, .failed:
            false
        }
    }
}
