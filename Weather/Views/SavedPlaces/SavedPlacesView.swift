//
//  SavedPlacesView.swift
//  Weather
//
//  Purpose: Presents one supplied set of places through three focused lenses:
//  a selected day, the next weekend, or the forecast outlook. Saved Places
//  and Map Find Sun both adapt their own data to this shared screen.
//

import SwiftUI
import UIKit

// MARK: - Forecast Presentation State

/// Shared presentation state for Saved Places and Find Sun planning lists.
enum SavedPlacesForecastPresentationState: Equatable {
    case emptyLibrary
    case loading
    case unavailable
    case ready
}

/// A neutral place identity used by both persistent Saved Places and temporary
/// Map query results. Weather remains keyed by the original city UUID even when
/// a semantic saved match supplies the display name.
struct ForecastComparisonPlace: Identifiable, Equatable {
    let city: City
    let displayName: String

    var id: City.ID { city.id }
}

/// Source-specific fallback copy keeps the shared cards truthful without
/// forking their layout or loading-state behavior.
struct PlaceComparisonStatusMessages {
    let empty: LocalizedStringResource
    let loading: LocalizedStringResource
    let unavailable: LocalizedStringResource
    let noDateComparison: LocalizedStringResource
    let noPeriodForecasts: LocalizedStringResource

    static let savedPlaces = PlaceComparisonStatusMessages(
        empty: "Save a place to compare sunny hours.",
        loading: "Loading place forecasts…",
        unavailable: "Place forecasts are unavailable.",
        noDateComparison: "No sunny-hour comparison is available for this date.",
        noPeriodForecasts: "No place forecasts are available for this period."
    )

    static let mapQuery = PlaceComparisonStatusMessages(
        empty: "No places are available for this search.",
        loading: "Loading place forecasts…",
        unavailable: "Place forecasts are unavailable.",
        noDateComparison: "No sunny-hour comparison is available for this date.",
        noPeriodForecasts: "No place forecasts are available for this period."
    )
}

/// Only the data source and route chrome differ between Saved Places and a Map
/// query. The comparison calculations and visible modes remain identical.
enum PlacesComparisonSource {
    case savedPlaces
    case mapQuery(title: String, cities: [City])

    var isSavedPlaces: Bool {
        if case .savedPlaces = self { return true }
        return false
    }

}

#if DEBUG

// MARK: - Preview

#Preview("Saved Places View") {
    SavedPlacesViewRoutePreview()
}
#endif

// MARK: - Saved Places Route

struct SavedPlacesView: View {
    @Bindable var model: WeatherModel
    @Bindable var router: AppNavigation
    @Binding var selectedDate: Date

    var body: some View {
        PlacesComparisonView(
            source: .savedPlaces,
            model: model,
            router: router,
            selectedDate: $selectedDate
        )
    }
}

// MARK: - Shared Place Comparison

struct PlacesComparisonView: View {
    private static let scrollTopID = "places-comparison-mode-title"

    let source: PlacesComparisonSource
    @Bindable var model: WeatherModel
    @Bindable var router: AppNavigation
    @Binding var selectedDate: Date

    @AppStorage(SavedPlacesViewMode.storageKey)
    private var storedModeRawValue = SavedPlacesViewMode.defaultRawValue
    /// Map results are themselves a Boolean navigation destination. Keeping
    /// their child Detail route local prevents the root path from replacing
    /// that destination, so Back returns to the comparison list.
    @State private var mapDetailPlaceID: City.ID?

