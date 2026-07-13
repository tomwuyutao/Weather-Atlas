//
//  CityNameTranslation.swift
//  Weather
//
//  Purpose: Loads the bundled GeoNames city-name localization catalog.
//

import Foundation

private struct CityNameLocalizationDocument: Decodable {
    let cities: [CityNameLocalizationEntry]
}

private struct CityNameLocalizationEntry: Decodable {
    let key: String
    let names: [String: String]
}

enum CityNameLocalizationCatalog {
    private static let namesByCityKey: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "city_name_localizations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(CityNameLocalizationDocument.self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: document.cities.map { ($0.key, $0.names) })
    }()

    static func localizedName(for city: City, locale: Locale) -> String? {
        guard let names = namesByCityKey[key(for: city)] else { return nil }
        let localized = names[languageIdentifier(for: locale)]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let localized, !localized.isEmpty {
            return localized
        }
        let english = names["en"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return english?.isEmpty == false ? english : nil
    }

    static func key(for city: City) -> String {
        let latitude = String(format: "%.4f", city.latitude)
        let longitude = String(format: "%.4f", city.longitude)
        return "\(city.name)|\(city.country)|\(latitude)|\(longitude)"
    }

    private static func languageIdentifier(for locale: Locale) -> String {
        let identifier = locale.identifier
        if identifier.hasPrefix("zh-Hant") { return "zh-Hant" }
        if identifier.hasPrefix("zh-Hans") { return "zh-Hans" }
        if #available(iOS 16.0, *) {
            return locale.language.languageCode?.identifier ?? "en"
        }
        return Locale(identifier: identifier).languageCode ?? "en"
    }
}
