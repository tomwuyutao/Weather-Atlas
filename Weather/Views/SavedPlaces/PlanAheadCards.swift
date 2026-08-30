//
//  PlanAheadCards.swift
//  Weather
//
//  Purpose: Presents saved-place sunny outlooks and compact weekend rankings
//  without coupling their calculation to the Saved Places screen.
//

import SwiftUI

// MARK: - Sunny Outlook Inputs

/// One saved destination's next mostly-sunny forecast state.
///
/// Keeping loading and unavailable at row level lets forecasts that have
/// already resolved remain useful while another saved place is still pending.
struct SavedPlaceSunnyOutlook: Identifiable, Equatable {
    enum Status: Equatable {
        /// The app-wide selection date for the first qualifying city-local day.
        case date(Date)
        /// Usable forecast rows exist, but none meet the 80% daylight rule.
        case noMatch
        /// This place still has an in-flight forecast request.
        case loading
        /// The request settled without a usable forecast.
        case unavailable
    }

    let place: SavedPlace
    let status: Status

    var id: SavedPlace.ID { place.id }

    var selectionDate: Date? {
        guard case .date(let date) = status else { return nil }
        return date
    }

    /// Places with a confirmed sunny date lead chronologically. Pending and
    /// unavailable forecasts follow, while a confirmed no-match stays last.
    /// Equal statuses retain saved-library order for deterministic updates.
    static func ranked(
        _ outlooks: [SavedPlaceSunnyOutlook]
    ) -> [SavedPlaceSunnyOutlook] {
        outlooks.enumerated().sorted { lhs, rhs in
            if case .date(let lhsDate) = lhs.element.status,
               case .date(let rhsDate) = rhs.element.status,
               lhsDate != rhsDate {
                return lhsDate < rhsDate
            }

            let lhsPriority = sortPriority(for: lhs.element.status)
            let rhsPriority = sortPriority(for: rhs.element.status)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }

            return lhs.offset < rhs.offset
        }
        .map { $0.element }
    }

    private static func sortPriority(for status: Status) -> Int {
        switch status {
        case .date:
            0
        case .loading:
            1
        case .unavailable:
            2
        case .noMatch:
            3
        }
    }
}

// MARK: - Sunny Outlook Card

/// Shows the first forecast day with at least 80% sunny daylight for every
/// saved place. All rows use native buttons so a caller can open the place and,
/// when available, synchronize the shared forecast date.
struct SunnyOutlookByPlaceCard: View {
    let rows: [SavedPlaceSunnyOutlook]
    let presentationState: SavedPlacesForecastPresentationState
    let onSelect: (SavedPlace.ID, Date?) -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: WeatherCardLayout.contentSpacing
        ) {
            WeatherCardHeader(
                icon: "sun.max",
                title: "Sunny Outlook by Place"
            )

            if rows.isEmpty {
                statusContent
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        Button {
                            onSelect(row.id, row.selectionDate)
                        } label: {
                            SunnyOutlookPlaceRow(outlook: row)
                        }
                        .buttonStyle(.plain)

                        if row.id != rows.last?.id {
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
            "No saved-place forecasts are available for this period."
        }
    }
}

private struct SunnyOutlookPlaceRow: View {
    let outlook: SavedPlaceSunnyOutlook

    @Environment(\.appTheme) private var theme
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: SavedPlacesRankingListLayout.columnSpacing) {
            leadingStatus
                .frame(
                    width: SavedPlacesRankingListLayout.leadingIconWidth,
                    alignment: .leading
                )

            Text(outlook.place.localizedDisplayName(locale: locale))
                .font(.body)
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(2)

            Spacer(minLength: 8)

            trailingStatus
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
    }

    @ViewBuilder
    private var leadingStatus: some View {
        switch outlook.status {
        case .date:
            Image(systemName: "sun.max.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(theme.colors.dotSun)
        case .noMatch:
            Image(systemName: "minus")
                .font(.callout.weight(.medium))
                .foregroundStyle(theme.colors.secondaryText)
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .unavailable:
            Image(systemName: "exclamationmark.triangle")
                .font(.callout.weight(.medium))
                .foregroundStyle(theme.colors.secondaryText)
        }
    }

    @ViewBuilder
    private var trailingStatus: some View {
        switch outlook.status {
        case .date(let date):
            Text(dateLabel(for: date))
                .font(.body)
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)
        case .noMatch:
            Text("None in forecast")
                .font(.callout)
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(2)
        case .loading:
            Text("Loading…")
                .font(.callout)
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
        case .unavailable:
            Text("Unavailable")
                .font(.callout)
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
        }
    }

    private func dateLabel(for date: Date) -> String {
        var style = Date.FormatStyle.dateTime
            .weekday(.abbreviated)
            .month(.abbreviated)
            .day()
            .locale(locale)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}