    @Environment(\.appTheme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(NetworkConnectivity.self) private var networkConnectivity

    // MARK: - Mode

    private var selectedMode: SavedPlacesViewMode {
        SavedPlacesViewMode(rawValue: storedModeRawValue) ?? .day
    }

    private var comparisonPlaces: [ForecastComparisonPlace] {
        switch source {
        case .savedPlaces:
            return model.placesStore.allPlaces.map { place in
                ForecastComparisonPlace(
                    city: place.city,
                    displayName: place.localizedDisplayName(locale: locale)
                )
            }
        case .mapQuery(_, let cities):
            var seenIDs: Set<City.ID> = []
            return cities.compactMap { city in
                guard seenIDs.insert(city.id).inserted else { return nil }

                let savedDisplayName = model.placesStore
                    .savedPlaceID(matching: city)
                    .flatMap { model.placesStore.place(id: $0) }?
                    .localizedDisplayName(locale: locale)
                return ForecastComparisonPlace(
                    city: city,
                    displayName: savedDisplayName
                        ?? city.localizedDisplayName(locale: locale)
                )
            }
        }
    }

    private var statusMessages: PlaceComparisonStatusMessages {
        source.isSavedPlaces ? .savedPlaces : .mapQuery
    }

    // MARK: - Shared Forecast Dates

    private var comparisonForecastDates: [Date] {
        let calendar = model.forecastCalendar
        var dates = Set<Date>()

        for place in comparisonPlaces {
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

    /// Day mode shares the global selection with every other app surface.
    private var dateSwitcherDates: [Date] {
        let calendar = model.forecastCalendar
        let sourceDates = comparisonForecastDates.isEmpty
            ? ForecastDateHorizon.dates(in: calendar)
            : comparisonForecastDates

        return Array(
            Set(
                (sourceDates + [selectedDate]).map(calendar.startOfDay(for:))
            )
        )
        .sorted()
    }

    private var outlookForecastDates: [Date] {
        let calendar = model.forecastCalendar
        let referenceDate = Date.now
        var dates = Set<Date>()

        // Outlook searches from each city's local Today. Build the displayed
        // range from that same domain so a far-west city cannot produce a row
        // dated one literal day before the toolbar's lower bound.
        for place in comparisonPlaces {
            guard let weather = model.weatherStore.weather(for: place.id) else {
                continue
            }

            var cityCalendar = calendar
            cityCalendar.timeZone = weather.timeZone
            let localToday = cityCalendar.startOfDay(for: referenceDate)

            for forecast in weather.dailyForecasts where
                cityCalendar.startOfDay(for: forecast.date) >= localToday {
                let data = SunnyHoursCalculation.sunnyHoursData(
                    for: forecast,
                    timeZone: weather.timeZone
                )
                guard !data.hours.isEmpty else { continue }

                let date = weather.selectionDate(
                    for: forecast,
                    selectionCalendar: calendar
                ) ?? calendar.startOfDay(for: forecast.date)
                dates.insert(calendar.startOfDay(for: date))
            }
        }

        let forecastDates = dates.sorted()
        return forecastDates.isEmpty
            ? ForecastDateHorizon.dates(in: calendar)
            : forecastDates
    }

    /// Today is part of the weekend when it is Saturday. Opening the screen on
    /// Sunday targets the following weekend instead of showing a half weekend.
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

    private var dateSwitcherDisplay: TopForecastDateSwitcher.Display {
        switch selectedMode {
        case .day:
            return .selectedDate
        case .weekend:
            return .staticRange(
                start: weekendDates.saturday,
                end: weekendDates.sunday
            )
        case .outlook:
            let dates = outlookForecastDates
            let fallback = model.forecastCalendar.startOfDay(for: .now)
            return .staticRange(
                start: dates.first ?? fallback,
                end: dates.last ?? fallback
            )
        }
    }

    // MARK: - Day Ranking

    private var recommendations: [PlaceRecommendation] {
        assessedRecommendations(on: selectedDate)
    }

    // MARK: - Weekend Ranking

    private var saturdayRecommendations: [PlaceRecommendation] {
        assessedRecommendations(on: weekendDates.saturday)
    }

    private var sundayRecommendations: [PlaceRecommendation] {
        assessedRecommendations(on: weekendDates.sunday)
    }

    /// A daily shell without daylight capsules cannot truthfully receive a
    /// zero-hour rank. Omit that settled result from every comparison mode.
    private func assessedRecommendations(
        on date: Date
    ) -> [PlaceRecommendation] {
        let recommendations: [PlaceRecommendation] = comparisonPlaces.compactMap {
            place -> PlaceRecommendation? in
            guard let weather = model.weatherStore.weather(for: place.id),
                  let forecast = weather.forecastIfAvailable(
                    on: date,
                    selectionCalendar: model.forecastCalendar
                  ) else {
                return nil
            }
            guard !SunnyHoursCalculation.sunnyHoursData(
                for: forecast,
                timeZone: weather.timeZone
            ).hours.isEmpty else {
                return nil
            }
            return model.placeRecommendation(for: weather, on: date)
        }

        return PlaceRecommendation.ranked(recommendations, locale: locale)
    }

    private var loadingPlaceIDs: Set<City.ID> {
        Set(comparisonPlaces.compactMap { place in
            if model.weatherStore.isLoading(place.id) {
                return place.id
            }
            if forecastPresentationState == .loading,
               model.weatherStore.weather(for: place.id) == nil,
               model.weatherStore.failuresByID[place.id] == nil {
                return place.id
            }
            return nil
        })
    }

    private var saturdayWeekendRows: [ForecastComparisonWeekendDayRanking] {
        weekendRows(recommendations: saturdayRecommendations)
    }

    private var sundayWeekendRows: [ForecastComparisonWeekendDayRanking] {
        weekendRows(recommendations: sundayRecommendations)
    }

    private func weekendRows(
        recommendations: [PlaceRecommendation]
    ) -> [ForecastComparisonWeekendDayRanking] {
        ForecastComparisonWeekendDayRanking.ranked(
            places: comparisonPlaces,
            recommendations: recommendations,
            loadingPlaceIDs: loadingPlaceIDs,
            locale: locale
        )
    }

    // MARK: - Outlook Ranking

    private var sunnyOutlooks: [ForecastComparisonSunnyOutlook] {
        let referenceDate = Date.now
        let outlooks = comparisonPlaces.map { place in
            let status: ForecastComparisonSunnyOutlook.Status
            let navigationDate: Date

            if let weather = model.weatherStore.weather(for: place.id) {
                let fallbackDate = firstOutlookSelectionDate(
                    for: weather,
                    onOrAfter: referenceDate
                ) ?? localSelectionDate(
                    for: referenceDate,
                    timeZone: weather.timeZone
                )
                switch weather.mostlySunnyForecastSearch(
                    onOrAfter: referenceDate,
                    selectionCalendar: model.forecastCalendar
                ) {
                case .match(_, let selectionDate):
                    status = .date(selectionDate)
                    navigationDate = selectionDate
                case .noMatch:
                    status = .noMatch
                    navigationDate = fallbackDate
                case .unavailable:
                    status = loadingPlaceIDs.contains(place.id)
                        ? .loading
                        : .unavailable
                    navigationDate = fallbackDate
                }
            } else if loadingPlaceIDs.contains(place.id) {
                status = .loading
                navigationDate = localSelectionDate(
                    for: referenceDate,
                    timeZone: placeTimeZone(for: place)
                )
            } else {
                status = .unavailable
                navigationDate = localSelectionDate(
                    for: referenceDate,
                    timeZone: placeTimeZone(for: place)
                )
            }

            return ForecastComparisonSunnyOutlook(
                place: place,
                status: status,
                navigationDate: navigationDate
            )
        }

        return ForecastComparisonSunnyOutlook.ranked(outlooks).filter { outlook in
            if case .unavailable = outlook.status {
                return false
            }
            return true
        }
    }

    private func firstOutlookSelectionDate(
        for weather: CityWeather,
        onOrAfter referenceDate: Date
    ) -> Date? {
        var cityCalendar = model.forecastCalendar
        cityCalendar.timeZone = weather.timeZone
        let localToday = cityCalendar.startOfDay(for: referenceDate)

        return weather.dailyForecasts
            .filter {
                cityCalendar.startOfDay(for: $0.date) >= localToday
            }
            .sorted { $0.date < $1.date }
            .compactMap { forecast -> Date? in
                let data = SunnyHoursCalculation.sunnyHoursData(
                    for: forecast,
                    timeZone: weather.timeZone
                )
                guard !data.hours.isEmpty else { return nil }
                return weather.selectionDate(
                    for: forecast,
                    selectionCalendar: model.forecastCalendar
                )
            }
            .first
    }

    private func placeTimeZone(
        for place: ForecastComparisonPlace
    ) -> TimeZone {
        place.city.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? model.forecastCalendar.timeZone
    }

    /// Carries a city-local literal day into the shared forecast calendar.
    private func localSelectionDate(
        for date: Date,
        timeZone: TimeZone
    ) -> Date {
        var cityCalendar = model.forecastCalendar
        cityCalendar.timeZone = timeZone
        let components = cityCalendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        return model.forecastCalendar.date(from: components)
            ?? model.forecastCalendar.startOfDay(for: date)
    }

    // MARK: - Loading State

    private var forecastPresentationState: SavedPlacesForecastPresentationState {
        if source.isSavedPlaces,
           model.placesStore.loadErrorDescription != nil {
            return .unavailable
        }

        let places = comparisonPlaces
        guard !places.isEmpty else { return .emptyLibrary }

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

        return .loading
    }

    // MARK: - Presentation

    var body: some View {
        GeometryReader { geometry in
            let topPadding = detailStyleTitleTopPadding(
                for: geometry.size,
                dynamicTypeSize: dynamicTypeSize
            )

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        modeHeader

                        modeList

                        if source.isSavedPlaces {
                            manageSavedPlacesLink
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, topPadding)
                    .padding(.bottom, 24)
                    .frame(maxWidth: contentWidth(for: geometry.size))
                    .frame(maxWidth: .infinity)
                    // Target the padded container rather than the title so a
                    // mode switch preserves its intentional top breathing room.
                    .id(Self.scrollTopID)
                }
                .scrollIndicators(.hidden)
                .onChange(of: storedModeRawValue) { _, _ in
                    // A mode switch is a direct navigation change. Reset the
                    // list without motion so Reduce Motion needs no exception.
                    proxy.scrollTo(Self.scrollTopID, anchor: .top)
                }
            }
        }
        .background(theme.colors.background)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if source.isSavedPlaces {
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
            }

            ToolbarItem(placement: .topBarTrailing) {
                TopForecastDateSwitcher(
                    selection: $selectedDate,
                    availableDates: dateSwitcherDates,
                    display: dateSwitcherDisplay,
                    staticRangeHorizontalPadding: selectedMode == .outlook ? 6 : 0
                )
            }
        }
        .refreshable {
            await refreshForecasts()
        }
        .navigationDestination(item: $mapDetailPlaceID) { placeID in
            DetailView(
                placeID: placeID,
                selectedDate: $selectedDate,
                model: model,
                router: router
            )
        }
    }

