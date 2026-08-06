//
//  PlacesLibraryValidator.swift
//  Weather
//
//  Purpose: Validates the flat Saved Places document at each persistence boundary.
//

import Foundation

enum PlacesLibraryValidationError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case tooManyPlaces(Int)
    case duplicatePlaceID(UUID)
    case invalidPlace(UUID)
    case invalidCustomName(UUID)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "The Places library uses unsupported schema version \(version)."
        case .tooManyPlaces(let count):
            "The Places library contains too many places (\(count))."
        case .duplicatePlaceID(let id):
            "The Places library contains duplicate place ID \(id.uuidString)."
        case .invalidPlace(let id):
            "Saved place \(id.uuidString) contains invalid place metadata."
        case .invalidCustomName(let id):
            "Saved place \(id.uuidString) contains an invalid custom name."
        }
    }
}

enum PlacesLibraryValidator {
    static let maximumPlaceCount = 25_000
    static let maximumPlaceNameLength = 500
    static let maximumIdentifierLength = 200

    static func validate(_ document: PlacesLibraryDocument) throws {
        guard document.schemaVersion == PlacesLibraryDocument.currentSchemaVersion else {
            throw PlacesLibraryValidationError.unsupportedSchemaVersion(document.schemaVersion)
        }
        guard document.places.count <= maximumPlaceCount else {
            throw PlacesLibraryValidationError.tooManyPlaces(document.places.count)
        }
        var placeIDs = Set<SavedPlace.ID>()
        for place in document.places {
            guard placeIDs.insert(place.id).inserted else {
                throw PlacesLibraryValidationError.duplicatePlaceID(place.id)
            }
            guard isValidCity(place.city) else {
                throw PlacesLibraryValidationError.invalidPlace(place.id)
            }
            if let customName = place.customName,
               !isValidUserFacingName(customName, maximumLength: maximumPlaceNameLength) {
                throw PlacesLibraryValidationError.invalidCustomName(place.id)
            }
        }
    }

    static func isValidCity(_ city: City) -> Bool {
        guard city.latitude.isFinite, city.longitude.isFinite,
              (-90...90).contains(city.latitude),
              (-180...180).contains(city.longitude),
              city.name.count <= maximumPlaceNameLength,
              city.country.count <= maximumPlaceNameLength,
              !containsUnsafeControlCharacters(city.name),
              !containsUnsafeControlCharacters(city.country) else { return false }
        if let timezone = city.timeZoneIdentifier,
           (timezone.count > maximumIdentifierLength || containsUnsafeControlCharacters(timezone)) {
            return false
        }
        if let catalogID = city.catalogIdentifier,
           (catalogID.isEmpty || catalogID.count > maximumIdentifierLength || containsUnsafeControlCharacters(catalogID)) {
            return false
        }
        return true
    }

    static func isValidUserFacingName(_ value: String, maximumLength: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.count <= maximumLength
            && !containsUnsafeControlCharacters(value)
    }

    private static func containsUnsafeControlCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t"
        }
    }
}
