//
//  SavedPlacesStore.swift
//  Weather
//
//  Purpose: Owns the flat Saved Places library, its validation rules, and its
//  atomic on-disk persistence. This is the single source of truth for saved
//  cities; SwiftUI views ask it to mutate a document instead of writing files.
//
//  Reading guide: the file moves from small value types at the top, through the
//  JSON document boundary and validation, to the observable store at the end.
//

import CoreLocation
import Foundation
import Observation

// MARK: - Saved Places Data

/// One city the user has chosen to keep in Saved Places.
///
/// The stable identity comes from `City.id`, not the display name. This lets a
/// person rename "London" without creating a second saved place or breaking
/// navigation and cached weather keyed by its UUID.
struct SavedPlace: Identifiable, Codable, Equatable, Hashable {
    var city: City
    var customName: String?

    /// `Identifiable` forwards the city's persistent UUID for SwiftUI lists.
    var id: UUID { city.id }

    init(city: City, customName: String? = nil) {
        self.city = city
        self.customName = Self.normalizedCustomName(customName)
    }

    /// Primary presentation name. A custom name never replaces the underlying
    /// geographic `City`; it only changes what saved-place surfaces lead with.
    var displayName: String { customName ?? city.displayName }

    /// Treats blank names as absent, so the UI naturally falls back to the city.
    static func normalizedCustomName(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Saved-place forecast state used by Map presentation.
///
/// This is presentation state, not something stored in the JSON library: a
/// recommendation/loading state belongs to the current weather request and is
/// allowed to disappear on the next launch.
struct SavedPlacePresentation: Identifiable {
    let place: SavedPlace
    let recommendation: PlaceRecommendation?
    let isLoading: Bool

    var id: SavedPlace.ID { place.id }
}

/// Versioned persistence payload for the flat Saved Places library.
///
/// `Codable` intentionally ignores historical collection keys when reading an
/// existing document. The next ordinary save rewrites it as this flat schema.
struct PlacesLibraryDocument: Codable, Equatable {
    /// Bumping this value creates an explicit migration decision for future code.
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

}

/// Gives UI code one stable entry point for Places-specific error copy.
func localizedPlacesErrorDescription(_ error: Error) -> String {
    (error as? PlacesStoreError)?.errorDescription ?? error.localizedDescription
}

// MARK: - Document Persistence

/// Persistence failures kept separate from domain validation failures.
///
/// Separating these categories helps callers distinguish a malformed library
/// from a storage problem such as a failed read-back verification.
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
///
/// It knows nothing about SwiftUI. That makes file operations testable with an
/// injected URL/FileManager and keeps the observable store focused on state.
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
    /// Application Support is appropriate for app-owned data that should be
    /// backed up with the app but not be manually visible in Files.
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
    /// `mappedIfSafe` lets Foundation use memory mapping for a normal file while
    /// remaining free to choose a safer loading strategy when necessary.
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
        // Validate before encoding so corrupt in-memory state can never replace
        // a previously good file on disk.
        try PlacesLibraryValidator.validate(document)
        let data = try makeEncoder().encode(document)
        guard data.count <= Self.maximumEncodedByteCount else {
            throw PlacesDocumentStoreError.documentTooLarge(data.count)
        }

        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // `.atomic` writes a temporary file then replaces the destination. A
        // crash cannot leave a half-written JSON document at `fileURL`.
        var writingOptions: Data.WritingOptions = [.atomic]
#if os(iOS) || os(tvOS) || os(watchOS)
        writingOptions.insert(.completeFileProtectionUnlessOpen)
#endif
        try data.write(to: fileURL, options: writingOptions)

        // Treat the save as a small transaction: read and validate the bytes we
        // just wrote before publishing them to the observable in-memory state.
        guard let verifiedDocument = try load() else {
            throw PlacesDocumentStoreError.readBackMissing
        }
        guard verifiedDocument == document else {
            throw PlacesDocumentStoreError.readBackMismatch
        }
        return verifiedDocument
    }