    private var navigationTitle: String {
        switch source {
        case .savedPlaces:
            localizedString("Saved Places", locale: locale)
        case .mapQuery(let title, _):
            title
        }
    }

    private func refreshForecasts() async {
        switch source {
        case .savedPlaces:
            await model.loadSavedWeather(forceRefresh: true)
        case .mapQuery:
            await model.weatherStore.load(
                cities: comparisonPlaces.map(\.city),
                forceRefresh: true
            )
        }
    }

    private func contentWidth(for size: CGSize) -> CGFloat {
        AppContentLayout.maximumWidth(
            for: size,
            horizontalSizeClass: horizontalSizeClass
        )
    }

    // MARK: - Mode Content

    @ViewBuilder
    private var modeList: some View {
        switch selectedMode {
        case .day:
            BestSunnyPlacesCard(
                recommendations: recommendations,
                places: comparisonPlaces,
                loadingPlaceIDs: loadingPlaceIDs,
                presentationState: forecastPresentationState,
                statusMessages: statusMessages,
                onSelect: { placeID in
                    openComparisonPlace(placeID, on: selectedDate)
                }
            )
        case .weekend:
            BestWeekendEscapeCard(
                saturdayDate: weekendDates.saturday,
                sundayDate: weekendDates.sunday,
                saturdayRows: saturdayWeekendRows,
                sundayRows: sundayWeekendRows,
                presentationState: forecastPresentationState,
                statusMessages: statusMessages,
                onSelect: openComparisonPlace
            )
        case .outlook:
            SunnyOutlookByPlaceCard(
                rows: sunnyOutlooks,
                presentationState: forecastPresentationState,
                statusMessages: statusMessages,
                onSelect: { placeID, date in
                    openComparisonPlace(placeID, on: date)
                }
            )
        }
    }

