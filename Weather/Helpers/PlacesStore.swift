//
//  PlacesStore.swift
//  Weather
//
//  Purpose: Owns the independent saved-place library, optional collection
//  relationships, atomic persistence, and one-time legacy import.
//

import Foundation
import Observation

/// Mutation and availability errors surfaced by `PlacesStore`.
enum PlacesStoreError: LocalizedError {
    case unavailable(String)
    case placeNotFound(UUID)
    case collectionNotFound(String)
    case invalidCollectionName
    case duplicateCollectionName(String)
    case duplicateCollectionID(String)
    case invalidOrdering

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return "The Places library is unavailable: \(reason)"
        case .placeNotFound(let id):
            return "Saved place \(id.uuidString) does not exist."
        case .collectionNotFound(let id):
            return "Collection \(id) does not exist."
        case .invalidCollectionName:
            return "A collection name cannot be empty or contain invalid characters."
        case .duplicateCollectionName(let name):
            return "A collection named \(name) already exists."
        case .duplicateCollectionID(let id):
            return "Collection identity \(id) already exists."
        case .invalidOrdering:
            return "The replacement order must contain every existing item exactly once."
        }
    }

    /// Resolves user-facing validation copy against the app-selected locale.
    func description(locale: Locale) -> String {
        switch self {
        case .unavailable(let reason):
            return localizedString(
                "The Places library is unavailable: \(reason)",
                locale: locale
            )
        case .placeNotFound(let id):
            return localizedString(
                "Saved place \(id.uuidString) does not exist.",
                locale: locale
            )
        case .collectionNotFound(let id):
            return localizedString(
                "Collection \(id) does not exist.",
                locale: locale
            )
        case .invalidCollectionName:
            return localizedString(
                "A collection name cannot be empty or contain invalid characters.",
                locale: locale
            )
        case .duplicateCollectionName(let name):
            return localizedString(
                "A collection named \(name) already exists.",
                locale: locale
            )
        case .duplicateCollectionID(let id):
            return localizedString(
                "Collection identity \(id) already exists.",
                locale: locale
            )
        case .invalidOrdering:
            return localizedString(
                "The replacement order must contain every existing item exactly once.",
                locale: locale
            )
        }
    }
}

/// Preserves system-provided I/O diagnostics while localizing app validation.
func localizedPlacesErrorDescription(
    _ error: Error,
    locale: Locale
) -> String {
    if let placesError = error as? PlacesStoreError {
        return placesError.description(locale: locale)
    }
    return error.localizedDescription
}

/// Main-actor source of truth consumed by Home, Places, Detail, and Settings.
@MainActor
@Observable
final class PlacesStore {
    /// Written only after an imported document was atomically saved and read back.
    static let legacyMigrationMarkerKey = "placesLibraryLegacyMigrationVersion"

    /// Complete verified document. All Places is computed from its global order.
    private(set) var document: PlacesLibraryDocument
    /// Non-`nil` when initial loading failed; mutations remain blocked to avoid
    /// replacing a recoverable corrupt or temporarily inaccessible file.
    private(set) var loadErrorDescription: String?
    /// Most recent mutation persistence error for native alert presentation.
    private(set) var lastPersistenceErrorDescription: String?

    @ObservationIgnored private var documentStore: PlacesDocumentStore?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let locale: Locale

    /// Creates the live store. Injectable dependencies support deterministic
    /// validator/import fixtures without a dedicated test target.
    init(
        documentStore: PlacesDocumentStore? = nil,
        defaults: UserDefaults = .standard,
        locale: Locale = .autoupdatingCurrent
    ) {
        self.document = .empty
        self.defaults = defaults
        self.locale = locale
        self.documentStore = documentStore

        do {
            let resolvedStore = try documentStore ?? PlacesDocumentStore.live()
            self.documentStore = resolvedStore
            self.document = try Self.loadOrBootstrap(
                documentStore: resolvedStore,
                defaults: defaults,
                locale: locale
            )
        } catch {
            self.loadErrorDescription = error.localizedDescription
        }
    }

