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
    case place(id: City.ID)
}

enum AppSheetDestination: Identifiable, Hashable {
    case addPlaces
    case settings

    var id: String {
        switch self {
        case .addPlaces:
            "add-places"
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
    var presentedSheet: AppSheetDestination?
    var selectedMapPlaceID: City.ID?

    func showMap(placeID: City.ID? = nil) {
        selectedMapPlaceID = placeID
        selectedTab = .map
    }

    func showPlaces() {
        selectedTab = .places
    }
}
