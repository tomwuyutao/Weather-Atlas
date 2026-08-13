//
//  SavedPlacesView.swift
//  Weather
//
//  Purpose: Presents saved-place planning and comparisons, with the full
//  editable library available as a pushed destination rather than a peer tab.
//

import SwiftUI

/// Shared presentation state for the two Saved Places planning cards.
///
/// The state changes only their explanatory fallback content. Any available
/// recommendations or date summaries continue to use the existing ranking and
/// heatmap paths.
enum SavedPlacesForecastPresentationState: Equatable {
    case emptyLibrary
    case loading
    case unavailable
    case ready
}

/// Planning dashboard for cities the person explicitly saved.
struct SavedPlacesView: View {
    // MARK: Shared Inputs

    @Bindable var model: WeatherModel
    @Binding var selectedDate: Date

    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale

    // MARK: Derived Planning Data

    /// One place's settled source issues. Keeping the place alongside its
    /// issues lets the overview present one concise, city-specific alert while
    /// the visible list continues to retain every saved destination.
    private struct SettledSavedPlaceIssue {
        let place: SavedPlace
        let issues: [WeatherDataIssue]
    }

    private var recommendationAssessment: SavedRecommendationsAssessment {
        model.savedRecommendationAssessment(on: selectedDate)
    }

    /// Places where the selected literal date has already passed stay visible
    /// as exclusions instead of silently disappearing from the page.
    private var dateExclusions: [SavedPlaceDateExclusion] {
        model.savedPlaceDateExclusions(on: selectedDate)
    }

    private var dateSummaries: [BestSunnyDateSummary] {
        ForecastDateHorizon.dates(in: model.forecastCalendar).compactMap { date in
            let assessment = model.savedRecommendationAssessment(on: date)
            let excludedIDs = Set(
                model.savedPlaceDateExclusions(on: date).map(\.id)
            )
            let recommendations = assessment.recommendations.filter {
                !excludedIDs.contains($0.id)
            }
            let weightedSunnyPlaceCount = Double(
                recommendations.count(where: {
                    $0.condition.isSunnyOrPartlySunny
                })
            )
            return BestSunnyDateSummary(
                date: date,
                weightedSunnyPlaceCount: weightedSunnyPlaceCount,
                availableCityCount: recommendations.count
            )
        }
    }

    /// Distinguishes first load, an intentionally empty library, and a settled
    /// failure so both planning cards can remain visible with honest fallback
    /// content. Loaded rows still take precedence inside each card.
    private var forecastPresentationState: SavedPlacesForecastPresentationState {
        if model.placesStore.loadErrorDescription != nil {
            return .unavailable
        }

        let places = model.placesStore.allPlaces
        guard !places.isEmpty else { return .emptyLibrary }

        if places.contains(where: { model.weatherStore.isLoading($0.id) }) {
            return .loading
        }

        if places.contains(where: {
            model.weatherStore.weather(for: $0.id) != nil
        }) {
            return .ready
        }

        if places.contains(where: {
            model.weatherStore.failuresByID[$0.id] != nil
        }) {
            return .unavailable
        }

        // Saved places exist but initial hydration has not started publishing
        // per-place request state yet. Present this brief gap as loading rather
        // than incorrectly declaring the forecasts unavailable.
        return .loading
    }

    private var timeZoneExclusionNotice: String? {
        switch dateExclusions.count {
        case 0:
            return nil
        case 1:
            return localizedString(
                "1 city is excluded from this overview due to time zone differences.",
                locale: locale
            )
        default:
            return String(
                format: localizedString(
                    "%d cities are excluded from this overview due to time zone differences.",
                    locale: locale
                ),
                locale: locale,
                dateExclusions.count
            )
        }
    }

    /// The repository performs its one immediate repair request before it
    /// commits an incomplete response. Only then may Saved Places present a
    /// consolidated alert. A date already passed in the destination's local
    /// timezone is an expected exclusion, so it remains a quiet footer only.
    private var settledMissingData: [SettledSavedPlaceIssue] {
        let excludedIDs = Set(dateExclusions.map(\.id))

        return model.placesStore.allPlaces.compactMap { place in
            guard !excludedIDs.contains(place.id),
                  !model.weatherStore.isLoading(place.id),
                  let issues = recommendationAssessment.issuesByPlaceID[place.id],
                  !issues.isEmpty else {
                return nil
            }

            // An absent snapshot is not a settled failure while its initial
            // request has not happened. It becomes eligible only after the
            // repository records a final failure. A loaded snapshot, by
            // contrast, is final partial data after the repository repair.
            let hasSettledSource = model.weatherStore.weather(for: place.id) != nil
                || model.weatherStore.failuresByID[place.id] != nil
            guard hasSettledSource else { return nil }

            return SettledSavedPlaceIssue(
                place: place,
                issues: Array(Set(issues)).sorted { lhs, rhs in
                    if lhs.kind.rawValue != rhs.kind.rawValue {
                        return lhs.kind.rawValue < rhs.kind.rawValue
                    }
                    return (lhs.forecastDate?.timeIntervalSinceReferenceDate ?? 0)
                        < (rhs.forecastDate?.timeIntervalSinceReferenceDate ?? 0)
                }
            )
        }
    }

