//
//  CountryCatalog.swift
//  Weather
//
//  Purpose: Loads the bundled country city catalog used by population-ranked
//  bulk place additions and first-run Starting Cities without runtime
//  geocoding or timezone guessing.
//

import CoreLocation
import Foundation

// MARK: - Geographic Place Sources

/// A country and its population-ranked bundled cities.
struct CountryPlacesOption: Identifiable, Hashable {
    /// ISO 3166-1 alpha-2 identity used by search and localization.
    let iso2: String
    /// Stable English fallback when a locale has no region name.
    let englishName: String
    /// Available source cities ordered from largest population downward.
    let cities: [CountryCityCatalogEntry]

    var id: String { iso2 }

    /// Resolves the system-localized country name without persisting it.
    func localizedName(locale: Locale) -> String {
        locale.localizedString(forRegionCode: iso2) ?? englishName
    }
}

/// The six continent sources available when adding places in bulk.
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
struct CountryCityCatalogEntry: Hashable {
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

    /// Converts the catalog row into the app's persistable city model.
    var appCity: City {
        City(
            name: city,
            country: country,
            latitude: latitude,
            longitude: longitude,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }
}

// MARK: - Country City Catalog

/// Loads and queries the bundled population-ranked country-city resource.
enum CountryCityCatalog {
    /// Default population-ranked geographic preset size.
    static let defaultGeneratedCityCount = 15
    /// Maximum size offered by the bulk-add preview.
    static let maximumGeneratedCityCount = 25

    /// Returns every available country, sorted by its localized display name.
    static func countries(locale: Locale) -> [CountryPlacesOption] {
        catalog.countriesByCode.values.sorted {
            $0.localizedName(locale: locale).localizedStandardCompare(
                $1.localizedName(locale: locale)
            ) == .orderedAscending
        }
    }

    /// Returns the requested leading population-ranked cities for a country.
    static func topCities(
        for country: CountryPlacesOption,
        limit: Int = defaultGeneratedCityCount
    ) -> [City] {
        Array(country.cities.prefix(clampedLimit(limit))).map(\.appCity)
    }

    /// Returns top catalog cities across the countries mapped to a continent.
    static func topCities(
        for continent: ContinentPlacesOption,
        limit: Int = defaultGeneratedCityCount
    ) -> [City] {
        guard let countryCodes = continentCountryCodes[continent] else { return [] }
        let cities = countryCodes
            .compactMap { catalog.countriesByCode[$0]?.cities }
            .flatMap { $0 }
            .sorted {
                if $0.population != $1.population {
                    return $0.population > $1.population
                }
                return $0.city.localizedCaseInsensitiveCompare($1.city) == .orderedAscending
            }
        return Array(cities.prefix(clampedLimit(limit))).map(\.appCity)
    }

    /// Returns the timezone of the closest validated bundled catalog city.
    ///
    /// This deliberately remains an offline fallback, rather than guessing a
    /// timezone such as GMT. It keeps WeatherKit conversion working when Apple
    /// reverse geocoding is temporarily unavailable (notably for a simulator
    /// current location and transient world-city candidates).
    static func nearestTimeZoneIdentifier(
        to coordinate: CLLocationCoordinate2D
    ) -> String? {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }

        let target = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        return catalog.allCities.min { lhs, rhs in
            let lhsDistance = target.distance(
                from: CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            )
            let rhsDistance = target.distance(
                from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
            )
            return lhsDistance < rhsDistance
        }?.timeZoneIdentifier
    }

    private static func clampedLimit(_ limit: Int) -> Int {
        min(max(1, limit), maximumGeneratedCityCount)
    }

    /// Built-in continents mapped to included ISO country codes.
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

    /// Complete parsed resource retained once for bulk place additions.
    private struct CatalogData {
        let countriesByCode: [String: CountryPlacesOption]
        /// Flattened validated rows reused by the offline timezone fallback.
        let allCities: [CountryCityCatalogEntry]
    }

    /// Lazily parses and validates the bundled catalog exactly once.
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
                ),
              let csv = try? String(contentsOf: url, encoding: .utf8) else {
            DeveloperDiagnostics.show(
                title: "Country City Catalog Missing",
                message: "The bundled country_city_coordinates.csv file could not be loaded. Places cannot be added by country or continent."
            )
            return CatalogData(countriesByCode: [:], allCities: [])
        }

        var grouped: [String: [CountryCityCatalogEntry]] = [:]
        var countryNames: [String: String] = [:]

        for (rowIndex, line) in csv.split(whereSeparator: \.isNewline).dropFirst().enumerated() {
            let fields = parseCSVLine(String(line))
            // Accept population values stored as either integers or integer-like decimals.
            let populationValue = fields.count == 7 ? fields[6] : ""
            let population = Int(populationValue)
                ?? Double(populationValue).flatMap { $0.isFinite ? Int($0.rounded()) : nil }
            guard fields.count == 7,
                  let latitude = Double(fields[3]),
                  let longitude = Double(fields[4]),
                  let population else {
                DeveloperDiagnostics.show(
                    title: "Country City Catalog Invalid",
                    message: "The bundled country_city_coordinates.csv row \(rowIndex + 2) is malformed and cannot be loaded."
                )
                continue
            }

            guard TimeZone(identifier: fields[5]) != nil else {
                DeveloperDiagnostics.show(
                    title: "Country City Time Zone Invalid",
                    message: "The bundled country_city_coordinates.csv row for \(fields[0]), \(fields[1]) has an invalid time zone identifier: \(fields[5])."
                )
                continue
            }

            let iso2 = fields[2]
            countryNames[iso2] = fields[1]
            grouped[iso2, default: []].append(
                CountryCityCatalogEntry(
                    city: fields[0],
                    country: fields[1],
                    iso2: iso2,
                    latitude: latitude,
                    longitude: longitude,
                    timeZoneIdentifier: fields[5],
                    population: population
                )
            )
        }

        let countriesByCode: [String: CountryPlacesOption] = grouped.reduce(
            into: [:]
        ) { result, pair in
            let cities = pair.value
            let sortedCities = cities.sorted {
                if $0.population != $1.population {
                    return $0.population > $1.population
                }
                return $0.city.localizedCaseInsensitiveCompare($1.city)
                    == .orderedAscending
            }
            result[pair.key] = CountryPlacesOption(
                iso2: pair.key,
                englishName: countryNames[pair.key] ?? pair.key,
                cities: sortedCities
            )
        }
        return CatalogData(
            countriesByCode: countriesByCode,
            allCities: grouped.values.flatMap { $0 }
        )
    }()

    /// Splits one CSV row while respecting quoted commas and escaped quotes.
    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var isInsideQuotes = false
        let characters = Array(line)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if isInsideQuotes,
                   index + 1 < characters.count,
                   characters[index + 1] == "\"" {
                        current.append("\"")
                        index += 1
                } else {
                    isInsideQuotes.toggle()
                }
            } else if character == ",", !isInsideQuotes {
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