    /// Decodes a fixture or on-disk payload through the production validator.
    /// Tests use this same boundary so a fixture cannot accidentally bypass the
    /// checks that protect a real customer library.
    func decodeAndValidate(_ data: Data) throws -> PlacesLibraryDocument {
        guard data.count <= Self.maximumEncodedByteCount else {
            throw PlacesDocumentStoreError.documentTooLarge(data.count)
        }
        let document = try makeDecoder().decode(PlacesLibraryDocument.self, from: data)
        try PlacesLibraryValidator.validate(document)
        return document
    }

    /// Uses deterministic JSON settings for stable files and reliable read-back.
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
    case missingPlaceName(UUID)
    case missingCountry(UUID)
    case missingTimeZone(UUID)
    case invalidTimeZone(UUID, String)
    case invalidPlace(UUID)
    case invalidCustomName(UUID)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "The Places library uses unsupported schema version \(version)."
        case .tooManyPlaces(let count):
            "The Places library contains too many places (\(count))."
        case .duplicatePlaceID:
            "The Places library contains duplicate internal place data."
        case .missingPlaceName:
            "Place name data is missing for a saved place."
        case .missingCountry:
            "Country data is missing for a saved place."
        case .missingTimeZone:
            "Time zone data is missing for a saved place."
        case .invalidTimeZone(_, let identifier):
            "A saved place has invalid time zone data: \(identifier)."
        case .invalidPlace:
            "A saved place contains invalid place metadata."
        case .invalidCustomName:
            "A saved place contains an invalid custom name."
        }
    }
}

/// Guards the document boundary against malformed, oversized, or duplicate data.
///
/// Validation is intentionally independent from the store so it can run on both
/// newly constructed documents and bytes read from storage.
enum PlacesLibraryValidator {
    static let maximumPlaceCount = 25_000
    static let maximumPlaceNameLength = 500
    static let maximumIdentifierLength = 200

    /// Performs cheap, deterministic checks before a document becomes visible.
    static func validate(_ document: PlacesLibraryDocument) throws {
        guard document.schemaVersion == PlacesLibraryDocument.currentSchemaVersion else {
            throw PlacesLibraryValidationError.unsupportedSchemaVersion(document.schemaVersion)
        }
        guard document.places.count <= maximumPlaceCount else {
            throw PlacesLibraryValidationError.tooManyPlaces(document.places.count)
        }
        // A `Set` makes duplicate UUID detection linear rather than repeatedly
        // scanning the growing array for every saved place.
        var placeIDs = Set<SavedPlace.ID>()
        for place in document.places {
            guard placeIDs.insert(place.id).inserted else {
                throw PlacesLibraryValidationError.duplicatePlaceID(place.id)
            }
            let city = place.city
            guard isValidUserFacingName(
                city.name,
                maximumLength: maximumPlaceNameLength
            ) else {
                if city.name.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty {
                    throw PlacesLibraryValidationError.missingPlaceName(place.id)
                }
                throw PlacesLibraryValidationError.invalidPlace(place.id)
            }
            guard isValidUserFacingName(
                city.country,
                maximumLength: maximumPlaceNameLength
            ) else {
                if city.country.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty {
                    throw PlacesLibraryValidationError.missingCountry(place.id)
                }
                throw PlacesLibraryValidationError.invalidPlace(place.id)
            }
            // A Saved Place is a durable user choice, not a completed forecast
            // record. Older libraries and a temporary geocoder outage can lack
            // a timezone, but that must not hide the entire library or turn a
            // harmless local-date exclusion into a load failure. Leave the
            // timezone optional here; the local coordinate time-zone lookup
            // resolves it before WeatherKit is queried, and a successfully
            // resolved city is written back by `WeatherModel.loadSavedWeather`.
            //
            // New places still go through `isValidCity(_:)` at the save boundary,
            // so search/map flows cannot deliberately create incomplete rows.
            if let timeZoneIdentifier = city.timeZoneIdentifier?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !timeZoneIdentifier.isEmpty {
                guard timeZoneIdentifier.count <= maximumIdentifierLength,
                      !containsUnsafeControlCharacters(timeZoneIdentifier) else {
                    throw PlacesLibraryValidationError.invalidTimeZone(
                        place.id,
                        timeZoneIdentifier
                    )
                }
            }
            guard isValidCityStructure(city) else {
                throw PlacesLibraryValidationError.invalidPlace(place.id)
            }
            if let customName = place.customName,
               !isValidUserFacingName(customName, maximumLength: maximumPlaceNameLength) {
                throw PlacesLibraryValidationError.invalidCustomName(place.id)
            }
        }
    }

