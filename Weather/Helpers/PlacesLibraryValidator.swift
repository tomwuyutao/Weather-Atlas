//
//  PlacesLibraryValidator.swift
//  Weather
//
//  Purpose: Validates the complete place library before and after every atomic
//  persistence operation.
//

import Foundation

/// Precise validation failures suitable for diagnostics and migration gating.
enum PlacesLibraryValidationError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case tooManyPlaces(Int)
    case tooManyCollections(Int)
    case duplicatePlaceID(UUID)
    case invalidPlace(UUID)
    case invalidCustomName(UUID)
    case duplicateCollectionID(String)
    case invalidCollectionID(String)
    case invalidCollectionName(String)
    case tooManyPlacesInCollection(collectionID: String, count: Int)
    case duplicateMembership(collectionID: String, placeID: UUID)
    case missingPlace(collectionID: String, placeID: UUID)
    case missingSelectedCollection(String)
    case invalidLegacyImportVersion(Int)

    /// Diagnostic text. Presentation code can map these cases to localized UI.
    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "The Places library uses unsupported schema version \(version)."
        case .tooManyPlaces(let count):
            return "The Places library contains too many places (\(count))."
        case .tooManyCollections(let count):
            return "The Places library contains too many collections (\(count))."
        case .duplicatePlaceID(let id):
            return "The Places library contains duplicate place ID \(id.uuidString)."
        case .invalidPlace(let id):
            return "Saved place \(id.uuidString) contains invalid place metadata."
        case .invalidCustomName(let id):
            return "Saved place \(id.uuidString) contains an invalid custom name."
        case .duplicateCollectionID(let id):
            return "The Places library contains duplicate collection ID \(id)."
        case .invalidCollectionID(let id):
            return "The Places library contains an invalid collection ID \(id)."
        case .invalidCollectionName(let id):
            return "Collection \(id) contains an invalid name."
        case let .tooManyPlacesInCollection(collectionID, count):
            return "Collection \(collectionID) contains too many place references (\(count))."
        case let .duplicateMembership(collectionID, placeID):
            return "Collection \(collectionID) contains duplicate place \(placeID.uuidString)."
        case let .missingPlace(collectionID, placeID):
            return "Collection \(collectionID) references missing place \(placeID.uuidString)."
        case .missingSelectedCollection(let id):
            return "The selected collection \(id) does not exist."
        case .invalidLegacyImportVersion(let version):
            return "The Places library contains invalid legacy import version \(version)."
        }
    }
}

/// Pure structural and value validation for a complete library document.
enum PlacesLibraryValidator {
    /// Defensive ceilings that keep a damaged file from exhausting memory or UI.
    static let maximumPlaceCount = 25_000
    static let maximumCollectionCount = 2_500
    static let maximumMembershipCount = 25_000
    // The legacy app allowed long Unicode custom labels. Keep a defensive
    // ceiling without rejecting or truncating valid existing user data during
    // the one-time list-to-places migration.
    static let maximumPlaceNameLength = 500
    static let maximumCollectionNameLength = 250
    static let maximumIdentifierLength = 200

    /// Throws at the first invariant violation.
    static func validate(_ document: PlacesLibraryDocument) throws {
        guard document.schemaVersion == PlacesLibraryDocument.currentSchemaVersion else {
            throw PlacesLibraryValidationError.unsupportedSchemaVersion(document.schemaVersion)
        }
        guard document.places.count <= maximumPlaceCount else {
            throw PlacesLibraryValidationError.tooManyPlaces(document.places.count)
        }
        guard document.collections.count <= maximumCollectionCount else {
            throw PlacesLibraryValidationError.tooManyCollections(document.collections.count)
        }
        if let legacyImportVersion = document.legacyImportVersion,
           legacyImportVersion <= 0 {
            throw PlacesLibraryValidationError.invalidLegacyImportVersion(legacyImportVersion)
        }

        var placeIDs = Set<SavedPlace.ID>()
        placeIDs.reserveCapacity(document.places.count)
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

        var collectionIDs = Set<PlaceCollection.ID>()
        collectionIDs.reserveCapacity(document.collections.count)
        for collection in document.collections {
            guard isValidIdentifier(collection.id) else {
                throw PlacesLibraryValidationError.invalidCollectionID(collection.id)
            }
            guard collectionIDs.insert(collection.id).inserted else {
                throw PlacesLibraryValidationError.duplicateCollectionID(collection.id)
            }
            guard isValidUserFacingName(
                collection.name,
                maximumLength: maximumCollectionNameLength
            ) else {
                throw PlacesLibraryValidationError.invalidCollectionName(collection.id)
            }
            guard collection.placeIDs.count <= maximumMembershipCount else {
                throw PlacesLibraryValidationError.tooManyPlacesInCollection(
                    collectionID: collection.id,
                    count: collection.placeIDs.count
                )
            }

            var membershipIDs = Set<SavedPlace.ID>()
            membershipIDs.reserveCapacity(collection.placeIDs.count)
            for placeID in collection.placeIDs {
                guard membershipIDs.insert(placeID).inserted else {
                    throw PlacesLibraryValidationError.duplicateMembership(
                        collectionID: collection.id,
                        placeID: placeID
                    )
                }
                guard placeIDs.contains(placeID) else {
                    throw PlacesLibraryValidationError.missingPlace(
                        collectionID: collection.id,
                        placeID: placeID
                    )
                }
            }
        }

        if let selectedCollectionID = document.selectedCollectionID,
           !collectionIDs.contains(selectedCollectionID) {
            throw PlacesLibraryValidationError.missingSelectedCollection(selectedCollectionID)
        }
    }

    /// Shared city validation used by both document checks and legacy import.
    static func isValidCity(_ city: City) -> Bool {
        guard city.latitude.isFinite, city.longitude.isFinite,
              (-90...90).contains(city.latitude),
              (-180...180).contains(city.longitude),
              city.name.count <= maximumPlaceNameLength,
              city.country.count <= maximumPlaceNameLength,
              !containsUnsafeControlCharacters(city.name),
              !containsUnsafeControlCharacters(city.country) else {
            return false
        }

        if let timeZoneIdentifier = city.timeZoneIdentifier {
            guard timeZoneIdentifier.count <= maximumIdentifierLength,
                  !containsUnsafeControlCharacters(timeZoneIdentifier) else {
                return false
            }
        }
        if let catalogIdentifier = city.catalogIdentifier {
            guard !catalogIdentifier.isEmpty,
                  catalogIdentifier.count <= maximumIdentifierLength,
                  !containsUnsafeControlCharacters(catalogIdentifier) else {
                return false
            }
        }
        return true
    }

    /// Validates a nonempty user-facing value without restricting languages.
    static func isValidUserFacingName(_ value: String, maximumLength: Int) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && value.count <= maximumLength
            && !containsUnsafeControlCharacters(value)
    }

    /// Stable persisted IDs may contain legacy strings but never control data.
    private static func isValidIdentifier(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= maximumIdentifierLength
            && !containsUnsafeControlCharacters(value)
    }

    private static func containsUnsafeControlCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
                && $0 != "\n"
                && $0 != "\t"
        }
    }
}
