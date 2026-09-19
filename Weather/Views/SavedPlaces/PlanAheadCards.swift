//
//  PlanAheadCards.swift
//  Weather
//
//  Purpose: Presents the two plan-ahead rankings without coupling their
//  calculation to either the Saved Places or Map query screen.
//

import SwiftUI

// MARK: - Sunny Outlook Inputs

/// One saved destination's next mostly-sunny forecast state.
struct ForecastComparisonSunnyOutlook: Identifiable, Equatable {
  enum Status: Equatable {
    case date(Date)
    case noMatch
    case loading
    case unavailable
  }

  let place: ForecastComparisonPlace
  let status: Status
  /// A city-local date suitable for opening Detail even when no qualifying
  /// mostly-sunny day exists or the forecast is still loading.
  let navigationDate: Date

  var id: City.ID { place.id }

  /// Confirmed sunny dates lead chronologically. Pending and unavailable
  /// forecasts follow, while a confirmed no-match stays last. Equal statuses
  /// retain saved-library order for deterministic updates.
  static func ranked(
    _ outlooks: [ForecastComparisonSunnyOutlook]
  ) -> [ForecastComparisonSunnyOutlook] {
    outlooks.enumerated().sorted { lhs, rhs in
      if case .date(let lhsDate) = lhs.element.status,
        case .date(let rhsDate) = rhs.element.status,
        lhsDate != rhsDate
      {
        return lhsDate < rhsDate
      }

      let lhsPriority =
        ({ (status: Status) in
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
        })(lhs.element.status)
      let rhsPriority =
        ({ (status: Status) in
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
        })(rhs.element.status)
      if lhsPriority != rhsPriority {
        return lhsPriority < rhsPriority
      }

      return lhs.offset < rhs.offset
    }
    .map(\.element)
  }

}

// MARK: - Sunny Outlook List

/// Shows every saved place's next forecast day with at least 80% sunny
/// daylight. The parent mode title supplies the list's heading.
struct SunnyOutlookByPlaceCard: View {
  let rows: [ForecastComparisonSunnyOutlook]
  let presentationState: SavedPlacesForecastPresentationState
  let statusMessages: PlaceComparisonStatusMessages
  let onSelect: (City.ID, Date?) -> Void

