//
//  AddPlaceSheet.swift
//  Weather
//
//  Purpose: Presents native place search and saves a place independently of
//  collections, with an optional collection relationship when requested.
//

import SwiftUI

/// Native search sheet for adding a place to All Places.
///
/// Passing a collection identity adds the saved place to that collection as a
/// convenience. A collection is never required.
struct AddPlaceSheet: View {
    let placesStore: PlacesStore
    let weatherStore: PlaceWeatherStore
    let targetCollectionID: PlaceCollection.ID?

    @Environment(\.dismiss) private var dismiss

    init(
        placesStore: PlacesStore,
        weatherStore: PlaceWeatherStore,
        targetCollectionID: PlaceCollection.ID? = nil
    ) {
        self.placesStore = placesStore
        self.weatherStore = weatherStore
        self.targetCollectionID = targetCollectionID
    }

    var body: some View {
        NavigationStack {
            PlaceSearchView(
                placesStore: placesStore,
                weatherStore: weatherStore,
                targetCollectionID: targetCollectionID
            ) { _ in
                dismiss()
            }
                .navigationTitle("Add Place")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
        }
    }
}
