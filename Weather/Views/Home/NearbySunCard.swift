//
//  NearbySunCard.swift
//  Weather
//
//  Purpose: Presents nearby World Cities recommendations using the same
//  scoring as Best Sunny Places, with each city's distance from the user.
//

import SwiftUI

struct NearestSunnyPlaceCard: View {
    let recommendations: [NearestSunnyPlaceResult]
    let locationStatus: LocationProviderStatus
    let isLoading: Bool
    let hasCompletedSearch: Bool
    let errorMessage: String?
    let savedPlaceIDs: Set<SavedPlace.ID>
    let requestLocation: () -> Void
    let retry: () -> Void
    let save: (NearestSunnyPlaceResult) -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .systemDefault
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                HomeWeatherCardHeader(
                    icon: "location.magnifyingglass",
                    title: "Nearby Sunny Places"
                )
            }

            cardContent
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .detailTranslucentCard(
            colorScheme: colorScheme,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    @ViewBuilder
    private var cardContent: some View {
        if !recommendations.isEmpty {
            VStack(spacing: 0) {
                ForEach(recommendations) { recommendation in
                    resultRow(recommendation)
                    if recommendation.id != recommendations.last?.id {
                        Divider()
                            .padding(.leading, 42)
                    }
                }
            }
        } else if isLoading {
            HStack(spacing: 12) {
                ProgressView()
                Text("Checking the nearest cities for clear weather…")
                    .font(.callout)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .padding(.vertical, 14)
        } else if let errorMessage {
            messageWithAction(
                errorMessage,
                actionTitle: "Try Again",
                systemImage: "arrow.clockwise",
                action: retry
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
            messageWithAction(
                localizedString(
                    "No sunny city was found within this range.",
                    locale: locale
                ),
                actionTitle: "Try Again",
                systemImage: "arrow.clockwise",
                action: retry
            )
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
        HStack(spacing: 10) {
            NavigationLink(value: AppRoute.place(id: recommendation.id)) {
                HStack(spacing: 10) {
                    Image(systemName: "sun.max.fill")
                        .font(.title2)
                        .foregroundStyle(theme.colors.sunIconColor)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            recommendation.cityWeather.city.displayName
                        )
                        .font(.body.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(1)

                        HStack(spacing: 6) {
                            if !recommendation.cityWeather.city.country.isEmpty {
                                Text(recommendation.cityWeather.city.country)
                            }
                            Text(
                                Measurement(
                                    value: recommendation.distanceKilometers,
                                    unit: UnitLength.kilometers
                                ),
                                format: .measurement(width: .abbreviated)
                            )
                        }
                        .font(.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text(
                        temperatureUnit.display(
                            recommendation.forecast.dailyHigh
                        )
                    )
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.colors.primaryText)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if !savedPlaceIDs.contains(recommendation.id) {
                Button("Save", systemImage: "bookmark") {
                    save(recommendation)
                }
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private func messageWithAction(
        _ message: String,
        actionTitle: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
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

private extension LocationProviderStatus {
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
