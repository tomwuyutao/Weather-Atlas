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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
        model.savedRecommendationAssessment(
            on: selectedDate,
            locale: locale
        )
    }

    /// Places where the selected literal date has already passed stay visible
    /// as exclusions instead of silently disappearing from the page.
    private var dateExclusions: [SavedPlaceDateExclusion] {
        model.savedPlaceDateExclusions(on: selectedDate)
    }

    /// Every literal selector day backed by at least one saved city's retained
    /// daily forecast. Forecasts are stored in each city's local time zone, so
    /// convert them into the shared location-calendar day before comparing or
    /// presenting them.
    private var savedForecastDates: [Date] {
        let calendar = model.forecastCalendar
        var dates = Set<Date>()

        for place in model.placesStore.allPlaces {
            guard let weather = model.weatherStore.weather(for: place.id) else {
                continue
            }

            for forecast in weather.dailyForecasts {
                guard let date = weather.selectionDate(
                    for: forecast,
                    selectionCalendar: calendar
                ) else {
                    continue
                }
                dates.insert(calendar.startOfDay(for: date))
            }
        }

        return dates.sorted()
    }

    /// Keep the global day intact when this tab opens from another surface.
    /// Once weather arrives, every real daily forecast date remains selectable,
    /// even when no place is sunny on that date.
    private var dateSwitcherDates: [Date] {
        let calendar = model.forecastCalendar
        let sourceDates = savedForecastDates.isEmpty
            ? ForecastDateHorizon.dates(in: calendar)
            : savedForecastDates

        return Array(
            Set(
                (sourceDates + [selectedDate]).map(calendar.startOfDay(for:))
            )
        )
        .sorted()
    }

    private var dateSummaries: [BestSunnyDateSummary] {
        return savedForecastDates.compactMap { date in
            let assessment = model.savedRecommendationAssessment(
                on: date,
                locale: locale
            )
            let excludedIDs = Set(
                model.savedPlaceDateExclusions(on: date).map(\.id)
            )
            let recommendations = assessment.recommendations.filter {
                !excludedIDs.contains($0.id)
            }

            // A calendar summary exists only for concrete recommendations.
            // This prevents an unexpected assessment gap from being displayed
            // as an apparently factual zero-sun day.
            guard !recommendations.isEmpty else { return nil }

            let averageSunnyHours = recommendations.map(\.sunnyHourCount)
                .reduce(0, +) / Double(recommendations.count)
            return BestSunnyDateSummary(
                date: date,
                averageSunnyHours: averageSunnyHours
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
        guard !dateExclusions.isEmpty else { return nil }
        return localizedString(
            "Excluded due to time zone differences.",
            locale: locale
        )
    }

    /// Feature-local checks may report a settled missing input without rejecting
    /// the city's otherwise usable forecast. A date already passed in the
    /// destination's timezone is expected, so it remains a quiet footer only.
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
            // contrast, can be assessed immediately by the consuming feature.
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

    /// Preserve the established phone and portrait layout. A full-width
    /// landscape iPad gets a more focused planning column with generous space
    /// on either side of the two comparison cards.
    private func contentWidth(for size: CGSize) -> CGFloat {
        guard horizontalSizeClass == .regular, size.width > size.height else {
            return 760
        }
        return 640
    }

    var body: some View {
        GeometryReader { geometry in
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
                    presentationState: forecastPresentationState,
                    timeZoneExclusionNotice: timeZoneExclusionNotice
                )

                // The dashboard stays focused on planning. Renaming and
                // deleting places live in the pushed Saved Places manager.
                manageSavedPlacesLink
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: contentWidth(for: geometry.size))
                .frame(maxWidth: .infinity)
            }
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
                    availableDates: dateSwitcherDates
                )
            }
        }
        .refreshable {
            await model.loadSavedWeather(forceRefresh: true)
        }
        .reportingMissingData(
            missingDataReport,
            recoveryKey: "saved-places-systemic-weather",
            retrying: {
                await model.loadSavedWeather(forceRefresh: true)
            }
        )
        // ContentView owns initial hydration and foreground freshness checks.
        // Re-entering this tab must only read that shared state; launching a
        // second load here used to rebuild and visibly reshuffle the ranking.
    }

    /// A quiet footer link shares Place Detail's secondary text-action style
    /// rather than competing with the forecast cards as another capsule.
    private var manageSavedPlacesLink: some View {
        NavigationLink(value: AppRoute.savedPlacesLibrary) {
            SecondaryTextActionLabel(
                title: "Manage Saved Places",
                systemImage: "chevron.right"
            )
        }
        .buttonStyle(.plain)

    }
}
