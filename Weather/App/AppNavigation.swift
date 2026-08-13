//
//  AppNavigation.swift
//  Weather
//
//  Purpose: Owns native tab selection, independent navigation histories, and
//  lightweight modal destinations for the redesigned app shell.
//

import Foundation
import Observation

// MARK: - Navigation Values

/// The four top-level destinations. `search` uses the system search-tab role,
/// while the other cases are visible in the regular tab bar.
enum AppTab: Hashable {
    case yourLocation
    case savedPlaces
    case map
    case search
}

/// Values pushed inside a tab's own `NavigationStack`.
///
/// Routes deliberately hold IDs rather than full models. This lets a detail
/// screen resolve the freshest saved-place and weather data after a refresh.
enum AppRoute: Hashable {
    case place(id: City.ID)
    case savedPlacesLibrary
}

// MARK: - Modal Values

/// Root-level sheets. An enum keeps mutually exclusive presentations in one
/// source of truth instead of coordinating several Boolean flags.
enum AppSheetDestination: Identifiable, Hashable {
    case settings

    var id: String {
        switch self {
        case .settings:
            "settings"
        }
    }
}

// MARK: - Shared Router

/// Main-actor observable navigation state shared by the root tab shell.
///
/// SwiftUI observes individual stored properties here, so a view updates only
/// when it reads the particular selection, path, or presentation that changes.
@MainActor
@Observable
final class AppNavigation {
    /// Currently visible top-level tab. The app opens on local weather.
    var selectedTab: AppTab = .yourLocation
    /// Separate paths preserve back-stack history as the person switches tabs.
    var yourLocationPath: [AppRoute] = []
    var savedPlacesPath: [AppRoute] = []
    var mapPath: [AppRoute] = []
    var searchPath: [AppRoute] = []
    /// Optional enum drives the single root `.sheet(item:)` modifier.
    var presentedSheet: AppSheetDestination?
    /// Saved-place annotation Map should center or select after navigation.
    var selectedMapPlaceID: City.ID?
    /// An unsaved search result that Map presents with the same floating card
    /// language as a Find Sun result.
    var mapPreviewCity: City?
    /// A country or continent query handed to Map from the Search tab. The
    /// companion token makes repeated selections of the same scope distinct.
    var pendingMapSunQuery: MapSunQueryScope?
    var mapSunQueryToken = 0
    /// Precomputed local-weather recommendations handed from Home to Map.
    /// Keeping these avoids repeating the WeatherKit search after tab switch.
    var nearbyMapResults: [NearestSunnyPlaceResult] = []
    /// Monotonic trigger Map observes even when the next result array matches
    /// the previous array exactly.
    var nearbyMapToken = 0

    /// Selects Map and optionally tells it which saved or temporary place to
    /// focus. The actual camera work remains owned by `MapView`.
    func showMap(placeID: City.ID? = nil, previewing city: City? = nil) {
        selectedMapPlaceID = placeID
        mapPreviewCity = city
        pendingMapSunQuery = nil
        selectedTab = .map
    }

    /// Sends a geographic Find Sun scope to Map, which remains the sole owner
    /// of candidate selection, weather loading, ranking, and result display.
    func showMap(findingSunIn scope: MapSunQueryScope) {
        // A country or continent choice must reveal Map itself even when a
        // previous Map visit left a detail route on that tab's navigation path.
        // Otherwise the hand-off would run behind that detail screen.
        mapPath = []
        selectedMapPlaceID = nil
        mapPreviewCity = nil
        selectedTab = .map
        pendingMapSunQuery = scope
        mapSunQueryToken &+= 1
    }

    /// Moves the existing nearby-sun result set to Map without fetching it
    /// again, then increments the request token so Map applies the hand-off.
    func showNearbyOnMap(_ results: [NearestSunnyPlaceResult]) {
        pendingMapSunQuery = nil
        nearbyMapResults = results
        nearbyMapToken &+= 1
        selectedTab = .map
    }

    /// Opens the full saved-city manager from an external entry point such as
    /// a widget, map empty state, or Home Screen quick action.
    func showPlacesLibrary() {
        selectedTab = .savedPlaces
        savedPlacesPath = [.savedPlacesLibrary]
    }
}
