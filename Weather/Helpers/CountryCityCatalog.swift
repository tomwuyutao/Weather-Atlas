//
//  CountryCityCatalog.swift
//  Weather
//
//  Purpose: Loads the bundled country city catalog used to create
//  generated country lists without runtime geocoding or timezone guessing.
//

import Foundation

// MARK: - Country List Models

struct CountryListOption: Identifiable, Hashable {
    let iso2: String
    let englishName: String
    let cities: [CountryCityCatalogEntry]

    var id: String { iso2 }

    func localizedName(locale: Locale) -> String {
        locale.localizedString(forRegionCode: iso2) ?? englishName
    }
}

struct CountryCityCatalogEntry: Hashable {
    let city: String
    let country: String
    let iso2: String
    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String
    let population: Int

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

enum CountryCityCatalog {
    static let defaultCountryCityCount = 15
    static let maxCountryCityCount = 20

    static func countries(locale: Locale) -> [CountryListOption] {
        countriesByCode.values.sorted {
            if $0.cities.count != $1.cities.count {
                return $0.cities.count > $1.cities.count
            }
            return $0.localizedName(locale: locale).localizedCaseInsensitiveCompare($1.localizedName(locale: locale)) == .orderedAscending
        }
    }

    static func topCities(for country: CountryListOption, limit: Int = defaultCountryCityCount) -> [City] {
        let cappedLimit = min(max(1, limit), maxCountryCityCount)
        return Array(country.cities.prefix(cappedLimit)).map(\.appCity)
    }

    static func topCities(forContinentRawValue rawValue: String, limit: Int = defaultCountryCityCount) -> [City] {
        let cappedLimit = min(max(1, limit), maxCountryCityCount)
        guard let countryCodes = continentCountryCodes[rawValue] else { return [] }
        let cities = countryCodes
            .compactMap { countriesByCode[$0]?.cities }
            .flatMap { $0 }
            .sorted {
                if $0.population != $1.population {
                    return $0.population > $1.population
                }
                return $0.city.localizedCaseInsensitiveCompare($1.city) == .orderedAscending
            }
        return Array(cities.prefix(cappedLimit)).map(\.appCity)
    }

    static func cityCount(forContinentRawValue rawValue: String) -> Int {
        guard let countryCodes = continentCountryCodes[rawValue] else { return 0 }
        return countryCodes.reduce(0) { count, code in
            count + (countriesByCode[code]?.cities.count ?? 0)
        }
    }

    private static let continentCountryCodes: [String: Set<String>] = [
        "europe": [
            "AL", "AD", "AT", "BY", "BE", "BA", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR",
            "DE", "GR", "HU", "IS", "IE", "IT", "XK", "LV", "LI", "LT", "LU", "MT", "MD", "MC",
            "ME", "NL", "MK", "NO", "PL", "PT", "RO", "RU", "SM", "RS", "SK", "SI", "ES", "SE",
            "CH", "TR", "UA", "GB", "VA"
        ],
        "asia": [
            "AF", "AM", "AZ", "BH", "BD", "BT", "BN", "KH", "CN", "GE", "HK", "IN", "ID", "IR",
            "IQ", "IL", "JP", "JO", "KZ", "KW", "KG", "LA", "LB", "MO", "MY", "MV", "MN", "MM",
            "NP", "KP", "OM", "PK", "PS", "PH", "QA", "SA", "SG", "KR", "LK", "SY", "TW", "TJ",
            "TH", "TL", "TM", "AE", "UZ", "VN", "YE"
        ],
        "northAmerica": [
            "CA", "US", "MX", "AG", "AI", "AW", "BS", "BB", "BZ", "BM", "VG", "KY", "CR", "CU",
            "CW", "DM", "DO", "SV", "GL", "GD", "GP", "GT", "HT", "HN", "JM", "MQ", "MS", "NI",
            "PA", "PR", "KN", "LC", "MF", "PM", "VC", "SX", "TT", "TC", "VI"
        ],
        "southAmerica": [
            "AR", "BO", "BR", "CL", "CO", "EC", "FK", "GF", "GY", "PY", "PE", "SR", "UY", "VE"
        ],
        "africa": [
            "DZ", "AO", "BJ", "BW", "BF", "BI", "CV", "CM", "CF", "TD", "KM", "CD", "CG", "CI",
            "DJ", "EG", "GQ", "ER", "SZ", "ET", "GA", "GM", "GH", "GN", "GW", "KE", "LS", "LR",
            "LY", "MG", "MW", "ML", "MR", "MU", "YT", "MA", "MZ", "NA", "NE", "NG", "RE", "RW",
            "SH", "ST", "SN", "SC", "SL", "SO", "ZA", "SS", "SD", "TZ", "TG", "TN", "UG", "EH",
            "ZM", "ZW"
        ],
        "australia": [
            "AS", "AU", "CK", "FJ", "PF", "GU", "KI", "MH", "FM", "NR", "NC", "NZ", "NU", "NF",
            "MP", "PW", "PG", "PN", "WS", "SB", "TK", "TO", "TV", "VU", "WF"
        ]
    ]

    private static let countriesByCode: [String: CountryListOption] = {
        guard let url = Bundle.main.url(forResource: "country_city_coordinates", withExtension: "csv")
                ?? Bundle.main.url(forResource: "country_city_coordinates", withExtension: "csv", subdirectory: "Assets"),
              let csv = try? String(contentsOf: url, encoding: .utf8) else {
            DeveloperWarningCenter.show(
                title: "Country City Catalog Missing",
                message: "The bundled country_city_coordinates.csv file could not be loaded. Country lists cannot be created."
            )
            return [:]
        }

        var grouped: [String: [CountryCityCatalogEntry]] = [:]
        var countryNames: [String: String] = [:]

        for (rowIndex, line) in csv.split(whereSeparator: \.isNewline).dropFirst().enumerated() {
            let fields = parseCSVLine(String(line))
            guard fields.count == 7,
                  let latitude = Double(fields[3]),
                  let longitude = Double(fields[4]),
                  let population = Int(fields[6]) else {
                DeveloperWarningCenter.show(
                    title: "Country City Catalog Invalid",
                    message: "The bundled country_city_coordinates.csv row \(rowIndex + 2) is malformed and cannot be loaded."
                )
                continue
            }

            guard TimeZone(identifier: fields[5]) != nil else {
                DeveloperWarningCenter.show(
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

        return grouped.reduce(into: [:]) { result, pair in
            let sortedCities = pair.value.sorted {
                if $0.population != $1.population {
                    return $0.population > $1.population
                }
                return $0.city.localizedCaseInsensitiveCompare($1.city) == .orderedAscending
            }
            result[pair.key] = CountryListOption(
                iso2: pair.key,
                englishName: countryNames[pair.key] ?? pair.key,
                cities: sortedCities
            )
        }
    }()

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
