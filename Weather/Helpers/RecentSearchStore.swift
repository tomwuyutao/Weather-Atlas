//
//  RecentSearchStore.swift
//  Weather
//
//  Purpose: Persists recent City, Country, and Continent search suggestions
//  shared by Search and Map.
//

import Foundation
import Observation

// MARK: - Persisted Recent Searches

/// A small MRU store for the three place scopes exposed by Search.
///
/// City values retain factual provider metadata so an unsaved destination can
/// be reopened without another name lookup. Countries and continents persist
/// only stable source identifiers; their labels are localized when displayed.
@MainActor
@Observable
final class RecentSearchStore {
    static let maximumSuggestionCount = 5

    /// City eligibility can change after access when a place is saved or made
    /// the current location. Keep a small private backfill behind the five
    /// visible suggestions so removing that newly ineligible row does not
    /// leave the Recent section artificially short.
    private static let maximumStoredCityCount = maximumSuggestionCount * 4

    private static let storageKey = "weatherAtlas.recentSearches"
    private static let schemaVersion = 1

    private(set) var cities: [City]
    private(set) var countryISO2Codes: [String]
    private(set) var continents: [ContinentPlacesOption]

    /// A nil defaults store makes previews and fixtures entirely in-memory.
    @ObservationIgnored private let defaults: UserDefaults?

    /// Restores the live app history from its small UserDefaults document.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let document = Self.load(from: defaults)
        cities = document.cities
        countryISO2Codes = document.countryISO2Codes
        continents = document.continentRawValues.compactMap(
            ContinentPlacesOption.init(rawValue:)
        )
        sanitizeLoadedValues()
    }

    /// Creates a storage-free history for previews and deterministic fixtures.
    init(
        inMemoryCities cities: [City],
        countryISO2Codes: [String] = [],
        continents: [ContinentPlacesOption] = []
    ) {
        defaults = nil
        self.cities = cities
        self.countryISO2Codes = countryISO2Codes
        self.continents = continents
        sanitizeLoadedValues()
    }

    // MARK: - Recording

    /// Moves one semantic city identity to the front of the bounded backing
    /// history. Search still exposes only `maximumSuggestionCount` rows.
    func record(city: City) {
        guard PlacesLibraryValidator.isValidCity(city) else { return }
        guard cities.first != city else { return }
        cities.removeAll { CitySemanticMatcher.matches($0, city) }
        cities.insert(city, at: 0)
        cities = Array(cities.prefix(Self.maximumStoredCityCount))
        persist()
    }

    /// Durably removes cities whose eligibility changed after they were
    /// recorded. MRU order is preserved and a no-op never writes or publishes.
    func removeCities(where shouldRemove: (City) -> Bool) {
        let retainedCities = cities.filter { !shouldRemove($0) }
        guard retainedCities != cities else { return }
        cities = retainedCities
        persist()
    }

    /// Country labels are locale-dependent, so only the normalized ISO code is
    /// retained. Catalog validation prevents obsolete arbitrary codes entering
    /// the visible history.
    func record(country: CountryPlacesOption) {
        let code = country.iso2.uppercased()
        guard countryISO2Codes.first != code else { return }
        countryISO2Codes.removeAll { $0 == code }
        countryISO2Codes.insert(code, at: 0)
        countryISO2Codes = Array(
            countryISO2Codes.prefix(Self.maximumSuggestionCount)
        )
        persist()
    }

    /// Continent raw values are stable product-defined identifiers.
    func record(continent: ContinentPlacesOption) {
        guard continents.first != continent else { return }
        continents.removeAll { $0 == continent }
        continents.insert(continent, at: 0)
        continents = Array(continents.prefix(Self.maximumSuggestionCount))
        persist()
    }

    /// Full app reset clears both published values and their durable document.
    func reset() {
        cities = []
        countryISO2Codes = []
        continents = []
        defaults?.removeObject(forKey: Self.storageKey)
    }

    // MARK: - Persistence

    private func sanitizeLoadedValues() {
        var validCities: [City] = []
        for city in cities where PlacesLibraryValidator.isValidCity(city) {
            guard !validCities.contains(where: {
                CitySemanticMatcher.matches($0, city)
            }) else {
                continue
            }
            validCities.append(city)
            if validCities.count == Self.maximumStoredCityCount { break }
        }
        cities = validCities

        var seenCountryCodes = Set<String>()
        countryISO2Codes = countryISO2Codes.compactMap { storedCode in
            let code = storedCode.uppercased()
            guard seenCountryCodes.insert(code).inserted,
                  CountryCityCatalog.country(iso2: code) != nil else {
                return nil
            }
            return code
        }
        countryISO2Codes = Array(
            countryISO2Codes.prefix(Self.maximumSuggestionCount)
        )

        var seenContinents = Set<ContinentPlacesOption>()
        continents = continents.filter { seenContinents.insert($0).inserted }
        continents = Array(continents.prefix(Self.maximumSuggestionCount))
    }

    private func persist() {
        guard let defaults,
              let data = try? JSONEncoder().encode(
                  Document(
                      schemaVersion: Self.schemaVersion,
                      cities: cities,
                      countryISO2Codes: countryISO2Codes,
                      continentRawValues: continents.map(\.rawValue)
                  )
              ) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults) -> Document {
        guard let data = defaults.data(forKey: storageKey),
              let document = try? JSONDecoder().decode(
                  Document.self,
                  from: data
              ),
              document.schemaVersion == schemaVersion else {
            return .empty
        }
        return document
    }

    private struct Document: Codable {
        let schemaVersion: Int
        let cities: [City]
        let countryISO2Codes: [String]
        let continentRawValues: [String]

        static let empty = Document(
            schemaVersion: RecentSearchStore.schemaVersion,
            cities: [],
            countryISO2Codes: [],
            continentRawValues: []
        )
    }
}