    /// Accepts only complete, representable place metadata.
    static func isValidCity(_ city: City) -> Bool {
        guard isValidUserFacingName(
            city.name,
            maximumLength: maximumPlaceNameLength
        ), isValidUserFacingName(
            city.country,
            maximumLength: maximumPlaceNameLength
        ), let timeZoneIdentifier = city.timeZoneIdentifier?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !timeZoneIdentifier.isEmpty,
           timeZoneIdentifier.count <= maximumIdentifierLength,
           !containsUnsafeControlCharacters(timeZoneIdentifier),
           TimeZone(identifier: timeZoneIdentifier) != nil else {
            return false
        }
        return isValidCityStructure(city)
    }

    private static func isValidCityStructure(_ city: City) -> Bool {
        guard city.latitude.isFinite, city.longitude.isFinite,
              (-90...90).contains(city.latitude),
              (-180...180).contains(city.longitude) else {
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

    /// Newlines/tabs are permitted in user text; other control scalars can make
    /// JSON/UI rendering confusing, so reject them at the persistence boundary.
    private static func containsUnsafeControlCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t"
        }
    }
}

// MARK: - Duplicate-Detection Identities

/// A normalized fallback identity for cities originating from different sources.
///
/// UUID is the preferred identity, followed by a catalog ID. This final form
/// catches a geocoded city and a catalog city that represent the same place but
/// arrived with different UUIDs.
private struct SavedPlaceSemanticIdentity {
    /// Different providers often use different representative points for the
    /// same city centre. Ten kilometres is deliberately city-scale; matching
    /// names/countries and conflict checks below keep nearby distinct cities apart.
    private static let maximumDistanceMeters: CLLocationDistance = 10_000

    let location: CLLocation
    let cityName: String
    let countryName: String
    let timeZoneIdentifier: String?
    let catalogIdentifier: String?

    init?(city: City) {
        guard city.latitude.isFinite, city.longitude.isFinite,
              (-90...90).contains(city.latitude), (-180...180).contains(city.longitude) else { return nil }
        let cityName = Self.normalized(city.name)
        let countryName = Self.normalized(city.country)
        guard !cityName.isEmpty, !countryName.isEmpty else { return nil }
        location = CLLocation(
            latitude: city.latitude,
            longitude: city.longitude
        )
        self.cityName = cityName
        self.countryName = countryName
        timeZoneIdentifier = city.timeZoneIdentifier?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        catalogIdentifier = city.catalogIdentifier?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    func matches(_ other: SavedPlaceSemanticIdentity) -> Bool {
        guard cityName == other.cityName,
              countryName == other.countryName else {
            return false
        }
        if let catalogIdentifier,
           let otherCatalogIdentifier = other.catalogIdentifier,
           catalogIdentifier != otherCatalogIdentifier {
            return false
        }
        if let timeZoneIdentifier,
           let otherTimeZoneIdentifier = other.timeZoneIdentifier,
           timeZoneIdentifier != otherTimeZoneIdentifier {
            return false
        }
        return location.distance(from: other.location)
            <= Self.maximumDistanceMeters
    }

    /// Removes presentation-only differences before comparing city/country text.
    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}

// MARK: - Observable Saved Places Store

/// The main-actor store exposes a safely observable library to SwiftUI.
///
/// `@Observable` lets views track only the properties they read. `@MainActor`
/// serializes mutations with UI updates, which is especially important because
/// every successful mutation replaces the complete `document` value.
@MainActor
@Observable
final class SavedPlacesStore {
    /// The verified in-memory copy of the complete JSON document.
    private(set) var document: PlacesLibraryDocument
    /// A persistent failure shown by settings/UI instead of causing a crash.
    private(set) var loadErrorDescription: String?
    /// File I/O dependency hidden from Observation because views never render it.
    @ObservationIgnored private var documentStore: PlacesDocumentStore?

