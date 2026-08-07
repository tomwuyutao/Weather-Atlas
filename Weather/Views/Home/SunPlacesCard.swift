//
//  SunPlacesCard.swift
//  Weather
//
//  Purpose: Presents compact ranked place recommendations on Home.
//

import SwiftUI

/// Heading geometry shared by Home's weather cards.
struct HomeWeatherCardHeader: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: String?

    @Environment(\.appTheme) private var theme

    init(icon: String, title: LocalizedStringKey, subtitle: String? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(spacing: HomeSunnyListLayout.columnSpacing) {
            Image(systemName: icon)
                .foregroundStyle(theme.colors.primaryText)
                .frame(
                    width: HomeSunnyListLayout.rankColumnWidth,
                    alignment: .leading
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)

                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Compact ranked recommendations for saved places.
struct BestSunnyPlacesCard: View {
    let recommendations: [PlaceRecommendation]
    let selectedDate: Date
    /// Identifies the ephemeral current-location row without treating it as a
    /// Saved Place anywhere else in the app.
    let currentLocationRecommendationID: City.ID?
    let showAllPlaces: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    private var selectedDateScope: String {
        let date = selectedDate.formatted(
            Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
                .locale(locale)
        )
        return String(
            format: localizedString("For %@", locale: locale),
            locale: locale,
            date
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeWeatherCardHeader(
                icon: "bookmark",
                title: "Best Sunny Places",
                subtitle: selectedDateScope
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
                    ForEach(
                        Array(recommendations.enumerated()),
                        id: \.element.id
                    ) { index, recommendation in
                        NavigationLink(
                            value: AppRoute.place(id: recommendation.id)
                        ) {
                            HomeSunnyPlaceRow(
                                recommendation: recommendation,
                                rank: index + 1,
                                isCurrentLocation:
                                    recommendation.id == currentLocationRecommendationID
                            )
                        }
                        .buttonStyle(.plain)

                        if index < recommendations.count - 1 {
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

            Button(action: showAllPlaces) {
                HStack(spacing: 8) {
                    Text("Show All Cities")
                        .font(.callout.weight(.medium))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(theme.colors.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .detailTranslucentCard(
            colorScheme: colorScheme,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }
}

private enum HomeSunnyListLayout {
    static let rankColumnWidth: CGFloat = 32
    static let columnSpacing: CGFloat = 5
    static let cityNameLeadingInset = rankColumnWidth + columnSpacing
}

private struct HomeSunnyPlaceRow: View {
    let recommendation: PlaceRecommendation
    let rank: Int
    let isCurrentLocation: Bool

    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var cityName: String {
        recommendation.cityWeather.city.displayName
    }

    var body: some View {
        HStack(spacing: HomeSunnyListLayout.columnSpacing) {
            HomeSunnyRankLabel(rank: rank)

            HStack(spacing: 5) {
                Text(cityName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)

                if isCurrentLocation {
                    Image(systemName: "location.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.secondaryText)
                        .accessibilityLabel("Current Location")
                }
            }

            Spacer(minLength: 8)

            let icon = recommendation.condition.displayIcon
            Image(systemName: icon)
                .weatherIconStyle(for: icon)
                .font(.callout.weight(.medium))
            .lineLimit(1)
            .frame(
                width: dynamicTypeSize > .large ? 92 : 76,
                alignment: .trailing
            )
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(rank), \(cityName), \(recommendation.condition.localizedDisplayName())"
        )
    }
}

private struct HomeSunnyRankLabel: View {
    let rank: Int

    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var pointSize: CGFloat {
        switch dynamicTypeSize {
        case .xSmall: 13
        case .small: 14
        case .medium: 15
        case .large: 16
        case .xLarge: 18
        default: 20
        }
    }

    var body: some View {
        Text(verbatim: String(rank))
            .font(.system(size: pointSize, weight: .semibold))
            .foregroundStyle(theme.colors.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.leading, 5)
            .frame(
                width: HomeSunnyListLayout.rankColumnWidth,
                alignment: .leading
            )
    }
}
