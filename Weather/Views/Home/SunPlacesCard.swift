//
//  SunPlacesCard.swift
//  Weather
//
//  Purpose: Presents compact sunny-place recommendations on Home.
//

import SwiftUI

/// Compact sunny recommendations for saved places.
struct BestSunnyPlacesCard: View {
    let recommendations: [PlaceRecommendation]

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WeatherCardHeader(
                icon: "bookmark",
                title: "Best Sunny Places"
            )

            if recommendations.isEmpty {
                Text("No sunny places for this date.")
                    .font(.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                    .background(
                        theme.colors.glassFill.opacity(0.42),
                        in: RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(recommendations) { recommendation in
                        NavigationLink(
                            value: AppRoute.place(id: recommendation.id)
                        ) {
                            HomeSunnyPlaceRow(
                                recommendation: recommendation
                            )
                        }
                        .buttonStyle(.plain)

                        if recommendation.id != recommendations.last?.id {
                            Divider()
                                .background(
                                    theme.colors.secondaryText.opacity(0.16)
                                )
                                .padding(
                                    .leading,
                                    HomeSunnyListLayout.cityNameLeadingInset
                                )
                        }
                    }
                }
            }

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
}

private enum HomeSunnyListLayout {
    static let leadingIconWidth = WeatherCardLayout.leadingIconWidth
    static let columnSpacing = WeatherCardLayout.headerSpacing
    static let cityNameLeadingInset = leadingIconWidth + columnSpacing
}

private struct HomeSunnyPlaceRow: View {
    let recommendation: PlaceRecommendation

    @Environment(\.appTheme) private var theme
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue

    private var cityName: String {
        recommendation.cityWeather.city.displayName
    }

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .systemDefault
    }

    var body: some View {
        HStack(spacing: HomeSunnyListLayout.columnSpacing) {
            let icon = recommendation.condition.displayIcon
            Image(systemName: icon)
                .weatherIconStyle(for: icon)
                .font(.callout.weight(.medium))
                .frame(
                    width: HomeSunnyListLayout.leadingIconWidth,
                    alignment: .leading
                )

            Text(cityName)
                .font(.body.weight(.medium))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(temperatureUnit.display(recommendation.forecast.dailyHigh))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
    }
}
