//
//  AppRouter.swift
//  Weather
//
//  Purpose: Owns native tab selection, independent navigation histories, and
//  lightweight modal destinations for the redesigned app shell.
//

import Foundation
import Observation

enum AppTab: Hashable {
    case home
    case places
    case search
}

enum PlacesViewMode: String, CaseIterable, Identifiable, Hashable {
    case list
    case map

    var id: Self { self }
}

enum AppRoute: Hashable {
    case place(id: City.ID, date: Date)
    case collections
}

enum AppSheetDestination: Identifiable, Hashable {
    case addPlace(collectionID: PlaceCollection.ID?)
    case createCollection(placeID: SavedPlace.ID?)
    case nearbyDiscovery
    case settings

    var id: String {
        switch self {
        case .addPlace(let collectionID):
            "add-place-\(collectionID ?? "all")"
        case .createCollection(let placeID):
            "create-collection-\(placeID?.uuidString ?? "empty")"
        case .nearbyDiscovery:
            "nearby-discovery"
        case .settings:
            "settings"
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var homePath: [AppRoute] = []
    var placesPath: [AppRoute] = []
    var searchPath: [AppRoute] = []
    var presentedSheet: AppSheetDestination?
    var placesViewMode: PlacesViewMode = .list
    var selectedCollectionID: PlaceCollection.ID?
    var selectedMapPlaceID: City.ID?

    func showPlace(id: City.ID, date: Date) {
        let route = AppRoute.place(id: id, date: date)
        switch selectedTab {
        case .home:
            homePath.append(route)
        case .places:
            placesPath.append(route)
        case .search:
            searchPath.append(route)
        }
    }

    func showPlaceOnMap(id: City.ID, collectionID: PlaceCollection.ID? = nil) {
        selectedCollectionID = collectionID
        selectedMapPlaceID = id
        placesViewMode = .map
        selectedTab = .places
    }

    func showPlaces(
        mode: PlacesViewMode = .list,
        collectionID: PlaceCollection.ID? = nil
    ) {
        selectedCollectionID = collectionID
        placesViewMode = mode
        selectedTab = .places
    }
}