    // MARK: Derived Library State

    /// Every saved place in the user's global order. No All Places collection is
    /// stored or maintained.
    var allPlaces: [SavedPlace] {
        document.places
    }

    /// Optional collections in user-visible order.
    var collections: [PlaceCollection] {
        document.collections
    }

    /// Current optional collection, or `nil` for All Places.
    var selectedCollection: PlaceCollection? {
        guard let selectedCollectionID = document.selectedCollectionID else {
            return nil
        }
        return document.collections.first { $0.id == selectedCollectionID }
    }

    /// Current optional collection identity; `nil` represents All Places.
    var selectedCollectionID: PlaceCollection.ID? {
        document.selectedCollectionID
    }

    /// Returns global or collection-specific places in the appropriate order.
    func places(in collectionID: PlaceCollection.ID?) -> [SavedPlace] {
        guard let collectionID else { return allPlaces }
        guard let collection = document.collections.first(where: { $0.id == collectionID }) else {
            return []
        }
        let placesByID = Dictionary(
            uniqueKeysWithValues: document.places.map { ($0.id, $0) }
        )
        return collection.placeIDs.compactMap { placesByID[$0] }
    }

    /// Finds a saved place by durable UUID.
    func place(id: SavedPlace.ID) -> SavedPlace? {
        document.places.first { $0.id == id }
    }

    /// Finds a saved identity by UUID, stable catalog identity, or a
    /// coordinate-and-name fallback that cannot merge neighboring cities.
    func savedPlaceID(matching city: City) -> SavedPlace.ID? {
        if let exactIdentity = document.places.first(where: { $0.id == city.id }) {
            return exactIdentity.id
        }
        if let catalogIdentifier = city.catalogIdentifier,
           let catalogMatch = document.places.first(where: {
               $0.city.catalogIdentifier == catalogIdentifier
           }) {
            return catalogMatch.id
        }
        guard let fallbackIdentity = PlaceFallbackIdentity(city: city) else {
            return nil
        }
        return document.places.first {
            PlaceFallbackIdentity(city: $0.city) == fallbackIdentity
        }?.id
    }

    /// Optional collections containing a place, in collection order.
    func collections(containing placeID: SavedPlace.ID) -> [PlaceCollection] {
        document.collections.filter { $0.placeIDs.contains(placeID) }
    }

    // MARK: Loading and Recovery

    /// Retries document loading or bootstrap after an initial I/O failure.
    func retryLoading() {
        guard let documentStore else { return }
        do {
            document = try Self.loadOrBootstrap(
                documentStore: documentStore,
                defaults: defaults,
                locale: locale
            )
            loadErrorDescription = nil
            lastPersistenceErrorDescription = nil
        } catch {
            loadErrorDescription = error.localizedDescription
        }
    }

    /// Replaces the verified document with a fresh, collection-free library.
    /// Reset flows should call this before clearing their UserDefaults domain.
    func resetToEmptyLibrary() throws {
        try persist(PlacesLibraryDocument.empty)
    }

    /// Clears a presented mutation error without changing library data.
    func clearLastPersistenceError() {
        lastPersistenceErrorDescription = nil
    }

    // MARK: Place Mutations