    /// Loads the existing library synchronously during app setup, or starts an
    /// empty, verified document on the first launch. The injectable argument is
    /// primarily for tests and previews that should not touch user storage.
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

    /// Creates a storage-free store for Xcode previews and deterministic UI
    /// fixtures. It deliberately has no backing document store, so a preview
    /// cannot read or change a person's Saved Places library.
    init(inMemoryDocument document: PlacesLibraryDocument) {
        self.document = document
        documentStore = nil
        loadErrorDescription = nil
    }

    /// Read-only convenience used by screens that should not edit the document.
    var allPlaces: [SavedPlace] { document.places }

    /// Looks up one row by its stable UUID for detail navigation and editing.
    func place(id: SavedPlace.ID) -> SavedPlace? {
        document.places.first { $0.id == id }
    }

    /// Finds an existing saved place using increasingly forgiving identities.
    ///
    /// Order matters: UUID is exact, a catalog ID links bundled rows, and the
    /// semantic identity only handles otherwise equivalent geocoded cities.
    func savedPlaceID(matching city: City) -> SavedPlace.ID? {
        if let match = document.places.first(where: { $0.id == city.id }) { return match.id }
        if let catalogID = city.catalogIdentifier,
           let match = document.places.first(where: { $0.city.catalogIdentifier == catalogID }) { return match.id }
        guard let identity = SavedPlaceSemanticIdentity(city: city) else { return nil }
        return document.places.first {
            guard let candidate = SavedPlaceSemanticIdentity(city: $0.city) else {
                return false
            }
            return identity.matches(candidate)
        }?.id
    }

    /// Lets the UI retry a transient file-system failure without recreating data.
    /// If the initial failure was resolving Application Support itself, acquire a
    /// new live store before attempting the normal document load again.
    func retryLoading() {
        guard loadErrorDescription != nil else { return }
        do {
            let store: PlacesDocumentStore
            if let documentStore {
                store = documentStore
            } else {
                let liveStore = try PlacesDocumentStore.live()
                documentStore = liveStore
                store = liveStore
            }
            document = try Self.loadOrCreate(documentStore: store)
            loadErrorDescription = nil
        } catch { loadErrorDescription = error.localizedDescription }
    }

    /// Replaces the whole library through the normal verified persistence path.
    func resetToEmptyLibrary() throws { try persist(.empty) }

