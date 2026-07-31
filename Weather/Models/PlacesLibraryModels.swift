//
//  PlacesLibraryModels.swift
//  Weather
//
//  Purpose: Defines the place-owned library that replaces list-owned city
//  persistence. "All Places" is derived from `places`; it is never persisted as
//  a synthetic collection.
//

import Foundation

// MARK: - Saved Place

/// One place the user has chosen to keep, independent of any collection.
struct SavedPlace: Identifiable, Codable, Equatable, Hashable {
    /// Canonical coordinate, naming, timezone, and stable UUID metadata.
    var city: City
    /// Optional user-provided label. The canonical city name remains untouched.
    var customName: String?

    /// Uses the city's durable UUID everywhere the place is referenced.
    var id: UUID { city.id }

    /// Creates a saved place while normalizing an empty custom label to `nil`.
    init(city: City, customName: String? = nil) {
        self.city = city
        self.customName = Self.normalizedCustomName(customName)
    }

    /// User-facing name with the custom label taking precedence.
    var displayName: String {
        customName ?? city.localizedName()
    }

    /// Returns a trimmed custom label, or `nil` when no meaningful label exists.
    static func normalizedCustomName(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Optional Collection

/// An optional, ordered grouping of saved places.
///
/// A place can occur in any number of collections. Collection deletion removes
/// only this relationship object and never removes a saved place.
struct PlaceCollection: Identifiable, Codable, Equatable, Hashable {
    /// Stable string identity. Migrated collections retain their legacy raw ID.
    let id: String
    /// User-facing collection name.
    var name: String
    /// Ordered references into `PlacesLibraryDocument.places`.
    var placeIDs: [SavedPlace.ID]

    /// Creates a collection with an explicit stable identity.
    init(id: String = UUID().uuidString, name: String, placeIDs: [SavedPlace.ID] = []) {
        self.id = id
        self.name = name
        self.placeIDs = placeIDs
    }
}

// MARK: - Versioned Library Document

/// Complete, versioned source of truth persisted in Application Support.
struct PlacesLibraryDocument: Codable, Equatable {
    /// Schema understood by this release.
    static let currentSchemaVersion = 1

    /// File-format version, validated before the document is used.
    var schemaVersion: Int
    /// Global saved-place order used by the computed All Places view.
    var places: [SavedPlace]
    /// Optional collections in user-visible order.
    var collections: [PlaceCollection]
    /// Last selected optional collection. `nil` means All Places.
    var selectedCollectionID: PlaceCollection.ID?
    /// Legacy-import version, absent for libraries created by the new app.
    var legacyImportVersion: Int?

    /// Creates a current-version document.
    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        places: [SavedPlace] = [],
        collections: [PlaceCollection] = [],
        selectedCollectionID: PlaceCollection.ID? = nil,
        legacyImportVersion: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.places = places
        self.collections = collections
        self.selectedCollectionID = selectedCollectionID
        self.legacyImportVersion = legacyImportVersion
    }

    /// Fresh-install document with no synthetic default collection.
    static let empty = PlacesLibraryDocument()
}
