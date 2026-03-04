//
//  CitySearchManager.swift
//  Weather
//

import Foundation
import MapKit
import CoreLocation

// MARK: - Search Result

struct CitySearchResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
}

// MARK: - City Search Manager

@Observable
class CitySearchManager: NSObject, MKLocalSearchCompleterDelegate {
    var searchResults: [CitySearchResult] = []
    private let completer: MKLocalSearchCompleter
    private var currentQuery: String = ""
    private let englishLocale = Locale(identifier: "en_US")
    
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
        currentQuery = query
        if query.isEmpty {
            searchResults = []
            return
        }
        completer.queryFragment = query
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let completions = completer.results
        let query = currentQuery
        
        Task { @MainActor in
            var englishResults: [CitySearchResult] = []
            
            for completion in completions {
                let searchRequest = MKLocalSearch.Request(completion: completion)
                let search = MKLocalSearch(request: searchRequest)
                
                do {
                    let response = try await search.start()
                    if let mapItem = response.mapItems.first {
                        let coordinate = mapItem.placemark.coordinate
                        
                        let geocoder = CLGeocoder()
                        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                        let placemarks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: englishLocale)
                        
                        if let placemark = placemarks.first {
                            let city = placemark.locality ?? completion.title
                            let country = placemark.country ?? completion.subtitle
                            englishResults.append(CitySearchResult(title: city, subtitle: country, coordinate: coordinate))
                        }
                    }
                } catch {
                    // Skip failed results silently
                }
                
                // If user typed something new, abort this batch
                guard currentQuery == query else { return }
            }
            
            // Only update if query hasn't changed
            if currentQuery == query {
                searchResults = englishResults
            }
        }
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Search error: \(error.localizedDescription)")
    }
}
