//
//  AppNavigation.swift
//  Weather
//
//  Purpose: Defines navigation destinations and the route-stack operations
//  shared by Home, List, Detail, Map, search, and generated-list previews.
//

import SwiftUI

// MARK: - Destinations

enum AppNavigationRoute: Hashable {
    case map
    case list
    case cityDetail(CityWeather)
    case addCityDetail(CityWeather)
    case listPreview
}

// MARK: - Root Navigation Stack

extension ContentView {
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
                    case .addCityDetail(let city):
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
    var currentRoute: AppNavigationRoute? {
        navigationPath.last
    }

    var isMapRoute: Bool {
        currentRoute == .map
    }

    /// Detail routes use the displayed city's own forecast range in the shared
    /// date switcher. Other routes continue to use the active list's date union.
    var detailDateSwitcherCity: CityWeather? {
        switch currentRoute {
        case .cityDetail(let city), .addCityDetail(let city):
            return city
        default:
            return nil
        }
    }

    var addCityDetailCity: CityWeather? {
        guard case .addCityDetail(let city) = currentRoute else { return nil }
        return city
    }

    var isAddCityDetailRoute: Bool {
        addCityDetailCity != nil
    }

    /// The searched city currently eligible to be added, whether it is shown in
    /// the dedicated add-detail route or as a temporary card on the full map.
    var cityPendingAddition: CityWeather? {
        addCityDetailCity ?? citySearchState.temporaryMapCity
    }
}

// MARK: - Route Operations

extension ContentView {
    func pushRoute(_ route: AppNavigationRoute) {
        if route == .list || route == .listPreview {
            showingMapExpandedCard = false
        }
        if case .cityDetail = route {
            navigationPath.append(route)
            return
        }
        guard !navigationPath.contains(route) else { return }
        navigationPath.append(route)
    }

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

    func presentDetail(for city: CityWeather) {
        showingMapExpandedCard = false
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
                showingMapExpandedCard = false
                selectedMapCity = nil
            }
            centerMap(on: revealedCity)
            showMapMarkerCard(revealedCity)
        }
    }

    func popRoute(_ route: AppNavigationRoute) {
        guard navigationPath.contains(route) else { return }
        if navigationPath.last == route {
            navigationPath.removeLast()
        } else {
            navigationPath.removeAll { $0 == route }
        }
        cleanupAfterLeavingRoute(route)
    }

    func popCurrentRoute() {
        guard let route = navigationPath.popLast() else { return }
        cleanupAfterLeavingRoute(route)
    }

    private func cleanupAfterLeavingRoute(_ route: AppNavigationRoute) {
        switch route {
        case .map:
            showingMapExpandedCard = false
            selectedMapCity = nil
        case .list:
            listEditMode = false
        case .cityDetail, .addCityDetail:
            break
        case .listPreview:
            clearGeneratedListPreview()
        }
    }
}
