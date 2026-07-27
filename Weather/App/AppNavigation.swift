//
//  AppNavigation.swift
//  Weather
//
//  Purpose: Defines navigation destinations and the route-stack operations
//  shared by Home, List, Detail, Map, search, and generated-list previews.
//

import SwiftUI

// MARK: - Destinations

/// Every destination that can be stored in the root `NavigationStack` path.
enum AppNavigationRoute: Hashable {
    case map
    case list
    case cityDetail(CityWeather)
    case listPreview
}

// MARK: - Root Navigation Stack

extension ContentView {
    /// Builds the shared navigation stack and maps route values to screens.
    var appNavigationStack: some View {
        NavigationStack(path: $navigationPath) {
            homeView
                .navigationDestination(for: AppNavigationRoute.self) { route in
                    switch route {
                    case .map:
                        fullMapDestination
                    case .list:
                        fullListDestination
                    case .cityDetail(let city):
                        cityDetailView(for: city)
                    case .listPreview:
                        listPreviewDestination
                    }
                }
        }
    }
}

// MARK: - Current Destination

extension ContentView {
    /// The route currently visible above Home, if any.
    var currentRoute: AppNavigationRoute? {
        navigationPath.last
    }

    /// Whether the full-screen map is the active destination.
    var isMapRoute: Bool {
        currentRoute == .map
    }

}

// MARK: - Route Operations

extension ContentView {
    /// Pushes a route while preventing duplicate singleton destinations.
    func pushRoute(_ route: AppNavigationRoute) {
        if route == .list || route == .listPreview {
            isMapCardPresented = false
        }
        if case .cityDetail = route {
            navigationPath.append(route)
            return
        }
        guard !navigationPath.contains(route) else { return }
        navigationPath.append(route)
    }

    /// Reveals the existing Map route or pushes it when it is not in the path.
    func navigateToMap() {
        guard let mapIndex = navigationPath.lastIndex(of: .map) else {
            pushRoute(.map)
            return
        }

        let routesAboveMap = navigationPath.count - mapIndex - 1
        if routesAboveMap > 0 {
            navigationPath.removeLast(routesAboveMap)
        }
    }

    /// Closes any map card and opens the requested saved-city detail report.
    func presentDetail(for city: CityWeather) {
        isMapCardPresented = false
        pushRoute(.cityDetail(city))
    }

    /// Opens the selected ranked city in its detail report or focuses its map
    /// marker, depending on the surface that initiated the selection.
    func selectCandidate(_ candidate: SunnyCandidate, focusMap: Bool = true) {
        let city = candidate.cityWeather
        if focusMap {
            pushRoute(.map)
            centerMap(on: city)
            showMapMarkerCard(city)
        } else {
            presentDetail(for: city)
        }
    }

    /// Switches to the city's owning list before revealing its map marker.
    /// The map only renders fetched data from the active list, so this ordering
    /// is an invariant rather than a presentation delay.
    func revealCityOnMap(_ city: CityWeather, in listID: CityListID) {
        Task {
            await switchToList(listID)
            guard let revealedCity = weatherService.cityWeatherData.first(where: {
                weatherService.citiesMatch($0.city, city.city)
            }) else {
                weatherService.reportDeveloperWarning(
                    title: "Map Reveal Failed",
                    message: "After switching to \(listID.rawValue), the requested city \(city.city.localizedName()) was not found in fetched weather data."
                )
                return
            }
            pushRoute(.map)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                isMapCardPresented = false
                selectedMapCity = nil
            }
            centerMap(on: revealedCity)
            showMapMarkerCard(revealedCity)
        }
    }

    /// Removes a particular destination and performs its feature cleanup.
    func popRoute(_ route: AppNavigationRoute) {
        guard navigationPath.contains(route) else { return }
        if navigationPath.last == route {
            navigationPath.removeLast()
        } else {
            navigationPath.removeAll { $0 == route }
        }
        cleanupAfterLeavingRoute(route)
    }

    /// Clears transient state that must not leak into a later visit.
    func cleanupAfterLeavingRoute(_ route: AppNavigationRoute) {
        switch route {
        case .map:
            isMapCardPresented = false
            selectedMapCity = nil
        case .list:
            listEditMode = false
        case .cityDetail:
            break
        case .listPreview:
            clearGeneratedListPreview()
        }
    }
}
