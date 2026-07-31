//
//  CitySearch.swift
//  Weather
//
//  Purpose: Searches the bundled world-city catalog for the native Search tab
//  and resolves selected cities for persistence and WeatherKit.
//

import CoreLocation
import Foundation
import MapKit
import Observation

/// Stable presentation wrapper around one world-city search result.
struct CitySearchResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    fileprivate let city: WorldCityRecord

    init(city: WorldCityRecord) {
        id = "world-city-\(city.id)"
        title = city.name
        subtitle = [city.administrativeArea, city.countryName]
            .compactMap { value in
                guard let value,
                      !value.isEmpty,
                      value.localizedCaseInsensitiveCompare(city.name)
                        != .orderedSame else {
                    return nil
                }
                return value
            }
            .joined(separator: ", ")
        self.city = city
    }
}

/// Concrete place metadata required by persistence and WeatherKit.
struct CitySearchResolvedPlace {
    let cityName: String
    let country: String
    let coordinate: CLLocationCoordinate2D
    let timeZoneIdentifier: String?
    let catalogIdentifier: String
}

/// Main-actor adapter around the shared, region-neutral world-city catalog.
@MainActor
@Observable
final class CitySearchManager {
    private(set) var searchResults: [CitySearchResult] = []
    private(set) var isSearching = false
    private(set) var searchErrorMessage: String?

    @ObservationIgnored
    private let catalog: WorldCitiesCatalog
    @ObservationIgnored
    private var searchTask: Task<Void, Never>?

    init(catalog: WorldCitiesCatalog = .shared) {
        self.catalog = catalog
    }

    /// Clears state for an empty query or starts a region-neutral catalog query.
    func search(
        query: String,
        locale: Locale = .autoupdatingCurrent
    ) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()

        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            searchErrorMessage = nil
            return
        }

        searchResults = []
        searchErrorMessage = nil
        isSearching = true
        searchTask = Task { [catalog] in
            do {
                let cities = try await catalog.cities(matching: query)
                guard !Task.isCancelled else { return }
                searchResults = cities.map(CitySearchResult.init(city:))
                searchErrorMessage = nil
                isSearching = false
            } catch {
                guard !Task.isCancelled else { return }
                searchResults = []
                searchErrorMessage = localizedString(
                    "City search is temporarily unavailable.",
                    locale: locale
                )
                isSearching = false
            }
        }
    }

    /// Resolves a catalog result into coordinates and labels for persistence.
    func resolvePlace(
        for result: CitySearchResult
    ) async -> CitySearchResolvedPlace? {
        let timeZoneIdentifier = await resolvedTimeZoneIdentifier(
            for: result.city.coordinate
        )
        return CitySearchResolvedPlace(
            cityName: result.city.name,
            country: result.city.countryName,
            coordinate: result.city.coordinate,
            timeZoneIdentifier: timeZoneIdentifier,
            catalogIdentifier: result.city.id
        )
    }

    /// Resolves timezone metadata only for the city the user selected, avoiding
    /// region-biased search while making widgets useful in the same session.
    private func resolvedTimeZoneIdentifier(
        for coordinate: CLLocationCoordinate2D
    ) async -> String? {
        let location = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        if #available(iOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location),
                  let item = try? await request.mapItems.first else {
                return nil
            }
            return item.timeZone?.identifier
        }
        return try? await CLGeocoder()
            .reverseGeocodeLocation(location)
            .first?
            .timeZone?
            .identifier
    }
}
