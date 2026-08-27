//
//  NearbySunnyPlacesCard.swift
//  Weather
//
//  Purpose: Presents nearby World Cities recommendations using the same
//  ranking as Best Sunny Places, with each city's distance from the reference.
//

import SwiftUI

// MARK: - Nearby Sunny Recommendations

/// A persistent card showing nearby places with more selected-day sunny hours
/// than the report's reference place. It displays fetched recommendations;
/// it does not search.
struct NearbySunnyPlacesCard: View {
    /// The card is a quick local scan, not a second full results screen.
    private static let maxRecommendations = 3

    // MARK: - Inputs and User Preferences

    /// Pre-ranked results supplied by `WeatherModel` for the selected day.
    let recommendations: [NearestSunnyPlaceResult]
    let locationStatus: LocationProviderStatus
    /// Only Your Location needs permission recovery; place reports already carry
    /// an exact coordinate and must never fall back to the device coordinate.
    let requiresCurrentLocation: Bool
    /// A non-nil name changes row distances from “your location” to that place.
    let distanceReferenceName: String?
    let isLoading: Bool
    let hasCompletedSearch: Bool
    let errorMessage: String?
    let requestLocation: () -> Void
    let openSettings: () -> Void
    let viewOnMap: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @AppStorage("distanceUnit")
    private var distanceUnitRaw = DistanceUnit.defaultRawValue

    // MARK: - Display Formatting

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    private var shownRecommendations: [NearestSunnyPlaceResult] {
        // `WeatherModel` has already excluded places that do not improve on the
        // reference place's sunny-hour total. This report is only a compact
        // preview; the Map receives the full eligible result list through the
        // action closure when the person wants to explore more choices.
        Array(recommendations.prefix(Self.maxRecommendations))
    }

    /// The card can be waiting while its task runs or while its origin is being
    /// handed to the search. Both phases use the same compact loading layout.
    private var showsLoadingContent: Bool {
        shownRecommendations.isEmpty
            && (
                isLoading
                    || (
                        hasSearchOrigin
                            && !hasCompletedSearch
                            && errorMessage == nil
                    )
            )
    }

    private var hasSearchOrigin: Bool {
        !requiresCurrentLocation || locationStatus.hasResolvedCoordinate
    }

    // MARK: - Presentation

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

    // MARK: - Content States

    @ViewBuilder
    private var cardContent: some View {
        if !shownRecommendations.isEmpty {
            // Render each discovery as native value navigation. Unlike saved
            // places, no bookmark action appears: these are suggestion rows.
            VStack(spacing: 0) {
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

                // A partial forecast failure must not distract from usable nearby
                // results. The card only explains an error when it has no result
                // to show, preserving this branch as a concise recommendation list.
                Button(action: viewOnMap) {
                    SecondaryTextActionLabel(
                        title: "View on Map",
                        systemImage: "chevron.right"
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        } else if showsLoadingContent {
            loadingContent

        } else if let errorMessage {
            message(errorMessage)
        } else if requiresCurrentLocation && locationStatus.requiresSettings {
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
        } else if requiresCurrentLocation && !locationStatus.hasResolvedCoordinate {
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
            loadingContent
        }
    }

    // MARK: - Recommendation Rows and Recovery Actions

    private var loadingContent: some View {
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
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(theme.colors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resultRow(
        _ recommendation: NearestSunnyPlaceResult
    ) -> some View {
        // The row mirrors `SavedPlacesSunnyPlaceRow`: fixed icon column, regular city
        // name, and a trailing total of sunny hours. Its extra line is the local distance.
        NavigationLink(value: AppRoute.place(id: recommendation.id)) {
            HStack(spacing: WeatherCardLayout.headerSpacing) {
                if recommendation.recommendation.symbolName.isEmpty {
                    Color.clear
                        .frame(
                            width: WeatherCardLayout.leadingIconWidth,
                            height: 1,
                            alignment: .leading
                        )
                } else {
                    Image(systemName: recommendation.recommendation.symbolName)
                        // Current local Today uses WeatherKit's live symbol;
                        // an unavailable observation does not fall back to a
                        // daily icon.
                        .weatherIconStyle(
                            for: recommendation.recommendation.condition?.iconTone
                                ?? .cloudy
                        )
                        .font(.callout.weight(.medium))
                        .frame(
                            width: WeatherCardLayout.leadingIconWidth,
                            alignment: .leading
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        recommendation.recommendation.cityWeather.city.displayName
                    )
                        .font(.body)
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(2)

                    Text(distanceLabel(for: recommendation))
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

    /// Keeps the complete distance phrase localizable while changing only its
    /// reference from the user to the place whose report is open.
    private func distanceLabel(
        for recommendation: NearestSunnyPlaceResult
    ) -> String {
        let distance = distanceUnit.display(recommendation.distanceKilometers)
        guard let distanceReferenceName else {
            return localizedString(
                "\(distance) from your location",
                locale: locale
            )
        }
        return localizedString(
            "\(distance) from \(distanceReferenceName)",
            locale: locale
        )
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

}

// MARK: - Xcode Previews

#if DEBUG
#Preview(
    "Nearby Sunnier Places – Loading",
    traits: .fixedLayout(width: 390, height: 150)
) {
    NearbySunnyPlacesCard(
        recommendations: [],
        locationStatus: .ready,
        requiresCurrentLocation: true,
        distanceReferenceName: nil,
        isLoading: true,
        hasCompletedSearch: false,
        errorMessage: nil,
        requestLocation: {},
        openSettings: {},
        viewOnMap: {}
    )
    .padding()
    .background(AppPalette.light.background)
    .environment(\.appTheme, .shared)
    .environment(\.locale, Locale(identifier: "en"))
    .preferredColorScheme(.light)
}
#endif

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
