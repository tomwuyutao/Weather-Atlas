//
//  BestSunnyPlacesCard.swift
//  Weather
//
//  Purpose: Presents compact sunny-place recommendations on Saved Places.
//

import SwiftUI

// MARK: - Saved-Place Recommendations

/// Saved places with usable data, ranked by the selected day's sunny-hour total.
struct BestSunnyPlacesCard: View {
    /// Available weather-derived values, ranked by the selected day.
    let recommendations: [PlaceRecommendation]
    /// The complete library is supplied so available recommendations can keep
    /// each saved place's custom display name and navigation identity.
    let savedPlaces: [SavedPlace]
    /// Describes why the ranking may not yet contain a usable row.
    let presentationState: SavedPlacesForecastPresentationState

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    private var recommendationsByID: [SavedPlace.ID: PlaceRecommendation] {
        Dictionary(
            uniqueKeysWithValues: recommendations.map { ($0.id, $0) }
        )
    }

    private var orderedRows: [SavedPlaceSunnyRow] {
        let orderedPlaces = SunnyPlacesRanking.savedPlacesBySunnyHours(
            savedPlaces,
            recommendations: recommendations,
            locale: locale
        )

        // The engine already excludes unavailable recommendations. `compactMap`
        // also makes that invariant explicit in the row type, preventing a
        // future caller change from bringing back a visually empty row.
        return orderedPlaces.compactMap { place in
            guard let recommendation = recommendationsByID[place.id] else {
                return nil
            }
            return SavedPlaceSunnyRow(
                place: place,
                recommendation: recommendation
            )
        }
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: WeatherCardLayout.contentSpacing
        ) {
            WeatherCardHeader(
                icon: "mappin.and.ellipse",
                title: "Best Sunny Places"
            )

            if !orderedRows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(orderedRows) { row in
                        NavigationLink(
                            value: AppRoute.place(id: row.id)
                        ) {
                            SavedPlacesPlaceRow(
                                recommendation: row.recommendation,
                                place: row.place
                            )
                        }
                        .buttonStyle(.plain)

                        if row.id != orderedRows.last?.id {
                            Divider()
                                .background(
                                    theme.colors.secondaryText.opacity(0.16)
                                )
                                .padding(
                                    .leading,
                                    SavedPlacesSunnyListLayout.cityNameLeadingInset
                                )
                        }
                    }
                }
            } else {
                statusContent
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

    /// Keeps the ranking card visible and explains its empty body instead of
    /// reserving space with an invisible placeholder.
    private var statusContent: some View {
        HStack(spacing: 8) {
            if presentationState == .loading {
                ProgressView()
                    .controlSize(.small)

            }

            Text(statusMessage)
        }
        .font(.callout)
        .foregroundStyle(theme.colors.secondaryText)
        .frame(
            maxWidth: .infinity,
            minHeight: WeatherCardFallbackLayout.savedPlacesContentHeight,
            alignment: .leading
        )

    }

    private var statusMessage: LocalizedStringKey {
        switch presentationState {
        case .emptyLibrary:
            "Save a place to compare sunny hours."
        case .loading:
            "Loading saved-place forecasts…"
        case .unavailable:
            "Saved-place forecasts are unavailable."
        case .ready:
            "No sunny-hour comparison is available for this date."
        }
    }
}

// MARK: - Shared Row Alignment

/// A fully renderable ranking row. Its stable identity remains the saved-place
/// UUID while the nonoptional recommendation guarantees weather content.
private struct SavedPlaceSunnyRow: Identifiable {
    let place: SavedPlace
    let recommendation: PlaceRecommendation

    var id: SavedPlace.ID { place.id }
}

/// The row grid deliberately shares the header's icon width and spacing, so
/// recommendation names and the card title begin on the same visual column.
private enum SavedPlacesSunnyListLayout {
    static let leadingIconWidth = WeatherCardLayout.leadingIconWidth
    static let columnSpacing = WeatherCardLayout.headerSpacing
    static let cityNameLeadingInset = leadingIconWidth + columnSpacing
}

/// One saved-place row. The parent omits a place when this selected date has no
/// usable recommendation, so every visible row has meaningful weather values.
private struct SavedPlacesPlaceRow: View {
    let recommendation: PlaceRecommendation
    let place: SavedPlace

    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale

    private var cityName: String {
        place.displayName
    }

    var body: some View {
        // The spacer pushes only the numeric value to the trailing edge; the
        // city name stays regular weight so rows remain easy to compare.
        HStack(spacing: SavedPlacesSunnyListLayout.columnSpacing) {
            let icon = recommendation.condition.displayIcon
            Image(systemName: icon)
                // Match the condition's Map-dot color rather than the
                // shared cloud-and-sun symbol's generic yellow fallback.
                .weatherIconStyle(for: recommendation.condition.iconTone)
                .font(.callout.weight(.medium))
                .frame(
                    width: SavedPlacesSunnyListLayout.leadingIconWidth,
                    alignment: .leading
                )
                // The row displays the localized condition;
                // the weather symbol itself would otherwise be a duplicate.


            VStack(alignment: .leading, spacing: 2) {
                Text(cityName)
                    .font(.body)
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(2)

            }

            Spacer(minLength: 8)

            Text(
                SunnyHoursFormatting.hourCountLabel(
                    recommendation.sunnyHourCount,
                    locale: locale
                )
            )
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .contentShape(.rect)



    }
}
