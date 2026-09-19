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

  var cities: [City]
  var countryISO2Codes: [String]
  var continents: [ContinentPlacesOption]

  /// A nil defaults store makes previews and fixtures entirely in-memory.
  @ObservationIgnored let defaults: UserDefaults?

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

  // MARK: - Persistence

  private func sanitizeLoadedValues() {
    var validCities: [City] = []
    for city in cities where PlacesLibraryValidator.isValidCity(city) {
      guard
        !validCities.contains(where: {
          CitySemanticMatcher.matches($0, city)
        })
      else {
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
        CountryCityCatalog.country(iso2: code) != nil
      else {
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

  func persist() {
    guard let defaults,
      let data = try? JSONEncoder().encode(
        Document(
          schemaVersion: Self.schemaVersion,
          cities: cities,
          countryISO2Codes: countryISO2Codes,
          continentRawValues: continents.map(\.rawValue)
        )
      )
    else {
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
      document.schemaVersion == schemaVersion
    else {
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
