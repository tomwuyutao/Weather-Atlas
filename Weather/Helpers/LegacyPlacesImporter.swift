//
//  LegacyPlacesImporter.swift
//  Weather
//
//  Purpose: Reads the existing UserDefaults-backed list format without mutating
//  it, then deterministically converts lists into independent saved places and
//  optional collections.
//

import Foundation

// MARK: - Pure Legacy Snapshot

/// One legacy city and its optional global custom label.
struct LegacySavedPlaceSnapshot: Equatable {
    let city: City
    let customName: String?
}

/// One legacy list after names, defaults, and saved city payloads are resolved.
struct LegacyCollectionSnapshot: Equatable {
    let rawID: String
    let name: String
    let places: [LegacySavedPlaceSnapshot]
}

/// Complete read-only input to the pure importer.
struct LegacyPlacesSnapshot: Equatable {
    let collections: [LegacyCollectionSnapshot]
    let activeCollectionID: String?
}

/// Failures that deliberately leave every legacy key and migration marker alone.
enum LegacyPlacesReaderError: LocalizedError {
    case corruptPreference(String)
    case duplicateListID(String)
    case invalidSavedCity(listID: String, cityID: UUID)

    var errorDescription: String? {
        switch self {
        case .corruptPreference(let key):
            return "Legacy preference \(key) could not be decoded."
        case .duplicateListID(let id):
            return "Legacy list identity \(id) occurs more than once."
        case let .invalidSavedCity(listID, cityID):
            return "Legacy list \(listID) contains invalid city \(cityID.uuidString)."
        }
    }
}

// MARK: - Read-only Legacy Persistence

/// Self-contained reader for the current list-based persistence keys.
///
/// This type never removes or rewrites a legacy key. It also refuses to infer a
/// migration from bundled default lists alone; first-install state therefore
/// remains an empty place library.
struct LegacyPlacesSnapshotReader {
    private enum Keys {
        static let hasLaunchedBefore = "hasLaunchedBefore"
        static let activeListID = "activeListID"
        static let userLists = "userCreatedLists"
        static let deletedBuiltInLists = "deletedBuiltInLists"
        static let listOrder = "listOrder"
        static let customListNames = "customListNames"
        static let customCityNames = "customCityNames"
        static let savedCitiesPrefix = "savedCitiesList_"
    }

    let defaults: UserDefaults
    let locale: Locale

    init(defaults: UserDefaults = .standard, locale: Locale = .autoupdatingCurrent) {
        self.defaults = defaults
        self.locale = locale
    }

    /// Evidence that this sandbox was used by the list-based app.
    ///
    /// Routine launch migrations and language/theme defaults are intentionally
    /// absent from this set because a brand-new install writes them too.
    func hasGenuineLegacyInstallEvidence() -> Bool {
        if defaults.bool(forKey: Keys.hasLaunchedBefore) {
            return true
        }

        let values = defaults.dictionaryRepresentation()
        let meaningfulKeys: Set<String> = [
            Keys.activeListID,
            Keys.userLists,
            Keys.deletedBuiltInLists,
            Keys.listOrder,
            Keys.customListNames,
            Keys.customCityNames
        ]
        return values.keys.contains(where: {
            meaningfulKeys.contains($0) || $0.hasPrefix(Keys.savedCitiesPrefix)
        })
    }

    /// Resolves the legacy catalog and returns `nil` for a genuine fresh install.
    func readIfExistingInstall() throws -> LegacyPlacesSnapshot? {
        guard hasGenuineLegacyInstallEvidence() else { return nil }

        let deletedBuiltInIDs = Set(
            defaults.stringArray(forKey: Keys.deletedBuiltInLists) ?? []
        )
        let userLists: [CityListID] = try decodeDataIfPresent(
            [CityListID].self,
            forKey: Keys.userLists
        ) ?? []
        let customListNames: [String: String] = try decodeDataIfPresent(
            [String: String].self,
            forKey: Keys.customListNames
        ) ?? [:]
        let customCityNames: [String: String] = try decodeDataIfPresent(
            [String: String].self,
            forKey: Keys.customCityNames
        ) ?? [:]

        let builtInLists = CityListID.builtInLists.filter {
            !deletedBuiltInIDs.contains($0.rawValue)
        }
        var visibleLists = builtInLists + userLists
        try ensureUniqueListIDs(visibleLists)

        if let persistedOrder = try readListOrder() {
            visibleLists = applyingPersistedOrder(persistedOrder, to: visibleLists)
        }

        let activeID = defaults.string(forKey: Keys.activeListID)
        if let activeID,
           let activeIndex = visibleLists.firstIndex(where: { $0.rawValue == activeID }),
           activeIndex != visibleLists.startIndex {
            let activeList = visibleLists.remove(at: activeIndex)
            visibleLists.insert(activeList, at: visibleLists.startIndex)
        }

        let snapshots = try visibleLists.map { listID in
            let name = resolvedListName(listID, customNames: customListNames)
            let cities = try resolvedCities(for: listID)
            let places = cities.map {
                LegacySavedPlaceSnapshot(
                    city: $0,
                    customName: resolvedCustomCityName($0, customNames: customCityNames)
                )
            }
            return LegacyCollectionSnapshot(
                rawID: listID.rawValue,
                name: name,
                places: places
            )
        }

        let selectedID = activeID.flatMap { id in
            snapshots.contains(where: { $0.rawID == id }) ? id : nil
        }
        return LegacyPlacesSnapshot(
            collections: snapshots,
            activeCollectionID: selectedID
        )
    }

