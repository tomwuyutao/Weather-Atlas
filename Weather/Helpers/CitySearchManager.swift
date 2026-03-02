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
        completer.addressFilter = MKAddressFilter(including: .locality)
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
        searchResults = completer.results
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Search error: \(error.localizedDescription)")
    }
}
