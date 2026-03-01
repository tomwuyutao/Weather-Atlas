//
//  CitySearchManager.swift
//  Weather
//

import Foundation
import MapKit

// MARK: - City Search Manager

@Observable
class CitySearchManager: NSObject, MKLocalSearchCompleterDelegate {
    var searchResults: [MKLocalSearchCompletion] = []
    private let completer: MKLocalSearchCompleter
    
    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)
        )
    }
    
    func search(query: String) {
        if query.isEmpty {
            searchResults = []
            return
        }
        completer.queryFragment = query
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // Filter to only show city-level results (Title: "Bologna", Subtitle: "Italy")
        searchResults = completer.results.filter { result in
            // We want results where NEITHER title nor subtitle contain commas
            // This gives us simple city results like "Bologna" / "Italy" or "London" / "England"
            // And filters out more specific results like "LHR, London" / "England"
            let titleHasNoComma = !result.title.contains(",")
            let subtitleHasNoComma = !result.subtitle.contains(",")
            
            // Also ensure subtitle is not empty (to avoid invalid results)
            let hasSubtitle = !result.subtitle.isEmpty
            
            return titleHasNoComma && subtitleHasNoComma && hasSubtitle
        }
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Search error: \(error.localizedDescription)")
    }
}
