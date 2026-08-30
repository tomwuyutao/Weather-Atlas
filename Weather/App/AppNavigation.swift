//
//  AppNavigation.swift
//  Weather
//
//  Purpose: Owns native tab selection, independent navigation histories, and
//  lightweight modal destinations for the current app shell.
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

/// The three result modes available from the Search tab. Keeping this value in
/// the app-session router lets Search restore the person's last mode whenever
/// its tab content is remounted, without persisting it across app launches.
enum PlaceSearchScope: String, CaseIterable, Identifiable {
    case city
    case country
    case continent

    var id: Self { self }
}

/// Values pushed inside a tab's own `NavigationStack`.
///
/// Routes deliberately hold IDs rather than full models. This lets a detail
/// screen resolve the freshest saved-place and weather data after a refresh.
enum AppRoute: Hashable {
    case place(id: City.ID)
    case savedPlacesLibrary
}

/// One-shot Find Sun navigation payload. The forecast date travels with the
/// geographic scope so Map can apply the exact originating selection before it
/// starts ranking results, while `ContentView` remains the single date owner.
struct MapSunHandoff: Equatable {
    let scope: MapSunQueryScope
    let selectedDate: Date
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
    /// Search restores this scope for the lifetime of the current app session.
    var placeSearchScope: PlaceSearchScope = .city
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
    /// A Find Sun request handed to Map from another tab. The companion token
    /// makes repeated selections of the same scope and date distinct.
    var pendingMapSunHandoff: MapSunHandoff?
    var mapSunQueryToken = 0
    /// Every external Map request receives a fresh generation. Map consumes
    /// this before showing the new marker, preview, or Find Sun scope, so a
    /// prior session's card or asynchronous query cannot mask the hand-off.
    var mapHandoffToken = 0

    /// Selects Map and optionally tells it which saved or temporary place to
    /// focus. A targeted hand-off first returns the Map tab to its root, so a
    /// preview can never appear behind a previously pushed detail view. A
    /// destination-free call simply reopens the current Map session.
    func showMap(placeID: City.ID? = nil, previewing city: City? = nil) {
        // Destination-free navigation reopens the existing Map session. In
        // particular, a Home Screen Map shortcut must not silently clear a
        // completed Find Sun query whose summary owns its explicit close.
        guard placeID != nil || city != nil else {
            mapPath = []
            selectedTab = .map
            return
        }

        beginMapHandoff()
        selectedMapPlaceID = placeID
        mapPreviewCity = city
        selectedTab = .map
    }

    /// Sends a geographic Find Sun scope to Map, which remains the sole owner
    /// of candidate selection, weather loading, ranking, and result display.
    func showMap(findingSunIn scope: MapSunQueryScope, on selectedDate: Date) {
        beginMapHandoff()
        pendingMapSunHandoff = MapSunHandoff(
            scope: scope,
            selectedDate: selectedDate
        )
        mapSunQueryToken &+= 1
        selectedTab = .map
    }

    /// Clears routing values which belong to the previous Map session. The
    /// caller establishes its replacement target immediately afterward and
    /// Map observes the generation to cancel any in-flight presentation state.
    private func beginMapHandoff() {
        mapPath = []
        selectedMapPlaceID = nil
        mapPreviewCity = nil
        pendingMapSunHandoff = nil
        mapHandoffToken &+= 1
    }

    /// Opens the Search tab at its root rather than restoring a previous
    /// pushed result. Empty-state calls to action should always begin at the
    /// place-search screen where the person can start a new query.
    func showSearchRoot() {
        searchPath = []
        selectedTab = .search
    }

    /// Opens the full saved-city manager from an external entry point such as
    /// a widget, map empty state, or Home Screen quick action.
    func showPlacesLibrary() {
        selectedTab = .savedPlaces
        savedPlacesPath = [.savedPlacesLibrary]
    }

    /// Discards every transient Map hand-off during a full app reset. Advancing
    /// both generations also makes a still-mounted Map session drop any
    /// in-flight preview or Find Sun work before the new library appears.
    func resetMapHandoffState() {
        mapPath = []
        selectedMapPlaceID = nil
        mapPreviewCity = nil
        pendingMapSunHandoff = nil
        mapSunQueryToken &+= 1
        mapHandoffToken &+= 1
    }
}
