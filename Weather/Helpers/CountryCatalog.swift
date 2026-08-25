//
//  CountryCatalog.swift
//  Weather
//
//  Purpose: Loads the bundled country-city catalog used by Map's country and
//  continent queries.
//
//  Reading guide: this file is a local-data service. It never calls WeatherKit
//  or the network; it parses one CSV resource, then answers deterministic
//  country, continent, and city-ranking questions.
//

import CryptoKit
import CoreLocation
import Foundation

// MARK: - Geographic Place Sources

/// A country and its population-ranked bundled cities.
/// `Identifiable` gives SwiftUI pickers a stable ISO-code identity, while
/// `Hashable` makes the value safe to use in navigation and selections.
struct CountryPlacesOption: Identifiable, Hashable {
    /// ISO 3166-1 alpha-2 identity used by search and localization.
    let iso2: String
    /// Stable English fallback when a locale has no region name.
    let englishName: String
    /// Available source cities ordered from largest population downward.
    let cities: [CountryCityCatalogEntry]

    var id: String { iso2 }

    /// Resolves the system-localized country name without persisting it.
    /// We retain English as source data but localize only at display time, so a
    /// language change does not require rewriting the catalog or saved cities.
    func localizedName(locale: Locale) -> String {
        locale.localizedString(forRegionCode: iso2) ?? englishName
    }
}

/// The six continent scopes available in Map's Find Sun query.
/// These are product-defined search buckets, not a full geopolitical taxonomy;
/// their exact country membership appears later in `continentCountryCodes`.
enum ContinentPlacesOption: String, CaseIterable, Identifiable, Hashable {
    case europe
    case asia
    case northAmerica
    case southAmerica
    case africa
    case australia

    var id: String { rawValue }

    /// Returns the canonical localized label used throughout Weather Atlas.
    func localizedName(locale: Locale) -> String {
        switch self {
        case .europe:
            localizedString("Europe", locale: locale)
        case .asia:
            localizedString("Asia", locale: locale)
        case .northAmerica:
            localizedString("North America", locale: locale)
        case .southAmerica:
            localizedString("South America", locale: locale)
        case .africa:
            localizedString("Africa", locale: locale)
        case .australia:
            localizedString("Australia", locale: locale)
        }
    }
}

/// One validated row from the bundled country-city CSV catalog.
/// Raw CSV is parsed once into this typed form so the rest of the app never
/// indexes string arrays or needs to revalidate latitude/timezone fields.
struct CountryCityCatalogEntry: Identifiable, Hashable {
    /// Reproducible identity derived only from factual source fields.
    let id: UUID
    /// Compact source identity persisted with a saved catalog city.
    let catalogIdentifier: String
    /// Canonical city name.
    let city: String
    /// Canonical country name.
    let country: String
    /// ISO 3166-1 alpha-2 country code.
    let iso2: String
    /// Geographic latitude.
    let latitude: Double
    /// Geographic longitude.
    let longitude: Double
    /// IANA timezone identifier.
    let timeZoneIdentifier: String
    /// Population used for deterministic city ranking.
    let population: Int

    init(
        city: String,
        country: String,
        iso2: String,
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String,
        population: Int
    ) {
        self.city = city
        self.country = country
        self.iso2 = iso2
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.population = population

        // The CSV has no provider ID. Hash the normalized factual row identity
        // (excluding population, which can be revised without moving a city) so
        // repeated catalog queries never manufacture a fresh UUID.
        let normalizedCity = city
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
        let sourceKey = [
            iso2.uppercased(),
            normalizedCity,
            String(latitude.bitPattern),
            String(longitude.bitPattern),
            timeZoneIdentifier
        ].joined(separator: "|")
        let digest = Array(SHA256.hash(data: Data(sourceKey.utf8)))
        var uuidBytes = Array(digest.prefix(16))
        uuidBytes[6] = (uuidBytes[6] & 0x0F) | 0x50
        uuidBytes[8] = (uuidBytes[8] & 0x3F) | 0x80
        id = UUID(
            uuid: (
                uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
                uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
                uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
                uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
            )
        )
        catalogIdentifier = "country-city:" + digest.map {
            String(format: "%02x", $0)
        }.joined()
    }

    /// Converts the catalog row into the app's persistable city model.
    var appCity: City {
        City(
            id: id,
            name: city,
            country: country,
            latitude: latitude,
            longitude: longitude,
            timeZoneIdentifier: timeZoneIdentifier,
            catalogIdentifier: catalogIdentifier
        )
    }

