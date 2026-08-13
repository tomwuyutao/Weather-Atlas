//
//  CitiesCatalog.swift
//  Weather
//
//  Purpose: Loads the bundled world-cities dataset once for Map discovery,
//  nearby-city lookup, and first-run saved places.
//
//  Reading guide: this actor protects one shared CSV load, then exposes local
//  geographic queries. It supplies candidates only; WeatherKit requests and
//  "sunny" decisions happen elsewhere in the model/service layer.
//

import CoreLocation
import Foundation
import MapKit

// MARK: - Catalog Models

/// One stable row in the bundled SimpleMaps world-cities dataset.
///
/// The source dataset's numeric identifier remains a string so its identity
/// does not depend on the integer width of the current platform.
/// `nonisolated` and `Sendable` let these immutable values safely move out of
/// the catalog actor into UI/model tasks without copying actor-owned state.
nonisolated struct CatalogCity: Identifiable, Hashable, Sendable {
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
    /// Population used for candidate ranking when the source supplied it.
    /// Missing population remains nil and is surfaced as a catalog issue.
    let population: Int?
    /// An authoritative IANA timezone supplied only for the fixed starter
    /// collection. General catalog rows intentionally leave this unset until
    /// their place metadata has been resolved.
    let timeZoneIdentifier: String?

    /// Core Location coordinate used by MapKit and WeatherKit integrations.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// A geographically eligible city plus its distance from the query center.
/// Keeping the distance with the row avoids recomputing it when a caller later
/// ranks or labels the candidates.
nonisolated struct CatalogCityDistanceCandidate: Identifiable, Hashable, Sendable {
    /// Catalog row selected before any weather request is made.
    let city: CatalogCity
    /// Great-circle distance from the user's coordinate.
    let distanceKilometers: Double

    /// Preserves the source dataset's stable city identity.
    var id: CatalogCity.ID { city.id }
}

/// Failures that can occur while loading the bundled world-cities resource.
/// They deliberately describe the local resource boundary rather than WeatherKit
/// failures, which belong to `WeatherService`.
nonisolated enum CitiesCatalogError: Error, Equatable, Sendable {
    case resourceMissing
    case unreadableResource
    case invalidHeader
    case noValidCities
    case missingStarterCities([String])
}

/// Partial bundled-data omissions that leave affected metadata blank while
/// allowing unrelated, fully sourced catalog rows to remain useful.
nonisolated enum CitiesCatalogIssue: Hashable, Sendable {
    case missingPopulation(Int)
    case invalidRows(Int)
}

/// One validated catalog load plus aggregate omissions retained for native
/// alert presentation by the feature that actually uses this source.
nonisolated private struct CitiesCatalogData: Sendable {
    let cities: [CatalogCity]
    let issues: [CitiesCatalogIssue]
}

// MARK: - Catalog

/// Lazily loads and queries the complete bundled world-cities dataset.
///
/// The catalog is an actor so every caller shares one background load task.
/// Geographic queries are distance-first with population as a stable tie-break;
/// callers choose their own result limit. The catalog performs no network or
/// weather work.
actor CitiesCatalog {
    /// App-wide catalog backed by `worldcities.csv` in the main bundle.
    static let shared = CitiesCatalog()

    /// The retained task ensures the 50,000-row resource is parsed at most once.
    /// Multiple callers arriving during the first load await this same task,
    /// rather than independently parsing the large CSV on separate threads.
    private var loadTask: Task<CitiesCatalogData, Error>?
    /// A deliberately curated, world-spanning starter collection for a new
    /// Saved Places library. The names resolve to their canonical rows in the
    /// bundled catalog; the zones are factual metadata for this fixed set so
    /// resetting the app never waits on a network lookup before restoring it.
    private static let starterCityLabels: [StarterCityLabel] = [
        .init("London", "GB", "Europe/London"),
        .init("Paris", "FR", "Europe/Paris"),
        .init("New York", "US", "America/New_York"),
        .init("Mexico City", "MX", "America/Mexico_City"),
        .init("Sao Paulo", "BR", "America/Sao_Paulo"),
        .init("Cairo", "EG", "Africa/Cairo"),
        .init("Johannesburg", "ZA", "Africa/Johannesburg"),
        .init("Istanbul", "TR", "Europe/Istanbul"),
        .init("Dubai", "AE", "Asia/Dubai"),
        .init("Mumbai", "IN", "Asia/Kolkata"),
        .init("Singapore", "SG", "Asia/Singapore"),
        .init("Beijing", "CN", "Asia/Shanghai"),
        .init("Shanghai", "CN", "Asia/Shanghai"),
        .init("Tokyo", "JP", "Asia/Tokyo"),
        .init("Sydney", "AU", "Australia/Sydney")
    ]

    private struct StarterCityLabel: Sendable {
        let name: String
        let countryCode: String
        let timeZoneIdentifier: String

        init(_ name: String, _ countryCode: String, _ timeZoneIdentifier: String) {
            self.name = name
            self.countryCode = countryCode
            self.timeZoneIdentifier = timeZoneIdentifier
        }
    }

    /// Returns the curated first-run cities in their intended overview order.
    /// Matching by normalized name + ISO code lets the labels remain readable in
    /// source while still resolving to one canonical data row. `max` settles a
    /// rare duplicate-name case with population, then a stable source ID.
    func starterCities() async throws -> [CatalogCity] {
        let cities = try await allCities()
        var resolved: [CatalogCity] = []
        var missingLabels: [String] = []
        for label in Self.starterCityLabels {
            let match = cities
                .filter {
                    $0.isoCountryCode == label.countryCode
                        && Self.normalizedSearchText($0.name)
                            == Self.normalizedSearchText(label.name)
                }
                .max { lhs, rhs in
                    if lhs.population != rhs.population {
                        return Self.populationRanksBefore(
                            rhs.population,
                            lhs.population
                        )
                    }
                    return lhs.id > rhs.id
                }
            if let match {
                resolved.append(
                    CatalogCity(
                        id: match.id,
                        name: match.name,
                        countryName: match.countryName,
                        isoCountryCode: match.isoCountryCode,
                        latitude: match.latitude,
                        longitude: match.longitude,
                        population: match.population,
                        timeZoneIdentifier: label.timeZoneIdentifier
                    )
                )
            } else {
                missingLabels.append("\(label.name) (\(label.countryCode))")
            }
        }
        guard missingLabels.isEmpty else {
            throw CitiesCatalogError.missingStarterCities(missingLabels)
        }
        return resolved
    }

    /// Aggregate partial omissions from the already shared catalog load.
    func dataIssues() async throws -> [CitiesCatalogIssue] {
        try await catalogData().issues
    }

    /// Discards one previously failed or partial parsing task so a caller can
    /// make one fresh attempt before surfacing a missing-catalog alert. The
    /// bundled resource itself is immutable for a running build, but retrying
    /// the read protects against a transient file-read or task-cancellation
    /// failure without inventing a fallback catalog.
    func reload() {
        loadTask?.cancel()
        loadTask = nil
    }

    /// Returns catalog cities inside a geographic radius, ordered nearest
    /// first so a caller can stop network work as soon as it finds a match.
    /// The catalog query itself is local and performs no WeatherKit requests.
    func cities(
        centeredAt center: CLLocationCoordinate2D,
        withinKilometers radiusKilometers: Double,
        fartherThanKilometers minimumDistanceKilometers: Double = 0,
        limit: Int
    ) async throws -> [CatalogCityDistanceCandidate] {
        // Treat invalid user/configuration values as an empty local query. This
        // avoids constructing nonsensical coordinates or throwing for a normal
        // empty-search UI state.
        guard CLLocationCoordinate2DIsValid(center),
              radiusKilometers.isFinite,
              radiusKilometers > 0,
              minimumDistanceKilometers.isFinite,
              minimumDistanceKilometers >= 0,
              limit > 0 else {
            return []
        }

        // A latitude-only bounding box is much cheaper than a Haversine distance.
        // It is deliberately conservative: cities that pass still get the exact
        // great-circle calculation in the loop below.
        let maximumLatitudeDelta = radiusKilometers / Self.minimumKilometersPerLatitudeDegree
        let cities = try await allCities()

        var candidates: [CatalogCityDistanceCandidate] = []
        candidates.reserveCapacity(min(limit * 8, cities.count))
        for (index, city) in cities.enumerated() {
            // The dataset is large enough that a cancelled sheet/search should
            // stop promptly instead of finishing a useless full scan.
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
                CatalogCityDistanceCandidate(
                    city: city,
                    distanceKilometers: distance
                )
            )
        }

        // Sorting after filtering is simpler and deterministic. `prefix` limits
        // only the returned candidates, not the geographic correctness of scan.
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
    ) async throws -> [CatalogCityDistanceCandidate] {
        guard CLLocationCoordinate2DIsValid(center),
              radiusKilometers.isFinite,
              radiusKilometers > 0,
              minimumDistanceKilometers.isFinite,
              minimumDistanceKilometers >= 0,
              limit > 0 else {
            return []
        }

        // This repeats the radius scan rather than calling `cities(...)` because
        // the two public methods differ in ordering: nearby UI wants distance,
        // while the nearby-sun candidate pool wants population first.
        let maximumLatitudeDelta =
            radiusKilometers / Self.minimumKilometersPerLatitudeDegree
        let cities = try await allCities()
        var candidates: [CatalogCityDistanceCandidate] = []
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
                CatalogCityDistanceCandidate(
                    city: city,
                    distanceKilometers: distance
                )
            )
        }

        // Population is the primary product heuristic; distance and stable ID
        // make tied populations deterministic across launches.
        return Array(candidates.sorted {
            if $0.city.population != $1.city.population {
                return Self.populationRanksBefore(
                    $0.city.population,
                    $1.city.population
                )
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
    ) async throws -> [CatalogCity] {
        guard CLLocationCoordinate2DIsValid(region.center),
              region.span.latitudeDelta > 0,
              region.span.longitudeDelta > 0,
              limit > 0 else {
            return []
        }

        // Clamp latitude because MapKit regions can be wider than a physical
        // world. Longitude uses a separate normalization step because it wraps.
        let lowerLatitude = max(-90, region.center.latitude - region.span.latitudeDelta / 2)
        let upperLatitude = min(90, region.center.latitude + region.span.latitudeDelta / 2)
        let rawLowerLongitude = region.center.longitude - region.span.longitudeDelta / 2
        let rawUpperLongitude = region.center.longitude + region.span.longitudeDelta / 2
        let lowerLongitude = Self.normalizedLongitude(rawLowerLongitude)
        let upperLongitude = Self.normalizedLongitude(rawUpperLongitude)
        // A region around ±180° is two longitude intervals, e.g. [170, 180] and
        // [-180, -170]. This Boolean keeps both halves in the map-visible query.
        let crossesAntimeridian = rawLowerLongitude < -180 || rawUpperLongitude > 180

        let cities = try await allCities()
        var matches: [CatalogCity] = []
        matches.reserveCapacity(min(cities.count, limit * 8))
        for (index, city) in cities.enumerated() {
            if index.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            guard city.latitude >= lowerLatitude,
                  city.latitude <= upperLatitude else {
                continue
            }
            // Choose between one ordinary interval and two antimeridian pieces.
            let longitudeMatches = crossesAntimeridian
                ? city.longitude >= lowerLongitude || city.longitude <= upperLongitude
                : city.longitude >= lowerLongitude && city.longitude <= upperLongitude
            if longitudeMatches {
                matches.append(city)
            }
        }

        return Array(matches.sorted {
            if $0.population != $1.population {
                return Self.populationRanksBefore($0.population, $1.population)
            }
            return $0.id < $1.id
        }.prefix(limit))
    }

    // MARK: - One-Time Resource Loading

    /// Returns parsed rows, starting and retaining one utility-priority task.
    private func allCities() async throws -> [CatalogCity] {
        try await catalogData().cities
    }

    private func catalogData() async throws -> CitiesCatalogData {
        // Actor isolation makes this check-and-store sequence serial. Once one
        // caller creates the task, every later caller awaits its same `value`.
        if let loadTask {
            return try await loadTask.value
        }

        let url = try resolvedResourceURL()
        // CSV decoding is CPU/file work, not UI work. A detached utility task
        // avoids inheriting a caller's actor and leaves interactive work ahead.
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
            throw CitiesCatalogError.resourceMissing
        }
        return bundledURL
    }

    // MARK: - Query Helpers

    /// Orders candidates strictly by distance and stable identity. Population
    /// is irrelevant to this query, so a missing population is never replaced
    /// merely to break a geographic tie.
    nonisolated private static func isNearerCandidate(
        _ lhs: CatalogCityDistanceCandidate,
        _ rhs: CatalogCityDistanceCandidate
    ) -> Bool {
        if lhs.distanceKilometers != rhs.distanceKilometers {
            return lhs.distanceKilometers < rhs.distanceKilometers
        }
        return lhs.id < rhs.id
    }

    /// Known populations rank high-to-low; nil remains an unknown value at the
    /// end instead of being converted into a real population of zero.
    nonisolated static func populationRanksBefore(
        _ lhs: Int?,
        _ rhs: Int?
    ) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): lhs > rhs
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): false
        }
    }

    // MARK: - CSV Decoding

    /// Reads and validates the source dataset off the main actor.
    /// `nonisolated` permits the detached load task above to call this pure
    /// helper without hopping back to the `CitiesCatalog` actor.
    nonisolated private static func decodeCities(
        at url: URL
    ) throws -> CitiesCatalogData {
        guard let csv = try? String(contentsOf: url, encoding: .utf8) else {
            throw CitiesCatalogError.unreadableResource
        }

        let lines = csv.split(whereSeparator: \.isNewline)
        guard let headerLine = lines.first else {
            throw CitiesCatalogError.invalidHeader
        }

        // Build a name → index table because the source column order is not an
        // app contract. A known header is safer than hard-coding numeric offsets.
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
            throw CitiesCatalogError.invalidHeader
        }

        var cities: [CatalogCity] = []
        cities.reserveCapacity(max(0, lines.count - 1))
        var missingPopulationCount = 0
        var invalidRowCount = 0

        // Skip malformed rows individually. A large public dataset can contain
        // imperfect records, but valid cities should remain available to Map.
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
                invalidRowCount += 1
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
                invalidRowCount += 1
                continue
            }

            let populationField = fields[populationIndex].trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            // The data source may encode a whole population as `1234` or
            // `1234.0`; accept either representation. Missing, negative, or
            // malformed population remains nil—it is never rewritten as zero.
            let population: Int?
            if populationField.isEmpty {
                population = nil
            } else if let integer = Int(populationField), integer >= 0 {
                population = integer
            } else if let value = Double(populationField),
                      value.isFinite,
                      value >= 0,
                      value.rounded(.towardZero) == value,
                      value < Double(Int.max) {
                population = Int(value)
            } else {
                population = nil
            }
            if population == nil {
                missingPopulationCount += 1
            }
            cities.append(
                CatalogCity(
                    id: identifier,
                    name: name,
                    countryName: countryName,
                    isoCountryCode: iso2,
                    latitude: latitude,
                    longitude: longitude,
                    population: population,
                    timeZoneIdentifier: nil
                )
            )
        }

        guard !cities.isEmpty else {
            throw CitiesCatalogError.noValidCities
        }
        var issues: [CitiesCatalogIssue] = []
        if missingPopulationCount > 0 {
            issues.append(.missingPopulation(missingPopulationCount))
        }
        if invalidRowCount > 0 {
            issues.append(.invalidRows(invalidRowCount))
        }
        return CitiesCatalogData(cities: cities, issues: issues)
    }

    /// Parses one quoted CSV row, including escaped quote pairs.
    /// This mirrors the smaller country catalog parser: commas are separators
    /// only outside quotes, while `""` inside quotes represents one literal `"`.
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
                // A doubled quote is data; every other quote flips parser state.
                if isInsideQuotes,
                   index + 1 < characters.count,
                   characters[index + 1] == "\"" {
                    currentField.append("\"")
                    index += 1
                } else {
                    isInsideQuotes.toggle()
                }
            } else if character == ",", !isInsideQuotes {
                // Finish the current field only at a delimiter outside quotes.
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
    /// The fixed POSIX locale makes matching repeatable regardless of the app
    /// language; folding ignores case, accents, and full-width characters while
    /// collapsing runs of whitespace into one canonical space.
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

    /// Wraps any longitude into the conventional closed range [-180, 180].
    /// Map regions can cross the antimeridian and temporarily produce values
    /// beyond that range before a city coordinate is compared against them.
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
        // Haversine converts two latitude/longitude pairs to the central angle
        // on a sphere. Trigonometric functions expect radians, not degrees.
        let latitudeDelta = degreesToRadians(destinationLatitude - sourceLatitude)
        let longitudeDelta = degreesToRadians(destinationLongitude - sourceLongitude)
        let sourceLatitudeRadians = degreesToRadians(sourceLatitude)
        let destinationLatitudeRadians = degreesToRadians(destinationLatitude)

        let haversine =
            pow(sin(latitudeDelta / 2), 2)
            + cos(sourceLatitudeRadians)
                * cos(destinationLatitudeRadians)
                * pow(sin(longitudeDelta / 2), 2)
        // `max(0, ...)` protects against a tiny floating-point overshoot above 1
        // before square root. Multiplying by Earth radius yields kilometres.
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