    /// Saves or updates a place and optionally appends it to one collection.
    ///
    /// Existing identity is resolved by UUID, stable catalog identity, then a
    /// semantic coordinate fallback. Saving without `collectionID` is the
    /// normal All Places flow.
    @discardableResult
    func savePlace(
        _ city: City,
        customName: String? = nil,
        in collectionID: PlaceCollection.ID? = nil
    ) throws -> SavedPlace.ID {
        var savedID = city.id
        try mutateAndPersist { candidate in
            if let collectionID,
               !candidate.collections.contains(where: { $0.id == collectionID }) {
                throw PlacesStoreError.collectionNotFound(collectionID)
            }

            let exactIndex = candidate.places.firstIndex { $0.id == city.id }
            let catalogIndex = city.catalogIdentifier.flatMap {
                catalogIdentifier in
                candidate.places.firstIndex {
                    $0.city.catalogIdentifier == catalogIdentifier
                }
            }
            let fallbackIndex = PlaceFallbackIdentity(city: city).flatMap {
                fallbackIdentity in
                candidate.places.firstIndex {
                    PlaceFallbackIdentity(city: $0.city) == fallbackIdentity
                }
            }

            if let existingIndex = exactIndex ?? catalogIndex ?? fallbackIndex {
                savedID = candidate.places[existingIndex].id
                Self.merge(
                    city: city,
                    customName: customName,
                    into: &candidate.places[existingIndex]
                )
            } else {
                let place = SavedPlace(city: city, customName: customName)
                candidate.places.insert(place, at: candidate.places.startIndex)
                savedID = place.id
            }

            if let collectionID,
               let collectionIndex = candidate.collections.firstIndex(
                where: { $0.id == collectionID }
               ),
               !candidate.collections[collectionIndex].placeIDs.contains(savedID) {
                candidate.collections[collectionIndex].placeIDs.append(savedID)
            }
        }
        return savedID
    }

    /// Changes or removes only the user-facing custom label.
    func setCustomName(_ name: String?, for placeID: SavedPlace.ID) throws {
        try mutateAndPersist { candidate in
            guard let index = candidate.places.firstIndex(where: { $0.id == placeID }) else {
                throw PlacesStoreError.placeNotFound(placeID)
            }
            candidate.places[index].customName = SavedPlace.normalizedCustomName(name)
        }
    }

    /// Globally deletes a place and prunes every collection membership.
    func deletePlace(id placeID: SavedPlace.ID) throws {
        try mutateAndPersist { candidate in
            guard candidate.places.contains(where: { $0.id == placeID }) else {
                throw PlacesStoreError.placeNotFound(placeID)
            }
            candidate.places.removeAll { $0.id == placeID }
            for index in candidate.collections.indices {
                candidate.collections[index].placeIDs.removeAll { $0 == placeID }
            }
        }
    }

    /// Replaces the All Places order after a native reorder operation.
    func setAllPlacesOrder(_ orderedIDs: [SavedPlace.ID]) throws {
        try mutateAndPersist { candidate in
            let existingIDs = candidate.places.map(\.id)
            guard Self.isExactReordering(orderedIDs, of: existingIDs) else {
                throw PlacesStoreError.invalidOrdering
            }
            let placesByID = Dictionary(
                uniqueKeysWithValues: candidate.places.map { ($0.id, $0) }
            )
            candidate.places = orderedIDs.compactMap { placesByID[$0] }
        }
    }

    // MARK: Collection Mutations

    /// Creates an empty or pre-populated optional collection.
    @discardableResult
    func createCollection(
        name: String,
        placeIDs: [SavedPlace.ID] = []
    ) throws -> PlaceCollection.ID {
        let normalizedName = try validatedCollectionName(name)
        var createdID = UUID().uuidString
        while document.collections.contains(where: { $0.id == createdID }) {
            createdID = UUID().uuidString
        }

        try mutateAndPersist { candidate in
            guard !Self.containsCollectionName(normalizedName, in: candidate.collections) else {
                throw PlacesStoreError.duplicateCollectionName(normalizedName)
            }
            guard Self.referencesKnownPlaces(placeIDs, in: candidate),
                  Set(placeIDs).count == placeIDs.count else {
                throw PlacesStoreError.invalidOrdering
            }
            candidate.collections.append(
                PlaceCollection(
                    id: createdID,
                    name: normalizedName,
                    placeIDs: placeIDs
                )
            )
        }
        return createdID
    }

    /// Renames a collection without changing its membership.
    func renameCollection(
        id collectionID: PlaceCollection.ID,
        to name: String
    ) throws {
        let normalizedName = try validatedCollectionName(name)
        try mutateAndPersist { candidate in
            guard let index = candidate.collections.firstIndex(
                where: { $0.id == collectionID }
            ) else {
                throw PlacesStoreError.collectionNotFound(collectionID)
            }
            guard !Self.containsCollectionName(
                normalizedName,
                in: candidate.collections,
                excluding: collectionID
            ) else {
                throw PlacesStoreError.duplicateCollectionName(normalizedName)
            }
            candidate.collections[index].name = normalizedName
        }
    }

