//
//  WorldCitiesCatalog.swift
//  Weather
//
//  Purpose: Loads the bundled world-cities dataset once for Map discovery,
//  nearby-city lookup, and first-run saved places.
//

import CoreLocation
import Foundation
import MapKit

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
    /// Canonical English country name.
    let countryName: String
    /// ISO 3166-1 alpha-2 country code.
    let isoCountryCode: String
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
    /// A deliberately curated, world-spanning starter collection for a new
    /// Saved Places library. Each label resolves to its canonical row in the
    /// bundled world-cities dataset rather than maintaining a second dataset.
    private static let starterCityLabels: [(name: String, countryCode: String)] = [
        ("London", "GB"),
        ("Paris", "FR"),
        ("New York", "US"),
        ("Mexico City", "MX"),
        ("Sao Paulo", "BR"),
        ("Cairo", "EG"),
        ("Johannesburg", "ZA"),
        ("Istanbul", "TR"),
        ("Dubai", "AE"),
        ("Mumbai", "IN"),
        ("Singapore", "SG"),
        ("Beijing", "CN"),
        ("Shanghai", "CN"),
        ("Tokyo", "JP"),
        ("Sydney", "AU")
    ]

    /// Returns the curated first-run cities in their intended overview order.
    func starterCities() async throws -> [WorldCityRecord] {
        let cities = try await allCities()
        return Self.starterCityLabels.compactMap { label in
            cities
                .filter {
                    $0.isoCountryCode == label.countryCode
                        && Self.normalizedSearchText($0.name)
                            == Self.normalizedSearchText(label.name)
                }
                .max { lhs, rhs in
                    if lhs.population != rhs.population {
                        return lhs.population < rhs.population
                    }
                    return lhs.id > rhs.id
                }
        }
    }

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

    /// Returns the most populous catalog cities inside a radius while retaining
    /// their distance for later local ranking. Home uses this one bounded set
    /// across date changes instead of making a new WeatherKit search per day.
    func mostPopulousCities(
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

        let maximumLatitudeDelta =
            radiusKilometers / Self.minimumKilometersPerLatitudeDegree
        let cities = try await allCities()
        var candidates: [WorldCityDistanceCandidate] = []
        candidates.reserveCapacity(min(limit * 8, cities.count))

        for (index, city) in cities.enumerated() {
            if index.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
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

        return Array(candidates.sorted {
            if $0.city.population != $1.city.population {
                return $0.city.population > $1.city.population
            }
            if $0.distanceKilometers != $1.distanceKilometers {
                return $0.distanceKilometers < $1.distanceKilometers
            }
            return $0.city.id < $1.city.id
        }.prefix(limit))
    }

    /// Returns the most populous cities visible in a MapKit region. This is a
    /// screen-area query rather than a radius query, so Find Sun mirrors the
    /// part of the map the person is actually looking at.
    func cities(
        visibleIn region: MKCoordinateRegion,
        limit: Int
    ) async throws -> [WorldCityRecord] {
        guard CLLocationCoordinate2DIsValid(region.center),
              region.span.latitudeDelta > 0,
              region.span.longitudeDelta > 0,
              limit > 0 else {
            return []
        }

        let lowerLatitude = max(-90, region.center.latitude - region.span.latitudeDelta / 2)
        let upperLatitude = min(90, region.center.latitude + region.span.latitudeDelta / 2)
        let rawLowerLongitude = region.center.longitude - region.span.longitudeDelta / 2
        let rawUpperLongitude = region.center.longitude + region.span.longitudeDelta / 2
        let lowerLongitude = Self.normalizedLongitude(rawLowerLongitude)
        let upperLongitude = Self.normalizedLongitude(rawUpperLongitude)
        let crossesAntimeridian = rawLowerLongitude < -180 || rawUpperLongitude > 180

        let cities = try await allCities()
        var matches: [WorldCityRecord] = []
        matches.reserveCapacity(min(cities.count, limit * 8))
        for (index, city) in cities.enumerated() {
            if index.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            guard city.latitude >= lowerLatitude,
                  city.latitude <= upperLatitude else {
                continue
            }
            let longitudeMatches = crossesAntimeridian
                ? city.longitude >= lowerLongitude || city.longitude <= upperLongitude
                : city.longitude >= lowerLongitude && city.longitude <= upperLongitude
            if longitudeMatches {
                matches.append(city)
            }
        }

        return Array(matches.sorted {
            if $0.population != $1.population { return $0.population > $1.population }
            return $0.id < $1.id
        }.prefix(limit))
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
            "lat",
            "lng",
            "country",
            "iso2",
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
                let latitudeIndex = columns["lat"],
                let longitudeIndex = columns["lng"],
                let countryIndex = columns["country"],
                let iso2Index = columns["iso2"],
                let populationIndex = columns["population"],
                let idIndex = columns["id"],
                fields.indices.contains(cityIndex),
                fields.indices.contains(latitudeIndex),
                fields.indices.contains(longitudeIndex),
                fields.indices.contains(countryIndex),
                fields.indices.contains(iso2Index),
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
            cities.append(
                WorldCityRecord(
                    id: identifier,
                    name: name,
                    countryName: countryName,
                    isoCountryCode: iso2,
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

    nonisolated private static func normalizedLongitude(_ longitude: Double) -> Double {
        let normalized = longitude.truncatingRemainder(dividingBy: 360)
        if normalized > 180 { return normalized - 360 }
        if normalized < -180 { return normalized + 360 }
        return normalized
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