    /// Mirrors Saved Places' city-scale duplicate rule so two near-identical
    /// source rows cannot later collapse onto one saved UUID only after Map has
    /// already accepted both as distinct candidates.
    func representsSamePlace(as other: CountryCityCatalogEntry) -> Bool {
        guard iso2 == other.iso2,
              timeZoneIdentifier == other.timeZoneIdentifier,
              normalizedCityName == other.normalizedCityName else {
            return false
        }
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let otherLocation = CLLocation(
            latitude: other.latitude,
            longitude: other.longitude
        )
        return location.distance(from: otherLocation) <= 10_000
    }

    private var normalizedCityName: String {
        city.trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}

/// Bundled-data failures retained by the catalog loader.
///
/// A few malformed rows are a developer diagnostic, not a reason to interrupt a
/// search that still has usable candidates. Only source-wide failures prevent a
/// country or continent query from running.
enum CountryCityCatalogIssue: Hashable {
    case resourceMissing
    case unreadableResource
    case invalidRows(Int)
    case noValidCities
}

// MARK: - Country City Catalog

/// Loads and queries the bundled population-ranked country-city resource.
///
/// This enum acts as a namespace for immutable global data. `catalog` is a lazy
/// static value, so Foundation initializes it once, on first use, and thereafter
/// each query works only with already-validated Swift values.
enum CountryCityCatalog {
    // MARK: - Public Queries

    /// Resource problems retained alongside any valid catalog rows.
    static var dataIssues: [CountryCityCatalogIssue] {
        catalog.issues
    }

    /// Returns every available country, sorted by its localized display name.
    /// `localizedStandardCompare` gives people familiar ordering such as natural
    /// number handling, rather than sorting the English fallback byte-for-byte.
    static func countries(locale: Locale) -> [CountryPlacesOption] {
        catalog.countriesByCode.values.sorted {
            $0.localizedName(locale: locale).localizedStandardCompare(
                $1.localizedName(locale: locale)
            ) == .orderedAscending
        }
    }

    /// Returns every catalog country ordered by distance from the supplied
    /// coordinate to that country's nearest bundled city. This is a factual
    /// proximity proxy: it avoids pretending that an irregular country has one
    /// authoritative centre point while still making nearby choices easy to
    /// reach. Without a usable coordinate, it preserves localized A–Z order.
    static func countries(
        near coordinate: CLLocationCoordinate2D?,
        locale: Locale
    ) -> [CountryPlacesOption] {
        let allCountries = countries(locale: locale)
        guard let coordinate,
              CLLocationCoordinate2DIsValid(coordinate) else {
            return allCountries
        }

        let location = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        return allCountries
            .map { country in
                let nearestDistance = country.cities.reduce(
                    CLLocationDistance.greatestFiniteMagnitude
                ) { nearestDistance, city in
                    let cityLocation = CLLocation(
                        latitude: city.latitude,
                        longitude: city.longitude
                    )
                    return min(nearestDistance, location.distance(from: cityLocation))
                }
                return (country, nearestDistance)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 < rhs.1
                }
                return lhs.0.localizedName(locale: locale)
                    .localizedStandardCompare(rhs.0.localizedName(locale: locale))
                    == .orderedAscending
            }
            .map(\.0)
    }

    /// Resolves one bundled country from an ISO 3166-1 alpha-2 code.
    static func country(iso2: String) -> CountryPlacesOption? {
        catalog.countriesByCode[iso2.uppercased()]
    }

    /// Returns a timezone only when every validated city in the factual bundled
    /// country catalog uses the same IANA identifier. This is not a nearest-city
    /// or coordinate guess: it merely lets another catalog with no timezone
    /// column reuse an unambiguous country-wide source fact (for example, GB).
    /// Countries spanning more than one zone intentionally return `nil` so
    /// WeatherService can resolve the exact coordinate through its local
    /// time-zone boundary database.
    static func unambiguousTimeZoneIdentifier(forISO2 iso2: String) -> String? {
        let identifiers = Set(
            catalog.countriesByCode[iso2.uppercased()]?.cities.map(
                \.timeZoneIdentifier
            ) ?? []
        )
        guard identifiers.count == 1 else { return nil }
        return identifiers.first
    }

    /// Resolves the supported continent for a bundled country.
    /// The inner `Set` keeps membership checks fast even though a continent can
    /// contain many ISO codes.
    static func continent(
        for country: CountryPlacesOption
    ) -> ContinentPlacesOption? {
        continentCountryCodes.first { _, countryCodes in
            countryCodes.contains(country.iso2)
        }?.key
    }

