//
//  PreviewFixtures.swift
//  Weather
//
//  Purpose: Supplies isolated, deterministic data for route-level Xcode
//  previews without reading persistence or making WeatherKit requests.
//

#if DEBUG
import Foundation
import SwiftUI

// MARK: - Deterministic Preview Data

/// Builds one in-memory London forecast and the dependency graph shared by
/// route-level previews, keeping every Canvas host fast and deterministic.
@MainActor
enum WeatherPreviewFixtures {
    // MARK: - Fixed Geography and Date

    static let timeZone = TimeZone(identifier: "Europe/London")!

    static let london = City(
        id: UUID(uuidString: "A3815252-7114-4D1D-AD29-0A162553236E")!,
        name: "London",
        country: "United Kingdom",
        latitude: 51.5072,
        longitude: -0.1276,
        timeZoneIdentifier: timeZone.identifier,
        catalogIdentifier: "preview-london"
    )

    static var selectedDate: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.startOfDay(for: .now)
    }

    // MARK: - Preview Dependencies

    static func model() -> WeatherModel {
        let placesStore = SavedPlacesStore(
            inMemoryDocument: PlacesLibraryDocument(
                places: [SavedPlace(city: london)]
            )
        )
        let connectivity = NetworkConnectivity()
        let weatherStore = SavedPlacesWeatherStore.preview(
            networkConnectivity: connectivity
        )
        weatherStore.insertPreviewWeather(weather(for: london))

        return WeatherModel(
            placesStore: placesStore,
            weatherStore: weatherStore,
            locationProvider: LocationProvider(),
            recentSearches: RecentSearchStore(inMemoryCities: []),
            initialHomeLocation: nil
        )
    }

    static func router() -> AppNavigation {
        AppNavigation()
    }

    // MARK: - Forecast Fixtures

    private static func weather(for city: City) -> CityWeather {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let firstDay = calendar.startOfDay(for: .now)
        let forecasts = (0..<10).compactMap { dayOffset -> DailyForecast? in
            guard let day = calendar.date(
                byAdding: .day,
                value: dayOffset,
                to: firstDay
            ),
            let sunrise = calendar.date(byAdding: .hour, value: 6, to: day),
            let sunset = calendar.date(byAdding: .hour, value: 20, to: day) else {
                return nil
            }

            let hourlyForecasts = (0..<24).compactMap { hour -> HourlyForecast? in
                guard let date = calendar.date(byAdding: .hour, value: hour, to: day) else {
                    return nil
                }
                let isDaylight = (6..<20).contains(hour)
                let isSunny = (9..<17).contains(hour)
                return HourlyForecast(
                    date: date,
                    symbolName: isSunny ? "sun.max.fill" : "cloud.fill",
                    condition: AppWeatherCondition(
                        rawValue: isSunny ? "clear" : "cloudy"
                    ),
                    isDaylight: isDaylight,
                    temperature: 14 + Double(hour % 7),
                    apparentTemperature: 14 + Double(hour % 7),
                    cloudCover: isSunny ? 0.1 : 0.7,
                    precipitationChance: isSunny ? 0 : 0.2,
                    uvIndex: isDaylight ? 4 : 0,
                    visibilityKilometers: 18
                )
            }

            return DailyForecast(
                date: day,
                dailyLow: 12,
                dailyHigh: 21,
                symbolName: "sun.max.fill",
                condition: AppWeatherCondition(rawValue: "clear"),
                hourlyForecasts: hourlyForecasts,
                cloudCover: 0.25,
                precipitationChance: 0.1,
                uvIndex: 5,
                sunrise: sunrise,
                sunset: sunset
            )
        }
        return CityWeather(
            city: city,
            dailyForecasts: forecasts,
            currentWeather: CurrentWeatherPresentation(
                date: .now,
                symbolName: "sun.max.fill",
                condition: AppWeatherCondition(rawValue: "clear")
            ),
            timeZone: timeZone
        )
    }
}

// MARK: - Route-Level Preview Hosts

struct DetailViewRoutePreview: View {
    @State private var selectedDate = WeatherPreviewFixtures.selectedDate
    @State private var model = WeatherPreviewFixtures.model()

    var body: some View {
        NavigationStack {
            DetailView(
                placeID: WeatherPreviewFixtures.london.id,
                selectedDate: $selectedDate,
                model: model,
                router: WeatherPreviewFixtures.router()
            )
        }
        .environment(\.appTheme, .shared)
    }
}

struct MapViewRoutePreview: View {
    @State private var selectedDate = WeatherPreviewFixtures.selectedDate
    @State private var model = WeatherPreviewFixtures.model()
    @State private var router = WeatherPreviewFixtures.router()

    var body: some View {
        NavigationStack {
            MapView(
                model: model,
                router: router,
                selectedDate: $selectedDate
            )
        }
        .environment(\.appTheme, .shared)
        .environment(MissingDataAlertCenter())
    }
}

struct SavedPlacesViewRoutePreview: View {
    @State private var selectedDate = WeatherPreviewFixtures.selectedDate
    @State private var model = WeatherPreviewFixtures.model()
    @State private var router = WeatherPreviewFixtures.router()

    var body: some View {
        NavigationStack {
            SavedPlacesView(
                model: model,
                router: router,
                selectedDate: $selectedDate
            )
        }
        .environment(\.appTheme, .shared)
    }
}

struct ManageSavedPlacesRoutePreview: View {
    @State private var model = WeatherPreviewFixtures.model()
    @State private var router = WeatherPreviewFixtures.router()

    var body: some View {
        NavigationStack {
            ManageSavedPlaces(
                placesStore: model.placesStore,
                router: router
            )
        }
        .environment(\.appTheme, .shared)
    }
}

#endif