    private var missingDataReport: MissingDataAlertReport? {
        // A single unavailable city is represented honestly in its own row.
        // Only an all-library outage is systemic enough to interrupt with one
        // post-retry alert.
        let comparablePlaceIDs = Set(
            model.placesStore.allPlaces.map(\.id)
        ).subtracting(Set(dateExclusions.map(\.id)))
        let missingPlaceIDs = Set(settledMissingData.map(\.place.id))
        guard !comparablePlaceIDs.isEmpty,
              missingPlaceIDs == comparablePlaceIDs else {
            return nil
        }

        let entries = settledMissingData.sorted {
            $0.place.displayName.localizedCaseInsensitiveCompare(
                $1.place.displayName
            ) == .orderedAscending
        }
        let identity = entries.map { entry in
            let issueIdentity = entry.issues.map { issue in
                let date = issue.forecastDate?.timeIntervalSinceReferenceDate ?? 0
                return "\(issue.kind.rawValue):\(date):\(issue.detail ?? "")"
            }
            .joined(separator: ",")
            return "\(entry.place.id.uuidString):\(issueIdentity)"
        }
        .joined(separator: "|")

        let messages = entries.flatMap { entry in
            entry.issues.map {
                weatherDataIssueMessage(
                    $0,
                    cityName: entry.place.displayName,
                    locale: locale
                )
            }
        }

        return MissingDataAlertReport(
            key: "saved-places:\(selectedDate.timeIntervalSinceReferenceDate):\(identity)",
            title: localizedString("Weather Data Missing", locale: locale),
            message: Array(Set(messages)).sorted().joined(separator: "\n")
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Planning cards retain their structure through first load,
                // empty-library, partial-data, and failure states. Their own
                // fallback content explains why weather values are absent.
                BestSunnyDatesCard(
                    summaries: dateSummaries,
                    selectedDate: $selectedDate,
                    presentationState: forecastPresentationState
                )

                BestSunnyPlacesCard(
                    recommendations: recommendationAssessment.recommendations,
                    savedPlaces: model.placesStore.allPlaces,
                    presentationState: forecastPresentationState
                )

                VStack(spacing: 0) {
                    if let timeZoneExclusionNotice {
                        WeatherTimeZoneFootnote(text: timeZoneExclusionNotice)
                    }

                    // The dashboard stays focused on planning. Renaming and
                    // deleting places live in the pushed Saved Places manager.
                    NavigationLink(value: AppRoute.savedPlacesLibrary) {
                        libraryLink
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Manage Saved Places"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(theme.colors.background)
        // A navigation title remains plain text. A custom leading toolbar item
        // is rendered as a circular glass control on iOS 26.
        .navigationTitle("Saved Places")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // This is intentionally the same shared root date binding used by
            // Your Location, Map, and detail charts.
            ToolbarItem(placement: .topBarTrailing) {
                TopForecastDateSwitcher(
                    selection: $selectedDate,
                    availableDates: ForecastDateHorizon.dates(in: model.forecastCalendar)
                )
            }
        }
        .refreshable {
            await model.loadSavedWeather(forceRefresh: true, locale: locale)
        }
        .reportingMissingData(
            missingDataReport,
            recoveryKey: "saved-places-systemic-weather",
            retrying: {
                await model.loadSavedWeather(forceRefresh: true, locale: locale)
            }
        )
        // ContentView owns initial hydration and foreground freshness checks.
        // Re-entering this tab must only read that shared state; launching a
        // second load here used to rebuild and visibly reshuffle the ranking.
    }

    private var libraryLink: some View {
        // Keep the dashboard action compact and visibly actionable while
        // maintaining Apple's 44-point minimum touch target.
        HStack(spacing: 5) {
            Text("Manage Saved Places")
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(theme.colors.primaryText)
        .padding(.horizontal, 18)
        .frame(minHeight: 44)
        .background(.thinMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(theme.colors.secondaryText.opacity(0.18), lineWidth: 0.8)
        )
        .contentShape(Capsule())
    }
}