    /// Returns the requested leading population-ranked cities for a country.
    /// `max(0, limit)` makes a negative UI/configuration value harmless rather
    /// than relying on `prefix` behavior at every call site.
    static func topCities(
        for country: CountryPlacesOption,
        limit: Int
    ) -> [City] {
        Array(country.cities.prefix(max(0, limit))).map(\.appCity)
    }

    // MARK: - Candidate Sampling

    /// Selects up to the requested number of population-leading cities while
    /// replacing nearby boroughs/localities with later distinct destinations.
    /// This uses only bundled catalog data, before any WeatherKit request.
    static func spatiallyDistinctTopCities(
        for country: CountryPlacesOption,
        resultLimit: Int,
        sourceCandidateLimit: Int,
        clusterRadiusKilometers: Double
    ) -> [City] {
        spatiallyDistinctCities(
            Array(country.cities.prefix(max(resultLimit, sourceCandidateLimit))),
            resultLimit: resultLimit,
            clusterRadiusKilometers: clusterRadiusKilometers
        )
    }

    /// Continent equivalent of the country sampler. It retains the global
    /// population ordering before clustering, so each selected city is the
    /// largest available representative of its local metro area.
    static func spatiallyDistinctTopCities(
        for continent: ContinentPlacesOption,
        resultLimit: Int,
        sourceCandidateLimit: Int,
        clusterRadiusKilometers: Double
    ) -> [City] {
        spatiallyDistinctCities(
            Array(
                cityEntries(for: continent)
                    .prefix(max(resultLimit, sourceCandidateLimit))
            ),
            resultLimit: resultLimit,
            clusterRadiusKilometers: clusterRadiusKilometers
        )
    }

