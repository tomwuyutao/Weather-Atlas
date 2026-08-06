//
//  WorldCitiesCatalog.swift
//  Weather
//
//  Purpose: Loads the bundled world-cities dataset once for region-neutral
//  place search and distance-ordered city lookup.
//

import CoreLocation
import Foundation

// MARK: - Catalog Models

/// One stable row in the bundled SimpleMaps world-cities dataset.
///
/// The source dataset's numeric identifier remains a string so its identity
/// does not depend on the integer width of the current platform.
nonisolated struct WorldCityRecord: Identifiable, Hashable, Sendable {
    /// Stable identifier supplied by the bundled dataset.
    let id: String
    /// Canonical city name, retaining source-language diacritics.
    let name: String
    /// ASCII city name supplied by the dataset.
    let asciiName: String
    /// Canonical English country name.
    let countryName: String
    /// ISO 3166-1 alpha-2 country code.
    let isoCountryCode: String
    /// ISO 3166-1 alpha-3 country code.
    let iso3CountryCode: String
    /// First-level administrative area, when supplied.
    let administrativeArea: String?
    /// Geographic latitude.
    let latitude: Double
    /// Geographic longitude.
    let longitude: Double
    /// Population used for deterministic candidate ranking.
    let population: Int

    /// Core Location coordinate used by MapKit and WeatherKit integrations.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// A geographically eligible city plus its distance from the query center.
nonisolated struct WorldCityDistanceCandidate: Identifiable, Hashable, Sendable {
    /// Catalog row selected before any weather request is made.
    let city: WorldCityRecord
    /// Great-circle distance from the user's coordinate.
    let distanceKilometers: Double

    /// Preserves the source dataset's stable city identity.
    var id: WorldCityRecord.ID { city.id }
}

/// Pre-normalized fields reused by every settled city-search query.
nonisolated private struct WorldCitySearchEntry: Sendable {
    let city: WorldCityRecord
    let normalizedName: String
    let normalizedASCIIName: String
    let normalizedNameWords: [Substring]
    let normalizedASCIINameWords: [Substring]
    let searchableMetadata: String
}

/// Failures that can occur while loading the bundled world-cities resource.
nonisolated enum WorldCitiesCatalogError: Error, Equatable, Sendable {
    case resourceMissing
    case unreadableResource
    case invalidHeader
    case noValidCities
}

// MARK: - Catalog

/// Lazily loads and queries the complete bundled world-cities dataset.
///
/// The catalog is an actor so every caller shares one background load task.
/// Geographic queries are distance-first with population as a stable tie-break;
/// callers choose their own result limit. The catalog performs no network or
/// weather work.
actor WorldCitiesCatalog {
    /// App-wide catalog backed by `worldcities.csv` in the main bundle.
    static let shared = WorldCitiesCatalog()

    /// The retained task ensures the 50,000-row resource is parsed at most once.
    private var loadTask: Task<[WorldCityRecord], Error>?
    /// Normalized search metadata is likewise built once, rather than folding
    /// all 50,000 rows after every debounce.
    private var searchIndexTask: Task<[WorldCitySearchEntry], Never>?

    /// Returns catalog cities inside a geographic radius, ordered nearest
    /// first so a caller can stop network work as soon as it finds a match.
    /// The catalog query itself is local and performs no WeatherKit requests.
    func cities(
        centeredAt center: CLLocationCoordinate2D,
        withinKilometers radiusKilometers: Double,
        fartherThanKilometers minimumDistanceKilometers: Double = 0,
        limit: Int
    ) async throws -> [WorldCityDistanceCandidate] {
        guard CLLocationCoordinate2DIsValid(center),
              radiusKilometers.isFinite,
              radiusKilometers > 0,
              minimumDistanceKilometers.isFinite,
              minimumDistanceKilometers >= 0,
              limit > 0 else {
            return []
        }

        let maximumLatitudeDelta = radiusKilometers / Self.minimumKilometersPerLatitudeDegree
        let cities = try await allCities()

        var candidates: [WorldCityDistanceCandidate] = []
        candidates.reserveCapacity(min(limit * 8, cities.count))
        for (index, city) in cities.enumerated() {
            if index.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            // This inexpensive geographic bound removes most of the dataset
            // before the more precise great-circle calculation.
            guard abs(city.latitude - center.latitude) <= maximumLatitudeDelta else {
                continue
            }

            let distance = Self.distanceKilometers(
                fromLatitude: center.latitude,
                longitude: center.longitude,
                toLatitude: city.latitude,
                longitude: city.longitude
            )
            guard distance <= radiusKilometers,
                  distance > minimumDistanceKilometers else {
                continue
            }

            candidates.append(
                WorldCityDistanceCandidate(
                    city: city,
                    distanceKilometers: distance
                )
            )
        }

        return Array(
            candidates.sorted(by: Self.isNearerCandidate).prefix(limit)
        )
    }

    /// Searches the bundled city index without inheriting the device's current
    /// MapKit region bias. Exact and prefix city-name matches come first, then
    /// population breaks ties so the most likely city remains easy to select.
    func cities(
        matching query: String,
        limit: Int = 12
    ) async throws -> [WorldCityRecord] {
        let normalizedQuery = Self.normalizedSearchText(query)
        guard !normalizedQuery.isEmpty, limit > 0 else { return [] }

        let queryTokens = normalizedQuery.split(separator: " ").map(String.init)
        let matches = try await searchIndex().compactMap {
            entry -> (city: WorldCityRecord, rank: Int)? in
            guard queryTokens.allSatisfy(entry.searchableMetadata.contains) else {
                return nil
            }

            let rank: Int
            if entry.normalizedName == normalizedQuery
                || entry.normalizedASCIIName == normalizedQuery {
                rank = 0
            } else if entry.normalizedName.hasPrefix(normalizedQuery)
                || entry.normalizedASCIIName.hasPrefix(normalizedQuery) {
                rank = 1
            } else if entry.normalizedNameWords.contains(
                where: { $0.hasPrefix(normalizedQuery) }
            ) || entry.normalizedASCIINameWords.contains(
                where: { $0.hasPrefix(normalizedQuery) }
            ) {
                rank = 2
            } else {
                rank = 3
            }
            return (entry.city, rank)
        }

        return Array(
            matches.sorted {
                if $0.rank != $1.rank {
                    return $0.rank < $1.rank
                }
                if $0.city.population != $1.city.population {
                    return $0.city.population > $1.city.population
                }
                if $0.city.name != $1.city.name {
                    return $0.city.name < $1.city.name
                }
                return $0.city.id < $1.city.id
            }
            .prefix(limit)
            .map(\.city)
        )
    }

    /// Returns parsed rows, starting and retaining one utility-priority task.
    private func allCities() async throws -> [WorldCityRecord] {
        if let loadTask {
            return try await loadTask.value
        }

        let url = try resolvedResourceURL()
        let task = Task.detached(priority: .utility) {
            try Self.decodeCities(at: url)
        }
        loadTask = task
        return try await task.value
    }

    /// Returns the one-time normalized search index.
    private func searchIndex() async throws -> [WorldCitySearchEntry] {
        if let searchIndexTask {
            return await searchIndexTask.value
        }

        let cities = try await allCities()
        let task = Task.detached(priority: .utility) {
            cities.map { city in
                let normalizedName = Self.normalizedSearchText(city.name)
                let normalizedASCIIName = Self.normalizedSearchText(
                    city.asciiName
                )
                let searchableMetadata = Self.normalizedSearchText(
                    [
                        city.name,
                        city.asciiName,
                        city.administrativeArea ?? "",
                        city.countryName,
                        city.isoCountryCode,
                        city.iso3CountryCode
                    ].joined(separator: " ")
                )
                return WorldCitySearchEntry(
                    city: city,
                    normalizedName: normalizedName,
                    normalizedASCIIName: normalizedASCIIName,
                    normalizedNameWords: normalizedName.split(separator: " "),
                    normalizedASCIINameWords: normalizedASCIIName.split(
                        separator: " "
                    ),
                    searchableMetadata: searchableMetadata
                )
            }
        }
        searchIndexTask = task
        return await task.value
    }

    /// Locates the resource in both Xcode's flattened bundle layout and a
    /// folder-preserving bundle layout.
    private func resolvedResourceURL() throws -> URL {
        guard let bundledURL =
                Bundle.main.url(forResource: "worldcities", withExtension: "csv")
                ?? Bundle.main.url(
                    forResource: "worldcities",
                    withExtension: "csv",
                    subdirectory: "Resources/Cities"
                )
                ?? Bundle.main.url(
                    forResource: "worldcities",
                    withExtension: "csv",
                    subdirectory: "Cities"
                ) else {
            throw WorldCitiesCatalogError.resourceMissing
        }
        return bundledURL
    }

    /// Orders candidates by distance, using population and stable identity only
    /// to make effectively equal coordinates deterministic.
    nonisolated private static func isNearerCandidate(
        _ lhs: WorldCityDistanceCandidate,
        _ rhs: WorldCityDistanceCandidate
    ) -> Bool {
        if lhs.distanceKilometers != rhs.distanceKilometers {
            return lhs.distanceKilometers < rhs.distanceKilometers
        }
        if lhs.city.population != rhs.city.population {
            return lhs.city.population > rhs.city.population
        }
        return lhs.id < rhs.id
    }

    /// Reads and validates the source dataset off the main actor.
    nonisolated private static func decodeCities(at url: URL) throws -> [WorldCityRecord] {
        guard let csv = try? String(contentsOf: url, encoding: .utf8) else {
            throw WorldCitiesCatalogError.unreadableResource
        }

        let lines = csv.split(whereSeparator: \.isNewline)
        guard let headerLine = lines.first else {
            throw WorldCitiesCatalogError.invalidHeader
        }

        let header = parseCSVRow(headerLine)
        let columns = Dictionary(
            uniqueKeysWithValues: header.enumerated().map { ($0.element, $0.offset) }
        )
        let requiredColumnNames = [
            "city",
            "city_ascii",
            "lat",
            "lng",
            "country",
            "iso2",
            "iso3",
            "admin_name",
            "population",
            "id"
        ]
        guard requiredColumnNames.allSatisfy({ columns[$0] != nil }) else {
            throw WorldCitiesCatalogError.invalidHeader
        }

        var cities: [WorldCityRecord] = []
        cities.reserveCapacity(max(0, lines.count - 1))

        for line in lines.dropFirst() {
            let fields = parseCSVRow(line)
            guard
                let cityIndex = columns["city"],
                let asciiIndex = columns["city_ascii"],
                let latitudeIndex = columns["lat"],
                let longitudeIndex = columns["lng"],
                let countryIndex = columns["country"],
                let iso2Index = columns["iso2"],
                let iso3Index = columns["iso3"],
                let adminIndex = columns["admin_name"],
                let populationIndex = columns["population"],
                let idIndex = columns["id"],
                fields.indices.contains(cityIndex),
                fields.indices.contains(asciiIndex),
                fields.indices.contains(latitudeIndex),
                fields.indices.contains(longitudeIndex),
                fields.indices.contains(countryIndex),
                fields.indices.contains(iso2Index),
                fields.indices.contains(iso3Index),
                fields.indices.contains(adminIndex),
                fields.indices.contains(populationIndex),
                fields.indices.contains(idIndex),
                let latitude = Double(fields[latitudeIndex]),
                let longitude = Double(fields[longitudeIndex]),
                latitude.isFinite,
                longitude.isFinite,
                (-90...90).contains(latitude),
                (-180...180).contains(longitude)
            else {
                continue
            }

            let identifier = fields[idIndex].trimmingCharacters(in: .whitespaces)
            let name = fields[cityIndex].trimmingCharacters(in: .whitespaces)
            let countryName = fields[countryIndex].trimmingCharacters(in: .whitespaces)
            let iso2 = fields[iso2Index]
                .trimmingCharacters(in: .whitespaces)
                .uppercased()
            guard !identifier.isEmpty,
                  !name.isEmpty,
                  !countryName.isEmpty,
                  iso2.count == 2 else {
                continue
            }

            let populationField = fields[populationIndex]
            let population = Int(populationField)
                ?? Double(populationField).flatMap {
                    $0.isFinite ? Int($0.rounded()) : nil
                }
                ?? 0
            let adminName = fields[adminIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            cities.append(
                WorldCityRecord(
                    id: identifier,
                    name: name,
                    asciiName: fields[asciiIndex],
                    countryName: countryName,
                    isoCountryCode: iso2,
                    iso3CountryCode: fields[iso3Index].uppercased(),
                    administrativeArea: adminName.isEmpty ? nil : adminName,
                    latitude: latitude,
                    longitude: longitude,
                    population: max(0, population)
                )
            )
        }

        guard !cities.isEmpty else {
            throw WorldCitiesCatalogError.noValidCities
        }
        return cities
    }

    /// Parses one quoted CSV row, including escaped quote pairs.
    nonisolated private static func parseCSVRow(_ row: Substring) -> [String] {
        let characters = Array(row)
        var fields: [String] = []
        fields.reserveCapacity(12)
        var currentField = ""
        var isInsideQuotes = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if isInsideQuotes,
                   index + 1 < characters.count,
                   characters[index + 1] == "\"" {
                    currentField.append("\"")
                    index += 1
                } else {
                    isInsideQuotes.toggle()
                }
            } else if character == ",", !isInsideQuotes {
                fields.append(currentField)
                currentField = ""
            } else {
                currentField.append(character)
            }
            index += 1
        }

        fields.append(currentField)
        return fields
    }

    /// Locale-stable normalization for city, region, and country search.
    nonisolated private static func normalizedSearchText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Haversine distance that handles the antimeridian without allocating
    /// thousands of `CLLocation` objects during each settings adjustment.
    nonisolated private static func distanceKilometers(
        fromLatitude sourceLatitude: Double,
        longitude sourceLongitude: Double,
        toLatitude destinationLatitude: Double,
        longitude destinationLongitude: Double
    ) -> Double {
        let latitudeDelta = degreesToRadians(destinationLatitude - sourceLatitude)
        let longitudeDelta = degreesToRadians(destinationLongitude - sourceLongitude)
        let sourceLatitudeRadians = degreesToRadians(sourceLatitude)
        let destinationLatitudeRadians = degreesToRadians(destinationLatitude)

        let haversine =
            pow(sin(latitudeDelta / 2), 2)
            + cos(sourceLatitudeRadians)
                * cos(destinationLatitudeRadians)
                * pow(sin(longitudeDelta / 2), 2)
        let centralAngle = 2 * atan2(sqrt(haversine), sqrt(max(0, 1 - haversine)))
        return earthRadiusKilometers * centralAngle
    }

    nonisolated private static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    /// Mean Earth radius recommended for great-circle distance.
    nonisolated private static let earthRadiusKilometers = 6_371.0088
    /// Conservative minimum distance represented by one latitude degree.
    nonisolated private static let minimumKilometersPerLatitudeDegree = 110.574
}