    private func resolvedCities(for listID: CityListID) throws -> [City] {
        let key = Keys.savedCitiesPrefix + listID.rawValue
        guard let data = defaults.data(forKey: key) else {
            // Only built-in IDs produce bundled defaults. Custom lists without a
            // payload remain empty rather than acquiring unrelated cities.
            return listID.defaultCities
        }

        let cities: [City]
        if let cachedCities = try? JSONDecoder().decode([CachedCity].self, from: data) {
            cities = cachedCities.map { $0.toCity() }
        } else if let legacyCities = try? JSONDecoder().decode([City].self, from: data) {
            cities = legacyCities
        } else {
            throw LegacyPlacesReaderError.corruptPreference(key)
        }

        for city in cities where !PlacesLibraryValidator.isValidCity(city) {
            throw LegacyPlacesReaderError.invalidSavedCity(
                listID: listID.rawValue,
                cityID: city.id
            )
        }
        return cities
    }

    private func resolvedListName(
        _ listID: CityListID,
        customNames: [String: String]
    ) -> String {
        if let customName = customNames[listID.rawValue] {
            return customName
        }
        if let nameSource = listID.nameSource {
            return nameSource.localizedDisplayName(locale: locale)
        }
        return CityListID.localizedBuiltInDisplayName(
            for: listID.rawValue,
            locale: locale
        ) ?? listID.displayName
    }

    private func resolvedCustomCityName(
        _ city: City,
        customNames: [String: String]
    ) -> String? {
        let latitude = legacyCoordinateString(city.latitude)
        let longitude = legacyCoordinateString(city.longitude)
        let currentKey = "\(city.name)|\(city.country)|\(latitude)|\(longitude)"
        let olderKey = "\(city.country)|\(latitude)|\(longitude)"
        return customNames[currentKey] ?? customNames[olderKey]
    }

    private func legacyCoordinateString(_ value: Double) -> String {
        String(
            format: "%.4f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }

    private func readListOrder() throws -> [String]? {
        if let data = defaults.data(forKey: Keys.listOrder) {
            guard let order = try? JSONDecoder().decode([String].self, from: data) else {
                throw LegacyPlacesReaderError.corruptPreference(Keys.listOrder)
            }
            return order
        }
        return defaults.stringArray(forKey: Keys.listOrder)
    }

    private func applyingPersistedOrder(
        _ rawIDs: [String],
        to lists: [CityListID]
    ) -> [CityListID] {
        let lookup = Dictionary(uniqueKeysWithValues: lists.map { ($0.rawValue, $0) })
        var consumed = Set<String>()
        var ordered: [CityListID] = []
        ordered.reserveCapacity(lists.count)

        for rawID in rawIDs where consumed.insert(rawID).inserted {
            if let list = lookup[rawID] {
                ordered.append(list)
            }
        }
        ordered.append(contentsOf: lists.filter { consumed.insert($0.rawValue).inserted })
        return ordered
    }

    private func ensureUniqueListIDs(_ lists: [CityListID]) throws {
        var identifiers = Set<String>()
        for list in lists where !identifiers.insert(list.rawValue).inserted {
            throw LegacyPlacesReaderError.duplicateListID(list.rawValue)
        }
    }

    private func decodeDataIfPresent<Value: Decodable>(
        _ type: Value.Type,
        forKey key: String
    ) throws -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let value = try? JSONDecoder().decode(type, from: data) else {
            throw LegacyPlacesReaderError.corruptPreference(key)
        }
        return value
    }
}

// MARK: - Deterministic Import

/// Four-decimal coordinate identity matching the existing custom-name format.
struct RoundedPlaceCoordinate: Hashable {
    let latitude: Int64
    let longitude: Int64

    init(latitude: Double, longitude: Double) {
        self.latitude = Int64((latitude * 10_000).rounded(.toNearestOrAwayFromZero))
        self.longitude = Int64((longitude * 10_000).rounded(.toNearestOrAwayFromZero))
    }

    init(city: City) {
        self.init(latitude: city.latitude, longitude: city.longitude)
    }
}

/// Coordinate fallback strengthened with semantic city and country identity.
///
/// This intentionally does not deduplicate unnamed coordinate placeholders:
/// distinct catalog cities can legitimately share the same rounded coordinate.
struct PlaceFallbackIdentity: Hashable {
    let coordinate: RoundedPlaceCoordinate
    let cityName: String
    let countryName: String

