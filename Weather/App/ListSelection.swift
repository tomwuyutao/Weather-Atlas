//
//  ListSelection.swift
//  Weather
//
//  Purpose: Bridges persisted city lists into app-level selection state and
//  keeps list switching consistent across toolbars, sheets, and shortcuts.
//

import Foundation

// MARK: - Available Lists

extension ContentView {
    var managedLists: [CityListID] {
        weatherService.availableLists
    }

    func refreshListOrder() {
        weatherService.reloadAvailableLists()
    }

    // MARK: List Selection

    func switchToList(_ listID: CityListID) async {
        guard listID.rawValue != weatherService.activeListID.rawValue else { return }
        await weatherService.switchList(to: listID)
        centerMapOnDots(useListCoordinates: true)
    }
}
