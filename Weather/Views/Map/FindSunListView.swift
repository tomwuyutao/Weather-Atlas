//
//  FindSunListView.swift
//  Weather
//
//  Purpose: Adapts one temporary Map Find Sun candidate set to the same
//  comparison screen used by the persistent Saved Places library.
//

import SwiftUI

// MARK: - Map Query Comparison Route

struct FindSunListView: View {
  let title: String
  let candidateCities: [City]
  @Bindable var model: WeatherModel
  @Bindable var router: AppNavigation
  @Binding var selectedDate: Date

  var body: some View {
    PlacesComparisonView(
      source: .mapQuery(title: title, cities: candidateCities),
      model: model,
      router: router,
      selectedDate: $selectedDate
    )
  }
}

#if DEBUG

  extension FindSunListView {
    /// A model-backed preview keeps the shared Day, Weekend, and Outlook logic
    /// active without reading persistence or making WeatherKit requests.
    @MainActor
    init(results: [MapSunSearchResult], title: String) {
      let placesStore = SavedPlacesStore(
        inMemoryDocument: .empty
      )
      let connectivity = NetworkConnectivity()
      let weatherStore = SavedPlacesWeatherStore(
        weatherService: WeatherService(),
        cache: PlaceWeatherSnapshotCache(fileURL: nil),
        networkConnectivity: connectivity
      )
      for result in results {
        let weather = result.recommendation.cityWeather
        weatherStore.weatherByID[weather.id] = weather
        weatherStore.refreshDatesByPlaceID[weather.id] = .now
        weatherStore.weatherRevision &+= 1
        weatherStore.scheduleCacheExpiry()
      }
      let previewModel = WeatherModel(
        placesStore: placesStore,
        weatherStore: weatherStore,
        locationProvider: LocationProvider(),
        recentSearches: RecentSearchStore(inMemoryCities: []),
        initialHomeLocation: nil
      )
      let previewDate =
        results.first?
        .recommendation.cityWeather.dailyForecasts.first?.date ?? .now

      self.init(
        title: title,
        candidateCities: results.map(\.recommendation.cityWeather.city),
        model: previewModel,
        router: AppNavigation(),
        selectedDate: .constant(previewDate)
      )
    }
  }

  #Preview("Find Sun List", traits: .fixedLayout(width: 390, height: 700)) {
    NavigationStack {
      FindSunListView(
        results: [
          ("Rome", "Italy", 12.0),
          ("Naples", "Italy", 10.0),
          ("Palermo", "Italy", 9.0),
          ("Bari", "Italy", 8.0),
          ("San Valentino in Abruzzo Citeriore", "Italy", 7.0),
        ].map { name, country, sunnyHours in
          let city = City(
            name: name,
            country: country,
            latitude: 41.9,
            longitude: 12.5,
            timeZoneIdentifier: "Europe/Rome"
          )
          let forecast = DailyForecast(
            date: Date(timeIntervalSince1970: 1_786_233_600),
            dailyLow: 18,
            dailyHigh: 30,
            symbolName: "sun.max.fill",
            condition: AppWeatherCondition(rawValue: "clear"),
            hourlyForecasts: [],
            cloudCover: 0.1,
            precipitationChance: 0,
            uvIndex: 7,
            sunrise: nil,
            sunset: nil
          )
          let weather = CityWeather(
            city: city,
            dailyForecasts: [forecast],
            timeZone: TimeZone(identifier: "Europe/Rome")!
          )
          return MapSunSearchResult(
            recommendation: PlaceRecommendation(
              cityWeather: weather,
              symbolName: forecast.symbolName,
              condition: forecast.condition,
              sunnyHourCount: sunnyHours
            )
          )
        },
        title: "Italy"
      )
      .environment(NetworkConnectivity())
      .environment(\.appTheme, .shared)
    }
  }

  #Preview("Find Sun List Empty", traits: .fixedLayout(width: 390, height: 700)) {
    NavigationStack {
      FindSunListView(
        results: [],
        title: "United Kingdom"
      )
      .environment(NetworkConnectivity())
      .environment(\.appTheme, .shared)
    }
  }

#endif