    private func openComparisonPlace(
        _ placeID: City.ID,
        on date: Date?
    ) {
        if let date {
            selectedDate = model.forecastCalendar.startOfDay(for: date)
        }

        guard let place = comparisonPlaces.first(where: { $0.id == placeID }) else {
            return
        }

        switch source {
        case .savedPlaces:
            router.savedPlacesPath.append(.place(id: placeID))
        case .mapQuery:
            if let savedPlaceID = model.placesStore.savedPlaceID(
                matching: place.city
            ) {
                mapDetailPlaceID = savedPlaceID
            } else {
                model.registerTransientCity(place.city)
                mapDetailPlaceID = placeID
            }
        }
    }

    private var modeHeader: some View {
        VStack(spacing: 9) {
            HStack(spacing: 0) {
                Spacer(minLength: 34)

                Menu {
                    ForEach(SavedPlacesViewMode.allCases) { mode in
                        Button {
                            storedModeRawValue = mode.rawValue
                        } label: {
                            HStack {
                                Text(mode.title)
                                if mode == selectedMode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    DetailStyleReportMenuLabel(
                        title: selectedMode.displayName(locale: locale)
                    )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 34)
            }

            Text(selectedMode.subtitle)
                .font(.body)
                .foregroundStyle(theme.colors.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

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
