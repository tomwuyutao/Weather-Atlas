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
    /// Proposed localized list name.
    var name: String?
    /// Canonical geographic source retained after save.
    var nameSource: CityListNameSource?
    /// Complete population-ranked source city collection.
    var allCities: [City] = []
    /// Number of leading cities currently included in the preview.
    var cityCount = CountryCityCatalog.defaultCountryCityCount
}

// MARK: - Preview Selection

extension ContentView {
    /// Leading source cities included at the preview's selected count.
    var listPreviewCities: [City] {
        Array(listPreviewState.allCities.prefix(listPreviewState.cityCount))
    }

    /// Maximum count supported by both source data and product limit.
    var listPreviewMaximumCount: Int {
        min(CountryCityCatalog.maxCountryCityCount, listPreviewState.allCities.count)
    }

    /// Whether a generated list has a name and source cities ready to preview.
    var isListPreviewActive: Bool {
        currentRoute == .listPreview && listPreviewState.name != nil
    }

    // MARK: Destination

    /// Reuses Home's visual hierarchy to preview an unfetched generated list.
    var listPreviewDestination: some View {
        homeContent(previewActive: true)
            .navigationTitle(listPreviewState.name ?? localizedString("List of Cities", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                isMapCardPresented = false
                centerMapOnDots()
            }
    }

    // MARK: Preview Creation

    /// Seeds preview state and navigates to its destination.
    func previewGeneratedList(name: String, cities: [City], nameSource: CityListNameSource? = nil) {
        listPreviewState.name = name
        listPreviewState.nameSource = nameSource
        // GeoNames names are captured only while creating Weather Atlas-generated
        // lists. User-search cities never pass through this creation flow.
        listPreviewState.allCities = cities.map { $0.localizedForGeneratedList(locale: locale) }
        listPreviewState.cityCount = min(
            CountryCityCatalog.defaultCountryCityCount,
            min(CountryCityCatalog.maxCountryCityCount, cities.count)
        )
        citySearchState.isPresented = false
        isMapCardPresented = false
        selectedMapCity = nil
        citySearchState.temporaryMapCity = nil
        navigationPath.removeAll { $0 == .listPreview }
        Haptics.lightImpact()
        pushRoute(.listPreview)
    }

    // MARK: Cancel and Commit

    /// Cancels preview with feedback and clears all staged values.
    func cancelGeneratedListPreview() {
        popRoute(.listPreview)
    }

    /// Removes preview route and resets staged generated-list state.
    func clearGeneratedListPreview(playsHaptic: Bool = true) {
        listPreviewState.name = nil
        listPreviewState.nameSource = nil
        listPreviewState.allCities = []
        listPreviewState.cityCount = CountryCityCatalog.defaultCountryCityCount
        if playsHaptic {
            Haptics.lightImpact()
        }
    }

    /// Persists and activates the staged generated list.
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
                centerMapOnDots()
            }
        }
    }
}