// MARK: - Weekend Escape Card

/// Ranks saved destinations independently for the next Saturday and Sunday,
/// then presents both capped rankings as one continuous list.
struct BestWeekendEscapeCard: View {
    private static let maximumRecommendationsPerDay = 5

    let saturdayDate: Date
    let sundayDate: Date
    let saturdayRecommendations: [PlaceRecommendation]
    let sundayRecommendations: [PlaceRecommendation]
    let savedPlaces: [SavedPlace]
    let presentationState: SavedPlacesForecastPresentationState
    let onSelect: (SavedPlace.ID, Date) -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    private var saturdayRows: [WeekendRecommendationRow] {
        rankedRows(from: saturdayRecommendations, on: saturdayDate)
    }

    private var sundayRows: [WeekendRecommendationRow] {
        rankedRows(from: sundayRecommendations, on: sundayDate)
    }

    private var weekendRows: [WeekendRecommendationRow] {
        saturdayRows + sundayRows
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: WeatherCardLayout.contentSpacing
        ) {
            WeatherCardHeader(
                icon: "suitcase.rolling",
                title: "Best Weekend Escape"
            ) {
                Text(weekendDateRangeLabel)
                    .font(.subheadline)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if weekendRows.isEmpty {
                statusContent
            } else {
                VStack(spacing: 0) {
                    ForEach(weekendRows) { row in
                        Button {
                            onSelect(row.place.id, row.date)
                        } label: {
                            SunnyPlaceRecommendationRow(
                                recommendation: row.recommendation,
                                displayName: row.place.localizedDisplayName(
                                    locale: locale
                                ),
                                trailingContext: weekdayLabel(for: row.date)
                            )
                        }
                        .buttonStyle(.plain)

                        if row.id != weekendRows.last?.id {
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
            minHeight: WeatherCardFallbackLayout.savedPlacesContentHeight,
            alignment: .leading
        )
    }

    private func rankedRows(
        from recommendations: [PlaceRecommendation],
        on date: Date
    ) -> [WeekendRecommendationRow] {
        let placesByID = Dictionary(
            uniqueKeysWithValues: savedPlaces.map { ($0.id, $0) }
        )

        let rows: [WeekendRecommendationRow] = PlaceRecommendation.ranked(
            recommendations.filter { $0.sunnyHourCount > 0 },
            locale: locale
        ).compactMap { recommendation in
            guard let place = placesByID[recommendation.id] else { return nil }
            return WeekendRecommendationRow(
                place: place,
                recommendation: recommendation,
                date: date
            )
        }

        return Array(rows.prefix(Self.maximumRecommendationsPerDay))
    }

    private func weekdayLabel(for date: Date) -> String {
        var style = Date.FormatStyle.dateTime
            .weekday(.abbreviated)
            .locale(locale)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    /// Omits the year and collapses a shared month, producing concise labels
    /// such as “Aug 29–30” while retaining each locale's natural field order.
    private var weekendDateRangeLabel: String {
        let style = Date.IntervalFormatStyle(
            locale: locale,
            calendar: calendar,
            timeZone: calendar.timeZone
        )
        .month(.abbreviated)
        .day()
        return (saturdayDate..<sundayDate).formatted(style)
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
            "No saved place has sunny hours this weekend."
        }
    }
}

private struct WeekendRecommendationRow: Identifiable {
    struct ID: Hashable {
        let placeID: SavedPlace.ID
        let date: Date
    }

    let place: SavedPlace
    let recommendation: PlaceRecommendation
    let date: Date

    var id: ID { ID(placeID: place.id, date: date) }
}
