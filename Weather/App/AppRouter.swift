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
    case map
    case places
    case search
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
    var mapPath: [AppRoute] = []
    var placesPath: [AppRoute] = []
    var searchPath: [AppRoute] = []
    var presentedSheet: AppSheetDestination?
    var selectedCollectionID: PlaceCollection.ID?
    var selectedMapPlaceID: City.ID?

    func showMap(
        collectionID: PlaceCollection.ID? = nil,
        placeID: City.ID? = nil
    ) {
        selectedCollectionID = collectionID
        selectedMapPlaceID = placeID
        selectedTab = .map
    }

    func showPlaces(
        collectionID: PlaceCollection.ID? = nil
    ) {
        selectedCollectionID = collectionID
        selectedTab = .places
    }
}