    @discardableResult
    /// Adds one city at the front of the library or merges refreshed metadata.
    /// Returning the existing/new ID lets a caller navigate to the canonical row.
    func savePlace(_ city: City, customName: String? = nil) throws -> SavedPlace.ID {
        // Incoming places are created only from a fully resolved Search/Map/
        // WeatherKit result. Existing legacy rows may be incomplete on disk, but
        // they remain displayable and are repaired asynchronously rather than
        // allowing new incomplete rows to accumulate.
        guard PlacesLibraryValidator.isValidCity(city) else {
            throw PlacesLibraryValidationError.invalidPlace(city.id)
        }
        var savedID = city.id
        try mutateAndPersist { candidate in
            // A repeated Save is an update, not a duplicate. The merge preserves
            // user-owned values such as the existing UUID and custom name.
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
    /// Saves a batch atomically, deduplicating both against the library and
    /// within the incoming array before one file write.
    func savePlaces(_ cities: [City]) throws -> [SavedPlace.ID] {
        guard !cities.isEmpty else { return [] }
        if let incompleteCity = cities.first(
            where: { !PlacesLibraryValidator.isValidCity($0) }
        ) {
            throw PlacesLibraryValidationError.invalidPlace(incompleteCity.id)
        }
        var savedIDs: [SavedPlace.ID] = []
        try mutateAndPersist { savedIDs = Self.mergeCities(cities, into: &$0) }
        return savedIDs
    }

    /// Deletes exactly one row; an unknown ID is surfaced rather than ignored.
    func deletePlace(id placeID: SavedPlace.ID) throws {
        try mutateAndPersist { candidate in
            guard candidate.places.contains(where: { $0.id == placeID }) else {
                throw PlacesStoreError.placeNotFound(placeID)
            }
            candidate.places.removeAll { $0.id == placeID }
        }
    }

    /// Changes only the user-owned custom name of one saved city.
    /// Passing `nil` or whitespace removes the override and restores the source
    /// city name through `SavedPlace.displayName`.
    func setCustomName(
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

    /// Runs a mutation against a throwaway value, then publishes it only after
    /// validated atomic persistence succeeds. This is a small value-type
    /// transaction: the live document remains unchanged if any step throws.
    private func mutateAndPersist(_ mutation: (inout PlacesLibraryDocument) throws -> Void) throws {
        try ensureAvailable()
        var candidate = document
        try mutation(&candidate)
        guard candidate != document else { return }
        try persist(candidate)
    }

    /// Makes the store's memory reflect the document read back from disk—not
    /// merely the candidate that was asked to be saved.
    private func persist(_ candidate: PlacesLibraryDocument) throws {
        try ensureAvailable()
        guard let documentStore else { throw PlacesStoreError.unavailable("No document location is available.") }
        document = try documentStore.saveAndReadBack(candidate)
    }

    /// Prevents a later edit from overwriting data after the initial load failed.
    private func ensureAvailable() throws {
        if let loadErrorDescription { throw PlacesStoreError.unavailable(loadErrorDescription) }
    }

    /// Establishes a real empty file on first launch so subsequent operations
    /// always use the same validation/read-back path as existing libraries.
    private static func loadOrCreate(documentStore: PlacesDocumentStore) throws -> PlacesLibraryDocument {
        if let document = try documentStore.load() { return document }
        return try documentStore.saveAndReadBack(.empty)
    }

    /// Shared private counterpart of `savedPlaceID(matching:)` for mutations.
    private static func matchingPlaceIndex(for city: City, in places: [SavedPlace]) -> Int? {
        if let index = places.firstIndex(where: { $0.id == city.id }) { return index }
        if let catalogID = city.catalogIdentifier,
           let index = places.firstIndex(where: { $0.city.catalogIdentifier == catalogID }) { return index }
        guard let identity = SavedPlaceSemanticIdentity(city: city) else { return nil }
        return places.firstIndex {
            guard let candidate = SavedPlaceSemanticIdentity(city: $0.city) else {
                return false
            }
            return identity.matches(candidate)
        }
    }

    /// Resolves each incoming city to a stable ID while accumulating unseen rows.
    /// New rows are inserted together at the front only after the full batch has
    /// been examined, preserving the incoming order and avoiding index drift.
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

    /// Refreshes source metadata without overwriting stable identity, coordinate,
    /// or a previously chosen custom name unless the caller provides a new one.
    private static func merge(city incoming: City, customName: String?, into existing: inout SavedPlace) {
        let current = existing.city
        existing.city = City(
            id: current.id,
            name: incoming.name.isEmpty ? current.name : incoming.name,
            titleName: incoming.titleName ?? current.titleName,
            country: incoming.country.isEmpty ? current.country : incoming.country,
            latitude: current.latitude,
            longitude: current.longitude,
            timeZoneIdentifier: incoming.timeZoneIdentifier ?? current.timeZoneIdentifier,
            catalogIdentifier: current.catalogIdentifier ?? incoming.catalogIdentifier
        )
        if let customName = SavedPlace.normalizedCustomName(customName) { existing.customName = customName }
    }
}
