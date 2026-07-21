//
//  AppLanguageDefaults.swift
//  Weather
//
//  Purpose: Chooses and persists the app's initial supported language.
//

import Foundation

enum AppLanguageDefaults {
    static let storageKey = "appLanguage"
    static let supportedLanguageCodes = ["en", "fr", "de", "it", "ja", "ko", "pt", "ru", "zh-Hans", "es", "zh-Hant"]

    static func configureInitialLanguage() {
        guard UserDefaults.standard.object(forKey: storageKey) == nil else { return }
        UserDefaults.standard.set(preferredSupportedLanguageCode(), forKey: storageKey)
    }

    private static func preferredSupportedLanguageCode() -> String {
        for identifier in Locale.preferredLanguages {
            if let supportedCode = supportedLanguageCode(for: identifier) {
                return supportedCode
            }
        }
        return "en"
    }

    private static func supportedLanguageCode(for identifier: String) -> String? {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
        if normalized.hasPrefix("zh-Hans") { return "zh-Hans" }
        if normalized.hasPrefix("zh-Hant") { return "zh-Hant" }

        let components = normalized.split(separator: "-").map(String.init)
        guard let languageCode = components.first else { return nil }
        if languageCode == "zh" {
            let regionCode = components.dropFirst().first?.uppercased()
            return ["TW", "HK", "MO"].contains(regionCode) ? "zh-Hant" : "zh-Hans"
        }
        return supportedLanguageCodes.contains(languageCode) ? languageCode : nil
    }
}