    /// Deletes only the optional collection; saved places remain in All Places.
    func deleteCollection(id collectionID: PlaceCollection.ID) throws {
        try mutateAndPersist { candidate in
            guard candidate.collections.contains(where: { $0.id == collectionID }) else {
                throw PlacesStoreError.collectionNotFound(collectionID)
            }
            candidate.collections.removeAll { $0.id == collectionID }
            if candidate.selectedCollectionID == collectionID {
                candidate.selectedCollectionID = nil
            }
        }
    }

    /// Adds or removes one place/collection relationship.
    func setMembership(
        of placeID: SavedPlace.ID,
        in collectionID: PlaceCollection.ID,
        isMember: Bool
    ) throws {
        try mutateAndPersist { candidate in
            guard candidate.places.contains(where: { $0.id == placeID }) else {
                throw PlacesStoreError.placeNotFound(placeID)
            }
            guard let collectionIndex = candidate.collections.firstIndex(
                where: { $0.id == collectionID }
            ) else {
                throw PlacesStoreError.collectionNotFound(collectionID)
            }

            let containsPlace = candidate.collections[collectionIndex]
                .placeIDs
                .contains(placeID)
            if isMember, !containsPlace {
                candidate.collections[collectionIndex].placeIDs.append(placeID)
            } else if !isMember, containsPlace {
                candidate.collections[collectionIndex].placeIDs.removeAll {
                    $0 == placeID
                }
            }
        }
    }

    /// Replaces one collection's member order after a native reorder operation.
    func setPlaceOrder(
        _ orderedIDs: [SavedPlace.ID],
        in collectionID: PlaceCollection.ID
    ) throws {
        try mutateAndPersist { candidate in
            guard let index = candidate.collections.firstIndex(
                where: { $0.id == collectionID }
            ) else {
                throw PlacesStoreError.collectionNotFound(collectionID)
            }
            let existingIDs = candidate.collections[index].placeIDs
            guard Self.isExactReordering(orderedIDs, of: existingIDs) else {
                throw PlacesStoreError.invalidOrdering
            }
            candidate.collections[index].placeIDs = orderedIDs
        }
    }

    /// Replaces optional collection order.
    func setCollectionOrder(_ orderedIDs: [PlaceCollection.ID]) throws {
        try mutateAndPersist { candidate in
            let existingIDs = candidate.collections.map(\.id)
            guard Self.isExactReordering(orderedIDs, of: existingIDs) else {
                throw PlacesStoreError.invalidOrdering
            }
            let collectionsByID = Dictionary(
                uniqueKeysWithValues: candidate.collections.map { ($0.id, $0) }
            )
            candidate.collections = orderedIDs.compactMap { collectionsByID[$0] }
        }
    }

    /// Selects an optional collection, with `nil` representing All Places.
    func selectCollection(id collectionID: PlaceCollection.ID?) throws {
        try mutateAndPersist { candidate in
            if let collectionID,
               !candidate.collections.contains(where: { $0.id == collectionID }) {
                throw PlacesStoreError.collectionNotFound(collectionID)
            }
            candidate.selectedCollectionID = collectionID
        }
    }

    // MARK: Persistence Transaction

    private func mutateAndPersist(
        _ mutation: (inout PlacesLibraryDocument) throws -> Void
    ) throws {
        try ensureAvailable()
        var candidate = document
        try mutation(&candidate)
        guard candidate != document else { return }
        try persist(candidate)
    }

    private func persist(_ candidate: PlacesLibraryDocument) throws {
        try ensureAvailable()
        guard let documentStore else {
            throw PlacesStoreError.unavailable("No document location is available.")
        }

        do {
            let verifiedDocument = try documentStore.saveAndReadBack(candidate)
            document = verifiedDocument
            lastPersistenceErrorDescription = nil
        } catch {
            lastPersistenceErrorDescription = error.localizedDescription
            throw error
        }
    }

