//
//  PlacesDocumentStore.swift
//  Weather
//
//  Purpose: Reads and atomically writes the versioned Places library document
//  in Application Support.
//

import Foundation

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
    /// A migration marker can safely be written only after this method returns.
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
