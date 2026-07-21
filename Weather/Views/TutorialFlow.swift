//
//  TutorialFlow.swift
//  Weather
//
//  Purpose: Owns onboarding selection state and the app-level actions that
//  convert tutorial choices into persisted city lists.
//

import Foundation

// MARK: - Presentation State

/// First-launch and replay selections owned by the tutorial flow.
struct TutorialPresentationState {
    var showsFirstLaunch = false
    var showsReplay = false
    var selectedContinentIDs: Set<String> = []
    var selectedCountryIDs: Set<String> = []
}

// MARK: - Tutorial List Selection

extension ContentView {
    var continentListTutorialLists: [CityListID] {
        CityListID.builtInLists
    }

    func prepareTutorialListSelection() {
        tutorialState.selectedContinentIDs = []
        tutorialState.selectedCountryIDs = []
    }

    func finishTutorialWithContinentList(_ listID: CityListID) async {
        tutorialState.selectedContinentIDs = [listID.rawValue]
        tutorialState.selectedCountryIDs = []
        await applyTutorialListSelectionAndLoad()
    }

    func finishTutorialWithCountryList(_ country: CountryListOption) async {
        tutorialState.selectedContinentIDs = []
        tutorialState.selectedCountryIDs = [country.id]
        await applyTutorialListSelectionAndLoad()
    }

    func applyTutorialListSelection() {
        Task {
            await applyTutorialListSelectionAndLoad()
        }
    }

    /// Replaces the built-in list selection, creates any selected country
    /// lists, and performs the first weather load before dismissing onboarding.
    func applyTutorialListSelectionAndLoad() async {
        let selectedContinentIDs = tutorialState.selectedContinentIDs
        let selectedCountryIDs = tutorialState.selectedCountryIDs
        guard !selectedContinentIDs.isEmpty || !selectedCountryIDs.isEmpty else { return }
        let selectedLists = CityListID.builtInLists.filter { selectedContinentIDs.contains($0.rawValue) }

        CityListID.keepBuiltInLists(withRawValues: selectedContinentIDs)
        refreshListOrder()
        navigationPath = []

        var firstList = selectedLists.first
        let selectedCountries = CountryCityCatalog.countries(locale: locale).filter {
            selectedCountryIDs.contains($0.id)
        }

        for country in selectedCountries {
            let identity = CityListID.availableGeneratedListIdentity(
                for: .country(iso2: country.iso2, duplicateIndex: nil),
                locale: locale
            )
            let listID = await weatherService.createCustomList(
                name: identity.displayName,
                cities: CountryCityCatalog.topCities(for: country),
                nameSource: identity.nameSource
            )
            if firstList == nil {
                firstList = listID
            }
        }

        if let firstList {
            if firstList.rawValue == weatherService.activeListID.rawValue {
                await weatherService.fetchWeatherForAllCities()
            } else {
                await switchToList(firstList)
            }
        }

        refreshListOrder()
        centerMapOnDots(useListCoordinates: true)

        if !mapCities.isEmpty {
            await refreshCitiesMissingDaytimeSunninessData()
        }

        hasCompletedInitialWeatherLoad = true
        hasLaunchedBefore = true
        tutorialState.showsFirstLaunch = false
    }
}