  @Environment(\.appTheme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Group {
      if rows.filter({
        if case .unavailable = $0.status { return false }
        return true
      }).isEmpty {
        statusContent
      } else {
        VStack(spacing: 0) {
          ForEach(
            rows.filter {
              if case .unavailable = $0.status { return false }
              return true
            }
          ) { row in
            VStack(spacing: 0) {
              Button {
                onSelect(row.id, row.navigationDate)
              } label: {
                SunnyOutlookPlaceRow(outlook: row)
              }
              .buttonStyle(.plain)

              if row.id
                != rows.filter({
                  if case .unavailable = $0.status { return false }
                  return true
                }).last?.id
              {
                (Divider()
                  .background(theme.colors.secondaryText.opacity(0.16))
                  .padding(
                    .leading,
                    SavedPlacesRankingListLayout.contentLeadingInset
                  ))
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

  private var statusContent: some View {
    HStack(spacing: 8) {
      if presentationState == .loading {
        ProgressView()
          .controlSize(.small)
      }

      Text(
        ({
          switch presentationState {
          case .emptyLibrary:
            statusMessages.empty
          case .loading:
            statusMessages.loading
          case .unavailable:
            statusMessages.unavailable
          case .ready:
            statusMessages.noPeriodForecasts
          }
        })())
    }
    .font(.callout)
    .foregroundStyle(theme.colors.secondaryText)
    .frame(
      maxWidth: .infinity,
      minHeight: WeatherCardFallbackLayout.savedPlacesContentHeight,
      alignment: .leading
    )
  }

}

private struct SunnyOutlookPlaceRow: View {
  let outlook: ForecastComparisonSunnyOutlook

  @Environment(\.appTheme) private var theme
  @Environment(\.calendar) private var calendar
  @Environment(\.locale) private var locale

  var body: some View {
    HStack(spacing: SavedPlacesRankingListLayout.columnSpacing) {
      Group {
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
      .frame(
        width: SavedPlacesRankingListLayout.leadingIconWidth,
        alignment: .leading
      )

      Text(outlook.place.displayName)
        .font(.body)
        .foregroundStyle(
          ({ () -> Color in

            if case .noMatch = outlook.status {
              return theme.colors.secondaryText
            }
            return theme.colors.primaryText
          }())
        )
        .lineLimit(2)

      Spacer(minLength: 8)

      Group {
        switch outlook.status {
        case .date(let date):
          Text(
            ({ (date: Date) in
              var style = Date.FormatStyle.dateTime
                .weekday(.abbreviated)
                .month(.abbreviated)
                .day()
                .locale(locale)
              style.timeZone = calendar.timeZone
              return date.formatted(style)
            })(date)
          )
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
      .multilineTextAlignment(.trailing)
    }
    .padding(.vertical, 8)
    .contentShape(.rect)
  }

}

// MARK: - Weekend Daily Ranking Model

/// One visible result in either weekend-day column. Confirmed forecasts lead in
/// their independently ranked order; pending forecasts follow.
/// Settled places without usable daylight data never become visible rows.
struct ForecastComparisonWeekendDayRanking: Identifiable {
  let place: ForecastComparisonPlace
  let recommendation: PlaceRecommendation?
  let isLoading: Bool

  var id: City.ID { place.id }

  static func ranked(
    places: [ForecastComparisonPlace],
    recommendations: [PlaceRecommendation],
    loadingPlaceIDs: Set<City.ID>,
    locale: Locale
  ) -> [ForecastComparisonWeekendDayRanking] {
    let placeByID = Dictionary(
      uniqueKeysWithValues: places.map { ($0.id, $0) }
    )
    let rankedPairs = PlaceRecommendation.ranked(
      recommendations,
      locale: locale
    ).compactMap { recommendation in
      placeByID[recommendation.id].map { ($0, recommendation) }
    }
    let rankedIDs = Set(rankedPairs.map { $0.0.id })

    let confirmedRows = rankedPairs.map { pair in
      ForecastComparisonWeekendDayRanking(
        place: pair.0,
        recommendation: pair.1,
        isLoading: false
      )
    }
    let pendingRows: [ForecastComparisonWeekendDayRanking] =
      places.compactMap { place in
        guard loadingPlaceIDs.contains(place.id),
          !rankedIDs.contains(place.id)
        else {
          return nil
        }
        return ForecastComparisonWeekendDayRanking(
          place: place,
          recommendation: nil,
          isLoading: true
        )
      }

    return confirmedRows + pendingRows
  }
}

// MARK: - Weekend Daily Ranking Card

/// Presents the next Saturday and Sunday as equal, independently ranked
/// columns inside one planning card.
struct BestWeekendEscapeCard: View {
  let saturdayDate: Date
  let sundayDate: Date
  let saturdayRows: [ForecastComparisonWeekendDayRanking]
  let sundayRows: [ForecastComparisonWeekendDayRanking]
  let presentationState: SavedPlacesForecastPresentationState
  let statusMessages: PlaceComparisonStatusMessages
  let onSelect: (City.ID, Date?) -> Void

  @Environment(\.appTheme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Group {
      if !saturdayRows.isEmpty || !sundayRows.isEmpty {
        HStack(alignment: .top, spacing: 12) {
          WeekendDayRankingColumn(
            date: saturdayDate,
            rows: saturdayRows,
            presentationState: presentationState,
            onSelect: onSelect
          )
          .frame(maxWidth: .infinity, alignment: .topLeading)

          Divider()
            .background(
              theme.colors.secondaryText.opacity(0.16)
            )

          WeekendDayRankingColumn(
            date: sundayDate,
            rows: sundayRows,
            presentationState: presentationState,
            onSelect: onSelect
          )
          .frame(maxWidth: .infinity, alignment: .topLeading)
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

  private var statusContent: some View {
    HStack(spacing: 8) {
      if presentationState == .loading {
        ProgressView()
          .controlSize(.small)
      }

      Text(
        ({
          switch presentationState {
          case .emptyLibrary:
            statusMessages.empty
          case .loading:
            statusMessages.loading
          case .unavailable:
            statusMessages.unavailable
          case .ready:
            statusMessages.noPeriodForecasts
          }
        })())
    }
    .font(.callout)
    .foregroundStyle(theme.colors.secondaryText)
    .frame(
      maxWidth: .infinity,
      minHeight: WeatherCardFallbackLayout.savedPlacesContentHeight,
      alignment: .leading
    )
  }

}

private struct WeekendDayRankingColumn: View {
  let date: Date
  let rows: [ForecastComparisonWeekendDayRanking]
  let presentationState: SavedPlacesForecastPresentationState
  let onSelect: (City.ID, Date?) -> Void

  @Environment(\.appTheme) private var theme
  @Environment(\.calendar) private var calendar
  @Environment(\.locale) private var locale

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 2) {
        Text(
          ({ () -> String in

            var style = Date.FormatStyle.dateTime
              .weekday(.wide)
              .locale(locale)
            style.timeZone = calendar.timeZone
            return date.formatted(style)
          }())
        )
        .font(.headline)
        .foregroundStyle(theme.colors.primaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.75)

        Text(
          ({
            var style = Date.FormatStyle.dateTime
              .month(.abbreviated)
              .day()
              .locale(locale)
            style.timeZone = calendar.timeZone
            return date.formatted(style)
          })()
        )
        .font(.caption)
        .foregroundStyle(theme.colors.secondaryText)
        .lineLimit(1)
      }
      .padding(.bottom, 8)

      if rows.isEmpty {
        if presentationState == .loading {
          ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
      } else {
        VStack(spacing: 0) {
          ForEach(rows) { row in
            VStack(spacing: 0) {
              Button {
                onSelect(row.id, date)
              } label: {
                WeekendDayRecommendationRow(row: row)
              }
              .buttonStyle(.plain)

              if row.id != rows.last?.id {
                Divider()
                  .background(
                    theme.colors.secondaryText.opacity(0.16)
                  )
              }
            }
          }
        }
      }
    }
  }

}

private struct WeekendDayRecommendationRow: View {
  let row: ForecastComparisonWeekendDayRanking

  @Environment(\.appTheme) private var theme
  @Environment(\.locale) private var locale

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(row.place.displayName)
        .font(.body)
        .foregroundStyle(theme.colors.primaryText)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)

      Group {
        if let recommendation = row.recommendation {
          Text(
            ({ () -> String in
              let hours = recommendation.sunnyHourCount
              return String(
                format: localizedString("%@ h", locale: locale),
                locale: locale,
                hours.formatted(
                  .number
                    .grouping(.never)
                    .precision(.fractionLength(hours.rounded() == hours ? 0 : 1))
                    .locale(locale)
                )
              )
            }())
          )
          .font(.body)
          .monospacedDigit()
          .foregroundStyle(theme.colors.secondaryText)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
        } else if row.isLoading {
          Text("Loading…")
            .font(.caption)
            .foregroundStyle(theme.colors.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
      }
    }
    .padding(.vertical, 8)
    .contentShape(.rect)
  }

}
