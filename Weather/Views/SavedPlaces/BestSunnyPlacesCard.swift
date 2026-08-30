//
//  BestSunnyPlacesCard.swift
//  Weather
//
//  Purpose: Presents compact sunny-place recommendations for any comparison
//  source, including Saved Places and temporary Map query results.
//

import SwiftUI

// MARK: - Saved-Place Recommendations

/// Places with usable data, ranked by the selected day's sunny-hour total.
struct BestSunnyPlacesCard: View {
    // MARK: - Inputs and Environment

    /// Available weather-derived values, ranked by the selected day.
    let recommendations: [PlaceRecommendation]
    /// The complete source supplies identity and source order. Settled places
    /// without a forecast are omitted from the visible ranking.
    let places: [ForecastComparisonPlace]
    /// Per-place request state preserves a row only while its forecast is
    /// actively loading. Settled missing data has no visible city row.
    let loadingPlaceIDs: Set<City.ID>
    /// Describes why the ranking may not yet contain a usable row.
    let presentationState: SavedPlacesForecastPresentationState
    let statusMessages: PlaceComparisonStatusMessages
    let onSelect: (City.ID) -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    // MARK: - Ranked Rows

    private var recommendationsByID: [City.ID: PlaceRecommendation] {
        Dictionary(
            uniqueKeysWithValues: recommendations.map { ($0.id, $0) }
        )
    }

    private var orderedRows: [ForecastComparisonSunnyRow] {
        let rankByPlaceID = Dictionary(
            uniqueKeysWithValues: PlaceRecommendation.ranked(
                recommendations,
                locale: locale
            ).enumerated().map { ($0.element.id, $0.offset) }
        )
        let sourceOrderByID = Dictionary(
            uniqueKeysWithValues: places.enumerated().map {
                ($0.element.id, $0.offset)
            }
        )

        let orderedPlaces = places.sorted { lhs, rhs in
            switch (rankByPlaceID[lhs.id], rankByPlaceID[rhs.id]) {
            case let (lhsRank?, rhsRank?):
                return lhsRank < rhsRank
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return sourceOrderByID[lhs.id, default: .max]
                    < sourceOrderByID[rhs.id, default: .max]
            }
        }

        return orderedPlaces.compactMap { place in
            let recommendation = recommendationsByID[place.id]
            let isLoading = loadingPlaceIDs.contains(place.id)
            guard recommendation != nil || isLoading else {
                return nil
            }

            return ForecastComparisonSunnyRow(
                place: place,
                recommendation: recommendation
            )
        }
    }

    // MARK: - List Presentation

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: WeatherCardLayout.contentSpacing
        ) {
            if orderedRows.isEmpty {
                statusContent
            } else {
                VStack(spacing: 0) {
                    ForEach(orderedRows) { row in
                        VStack(spacing: 0) {
                            Button {
                                onSelect(row.id)
                            } label: {
                                ForecastComparisonDayRow(
                                    row: row
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
                                        SavedPlacesRankingListLayout
                                            .contentLeadingInset
                                    )
                            }
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

    private var statusMessage: LocalizedStringResource {
        switch presentationState {
        case .emptyLibrary:
            statusMessages.empty
        case .loading:
            statusMessages.loading
        case .unavailable:
            statusMessages.unavailable
        case .ready:
            statusMessages.noDateComparison
        }
    }
}

// MARK: - Shared Row Alignment

/// One stable visible city row. Settled places without usable data are filtered
/// out before row construction; only in-flight forecast requests remain.
private struct ForecastComparisonSunnyRow: Identifiable {
    let place: ForecastComparisonPlace
    let recommendation: PlaceRecommendation?

    var id: City.ID { place.id }
}

private struct ForecastComparisonDayRow: View {
    let row: ForecastComparisonSunnyRow

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            if let recommendation = row.recommendation {
                SunnyPlaceRecommendationRow(
                    recommendation: recommendation,
                    displayName: row.place.displayName
                )
            } else {
                loadingRow
            }
        }
    }

    private var loadingRow: some View {
        HStack(spacing: SavedPlacesRankingListLayout.columnSpacing) {
            ProgressView()
                .controlSize(.small)
                .frame(
                    width: SavedPlacesRankingListLayout.leadingIconWidth,
                    alignment: .leading
                )

            Text(row.place.displayName)
                .font(.body)
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(2)

            Spacer(minLength: 8)

            Text("Loading…")
                .font(.callout)
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
    }
}

/// The row grid deliberately shares the header's icon width and spacing, so
/// recommendation names and the card title begin on the same visual column.
enum SavedPlacesRankingListLayout {
    static let leadingIconWidth = WeatherCardLayout.leadingIconWidth
    static let columnSpacing = WeatherCardLayout.headerSpacing
    static let contentLeadingInset = leadingIconWidth + columnSpacing
    /// Numerals are narrower than the header's SF Symbols. This keeps their
    /// optical center on the same vertical axis without moving later columns.
    static let rankOpticalInset: CGFloat = 3
}

/// One reusable available-forecast row shared by Saved Places and Find Sun.
struct SunnyPlaceRecommendationRow: View {
    let recommendation: PlaceRecommendation
    let displayName: String
    /// Optional compact context appended after the localized hour total.
    let trailingContext: String?

    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale

    init(
        recommendation: PlaceRecommendation,
        displayName: String,
        trailingContext: String? = nil
    ) {
        self.recommendation = recommendation
        self.displayName = displayName
        self.trailingContext = trailingContext
    }

    var body: some View {
        // The spacer pushes only the numeric value to the trailing edge; the
        // city name stays regular weight so rows remain easy to compare.
        HStack(spacing: SavedPlacesRankingListLayout.columnSpacing) {
            if recommendation.symbolName.isEmpty {
                Color.clear
                    .frame(
                        width: SavedPlacesRankingListLayout.leadingIconWidth,
                        height: 1,
                        alignment: .leading
                    )
            } else {
                Image(systemName: recommendation.symbolName)
                    // Current local Today uses WeatherKit's live symbol; all
                    // other selected dates use their daily forecast symbol.
                    .weatherIconStyle(
                        for: recommendation.condition?.iconTone ?? .cloudy
                    )
                    .font(.callout.weight(.medium))
                    .frame(
                        width: SavedPlacesRankingListLayout.leadingIconWidth,
                        alignment: .leading
                    )
                    // The row displays the localized condition;
                    // the weather symbol itself would otherwise be a duplicate.
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body)
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(trailingLabel)
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
    }

    private var trailingLabel: String {
        let hourLabel = SunnyHoursFormatting.hourCountLabel(
            recommendation.sunnyHourCount,
            locale: locale
        )
        guard let trailingContext else { return hourLabel }

        // Keep both values inside one localized resource so translators can
        // reorder the hour total and compact day label if their language needs
        // a different reading order.
        var resource: LocalizedStringResource =
            "\(hourLabel) · \(trailingContext)"
        resource.locale = locale
        return String(localized: resource)
    }
}
