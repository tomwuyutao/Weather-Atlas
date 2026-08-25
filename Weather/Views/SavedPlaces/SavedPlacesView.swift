//
//  SavedPlacesView.swift
//  Weather
//
//  Purpose: Presents saved-place planning and comparisons, with the full
//  editable library available as a pushed destination rather than a peer tab.
//

import SwiftUI
import UIKit

// MARK: - Forecast Presentation State

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

#if DEBUG

// MARK: - Preview

#Preview("Saved Places View") {
    SavedPlacesViewRoutePreview()
}
#endif

// MARK: - Planning Dashboard

/// Planning dashboard for cities the person explicitly saved.
struct SavedPlacesView: View {
    // MARK: - Shared Inputs

    @Bindable var model: WeatherModel
    @Bindable var router: AppNavigation
    @Binding var selectedDate: Date

    @Environment(\.appTheme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // MARK: - Derived Planning Data

    private var recommendations: [PlaceRecommendation] {
        model.savedRecommendations(
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
                let date = weather.selectionDate(
                    for: forecast,
                    selectionCalendar: calendar
                ) ?? calendar.startOfDay(for: forecast.date)
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
            let recommendations = model.savedRecommendations(
                on: date,
                locale: locale
            )

            // A calendar summary exists only for concrete recommendations.
            // This prevents an unexpected recommendation gap from being displayed
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
        let excludedCityCount = dateExclusions.count
        guard excludedCityCount > 0 else { return nil }

        // Keep the count inside the localized resource so String Catalog plural
        // rules can select singular, plural, and language-specific forms.
        var resource: LocalizedStringResource =
            "\(excludedCityCount) cities excluded due to time zone differences."
        resource.locale = locale
        return String(localized: resource)
    }

    /// Preserve the established phone and portrait layout. A full-width
    /// landscape iPad gets a more focused planning column with generous space
    /// on either side of the two comparison cards.
    private func contentWidth(for size: CGSize) -> CGFloat {
        AppContentLayout.maximumWidth(
            for: size,
            horizontalSizeClass: horizontalSizeClass
        )
    }

    // MARK: - Presentation

    var body: some View {
        GeometryReader { geometry in
            let usesLandscapeIPadSplit = LandscapeReportLayout.usesSplit(
                for: geometry.size
            )
            let topPadding = detailStyleTitleTopPadding(
                for: geometry.size,
                dynamicTypeSize: dynamicTypeSize
            )

            if usesLandscapeIPadSplit {
                planningLayout(
                    usesLandscapeIPadSplit: true,
                    landscapeContentWidth: geometry.size.width - 32,
                    landscapeContentHeight: geometry.size.height - topPadding - 24
                )
                .padding(.horizontal, 16)
                .padding(.top, topPadding)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    planningLayout(
                        usesLandscapeIPadSplit: false,
                        landscapeContentWidth: 0,
                        landscapeContentHeight: 0
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, topPadding)
                    .padding(.bottom, 24)
                    .frame(maxWidth: contentWidth(for: geometry.size))
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .scrollIndicators(.hidden)
        .background(theme.colors.background)
        // A navigation title remains plain text. A custom leading toolbar item
        // is rendered as a circular glass control on iOS 26.
        .navigationTitle("Saved Places")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The shared large in-content heading is the visible Saved Places
            // title. Reserve the compact toolbar slot without duplicating it,
            // matching Detail View and Your Location.
            ToolbarItem(placement: .principal) {
                Text("Saved Places")
                    .lineLimit(1)
                    .opacity(0)
            }

            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "slider.horizontal.3") {
                    router.presentedSheet = .settings
                }
                .labelStyle(.iconOnly)
            }

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
        // ContentView owns initial hydration and foreground freshness checks.
        // Re-entering this tab must only read that shared state; launching a
            // second load here used to rebuild and visibly reshuffle the ranking.
    }

    // MARK: - Adaptive Layout

    @ViewBuilder
    private func planningLayout(
        usesLandscapeIPadSplit: Bool,
        landscapeContentWidth: CGFloat,
        landscapeContentHeight: CGFloat
    ) -> some View {
        if usesLandscapeIPadSplit {
            let splitWidth = max(0, landscapeContentWidth - 20)
            let leftColumnWidth = splitWidth * 0.4
            let rightColumnWidth = splitWidth - leftColumnWidth
            let rightColumnContentInset: CGFloat = 80

            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 0) {
                    savedPlacesTitle

                    Spacer(minLength: 0)

                    BestSunnyDatesCard(
                        summaries: dateSummaries,
                        selectedDate: $selectedDate,
                        presentationState: forecastPresentationState
                    )
                }
                .frame(height: landscapeContentHeight, alignment: .top)
                .frame(width: leftColumnWidth, alignment: .top)
                // Match Detail View's visual balance against the right column's
                // large reading inset without changing the 40/60 split.
                .offset(x: rightColumnContentInset / 2)

                ScrollView {
                    LazyVStack(spacing: 20) {
                        BestSunnyPlacesCard(
                            recommendations: recommendations,
                            savedPlaces: model.placesStore.allPlaces,
                            presentationState: forecastPresentationState,
                            timeZoneExclusionNotice: timeZoneExclusionNotice
                        )

                        // The dashboard stays focused on planning. Renaming and
                        // deleting places live in the pushed Saved Places manager.
                        manageSavedPlacesLink
                    }
                    .padding(.horizontal, rightColumnContentInset)
                    .frame(width: rightColumnWidth, alignment: .top)
                }
                .scrollIndicators(.hidden)
                .hidesLandscapePaneScrollEdgeEffects()
                .scrollClipDisabled()
                .frame(height: landscapeContentHeight)
                .frame(width: rightColumnWidth, alignment: .top)
            }
        } else {
            LazyVStack(spacing: 20) {
                savedPlacesTitle

                BestSunnyDatesCard(
                    summaries: dateSummaries,
                    selectedDate: $selectedDate,
                    presentationState: forecastPresentationState
                )

                BestSunnyPlacesCard(
                    recommendations: recommendations,
                    savedPlaces: model.placesStore.allPlaces,
                    presentationState: forecastPresentationState,
                    timeZoneExclusionNotice: timeZoneExclusionNotice
                )

                manageSavedPlacesLink
            }
        }
    }

    /// The planning dashboard uses the same in-content heading treatment as
    /// every Detail View, independent of device, orientation, or platform.
    private var savedPlacesTitle: some View {
        DetailStyleReportTitle(
            title: localizedString("Saved Places", locale: locale)
        )
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .padding(.bottom, 4)
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
