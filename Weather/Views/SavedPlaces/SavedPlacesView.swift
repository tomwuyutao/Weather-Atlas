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

/// Shared presentation state for Saved Places planning cards.
///
/// The state changes only their explanatory fallback content. Any available
/// recommendations continue to use the established ranking paths.
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

private enum SavedPlacesSheet: String, Identifiable {
    case customize

    var id: String { rawValue }
}

/// Planning dashboard for cities the person explicitly saved.
struct SavedPlacesView: View {
    // MARK: - Shared Inputs

    @Bindable var model: WeatherModel
    @Bindable var router: AppNavigation
    @Binding var selectedDate: Date

    @State private var presentedSheet: SavedPlacesSheet?
    @AppStorage(SavedPlacesDashboardSection.storageKey)
    private var storedDashboardSectionOrder =
        SavedPlacesDashboardSection.defaultStorageValue
    @AppStorage(SavedPlacesSelectedDayCard.storageKey)
    private var storedSelectedDayCardOrder =
        SavedPlacesSelectedDayCard.defaultStorageValue
    @AppStorage(SavedPlacesPlanAheadCard.storageKey)
    private var storedPlanAheadCardOrder =
        SavedPlacesPlanAheadCard.defaultStorageValue

    @Environment(\.appTheme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(NetworkConnectivity.self) private var networkConnectivity

    // MARK: - Derived Planning Data

    private var recommendations: [PlaceRecommendation] {
        model.savedRecommendations(
            on: selectedDate,
            locale: locale
        )
    }

    private var orderedDashboardSections: [SavedPlacesDashboardSection] {
        SavedPlacesDashboardSection.order(
            from: storedDashboardSectionOrder
        )
    }

    private var orderedSelectedDayCards: [SavedPlacesSelectedDayCard] {
        SavedPlacesSelectedDayCard.order(
            from: storedSelectedDayCardOrder
        )
    }

    private var orderedPlanAheadCards: [SavedPlacesPlanAheadCard] {
        SavedPlacesPlanAheadCard.order(
            from: storedPlanAheadCardOrder
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

    /// The next weekend starts with today when the dashboard is opened on a
    /// Saturday; on Sunday it advances to the following weekend. These dates
    /// stay independent from the selected-day switcher.
    private var weekendDates: (saturday: Date, sunday: Date) {
        let calendar = model.forecastCalendar
        let today = calendar.startOfDay(for: .now)
        let weekday = calendar.component(.weekday, from: today)
        let daysUntilSaturday = (7 - weekday + 7) % 7
        let saturday = calendar.date(
            byAdding: .day,
            value: daysUntilSaturday,
            to: today
        ) ?? today
        let sunday = calendar.date(
            byAdding: .day,
            value: 1,
            to: saturday
        ) ?? saturday
        return (saturday, sunday)
    }

    private var saturdayRecommendations: [PlaceRecommendation] {
        model.savedRecommendations(
            on: weekendDates.saturday,
            locale: locale
        )
    }

    private var sundayRecommendations: [PlaceRecommendation] {
        model.savedRecommendations(
            on: weekendDates.sunday,
            locale: locale
        )
    }

    /// Every saved place remains represented, even while different WeatherKit
    /// requests settle at different times. A loaded place searches its own
    /// local forecast days and maps the first qualifying date back into the
    /// shared selector calendar.
    private var sunnyOutlooks: [SavedPlaceSunnyOutlook] {
        let outlooks = model.placesStore.allPlaces.map { place in
            let status: SavedPlaceSunnyOutlook.Status

            if let weather = model.weatherStore.weather(for: place.id) {
                switch weather.mostlySunnyForecastSearch(
                    onOrAfter: .now,
                    selectionCalendar: model.forecastCalendar
                ) {
                case .match(_, let selectionDate):
                    status = .date(selectionDate)
                case .noMatch:
                    status = .noMatch
                case .unavailable:
                    status = .unavailable
                }
            } else if model.weatherStore.isLoading(place.id)
                        || (forecastPresentationState == .loading
                            && model.weatherStore.failuresByID[place.id] == nil) {
                status = .loading
            } else {
                status = .unavailable
            }

            return SavedPlaceSunnyOutlook(
                place: place,
                status: status
            )
        }

        return SavedPlaceSunnyOutlook.ranked(outlooks)
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

        // A retained snapshot remains useful offline. Without one, confirmed
        // offline is a settled unavailable state rather than imaginary loading.
        if networkConnectivity.isOffline {
            return places.contains(where: {
                model.weatherStore.weather(for: $0.id) != nil
            }) ? .ready : .unavailable
        }

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
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .customize:
                CustomizeSavedPlaces()
            }
        }
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
        landscapeContentHeight: CGFloat
    ) -> some View {
        if usesLandscapeIPadSplit {
            VStack(spacing: 20) {
                savedPlacesTitle

                HStack(alignment: .top, spacing: 20) {
                    ForEach(orderedDashboardSections) { section in
                        ScrollView {
                            LazyVStack(spacing: 20) {
                                planningSection(section)

                                if section == orderedDashboardSections.last {
                                    manageSavedPlacesLink
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                        .scrollIndicators(.hidden)
                        .hidesLandscapePaneScrollEdgeEffects()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: landscapeContentHeight, alignment: .top)
        } else {
            LazyVStack(spacing: 20) {
                savedPlacesTitle

                ForEach(orderedDashboardSections) { section in
                    planningSection(section)
                }

                manageSavedPlacesLink
            }
        }
    }

    private func planningSection(
        _ section: SavedPlacesDashboardSection
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            switch section {
            case .selectedDay:
                selectedDayCards
            case .planAhead:
                planAheadCards
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var selectedDayCards: some View {
        ForEach(orderedSelectedDayCards) { card in
            switch card {
            case .bestSunnyPlaces:
                BestSunnyPlacesCard(
                    recommendations: recommendations,
                    selectedDate: selectedDate,
                    savedPlaces: model.placesStore.allPlaces,
                    presentationState: forecastPresentationState,
                    timeZoneExclusionNotice: timeZoneExclusionNotice
                )
            }
        }
    }

    @ViewBuilder
    private var planAheadCards: some View {
        ForEach(orderedPlanAheadCards) { card in
            switch card {
            case .bestWeekendEscape:
                BestWeekendEscapeCard(
                    saturdayDate: weekendDates.saturday,
                    sundayDate: weekendDates.sunday,
                    saturdayRecommendations: saturdayRecommendations,
                    sundayRecommendations: sundayRecommendations,
                    savedPlaces: model.placesStore.allPlaces,
                    presentationState: forecastPresentationState,
                    onSelect: { placeID, date in
                        openPlanAheadPlace(placeID, on: date)
                    }
                )
            case .sunnyOutlookByPlace:
                SunnyOutlookByPlaceCard(
                    rows: sunnyOutlooks,
                    presentationState: forecastPresentationState,
                    onSelect: { placeID, date in
                        openPlanAheadPlace(placeID, on: date)
                    }
                )
            }
        }
    }

    private func openPlanAheadPlace(
        _ placeID: SavedPlace.ID,
        on date: Date?
    ) {
        if let date {
            selectedDate = model.forecastCalendar.startOfDay(for: date)
        }
        router.savedPlacesPath.append(.place(id: placeID))
    }

    /// The planning dashboard uses the same in-content heading treatment as
    /// every Detail View, independent of device, orientation, or platform.
    private var savedPlacesTitle: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 34)

            Menu {
                Button(
                    "Customize Saved Places",
                    systemImage: "arrow.up.arrow.down"
                ) {
                    presentedSheet = .customize
                }
            } label: {
                DetailStyleReportMenuLabel(
                    title: localizedString("Saved Places", locale: locale)
                )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 34)
        }
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