    init?(city: City) {
        let cityName = Self.normalized(city.name)
        let countryName = Self.normalized(city.country)
        guard !cityName.isEmpty, !countryName.isEmpty else { return nil }

        coordinate = RoundedPlaceCoordinate(city: city)
        self.cityName = cityName
        self.countryName = countryName
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }
}

/// Pure conversion from list ownership to place ownership.
enum LegacyPlacesImporter {
    static let currentImportVersion = 1

    /// Deduplicates by UUID, then stable catalog identity, then coordinates
    /// only when semantic city and country names also agree.
    ///
    /// Collections preserve their legacy raw IDs, names, city order, and the
    /// reader's active-list-first collection order.
    static func makeDocument(
        from snapshot: LegacyPlacesSnapshot
    ) throws -> PlacesLibraryDocument {
        var places: [SavedPlace] = []
        var placeIndexByID: [SavedPlace.ID: Int] = [:]
        var placeIndexByCatalogID: [String: Int] = [:]
        var placeIndexByFallbackIdentity: [PlaceFallbackIdentity: Int] = [:]
        var collections: [PlaceCollection] = []

        for legacyCollection in snapshot.collections {
            var membership: [SavedPlace.ID] = []
            var membershipSet = Set<SavedPlace.ID>()

            for legacyPlace in legacyCollection.places {
                let city = legacyPlace.city
                let existingIndex = placeIndexByID[city.id]
                    ?? city.catalogIdentifier.flatMap {
                        placeIndexByCatalogID[$0]
                    }
                    ?? PlaceFallbackIdentity(city: city).flatMap {
                        placeIndexByFallbackIdentity[$0]
                    }
                let placeID: SavedPlace.ID

                if let existingIndex {
                    merge(
                        legacyPlace,
                        into: &places[existingIndex]
                    )
                    if let catalogIdentifier = places[existingIndex]
                        .city
                        .catalogIdentifier {
                        placeIndexByCatalogID[catalogIdentifier] = existingIndex
                    }
                    if let fallbackIdentity = PlaceFallbackIdentity(
                        city: places[existingIndex].city
                    ) {
                        placeIndexByFallbackIdentity[fallbackIdentity] = existingIndex
                    }
                    placeID = places[existingIndex].id
                } else {
                    let savedPlace = SavedPlace(
                        city: city,
                        customName: legacyPlace.customName
                    )
                    let newIndex = places.endIndex
                    places.append(savedPlace)
                    placeIndexByID[savedPlace.id] = newIndex
                    if let catalogIdentifier = savedPlace.city.catalogIdentifier {
                        placeIndexByCatalogID[catalogIdentifier] = newIndex
                    }
                    if let fallbackIdentity = PlaceFallbackIdentity(
                        city: savedPlace.city
                    ) {
                        placeIndexByFallbackIdentity[fallbackIdentity] = newIndex
                    }
                    placeID = savedPlace.id
                }

                if membershipSet.insert(placeID).inserted {
                    membership.append(placeID)
                }
            }

            collections.append(
                PlaceCollection(
                    id: legacyCollection.rawID,
                    name: legacyCollection.name,
                    placeIDs: membership
                )
            )
        }

        let selectedCollectionID = snapshot.activeCollectionID.flatMap { activeID in
            collections.contains(where: { $0.id == activeID }) ? activeID : nil
        }
        let document = PlacesLibraryDocument(
            places: places,
            collections: collections,
            selectedCollectionID: selectedCollectionID,
            legacyImportVersion: currentImportVersion
        )
        try PlacesLibraryValidator.validate(document)
        return document
    }

    /// Keeps the first-seen identity and coordinates while filling metadata that
    /// may have been absent in one list's copy.
    private static func merge(
        _ incoming: LegacySavedPlaceSnapshot,
        into existing: inout SavedPlace
    ) {
        let currentCity = existing.city
        let incomingCity = incoming.city
        let mergedName = currentCity.name.isEmpty ? incomingCity.name : currentCity.name
        let mergedCountry = currentCity.country.isEmpty
            ? incomingCity.country
            : currentCity.country
        let mergedTimeZone = currentCity.timeZoneIdentifier
            ?? incomingCity.timeZoneIdentifier

        existing.city = City(
            id: currentCity.id,
            name: mergedName,
            country: mergedCountry,
            latitude: currentCity.latitude,
            longitude: currentCity.longitude,
            timeZoneIdentifier: mergedTimeZone,
            catalogIdentifier: currentCity.catalogIdentifier
                ?? incomingCity.catalogIdentifier
        )
        if existing.customName == nil {
            existing.customName = SavedPlace.normalizedCustomName(incoming.customName)
        }
    }
}
