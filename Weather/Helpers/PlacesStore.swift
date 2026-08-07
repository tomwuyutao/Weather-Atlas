//
//  PlacesStore.swift
//  Weather
//
//  Purpose: Owns the flat Saved Places library and atomic persistence.
//

import Foundation
import Observation

// MARK: - Saved Places Data

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

/// Saved-place forecast state shared by the Places list and map.
struct SavedPlacePresentation: Identifiable {
    let place: SavedPlace
    let recommendation: PlaceRecommendation?
    let isLoading: Bool
    let failureMessage: String?

    var id: SavedPlace.ID { place.id }
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

// MARK: - Document Persistence

/// Persistence failures kept separate from domain validation failures.
enum PlacesDocumentStoreError: LocalizedError {
    case documentTooLarge(Int)
    case readBackMissing
    case readBackMismatch

    var errorDescription: String? {
        switch self {
        case .documentTooLarge(let byteCount):
            return "The Places library file is unexpectedly large (\(byteCount) bytes)."
        case .readBackMissing:
            return "The Places library could not be read after it was saved."
        case .readBackMismatch:
            return "The Places library changed while verifying its saved contents."
        }
    }
}

/// File-backed document persistence with validation on every boundary.
struct PlacesDocumentStore {
    /// The current schema has its own filename so a future migration can keep
    /// the previous version available until the replacement is verified.
    static let currentFileName = "places-library-v1.json"
    /// Defensive encoded-file limit; the model has stricter item-count limits.
    static let maximumEncodedByteCount = 25 * 1_024 * 1_024

    let fileURL: URL
    private let fileManager: FileManager

    /// Creates an injectable store for production or deterministic fixtures.
    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    /// Resolves the app-specific Application Support document location.
    static func live(
        fileManager: FileManager = .default,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) throws -> PlacesDocumentStore {
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryName = bundleIdentifier ?? "WeatherAtlas"
        let directoryURL = applicationSupportURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("Places", isDirectory: true)
        return PlacesDocumentStore(
            fileURL: directoryURL.appendingPathComponent(currentFileName),
            fileManager: fileManager
        )
    }

    /// Loads and validates the current document, or returns `nil` if none exists.
    func load() throws -> PlacesLibraryDocument? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        return try decodeAndValidate(data)
    }

    /// Atomically saves, reopens, validates, and compares a complete document.
    ///
    /// Callers must use the returned value as their in-memory source of truth.
    /// Callers can treat a successful return as a fully verified commit.
    @discardableResult
    func saveAndReadBack(
        _ document: PlacesLibraryDocument
    ) throws -> PlacesLibraryDocument {
        try PlacesLibraryValidator.validate(document)
        let data = try makeEncoder().encode(document)
        guard data.count <= Self.maximumEncodedByteCount else {
            throw PlacesDocumentStoreError.documentTooLarge(data.count)
        }

        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var writingOptions: Data.WritingOptions = [.atomic]
#if os(iOS) || os(tvOS) || os(watchOS)
        writingOptions.insert(.completeFileProtectionUnlessOpen)
#endif
        try data.write(to: fileURL, options: writingOptions)

        guard let verifiedDocument = try load() else {
            throw PlacesDocumentStoreError.readBackMissing
        }
        guard verifiedDocument == document else {
            throw PlacesDocumentStoreError.readBackMismatch
        }
        return verifiedDocument
    }

    /// Decodes a fixture or on-disk payload through the production validator.
    func decodeAndValidate(_ data: Data) throws -> PlacesLibraryDocument {
        guard data.count <= Self.maximumEncodedByteCount else {
            throw PlacesDocumentStoreError.documentTooLarge(data.count)
        }
        let document = try makeDecoder().decode(PlacesLibraryDocument.self, from: data)
        try PlacesLibraryValidator.validate(document)
        return document
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Library Validation

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

    /// Changes only the user-owned display name of one saved city.
    func renamePlace(
        id placeID: SavedPlace.ID,
        customName: String?
    ) throws {
        try mutateAndPersist { candidate in
            guard let index = candidate.places.firstIndex(
                where: { $0.id == placeID }
            ) else {
                throw PlacesStoreError.placeNotFound(placeID)
            }
            candidate.places[index].customName = SavedPlace.normalizedCustomName(
                customName
            )
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
