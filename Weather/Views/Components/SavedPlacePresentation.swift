//
//  SavedPlacePresentation.swift
//  Weather
//
//  Purpose: Carries one saved place and its selected-date forecast state
//  between the dedicated Places list and Map tab.
//

import Foundation

struct SavedPlacePresentation: Identifiable {
    let place: SavedPlace
    let recommendation: PlaceRecommendation?
    let isLoading: Bool
    let failureMessage: String?

    var id: SavedPlace.ID { place.id }
}
