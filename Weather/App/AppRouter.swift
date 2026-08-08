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
    case currentLocation
    case place(id: City.ID)
}

enum AppSheetDestination: Identifiable, Hashable {
    case settings

    var id: String {
        switch self {
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
    var selectedMapPlaceID: City.ID?
    /// An unsaved search result that Map presents with the same floating card
    /// language as a Find Sun result.
    var mapPreviewCity: City?

    func showMap(placeID: City.ID? = nil, previewing city: City? = nil) {
        selectedMapPlaceID = placeID
        mapPreviewCity = city
        selectedTab = .map
    }

    func showPlaces() {
        selectedTab = .places
    }
}
