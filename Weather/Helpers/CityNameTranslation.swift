//
//  CityNameTranslation.swift
//  Weather
//
//  Purpose: Translates city display names with Apple's Translation framework
//  and caches translated names per target locale.
//

import Foundation
import SwiftUI
#if canImport(Translation)
import Translation
#endif

struct CityNameTranslationInput: Hashable, Identifiable {
    let key: String
    let sourceName: String

    var id: String { key }
}

enum CityNameTranslationCache {
    private static let keyPrefix = "cityNameTranslations"

    static func key(for city: City) -> String {
        let latitude = String(format: "%.4f", city.latitude)
        let longitude = String(format: "%.4f", city.longitude)
        return "\(city.name)|\(city.country)|\(latitude)|\(longitude)"
    }

    static func languageIdentifier(for locale: Locale) -> String {
        if #available(iOS 16.0, *) {
            return locale.language.languageCode?.identifier ?? locale.identifier
        }
        return locale.identifier
    }

    static func load(languageIdentifier: String) -> [String: String] {
        UserDefaults.standard.dictionary(forKey: storageKey(languageIdentifier: languageIdentifier)) as? [String: String] ?? [:]
    }

    static func save(_ cache: [String: String], languageIdentifier: String) {
        UserDefaults.standard.set(cache, forKey: storageKey(languageIdentifier: languageIdentifier))
    }

    private static func storageKey(languageIdentifier: String) -> String {
        "\(keyPrefix).\(languageIdentifier)"
    }
}

#if canImport(Translation)
@available(iOS 18.0, *)
struct CityNameTranslationTaskView: View {
    let inputs: [CityNameTranslationInput]
    let sourceLanguage: Locale.Language
    let targetLanguage: Locale.Language
    let onTranslations: ([String: String]) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(source: sourceLanguage, target: targetLanguage) { session in
                await translateMissingNames(with: session)
            }
    }

    private func translateMissingNames(with session: TranslationSession) async {
        let requests = inputs.map {
            TranslationSession.Request(sourceText: $0.sourceName, clientIdentifier: $0.key)
        }
        guard !requests.isEmpty else { return }

        do {
            let responses = try await session.translations(from: requests)
            let translations = Dictionary(
                uniqueKeysWithValues: responses.compactMap { response -> (String, String)? in
                    guard let key = response.clientIdentifier else { return nil }
                    let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !translated.isEmpty else { return nil }
                    return (key, translated)
                }
            )
            guard !translations.isEmpty else { return }
            await MainActor.run {
                onTranslations(translations)
            }
        } catch {
            // Keep original city names if translation is unavailable or the language pair is unsupported.
        }
    }
}
#endif
