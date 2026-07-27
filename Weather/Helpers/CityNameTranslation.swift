//
//  CityNameTranslation.swift
//  Weather
//
//  Purpose: Loads the bundled GeoNames city-name localization catalog.
//

import Foundation

// MARK: - Bundled City-Name Catalog

/// Top-level shape of the bundled city-name localization resource.
private struct CityNameLocalizationDocument: Decodable {
    /// All canonical city localization entries.
    let cities: [CityNameLocalizationEntry]
}

/// One canonical city key and its language-to-name lookup.
private struct CityNameLocalizationEntry: Decodable {
    /// Normalized city-country resource key.
    let key: String
    /// Localized spellings keyed by supported language identifier.
    let names: [String: String]
}

/// In-memory lookup backed by the bundled city-name localization JSON.
enum CityNameLocalizationCatalog {
    /// Resource entries indexed once by normalized city key.
    private static let namesByCityKey: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "city_name_localizations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(CityNameLocalizationDocument.self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: document.cities.map { ($0.key, $0.names) })
    }()

    /// Returns an explicit localized spelling when the catalog contains one.
    static func localizedName(for city: City, locale: Locale) -> String? {
        guard let names = namesByCityKey[key(for: city)] else { return nil }
        // Normalize locale variants to the identifiers stored in the catalog.
        let identifier = locale.identifier
        let language = identifier.hasPrefix("zh-Hant")
            ? "zh-Hant"
            : identifier.hasPrefix("zh-Hans")
                ? "zh-Hans"
                : identifier.components(separatedBy: CharacterSet(charactersIn: "_-@")).first ?? "en"
        let localized = names[language]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let localized, !localized.isEmpty {
            return localized
        }
        let english = names["en"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return english?.isEmpty == false ? english : nil
    }

    /// Builds the normalized city-country key used by the resource.
    static func key(for city: City) -> String {
        let stableLocale = Locale(identifier: "en_US_POSIX")
        let latitude = String(format: "%.4f", locale: stableLocale, city.latitude)
        let longitude = String(format: "%.4f", locale: stableLocale, city.longitude)
        return "\(city.name)|\(city.country)|\(latitude)|\(longitude)"
    }
}

/// Single source of truth for every user-visible city name in the app.
func localizedCityDisplayName(for city: City, locale: Locale) -> String {
    CityListID.customCityName(for: city)
        ?? CityNameLocalizationCatalog.localizedName(for: city, locale: locale)
        ?? city.localizedName(locale: locale)
}
