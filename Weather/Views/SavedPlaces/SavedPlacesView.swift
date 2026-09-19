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

  /// The dashboard retains its established preference, while Map results use
  /// a separate key so changing either screen cannot mutate the other.
  @AppStorage private var storedModeRawValue: String
  /// Map results are themselves a Boolean navigation destination. Keeping
  /// their child Detail route local prevents the root path from replacing
  /// that destination, so Back returns to the comparison list.
  @State private var mapDetailPlaceID: City.ID?
  /// Mirrors the Detail screens: the compact navigation title appears only
  /// after Saved Places' large in-content mode title scrolls out of view.
  @State private var showsLargeTitle = true

  @Environment(\.appTheme) private var theme
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.locale) private var locale
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(NetworkConnectivity.self) private var networkConnectivity

  init(
    source: PlacesComparisonSource,
    model: WeatherModel,
    router: AppNavigation,
    selectedDate: Binding<Date>
  ) {
    self.source = source
    self.model = model
    self.router = router
    _selectedDate = selectedDate
    _storedModeRawValue = AppStorage(
      wrappedValue: SavedPlacesViewMode.defaultRawValue,
      source.isSavedPlaces
        ? SavedPlacesViewMode.storageKey
        : SavedPlacesViewMode.mapResultsStorageKey
    )
  }

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

  // MARK: - Shared Forecast Dates

  private var comparisonForecastDates: [Date] {
    let calendar = model.forecastCalendar
    var dates = Set<Date>()

    for place in comparisonPlaces {
      guard let weather = model.weatherStore.weather(for: place.id) else {
        continue
      }

      for forecast in weather.dailyForecasts {
        let date =
          weather.selectionDate(
            for: forecast,
            selectionCalendar: calendar
          ) ?? calendar.startOfDay(for: forecast.date)
        dates.insert(calendar.startOfDay(for: date))
      }
    }

    return dates.sorted()
  }

  /// Day mode shares the global selection with every other app surface.

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

      for forecast in weather.dailyForecasts
      where
        cityCalendar.startOfDay(for: forecast.date) >= localToday
      {
        let data = SunnyHoursCalculation.sunnyHoursData(
          for: forecast,
          timeZone: weather.timeZone
        )
        guard !data.hours.isEmpty else { continue }

        let date =
          weather.selectionDate(
            for: forecast,
            selectionCalendar: calendar
          ) ?? calendar.startOfDay(for: forecast.date)
        dates.insert(calendar.startOfDay(for: date))
      }
    }

    let forecastDates = dates.sorted()
    return forecastDates.isEmpty
      ? (0..<10).compactMap {
        calendar.date(
          byAdding: .day,
          value: $0,
          to: calendar.startOfDay(for: Date())
        )
      }
      : forecastDates
  }

  /// Today is part of the weekend when it is Saturday. Opening the screen on
  /// Sunday targets the following weekend instead of showing a half weekend.
  private var weekendDates: (saturday: Date, sunday: Date) {
    let calendar = model.forecastCalendar
    let today = calendar.startOfDay(for: .now)
    let weekday = calendar.component(.weekday, from: today)
    let daysUntilSaturday = (7 - weekday + 7) % 7
    let saturday =
      calendar.date(
        byAdding: .day,
        value: daysUntilSaturday,
        to: today
      ) ?? today
    let sunday =
      calendar.date(
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
        )
      else {
        return nil
      }
      guard
        !SunnyHoursCalculation.sunnyHoursData(
          for: forecast,
          timeZone: weather.timeZone
        ).hours.isEmpty
      else {
        return nil
      }
      return model.placeRecommendation(for: weather, on: date)
    }

    return PlaceRecommendation.ranked(recommendations, locale: locale)
  }

  private var loadingPlaceIDs: Set<City.ID> {
    Set(
      comparisonPlaces.compactMap { place in
        if model.weatherStore.isLoading(place.id) {
          return place.id
        }
        if forecastPresentationState == .loading,
          model.weatherStore.weather(for: place.id) == nil,
          model.weatherStore.failuresByID[place.id] == nil
        {
          return place.id
        }
        return nil
      })
  }

  // MARK: - Outlook Ranking

  private var sunnyOutlooks: [ForecastComparisonSunnyOutlook] {
    let referenceDate = Date.now
    let outlooks = comparisonPlaces.map { place in
      let status: ForecastComparisonSunnyOutlook.Status
      let navigationDate: Date

      if let weather = model.weatherStore.weather(for: place.id) {
        let fallbackDate =
          firstOutlookSelectionDate(
            for: weather,
            onOrAfter: referenceDate
          )
          ?? ({ (date: Date, timeZone: TimeZone) in
            var cityCalendar = model.forecastCalendar
            cityCalendar.timeZone = timeZone
            let components = cityCalendar.dateComponents(
              [.year, .month, .day],
              from: date
            )
            return model.forecastCalendar.date(from: components)
              ?? model.forecastCalendar.startOfDay(for: date)
          })(referenceDate, weather.timeZone)
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
          status =
            loadingPlaceIDs.contains(place.id)
            ? .loading
            : .unavailable
          navigationDate = fallbackDate
        }
      } else if loadingPlaceIDs.contains(place.id) {
        status = .loading
        navigationDate =
          ({ (date: Date, timeZone: TimeZone) in
            var cityCalendar = model.forecastCalendar
            cityCalendar.timeZone = timeZone
            let components = cityCalendar.dateComponents(
              [.year, .month, .day],
              from: date
            )
            return model.forecastCalendar.date(from: components)
              ?? model.forecastCalendar.startOfDay(for: date)
          })(
            referenceDate,
            place.city.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
              ?? model.forecastCalendar.timeZone)
      } else {
        status = .unavailable
        navigationDate =
          ({ (date: Date, timeZone: TimeZone) in
            var cityCalendar = model.forecastCalendar
            cityCalendar.timeZone = timeZone
            let components = cityCalendar.dateComponents(
              [.year, .month, .day],
              from: date
            )
            return model.forecastCalendar.date(from: components)
              ?? model.forecastCalendar.startOfDay(for: date)
          })(
            referenceDate,
            place.city.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
              ?? model.forecastCalendar.timeZone)
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

  /// Carries a city-local literal day into the shared forecast calendar.

  // MARK: - Loading State

  private var forecastPresentationState: SavedPlacesForecastPresentationState {
    if source.isSavedPlaces,
      model.placesStore.loadErrorDescription != nil
    {
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
      let topPadding =
        UIDevice.current.userInterfaceIdiom == .phone
          && !dynamicTypeSize.isAccessibilitySize
        ? min(52, max(8, geometry.size.height * 0.055))
        : 8

      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 20) {
            modeHeader

            modeList

            if source.isSavedPlaces {
              (NavigationLink(value: AppRoute.savedPlacesLibrary) {
                SecondaryTextActionLabel(
                  title: "Manage Saved Places",
                  systemImage: "chevron.right"
                )
              }
              .buttonStyle(.plain))
            }
          }
          .padding(.horizontal, 16)
          .padding(.top, topPadding)
          .padding(.bottom, 24)
          .frame(
            maxWidth: horizontalSizeClass == .regular
              && geometry.size.width > geometry.size.height
              ? min(
                IPadLayout.standardMaximumWidth,
                IPadLayout.landscapeMaximumWidth
              )
              : IPadLayout.standardMaximumWidth
          )
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
    .navigationTitle(
      ({
        switch source {
        case .savedPlaces:
          localizedString("Saved Places", locale: locale)
        case .mapQuery(let title, _):
          title
        }
      })()
    )
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if source.isSavedPlaces {
        // Keep this item mounted while scrolling. Changing only its
        // opacity avoids rebuilding the toolbar preference structure.
        ToolbarItem(placement: .principal) {
          Text(
            ({
              switch source {
              case .savedPlaces:
                localizedString("Saved Places", locale: locale)
              case .mapQuery(let title, _):
                title
              }
            })()
          )
          .lineLimit(1)
          .opacity(showsLargeTitle ? 0 : 1)
        }

        ToolbarItem(placement: .topBarLeading) {
          Button("Settings", systemImage: "slider.horizontal.3") {
            router.isSettingsPresented = true
          }
          .labelStyle(.iconOnly)
        }
      }

      ToolbarItem(placement: .topBarTrailing) {
        TopForecastDateSwitcher(
          selection: $selectedDate,
          availableDates: ({
            let calendar = model.forecastCalendar
            let sourceDates =
              comparisonForecastDates.isEmpty
              ? (0..<10).compactMap {
                calendar.date(
                  byAdding: .day,
                  value: $0,
                  to: calendar.startOfDay(for: Date())
                )
              }
              : comparisonForecastDates

            return Array(
              Set(
                (sourceDates + [selectedDate]).map(calendar.startOfDay(for:))
              )
            )
            .sorted()
          })(),
          display: dateSwitcherDisplay,
          staticRangeHorizontalPadding: selectedMode == .outlook ? 6 : 0
        )
      }
    }
    .refreshable {
      switch source {
      case .savedPlaces:
        await model.weatherStore.load(
          cities: model.placesStore.allPlaces.map(\.city),
          forceRefresh: true
        )
        let resolvedCities = model.placesStore.allPlaces.compactMap { place in
          model.weatherStore.weather(for: place.id)?.city
        }.filter(PlacesLibraryValidator.isValidCity)
        _ = try? model.placesStore.savePlaces(resolvedCities)
      case .mapQuery:
        await model.weatherStore.load(
          cities: comparisonPlaces.map(\.city),
          forceRefresh: true
        )
      }
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

  // MARK: - Mode Content

  @ViewBuilder
  private var modeList: some View {
    switch selectedMode {
    case .day:
      BestSunnyPlacesCard(
        recommendations: (assessedRecommendations(on: selectedDate)),
        places: comparisonPlaces,
        loadingPlaceIDs: loadingPlaceIDs,
        presentationState: forecastPresentationState,
        statusMessages: (source.isSavedPlaces ? .savedPlaces : .mapQuery),
        onSelect: { placeID in
          openComparisonPlace(placeID, on: selectedDate)
        }
      )
    case .weekend:
      BestWeekendEscapeCard(
        saturdayDate: weekendDates.saturday,
        sundayDate: weekendDates.sunday,
        saturdayRows: ((ForecastComparisonWeekendDayRanking.ranked(
          places: comparisonPlaces,
          recommendations: (assessedRecommendations(on: selectedDate)),
          loadingPlaceIDs: loadingPlaceIDs,
          locale: locale
        ))),
        sundayRows: ((ForecastComparisonWeekendDayRanking.ranked(
          places: comparisonPlaces,
          recommendations: (assessedRecommendations(on: selectedDate)),
          loadingPlaceIDs: loadingPlaceIDs,
          locale: locale
        ))),
        presentationState: forecastPresentationState,
        statusMessages: (source.isSavedPlaces ? .savedPlaces : .mapQuery),
        onSelect: openComparisonPlace
      )
    case .outlook:
      SunnyOutlookByPlaceCard(
        rows: sunnyOutlooks,
        presentationState: forecastPresentationState,
        statusMessages: (source.isSavedPlaces ? .savedPlaces : .mapQuery),
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
        Spacer(minLength: 0)

        Menu {
          ForEach(SavedPlacesViewMode.allCases) { mode in
            Button {
              storedModeRawValue = mode.rawValue
            } label: {
              HStack {
                Text(
                  {
                    switch mode {
                    case .day: "Best Sunny Places"
                    case .weekend: "Best Weekend Escape"
                    case .outlook: "Next Sunny Day"
                    }
                  }())
                if mode == selectedMode {
                  Image(systemName: "checkmark")
                }
              }
            }
          }
        } label: {
          DetailStyleReportMenuLabel(
            title: {
              var title: LocalizedStringResource = {
                switch selectedMode {
                case .day: "Best Sunny Places"
                case .weekend: "Best Weekend Escape"
                case .outlook: "Next Sunny Day"
                }
              }()
              title.locale = locale
              return String(localized: title)
            }(),
            style: .compact
          )
        }
        .buttonStyle(.plain)

        Spacer(minLength: 0)
      }

      Text(
        {
          switch selectedMode {
          case .day:
            "Places ranked by daytime sunny hours on the selected day."
          case .weekend:
            "Places ranked by daytime sunny hours this weekend."
          case .outlook:
            "Next day with sunshine for at least 80% of daytime hours."
          }
        }()
      )
      .font(.body)
      .foregroundStyle(theme.colors.secondaryText)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 4)
    .padding(.bottom, 4)
    .onScrollVisibilityChange(threshold: 0.01) { isVisible in
      guard source.isSavedPlaces,
        showsLargeTitle != isVisible
      else {
        return
      }
      showsLargeTitle = isVisible
    }
  }

}
