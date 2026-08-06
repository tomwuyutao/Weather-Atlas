//
//  PlacesLibraryModels.swift
//  Weather
//
//  Purpose: Defines Weather Atlas's one-level Saved Places library.
//

import Foundation

/// One city the user has chosen to keep in Saved Places.
struct SavedPlace: Identifiable, Codable, Equatable, Hashable {
    var city: City
    var customName: String?

    var id: UUID { city.id }

    init(city: City, customName: String? = nil) {
        self.city = city
        self.customName = Self.normalizedCustomName(customName)
    }

    var displayName: String { customName ?? city.displayName }

    static func normalizedCustomName(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Versioned persistence payload for the flat Saved Places library.
///
/// `Codable` intentionally ignores historical collection keys when reading an
/// existing document. The next ordinary save rewrites it as this flat schema.
struct PlacesLibraryDocument: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var places: [SavedPlace]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        places: [SavedPlace] = []
    ) {
        self.schemaVersion = schemaVersion
        self.places = places
    }

    static let empty = PlacesLibraryDocument()
}
