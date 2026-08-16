//
//  NearbySunnyPlacesCard.swift
//  Weather
//
//  Purpose: Presents nearby World Cities recommendations using the same
//  ranking as Best Sunny Places, with each city's distance from the user.
//

import SwiftUI

// MARK: - Nearby Sunny Recommendations

/// A persistent card showing nearby places with more selected-day sunny hours
/// than the person's location. It displays already-fetched recommendations;
/// it does not search.
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
    @AppStorage("distanceUnit")
    private var distanceUnitRaw = DistanceUnit.defaultRawValue

    // MARK: Display Formatting

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    private var shownRecommendations: [NearestSunnyPlaceResult] {
        // `WeatherModel` has already excluded places that do not improve on the
        // current location's sunny-hour total. This report is only a compact
        // preview; the Map receives the full eligible result list through the
        // action closure when the person wants to explore more choices.
        Array(recommendations.prefix(Self.maxRecommendations))
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: WeatherCardLayout.contentSpacing
        ) {
            WeatherCardHeader(
                icon: "location.magnifyingglass",
                title: "Nearby Sunnier Places"
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
                message(errorMessage)
                .padding(.top, 4)
            }

            Button(action: viewOnMap) {
                Label("View on Map", systemImage: "map")
            }
            .weatherGlassActionStyle()
            .frame(maxWidth: .infinity, alignment: .center)
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

                Text("Loading nearby sunnier places…")
                    .font(.callout)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        } else if let errorMessage {
            message(errorMessage)
        } else if locationStatus.requiresSettings {
            messageWithAction(
                locationStatus == .denied
                    ? localizedString(
                        "Location access is off. Allow it in Settings to show your local timeline and nearby sunnier places.",
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
                    "Use your location to find nearby places with more sunny hours.",
                    locale: locale
                ),
                actionTitle: "Use Current Location",
                systemImage: "location",
                action: requestLocation
            )
        } else if hasCompletedSearch {
            Text(
                localizedString(
                    "No nearby place has more sunny hours on this date.",
                    locale: locale
                )
            )
            .font(.callout)
            .foregroundStyle(theme.colors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            messageWithAction(
                localizedString(
                    "Find nearby World Cities with more sunny hours.",
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
        // name, and a trailing total of sunny hours. Its extra line is the local distance.
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

                Text(
                    SunnyHoursFormatting.hourCountLabel(
                        recommendation.recommendation.sunnyHourCount,
                        locale: locale
                    )
                )
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)



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
            .weatherGlassActionStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func message(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(theme.colors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
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
