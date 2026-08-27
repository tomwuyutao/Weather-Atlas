//
//  BestSunnyDatesCard.swift
//  Weather
//
//  Purpose: Ranks the strongest upcoming sunny days across a set of places.
//

import SwiftUI

// MARK: - Date Summary Model

/// One forecast date summarized across every place with usable weather.
struct BestSunnyDateSummary: Identifiable, Equatable {
    let date: Date
    /// Mean selected-day sunny hours across available place forecasts.
    let averageSunnyHours: Double
    /// Places with at least one sunny daytime hour on this date.
    let sunnyPlaceCount: Int
    /// Places that contributed usable weather to this date's comparison.
    let availablePlaceCount: Int
    /// Highest-ranked place for the date, resolved for the current surface.
    let bestPlaceName: String?
    /// Sunny-hour total paired with `bestPlaceName`.
    let bestPlaceSunnyHours: Double?

    var id: Date { date }

    /// Centralizes the comparison math shared by Saved Places and Find Sun.
    init?(
        date: Date,
        recommendations: [PlaceRecommendation],
        locale: Locale,
        placeName: (PlaceRecommendation) -> String
    ) {
        guard !recommendations.isEmpty else { return nil }

        let rankedRecommendations = PlaceRecommendation.ranked(
            recommendations,
            locale: locale
        )
        let totalSunnyHours = recommendations.map(\.sunnyHourCount).reduce(0, +)
        let bestRecommendation = rankedRecommendations.first

        self.date = date
        averageSunnyHours = totalSunnyHours / Double(recommendations.count)
        sunnyPlaceCount = recommendations.count { $0.sunnyHourCount > 0 }
        availablePlaceCount = recommendations.count
        bestPlaceName = bestRecommendation.flatMap { recommendation in
            recommendation.sunnyHourCount > 0 ? placeName(recommendation) : nil
        }
        bestPlaceSunnyHours = bestRecommendation.flatMap { recommendation in
            recommendation.sunnyHourCount > 0
                ? recommendation.sunnyHourCount
                : nil
        }
    }

    /// Best dates lead; broader sunshine and the strongest place break ties.
    static func ranked(
        _ summaries: [BestSunnyDateSummary]
    ) -> [BestSunnyDateSummary] {
        summaries.sorted { lhs, rhs in
            if lhs.averageSunnyHours != rhs.averageSunnyHours {
                return lhs.averageSunnyHours > rhs.averageSunnyHours
            }
            if lhs.sunnyPlaceCount != rhs.sunnyPlaceCount {
                return lhs.sunnyPlaceCount > rhs.sunnyPlaceCount
            }
            if lhs.bestPlaceSunnyHours != rhs.bestPlaceSunnyHours {
                return (lhs.bestPlaceSunnyHours ?? 0) > (rhs.bestPlaceSunnyHours ?? 0)
            }
            return lhs.date < rhs.date
        }
    }
}

// MARK: - Ranked Date Card

/// Planning card that recommends dates instead of duplicating chronological
/// date navigation. Selecting a recommendation still updates the shared date so
/// the adjacent place ranking can immediately explain that choice.
struct BestSunnyDatesCard: View {
    let summaries: [BestSunnyDateSummary]
    @Binding var selectedDate: Date
    let presentationState: SavedPlacesForecastPresentationState

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var featuredDates: [RankedSunnyDate] {
        Array(BestSunnyDateSummary.ranked(summaries).prefix(3))
            .enumerated()
            .map { index, summary in
                RankedSunnyDate(rank: index + 1, summary: summary)
            }
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: WeatherCardLayout.contentSpacing
        ) {
            WeatherCardHeader(
                icon: "calendar.badge.checkmark",
                title: "Best Sunny Dates"
            )

            if featuredDates.isEmpty {
                statusContent
            } else {
                VStack(spacing: 0) {
                    ForEach(featuredDates) { rankedDate in
                        BestSunnyDateRow(
                            rankedDate: rankedDate,
                            selectedDate: $selectedDate
                        )

                        if rankedDate.id != featuredDates.last?.id {
                            Divider()
                                .background(theme.colors.secondaryText.opacity(0.16))
                                .padding(
                                    .leading,
                                    SavedPlacesRankingListLayout.contentLeadingInset
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
            minHeight: WeatherCardFallbackLayout.savedDatesContentHeight,
            alignment: .leading
        )
    }

    private var statusMessage: LocalizedStringKey {
        switch presentationState {
        case .emptyLibrary:
            "Save a place to compare upcoming sunny dates."
        case .loading:
            "Loading saved-place forecasts…"
        case .unavailable:
            "Saved-place forecasts are unavailable."
        case .ready:
            "No saved-place forecasts are available for this period."
        }
    }
}

// MARK: - Ranked Date Row

private struct RankedSunnyDate: Identifiable {
    let rank: Int
    let summary: BestSunnyDateSummary

    var id: Date { summary.id }
}

private struct BestSunnyDateRow: View {
    let rankedDate: RankedSunnyDate
    @Binding var selectedDate: Date

    @Environment(\.appTheme) private var theme
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    private var summary: BestSunnyDateSummary { rankedDate.summary }

    /// The root date switcher and this ranking share one calendar-day
    /// selection. Comparing days through the environment calendar keeps the
    /// emphasis correct even when the stored dates have different times.
    private var isSelected: Bool {
        calendar.isDate(summary.date, inSameDayAs: selectedDate)
    }

    /// Explains the distribution hidden by the arithmetic mean. The complete
    /// localized sentence lets translators reorder every value naturally.
    private var sunnyPlacesSummary: String {
        let sunnyCount = summary.sunnyPlaceCount.formatted(
            .number.grouping(.never).locale(locale)
        )
        let availableCount = summary.availablePlaceCount.formatted(
            .number.grouping(.never).locale(locale)
        )

        return String(
            format: localizedString(
                "Sunny places: %1$@ of %2$@",
                locale: locale
            ),
            locale: locale,
            sunnyCount,
            availableCount
        )
    }

    var body: some View {
        Button {
            selectedDate = calendar.startOfDay(for: summary.date)
        } label: {
            HStack(spacing: SavedPlacesRankingListLayout.columnSpacing) {
                Text(
                    rankedDate.rank,
                    format: .number.grouping(.never).locale(locale)
                )
                .font(.body.monospacedDigit())
                .foregroundStyle(theme.colors.primaryText)
                .padding(
                    .leading,
                    SavedPlacesRankingListLayout.rankOpticalInset
                )
                .frame(
                    width: SavedPlacesRankingListLayout.leadingIconWidth,
                    alignment: .leading
                )

                // Match Nearby Sunnier Places: the primary identity and its
                // supporting context share a compact two-line leading column.
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        summary.date,
                        format: .dateTime
                            .weekday(.wide)
                            .month(.abbreviated)
                            .day()
                            .locale(locale)
                    )
                    .font(
                        .body.weight(isSelected ? .semibold : .regular)
                    )
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(2)

                    Text(sunnyPlacesSummary)
                        .font(.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(
                        SunnyHoursFormatting.hourCountLabel(
                            summary.averageSunnyHours,
                            locale: locale
                        )
                    )
                    .font(
                        .body.weight(isSelected ? .semibold : .regular)
                    )
                    .monospacedDigit()
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)

                    Text(
                        "Average",
                        comment: "Small caption identifying the sunny-hour value as an arithmetic mean across available saved places."
                    )
                    .font(.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
                }
                .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
