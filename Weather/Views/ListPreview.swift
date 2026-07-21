//
//  ListPreview.swift
//  Weather
//
//  Purpose: Owns the draft state, presentation, and commit/cancel actions for
//  generated country and continent list previews.
//

import SwiftUI

// MARK: - Preview State

/// Draft data shown before a generated country or continent list is committed.
struct GeneratedListPreviewState {
    var name: String?
    var nameSource: CityListNameSource?
    var allCities: [City] = []
    var cityCount = CountryCityCatalog.defaultCountryCityCount
}

// MARK: - Preview Selection

extension ContentView {
    var listPreviewCities: [City] {
        Array(listPreviewState.allCities.prefix(listPreviewState.cityCount))
    }

    var listPreviewMaximumCount: Int {
        min(CountryCityCatalog.maxCountryCityCount, listPreviewState.allCities.count)
    }

    var isListPreviewActive: Bool {
        currentRoute == .listPreview && listPreviewState.name != nil
    }

    func cityCountText(_ count: Int) -> String {
        if count == 1 {
            return "\(count) \(localizedString("City", locale: locale))"
        }
        return "\(count) \(localizedString("Cities", locale: locale))"
    }

    // MARK: Destination

    var listPreviewDestination: some View {
        homeContent(previewActive: true)
            .navigationTitle(listPreviewState.name ?? localizedString("List of Cities", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                showingMapExpandedCard = false
                centerMapOnDots(useListCoordinates: true)
            }
    }

    // MARK: Preview Creation

    func previewGeneratedList(name: String, cities: [City], nameSource: CityListNameSource? = nil) {
        listPreviewState.name = name
        listPreviewState.nameSource = nameSource
        listPreviewState.allCities = cities
        listPreviewState.cityCount = min(
            CountryCityCatalog.defaultCountryCityCount,
            min(CountryCityCatalog.maxCountryCityCount, cities.count)
        )
        citySearchState.isPresented = false
        showingMapExpandedCard = false
        selectedMapCity = nil
        citySearchState.temporaryMapCity = nil
        navigationPath.removeAll { $0 == .listPreview }
        Haptics.lightImpact()
        pushRoute(.listPreview)
    }

    func previewContinentList(_ listID: CityListID) {
        let populationSortedCities = CountryCityCatalog.topCities(
            forContinentRawValue: listID.rawValue,
            limit: CountryCityCatalog.maxCountryCityCount
        )
        previewGeneratedList(
            name: listID.canonicalLocalizedDisplayName(locale: locale),
            cities: populationSortedCities.isEmpty ? listID.defaultCities : populationSortedCities,
            nameSource: .continent(rawValue: listID.rawValue, duplicateIndex: nil)
        )
    }

    func previewCountryList(_ country: CountryListOption) {
        previewGeneratedList(
            name: country.localizedName(locale: locale),
            cities: CountryCityCatalog.topCities(for: country, limit: CountryCityCatalog.maxCountryCityCount),
            nameSource: .country(iso2: country.iso2, duplicateIndex: nil)
        )
    }

    // MARK: Cancel and Commit

    func cancelGeneratedListPreview() {
        popRoute(.listPreview)
    }

    func clearGeneratedListPreview(playsHaptic: Bool = true) {
        listPreviewState.name = nil
        listPreviewState.nameSource = nil
        listPreviewState.allCities = []
        listPreviewState.cityCount = CountryCityCatalog.defaultCountryCityCount
        if playsHaptic {
            Haptics.lightImpact()
        }
    }

    func confirmGeneratedListPreview() {
        guard let previewName = listPreviewState.name,
              !listPreviewCities.isEmpty else { return }
        let generatedIdentity = listPreviewState.nameSource.map {
            CityListID.availableGeneratedListIdentity(for: $0, locale: locale)
        }
        let uniqueName = generatedIdentity?.displayName ?? CityListID.availableListName(for: previewName)
        let nameSource = generatedIdentity?.nameSource
        let cities = listPreviewCities
        cancelGeneratedListPreview()

        Task {
            let listID = await weatherService.createCustomList(name: uniqueName, cities: cities, nameSource: nameSource)
            await switchToList(listID)
            await MainActor.run {
                refreshListOrder()
                centerMapOnDots(useListCoordinates: true)
            }
        }
    }
}
