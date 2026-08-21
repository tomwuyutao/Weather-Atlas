//
//  CityNameTranslation.swift
//  Weather
//
//  Purpose: Resolves bundled GeoNames labels at presentation time without
//  changing a city's canonical, persisted identity.
//

import Foundation

#if !WEATHER_WIDGETS

// MARK: - GeoNames City Labels

/// Immutable lookup decoded from the generated GeoNames resource.
///
/// The catalog intentionally stores presentation labels separately from
/// `City.name`. Saved places, weather-cache keys, and duplicate detection keep
/// using the canonical source name, while every visible label can follow the
/// selected app language.
nonisolated private struct CityNameLocalizationDocument: Decodable, Sendable {
    let namesByCatalogIdentifier: [String: [String: String]]
    let catalogIdentifierByLegacyKey: [String: String]
}

/// Provides locale-aware city names from the bundled GeoNames export.
///
/// `worldcities.csv` identifiers are the primary lookup. The coordinate key
/// preserves compatibility with the country catalog and saved places created
/// before catalog identifiers existed. A missing localized label deliberately
/// returns `nil`; callers then retain the canonical English/source name.
nonisolated enum CityNameLocalizationCatalog {
    private static let resourceName = "city_name_localizations"
    private static let appLanguageStorageKey = "appLanguage"

    private static let document: CityNameLocalizationDocument? = {
        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: "json"
        ),
        let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(
            CityNameLocalizationDocument.self,
            from: data
        )
    }()

    /// The language selected by Settings. Before first launch initialization
    /// has run (for example, in a preview), the current device locale is a
    /// sensible read-only fallback.
    static var selectedAppLocale: Locale {
        let identifier = UserDefaults.standard.string(
            forKey: appLanguageStorageKey
        ) ?? Locale.autoupdatingCurrent.identifier
        return Locale(identifier: identifier)
    }

    static func localizedName(for city: City, locale: Locale) -> String? {
        guard let document else { return nil }
        let names: [String: String]?

        if let catalogIdentifier = city.catalogIdentifier,
           let directNames = document.namesByCatalogIdentifier[
               catalogIdentifier
           ] {
            names = directNames
        } else {
            let key = legacyKey(for: city)
            guard let catalogIdentifier = document
                .catalogIdentifierByLegacyKey[key] else {
                return nil
            }
            names = document.namesByCatalogIdentifier[catalogIdentifier]
        }

        guard let names,
              let localizedName = names[languageIdentifier(for: locale)]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !localizedName.isEmpty else {
            return nil
        }
        return localizedName
    }

    /// Uses the format of the generated catalog rather than a localized number
    /// formatter, so a key remains stable regardless of the current language.
    static func legacyKey(for city: City) -> String {
        [
            city.name,
            city.country,
            String(
                format: "%.4f",
                locale: Locale(identifier: "en_US_POSIX"),
                city.latitude
            ),
            String(
                format: "%.4f",
                locale: Locale(identifier: "en_US_POSIX"),
                city.longitude
            )
        ].joined(separator: "|")
    }

    private static func languageIdentifier(for locale: Locale) -> String {
        let identifier = locale.identifier.replacingOccurrences(
            of: "_",
            with: "-"
        )
        let lowercaseIdentifier = identifier.lowercased()

        if lowercaseIdentifier.hasPrefix("zh-hant")
            || lowercaseIdentifier.hasPrefix("zh-tw")
            || lowercaseIdentifier.hasPrefix("zh-hk")
            || lowercaseIdentifier.hasPrefix("zh-mo") {
            return "zh-Hant"
        }
        if lowercaseIdentifier.hasPrefix("zh") {
            return "zh-Hans"
        }

        let languageCode = identifier.split(separator: "-").first
            .map(String.init) ?? "en"
        switch languageCode {
        case "fr", "de", "it", "ja", "ko", "pt", "ru", "es":
            return languageCode
        default:
            return "en"
        }
    }
}

// MARK: - Presentation Helpers

extension City {
    /// Canonical source text retained for persistence, matching, and English
    /// fallback. It is never replaced by a translated display label.
    var canonicalDisplayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The localized catalog label when GeoNames provides one for `locale`;
    /// otherwise the canonical source name. This does not mutate the city.
    func localizedDisplayName(locale: Locale) -> String {
        CityNameLocalizationCatalog.localizedName(for: self, locale: locale)
            ?? canonicalDisplayName
    }

    /// Existing presentation call sites use the chosen app language by default.
    /// Explicit-locale work, such as widget publication and sorting, should use
    /// `localizedDisplayName(locale:)` so it cannot observe a stale preference.
    var displayName: String {
        localizedDisplayName(locale: CityNameLocalizationCatalog.selectedAppLocale)
    }

    /// A richer reverse-geocoded locality remains the intended report heading.
    /// Catalog cities have no title variant, so their heading follows the same
    /// localized city label as ordinary presentation.
    func localizedTitleDisplayName(locale: Locale) -> String {
        let trimmedTitle = titleName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
        return trimmedTitle.isEmpty
            ? localizedDisplayName(locale: locale)
            : trimmedTitle
    }

    var titleDisplayName: String {
        localizedTitleDisplayName(
            locale: CityNameLocalizationCatalog.selectedAppLocale
        )
    }
}

#endif