    private func ensureAvailable() throws {
        if let loadErrorDescription {
            throw PlacesStoreError.unavailable(loadErrorDescription)
        }
    }

    private static func loadOrBootstrap(
        documentStore: PlacesDocumentStore,
        defaults: UserDefaults,
        locale: Locale
    ) throws -> PlacesLibraryDocument {
        if let existingDocument = try documentStore.load() {
            if let importVersion = existingDocument.legacyImportVersion,
               defaults.integer(forKey: legacyMigrationMarkerKey) < importVersion {
                // `load()` is the required on-disk read-back and validation.
                defaults.set(importVersion, forKey: legacyMigrationMarkerKey)
            }
            return existingDocument
        }

        // A verified migration marker is also a tombstone for the old
        // list-owned format. If the current document is later removed or a
        // future file migration starts from an empty path, never resurrect
        // places the user may already have deleted in the new app.
        if defaults.integer(forKey: legacyMigrationMarkerKey)
            >= LegacyPlacesImporter.currentImportVersion {
            return try documentStore.saveAndReadBack(.empty)
        }

        let reader = LegacyPlacesSnapshotReader(defaults: defaults, locale: locale)
        if let legacySnapshot = try reader.readIfExistingInstall() {
            let importedDocument = try LegacyPlacesImporter.makeDocument(
                from: legacySnapshot
            )
            let verifiedDocument = try documentStore.saveAndReadBack(importedDocument)
            // Every legacy key remains untouched. Only this marker is added, and
            // only after atomic save plus independent decode/validation.
            defaults.set(
                LegacyPlacesImporter.currentImportVersion,
                forKey: legacyMigrationMarkerKey
            )
            return verifiedDocument
        }

        // A fresh install receives a real verified empty document but is never
        // labeled as migrated and receives no bundled synthetic collections.
        return try documentStore.saveAndReadBack(.empty)
    }

    private func validatedCollectionName(_ name: String) throws -> String {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PlacesLibraryValidator.isValidUserFacingName(
            normalizedName,
            maximumLength: PlacesLibraryValidator.maximumCollectionNameLength
        ) else {
            throw PlacesStoreError.invalidCollectionName
        }
        return normalizedName
    }

    private static func containsCollectionName(
        _ name: String,
        in collections: [PlaceCollection],
        excluding excludedID: PlaceCollection.ID? = nil
    ) -> Bool {
        collections.contains {
            $0.id != excludedID
                && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    private static func referencesKnownPlaces(
        _ placeIDs: [SavedPlace.ID],
        in document: PlacesLibraryDocument
    ) -> Bool {
        let knownIDs = Set(document.places.map(\.id))
        return placeIDs.allSatisfy { knownIDs.contains($0) }
    }

    private static func isExactReordering<ID: Hashable>(
        _ replacement: [ID],
        of existing: [ID]
    ) -> Bool {
        replacement.count == existing.count
            && Set(replacement).count == replacement.count
            && Set(replacement) == Set(existing)
    }

    private static func merge(
        city incomingCity: City,
        customName: String?,
        into existing: inout SavedPlace
    ) {
        let currentCity = existing.city
        existing.city = City(
            id: currentCity.id,
            name: incomingCity.name.isEmpty ? currentCity.name : incomingCity.name,
            country: incomingCity.country.isEmpty
                ? currentCity.country
                : incomingCity.country,
            latitude: currentCity.latitude,
            longitude: currentCity.longitude,
            timeZoneIdentifier: incomingCity.timeZoneIdentifier
                ?? currentCity.timeZoneIdentifier,
            catalogIdentifier: currentCity.catalogIdentifier
                ?? incomingCity.catalogIdentifier
        )
        if let normalizedName = SavedPlace.normalizedCustomName(customName) {
            existing.customName = normalizedName
        }
    }
}
