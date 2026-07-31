//
//  LegacyCityListModels.swift
//  Weather
//
//  Purpose: Decodes legacy list identities and preserves the metadata needed
//  for one-time place migration and installed widget compatibility.
//

import Foundation

// MARK: - List Identity

/// Canonical geographic origin retained separately from a list's editable name.
enum CityListNameSource: Equatable, Hashable, Codable {
    case country(iso2: String, duplicateIndex: Int?)
    case continent(rawValue: String, duplicateIndex: Int?)

    /// Stable encoded fields for the associated-value enum.
    enum CodingKeys: String, CodingKey {
        case kind
        case value
        case duplicateIndex
    }

    /// Discriminator persisted alongside the source value.
    enum Kind: String, Codable {
        case country
        case continent
    }

    /// Restores a country or continent source from its stable tagged payload.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let value = try container.decode(String.self, forKey: .value)
        let duplicateIndex = try container.decodeIfPresent(Int.self, forKey: .duplicateIndex)

        switch kind {
        case .country:
            self = .country(iso2: value, duplicateIndex: duplicateIndex)
        case .continent:
            self = .continent(rawValue: value, duplicateIndex: duplicateIndex)
        }
    }

    /// Persists the source kind, canonical value, and optional duplicate suffix.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .country(iso2, duplicateIndex):
            try container.encode(Kind.country, forKey: .kind)
            try container.encode(iso2, forKey: .value)
            try container.encodeIfPresent(duplicateIndex, forKey: .duplicateIndex)
        case let .continent(rawValue, duplicateIndex):
            try container.encode(Kind.continent, forKey: .kind)
            try container.encode(rawValue, forKey: .value)
            try container.encodeIfPresent(duplicateIndex, forKey: .duplicateIndex)
        }
    }

    /// Resolves the canonical geographic label and optional duplicate number.
    func localizedDisplayName(locale: Locale) -> String {
        let baseName: String
        let duplicateIndex: Int?

        switch self {
        case let .country(iso2, index):
            baseName = locale.localizedString(forRegionCode: iso2) ?? iso2
            duplicateIndex = index
        case let .continent(rawValue, index):
            baseName = CityListID.localizedBuiltInDisplayName(for: rawValue, locale: locale) ?? rawValue
            duplicateIndex = index
        }

        guard let duplicateIndex else { return baseName }
        return "\(baseName) \(duplicateIndex)"
    }
}

/// Stable list identity plus editable and canonical naming metadata.
struct CityListID: Identifiable, Equatable, Hashable, Codable {
    /// Persistence key; equality and hashing intentionally use only this value.
    let rawValue: String
    /// Stored display name used for custom lists and migration compatibility.
    let displayName: String
    /// Optional canonical country/continent origin for generated lists.
    let nameSource: CityListNameSource?

    /// Creates a list identity from stable and user-facing naming values.
    init(rawValue: String, displayName: String, nameSource: CityListNameSource? = nil) {
        self.rawValue = rawValue
        self.displayName = displayName
        self.nameSource = nameSource
    }

    /// SwiftUI identity matching the persisted raw value.
    var id: String { rawValue }

    /// Compares stable list identity rather than an editable name.
    static func == (lhs: CityListID, rhs: CityListID) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    /// Hashes stable list identity to match equality semantics.
    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }

    /// Built-in Europe list identity.
    static let europe = CityListID(rawValue: "europe", displayName: "Europe")
    /// Built-in Asia list identity.
    static let asia = CityListID(rawValue: "asia", displayName: "Asia")
    /// Built-in North America list identity.
    static let northAmerica = CityListID(rawValue: "northAmerica", displayName: "North America")
    /// Built-in South America list identity.
    static let southAmerica = CityListID(rawValue: "southAmerica", displayName: "South America")
    /// Built-in Africa list identity.
    static let africa = CityListID(rawValue: "africa", displayName: "Africa")
    /// Built-in Australia list identity.
    static let australia = CityListID(rawValue: "australia", displayName: "Australia")

    /// Returns the localized canonical label for a known built-in raw value.
    static func localizedBuiltInDisplayName(for rawValue: String, locale: Locale = .current) -> String? {
        switch rawValue {
        case "europe": return localizedString("Europe", locale: locale)
        case "asia": return localizedString("Asia", locale: locale)
        case "northAmerica": return localizedString("North America", locale: locale)
        case "southAmerica": return localizedString("South America", locale: locale)
        case "africa": return localizedString("Africa", locale: locale)
        case "australia": return localizedString("Australia", locale: locale)
        default: return nil
        }
    }

    /// Complete built-in list catalog in its default order.
    static let builtInLists: [CityListID] = [.europe, .asia, .northAmerica, .southAmerica, .africa, .australia]

    /// Population-ranked bundled cities for this built-in continent identity.
    var defaultCities: [City] {
        CountryCityCatalog.topCities(forContinentRawValue: rawValue)
    }
}
