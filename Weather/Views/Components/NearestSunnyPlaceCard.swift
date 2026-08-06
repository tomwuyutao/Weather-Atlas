//
//  NearestSunnyPlaceCard.swift
//  Weather
//
//  Purpose: Presents the first fully sunny World Cities result found by the
//  query-budgeted nearest-first Home search.
//

import SwiftUI

struct NearestSunnyPlaceCard: View {
    @Binding var radius: NearestSunnySearchRadius

    let recommendation: NearestSunnyPlaceResult?
    /// Selected-day state that replaces card disappearance with an explanation.
    let currentLocationIsFullySunny: Bool
    let locationStatus: LocationProviderStatus
    let isLoading: Bool
    let hasCompletedSearch: Bool
    let checkedCityCount: Int
    let weatherKitQueryCount: Int
    let errorMessage: String?
    let isSaved: Bool
    let requestLocation: () -> Void
    let retry: () -> Void
    let save: () -> Void

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
                    title: "Nearest Sunny Place"
                )

                radiusMenu
            }

            cardContent

            #if DEBUG
            if hasCompletedSearch, !isLoading {
                Text(
                    verbatim:
                        "Debug · \(weatherKitQueryCount) WeatherKit queries · "
                        + "\(checkedCityCount) cities checked"
                )
                .font(.caption2.monospacedDigit())
                .foregroundStyle(theme.colors.secondaryText)
                .accessibilityLabel(
                    Text(
                        verbatim:
                            "Debug. \(weatherKitQueryCount) WeatherKit queries. "
                            + "\(checkedCityCount) cities checked."
                    )
                )
            }
            #endif
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .detailTranslucentCard(
            colorScheme: colorScheme,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private var radiusMenu: some View {
        Menu {
            Picker("Search Radius", selection: $radius) {
                ForEach(NearestSunnySearchRadius.allCases) { option in
                    Text(
                        option.measurement,
                        format: .measurement(width: .abbreviated)
                    )
                    .tag(option)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(
                    radius.measurement,
                    format: .measurement(width: .abbreviated)
                )
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .accessibilityHint("Changes the maximum nearest-sunny search distance.")
    }

    @ViewBuilder
    private var cardContent: some View {
        if let recommendation {
            resultRow(recommendation)
        } else if currentLocationIsFullySunny, hasCompletedSearch {
            Text("Your current location is already fully sunny on this date.")
                .font(.callout)
                .foregroundStyle(theme.colors.secondaryText)
                .padding(.vertical, 14)
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
                    "No fully sunny city was found within the selected distance.",
                    locale: locale
                ),
                actionTitle: "Try Again",
                systemImage: "arrow.clockwise",
                action: retry
            )
        } else {
            messageWithAction(
                localizedString(
                    "Find the nearest World Cities location with fully clear conditions.",
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

            if !isSaved {
                Button("Save", systemImage: "bookmark", action: save)
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
