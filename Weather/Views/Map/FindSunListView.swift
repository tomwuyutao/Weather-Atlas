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
        let weatherStore = SavedPlacesWeatherStore.preview(
            networkConnectivity: connectivity
        )
        for result in results {
            weatherStore.insertPreviewWeather(
                result.recommendation.cityWeather
            )
        }
        let previewModel = WeatherModel(
            placesStore: placesStore,
            weatherStore: weatherStore,
            locationProvider: LocationProvider(),
            recentSearches: RecentSearchStore(inMemoryCities: []),
            initialHomeLocation: nil
        )
        let previewDate = results.first?
            .recommendation.cityWeather.dailyForecasts.first?.date ?? .now

        self.init(
            title: title,
            candidateCities: results.map(\.city),
            model: previewModel,
            router: AppNavigation(),
            selectedDate: .constant(previewDate)
        )
    }
}

#Preview("Find Sun List", traits: .fixedLayout(width: 390, height: 700)) {
    NavigationStack {
        FindSunListView(
            results: MapSunResultsPreviewData.results,
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