    /// Preserves population alongside each source row for geographic sampling.
    /// Public callers receive app cities above; the private form is used only
    /// where choosing a metro representative requires population ordering.
    private static func cityEntries(
        for continent: ContinentPlacesOption
    ) -> [CountryCityCatalogEntry] {
        guard let countryCodes = continentCountryCodes[continent] else { return [] }
        return countryCodes
            .flatMap { countryCode in
                catalog.countriesByCode[countryCode]?.cities ?? []
            }
            .sorted {
                if $0.population != $1.population {
                    return $0.population > $1.population
                }
                let nameOrder = $0.city.localizedCaseInsensitiveCompare($1.city)
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    /// Uses the already population-sorted country catalog. A selected city
    /// becomes the representative for source rows inside its 25 km metro
    /// radius; subsequent non-overlapping rows backfill the requested result
    /// count.
    private static func spatiallyDistinctCities(
        _ candidates: [CountryCityCatalogEntry],
        resultLimit: Int,
        clusterRadiusKilometers: Double
    ) -> [City] {
        guard resultLimit > 0,
              clusterRadiusKilometers.isFinite,
              clusterRadiusKilometers > 0 else {
            return []
        }
        var selected: [CountryCityCatalogEntry] = []
        selected.reserveCapacity(min(resultLimit, candidates.count))

        for candidate in candidates {
            let candidateLocation = CLLocation(
                latitude: candidate.latitude,
                longitude: candidate.longitude
            )
            let isInExistingCluster = selected.contains { selectedCandidate in
                candidateLocation.distance(
                    from: CLLocation(
                        latitude: selectedCandidate.latitude,
                        longitude: selectedCandidate.longitude
                    )
                ) <= clusterRadiusKilometers * 1_000
            }
            guard !isInExistingCluster else { continue }

            selected.append(candidate)
            if selected.count == resultLimit { break }
        }
        return selected.map(\.appCity)
    }

    // MARK: - Continent Membership

    /// Built-in continents mapped to included ISO country codes.
    /// `Set` literals express membership rather than order; no UI relies on the
    /// ordering in this data structure.
    private static let continentCountryCodes: [ContinentPlacesOption: Set<String>] = [
        .europe: [
            "AL", "AD", "AT", "BY", "BE", "BA", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR",
            "DE", "GR", "HU", "IS", "IE", "IT", "XK", "LV", "LI", "LT", "LU", "MT", "MD", "MC",
            "ME", "NL", "MK", "NO", "PL", "PT", "RO", "RU", "SM", "RS", "SK", "SI", "ES", "SE",
            "CH", "TR", "UA", "GB", "VA"
        ],
        .asia: [
            "AF", "AM", "AZ", "BH", "BD", "BT", "BN", "KH", "CN", "GE", "HK", "IN", "ID", "IR",
            "IQ", "IL", "JP", "JO", "KZ", "KW", "KG", "LA", "LB", "MO", "MY", "MV", "MN", "MM",
            "NP", "KP", "OM", "PK", "PS", "PH", "QA", "SA", "SG", "KR", "LK", "SY", "TW", "TJ",
            "TH", "TL", "TM", "AE", "UZ", "VN", "YE"
        ],
        .northAmerica: [
            "CA", "US", "MX", "AG", "AI", "AW", "BS", "BB", "BZ", "BM", "VG", "KY", "CR", "CU",
            "CW", "DM", "DO", "SV", "GL", "GD", "GP", "GT", "HT", "HN", "JM", "MQ", "MS", "NI",
            "PA", "PR", "KN", "LC", "MF", "PM", "VC", "SX", "TT", "TC", "VI"
        ],
        .southAmerica: [
            "AR", "BO", "BR", "CL", "CO", "EC", "FK", "GF", "GY", "PY", "PE", "SR", "UY", "VE"
        ],
        .africa: [
            "DZ", "AO", "BJ", "BW", "BF", "BI", "CV", "CM", "CF", "TD", "KM", "CD", "CG", "CI",
            "DJ", "EG", "GQ", "ER", "SZ", "ET", "GA", "GM", "GH", "GN", "GW", "KE", "LS", "LR",
            "LY", "MG", "MW", "ML", "MR", "MU", "YT", "MA", "MZ", "NA", "NE", "NG", "RE", "RW",
            "SH", "ST", "SN", "SC", "SL", "SO", "ZA", "SS", "SD", "TZ", "TG", "TN", "UG", "EH",
            "ZM", "ZW"
        ],
        .australia: [
            "AS", "AU", "CK", "FJ", "PF", "GU", "KI", "MH", "FM", "NR", "NC", "NZ", "NU", "NF",
            "MP", "PW", "PG", "PN", "WS", "SB", "TK", "TO", "TV", "VU", "WF"
        ]
    ]

    // MARK: - Bundle Resource Loading

    /// Complete parsed resource retained once for Map queries, together with
    /// source-wide failures and nonfatal malformed-row diagnostics.
    private struct CatalogData {
        let countriesByCode: [String: CountryPlacesOption]
        let issues: [CountryCityCatalogIssue]
    }

    /// Lazily parses and validates the bundled catalog exactly once.
    ///
    /// The multiple resource paths support both Xcode's usual flattened bundle
    /// and project layouts that retain a Resources/Cities folder. A missing or
    /// unreadable file produces an empty catalog plus a native-alert issue.
    private static let catalog: CatalogData = {
        guard let url = Bundle.main.url(forResource: "country_city_coordinates", withExtension: "csv")
                ?? Bundle.main.url(
                    forResource: "country_city_coordinates",
                    withExtension: "csv",
                    subdirectory: "Resources/Cities"
                )
                ?? Bundle.main.url(
                    forResource: "country_city_coordinates",
                    withExtension: "csv",
                    subdirectory: "Cities"
                )
                ?? Bundle.main.url(
                    forResource: "country_city_coordinates",
                    withExtension: "csv",
                    subdirectory: "Assets"
                ) else {
            DeveloperDiagnostics.show(
                title: "Country City Catalog Missing",
                message: "The bundled country_city_coordinates.csv file is missing. Country and continent searches are unavailable."
            )
            return CatalogData(
                countriesByCode: [:],
                issues: [.resourceMissing]
            )
        }

        let csv: String
        do {
            csv = try String(contentsOf: url, encoding: .utf8)
        } catch {
            DeveloperDiagnostics.show(
                title: "Country City Catalog Unreadable",
                message: "The bundled country_city_coordinates.csv file could not be read: \(error.localizedDescription)"
            )
            return CatalogData(
                countriesByCode: [:],
                issues: [.unreadableResource]
            )
        }

        var grouped: [String: [CountryCityCatalogEntry]] = [:]
        var countryNames: [String: String] = [:]
        var invalidRowCount = 0

        // The first line is the header. Each later row is independently checked;
        // one malformed source row is logged and skipped, not allowed to discard
        // every otherwise valid country.
        for (rowIndex, line) in csv.split(whereSeparator: \.isNewline).dropFirst().enumerated() {
            let fields = parseCSVLine(String(line))
            // Accept population values stored as either integers or integer-like decimals.
            let populationValue = fields.count == 7 ? fields[6] : ""
            guard fields.count == 7,
                  let city = nonemptyCatalogValue(fields[0]),
                  let country = nonemptyCatalogValue(fields[1]),
                  let iso2 = validISO2(fields[2]),
                  let latitude = finiteCatalogCoordinate(
                      fields[3],
                      allowedRange: -90...90
                  ),
                  let longitude = finiteCatalogCoordinate(
                      fields[4],
                      allowedRange: -180...180
                  ),
                  let timeZoneIdentifier = validTimeZoneIdentifier(fields[5]),
                  let population = catalogPopulation(populationValue) else {
                invalidRowCount += 1
                DeveloperDiagnostics.show(
                    title: "Country City Catalog Invalid",
                    message: "The bundled country_city_coordinates.csv row \(rowIndex + 2) is malformed and cannot be loaded."
                )
                continue
            }

            countryNames[iso2] = country
            grouped[iso2, default: []].append(
                CountryCityCatalogEntry(
                    city: city,
                    country: country,
                    iso2: iso2,
                    latitude: latitude,
                    longitude: longitude,
                    timeZoneIdentifier: timeZoneIdentifier,
                    population: population
                )
            )
        }

        // Convert the raw dictionary into query-ready country values. Sorting once
        // here means every later top-city request is only a cheap `prefix`.
        let countriesByCode: [String: CountryPlacesOption] = grouped.reduce(
            into: [:]
        ) { result, pair in
            let cities = pair.value
            let rankedCities = cities.sorted {
                if $0.population != $1.population {
                    return $0.population > $1.population
                }
                let nameOrder = $0.city.localizedCaseInsensitiveCompare($1.city)
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            var sortedCities: [CountryCityCatalogEntry] = []
            sortedCities.reserveCapacity(rankedCities.count)
            for city in rankedCities where !sortedCities.contains(
                where: { $0.representsSamePlace(as: city) }
            ) {
                // Ranking is deterministic, so the retained representative is
                // always the highest-population row for this logical place.
                sortedCities.append(city)
            }
            guard let countryName = countryNames[pair.key] else {
                DeveloperDiagnostics.show(
                    title: "Country City Catalog Invalid",
                    message: "The bundled country-city catalog has no country name for \(pair.key)."
                )
                return
            }
            result[pair.key] = CountryPlacesOption(
                iso2: pair.key,
                englishName: countryName,
                cities: sortedCities
            )
        }
        var issues: [CountryCityCatalogIssue] = []
        if invalidRowCount > 0 {
            issues.append(.invalidRows(invalidRowCount))
        }
        if countriesByCode.isEmpty {
            issues.append(.noValidCities)
        }
        return CatalogData(countriesByCode: countriesByCode, issues: issues)
    }()

    // MARK: - CSV Field Validation

    private static func nonemptyCatalogValue(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func validISO2(_ value: String) -> String? {
        guard let value = nonemptyCatalogValue(value)?.uppercased(),
              value.unicodeScalars.count == 2,
              value.unicodeScalars.allSatisfy({
                  (65...90).contains(Int($0.value))
              }) else {
            return nil
        }
        return value
    }

    private static func finiteCatalogCoordinate(
        _ value: String,
        allowedRange: ClosedRange<Double>
    ) -> Double? {
        guard let value = Double(value),
              value.isFinite,
              allowedRange.contains(value) else {
            return nil
        }
        return value
    }

    private static func validTimeZoneIdentifier(_ value: String) -> String? {
        guard let value = nonemptyCatalogValue(value),
              TimeZone(identifier: value) != nil else {
            return nil
        }
        return value
    }

    private static func catalogPopulation(_ value: String) -> Int? {
        if let population = Int(value), population >= 0 {
            return population
        }
        guard let value = Double(value),
              value.isFinite,
              value >= 0,
              value.rounded(.towardZero) == value,
              value < Double(Int.max) else {
            return nil
        }
        return Int(value)
    }

    // MARK: - CSV Parsing

    /// Splits one CSV row while respecting quoted commas and escaped quotes.
    ///
    /// CSV permits commas inside a quoted field and represents a literal quote
    /// as two adjacent quotes. The loop is intentionally small and dependency-
    /// free because Foundation has no general-purpose CSV parser in this target.
    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var isInsideQuotes = false
        let characters = Array(line)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                // Inside quotes, a doubled quote becomes one literal character;
                // otherwise this quote starts or ends the quoted field.
                if isInsideQuotes,
                   index + 1 < characters.count,
                   characters[index + 1] == "\"" {
                        current.append("\"")
                        index += 1
                } else {
                    isInsideQuotes.toggle()
                }
            } else if character == ",", !isInsideQuotes {
                // Only commas outside quotes separate fields.
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index += 1
        }

        fields.append(current)
        return fields
    }
}
