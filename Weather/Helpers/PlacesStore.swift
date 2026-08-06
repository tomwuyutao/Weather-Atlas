//
//  PlacesStore.swift
//  Weather
//
//  Purpose: Owns the flat Saved Places library and atomic persistence.
//

import Foundation
import Observation

enum PlacesStoreError: LocalizedError {
    case unavailable(String)
    case placeNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): "The Places library is unavailable: \(reason)"
        case .placeNotFound(let id): "Saved place \(id.uuidString) does not exist."
        }
    }

    func description(locale: Locale) -> String { errorDescription ?? "" }
}

func localizedPlacesErrorDescription(_ error: Error, locale: Locale) -> String {
    (error as? PlacesStoreError)?.description(locale: locale) ?? error.localizedDescription
}

private struct SavedPlaceCoordinateIdentity: Hashable {
    let latitude: Int64
    let longitude: Int64

    init(city: City) {
        latitude = Int64((city.latitude * 10_000).rounded(.toNearestOrAwayFromZero))
        longitude = Int64((city.longitude * 10_000).rounded(.toNearestOrAwayFromZero))
    }
}

private struct SavedPlaceSemanticIdentity: Hashable {
    let coordinate: SavedPlaceCoordinateIdentity
    let cityName: String
    let countryName: String

    init?(city: City) {
        guard city.latitude.isFinite, city.longitude.isFinite,
              (-90...90).contains(city.latitude), (-180...180).contains(city.longitude) else { return nil }
        let cityName = Self.normalized(city.name)
        let countryName = Self.normalized(city.country)
        guard !cityName.isEmpty, !countryName.isEmpty else { return nil }
        coordinate = SavedPlaceCoordinateIdentity(city: city)
        self.cityName = cityName
        self.countryName = countryName
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}

@MainActor
@Observable
final class PlacesStore {
    private(set) var document: PlacesLibraryDocument
    private(set) var loadErrorDescription: String?
    @ObservationIgnored private var documentStore: PlacesDocumentStore?

    init(documentStore: PlacesDocumentStore? = nil) {
        document = .empty
        self.documentStore = documentStore
        do {
            let store = try documentStore ?? PlacesDocumentStore.live()
            self.documentStore = store
            document = try Self.loadOrCreate(documentStore: store)
        } catch {
            loadErrorDescription = error.localizedDescription
        }
    }

    var allPlaces: [SavedPlace] { document.places }

    func place(id: SavedPlace.ID) -> SavedPlace? {
        document.places.first { $0.id == id }
    }

    func savedPlaceID(matching city: City) -> SavedPlace.ID? {
        if let match = document.places.first(where: { $0.id == city.id }) { return match.id }
        if let catalogID = city.catalogIdentifier,
           let match = document.places.first(where: { $0.city.catalogIdentifier == catalogID }) { return match.id }
        guard let identity = SavedPlaceSemanticIdentity(city: city) else { return nil }
        return document.places.first { SavedPlaceSemanticIdentity(city: $0.city) == identity }?.id
    }

    func retryLoading() {
        guard let documentStore else { return }
        do {
            document = try Self.loadOrCreate(documentStore: documentStore)
            loadErrorDescription = nil
        } catch { loadErrorDescription = error.localizedDescription }
    }

    func resetToEmptyLibrary() throws { try persist(.empty) }

    @discardableResult
    func savePlace(_ city: City, customName: String? = nil) throws -> SavedPlace.ID {
        var savedID = city.id
        try mutateAndPersist { candidate in
            if let index = Self.matchingPlaceIndex(for: city, in: candidate.places) {
                savedID = candidate.places[index].id
                Self.merge(city: city, customName: customName, into: &candidate.places[index])
            } else {
                let place = SavedPlace(city: city, customName: customName)
                candidate.places.insert(place, at: candidate.places.startIndex)
                savedID = place.id
            }
        }
        return savedID
    }

    @discardableResult
    func savePlaces(_ cities: [City]) throws -> [SavedPlace.ID] {
        guard !cities.isEmpty else { return [] }
        var savedIDs: [SavedPlace.ID] = []
        try mutateAndPersist { savedIDs = Self.mergeCities(cities, into: &$0) }
        return savedIDs
    }

    func deletePlace(id placeID: SavedPlace.ID) throws {
        try mutateAndPersist { candidate in
            guard candidate.places.contains(where: { $0.id == placeID }) else {
                throw PlacesStoreError.placeNotFound(placeID)
            }
            candidate.places.removeAll { $0.id == placeID }
        }
    }

    private func mutateAndPersist(_ mutation: (inout PlacesLibraryDocument) throws -> Void) throws {
        try ensureAvailable()
        var candidate = document
        try mutation(&candidate)
        guard candidate != document else { return }
        try persist(candidate)
    }

    private func persist(_ candidate: PlacesLibraryDocument) throws {
        try ensureAvailable()
        guard let documentStore else { throw PlacesStoreError.unavailable("No document location is available.") }
        document = try documentStore.saveAndReadBack(candidate)
    }

    private func ensureAvailable() throws {
        if let loadErrorDescription { throw PlacesStoreError.unavailable(loadErrorDescription) }
    }

    private static func loadOrCreate(documentStore: PlacesDocumentStore) throws -> PlacesLibraryDocument {
        if let document = try documentStore.load() { return document }
        return try documentStore.saveAndReadBack(.empty)
    }

    private static func matchingPlaceIndex(for city: City, in places: [SavedPlace]) -> Int? {
        if let index = places.firstIndex(where: { $0.id == city.id }) { return index }
        if let catalogID = city.catalogIdentifier,
           let index = places.firstIndex(where: { $0.city.catalogIdentifier == catalogID }) { return index }
        guard let identity = SavedPlaceSemanticIdentity(city: city) else { return nil }
        return places.firstIndex { SavedPlaceSemanticIdentity(city: $0.city) == identity }
    }

    private static func mergeCities(_ cities: [City], into document: inout PlacesLibraryDocument) -> [SavedPlace.ID] {
        var resolvedIDs: [SavedPlace.ID] = []
        var seen = Set<SavedPlace.ID>()
        var additions: [SavedPlace] = []
        for city in cities {
            let id: SavedPlace.ID
            if let index = matchingPlaceIndex(for: city, in: document.places) {
                id = document.places[index].id
                merge(city: city, customName: nil, into: &document.places[index])
            } else if let index = matchingPlaceIndex(for: city, in: additions) {
                id = additions[index].id
                merge(city: city, customName: nil, into: &additions[index])
            } else {
                let place = SavedPlace(city: city)
                additions.append(place)
                id = place.id
            }
            if seen.insert(id).inserted { resolvedIDs.append(id) }
        }
        document.places.insert(contentsOf: additions, at: document.places.startIndex)
        return resolvedIDs
    }

    private static func merge(city incoming: City, customName: String?, into existing: inout SavedPlace) {
        let current = existing.city
        existing.city = City(
            id: current.id,
            name: incoming.name.isEmpty ? current.name : incoming.name,
            country: incoming.country.isEmpty ? current.country : incoming.country,
            latitude: current.latitude,
            longitude: current.longitude,
            timeZoneIdentifier: incoming.timeZoneIdentifier ?? current.timeZoneIdentifier,
            catalogIdentifier: current.catalogIdentifier ?? incoming.catalogIdentifier
        )
        if let customName = SavedPlace.normalizedCustomName(customName) { existing.customName = customName }
    }
}
