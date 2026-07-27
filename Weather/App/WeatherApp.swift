//
//  WeatherApp.swift
//  Weather
//
//  Purpose: Defines app launch, first-run language defaults, data migrations,
//  and the root environment applied to every window.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - First-Run Language Selection

/// Selects a supported first-run language without overriding later user choices.
enum AppLanguageDefaults {
    /// Shared preference key read by the app and shortcut publisher.
    static let storageKey = "appLanguage"
    /// Language identifiers for which the bundled localization table is complete.
    static let supportedLanguageCodes = ["en", "fr", "de", "it", "ja", "ko", "pt", "ru", "zh-Hans", "es", "zh-Hant"]

    /// Seeds the language preference only when no app-specific choice exists.
    static func configureInitialLanguage() {
        guard UserDefaults.standard.object(forKey: storageKey) == nil else { return }
        // Use the first device preference the bundled localization table supports.
        for identifier in Locale.preferredLanguages {
            if let supportedCode = supportedLanguageCode(for: identifier) {
                UserDefaults.standard.set(supportedCode, forKey: storageKey)
                return
            }
        }
        UserDefaults.standard.set("en", forKey: storageKey)
    }

    /// Normalizes an Apple locale identifier to a bundled language code.
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

// MARK: - App Entry Point

/// Process entry point that performs migrations before opening themed windows.
@main
struct WeatherApp: App {
    /// UIKit delegate bridge used for Home Screen quick actions.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    /// Persisted language identifier selected within the app.
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    /// Shared observable theme mode.
    @State private var theme = AppTheme.shared
    /// Observable model shared across WindowGroup scenes so list and weather
    /// mutations remain consistent in multiple iPad windows.
    @State private var weatherService: WeatherService

    /// Runs preference and cache migrations before constructing shared app state.
    init() {
        AppLanguageDefaults.configureInitialLanguage()

        // Always reset overlay mode to weather on launch
        UserDefaults.standard.set("weather", forKey: "mapOverlayMode")

        // One-time migration: clear old default-list data so new region defaults take effect.
        let migrationKey = "defaultCitiesMigrationV3"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            UserDefaults.standard.removeObject(forKey: "savedCitiesList")
            UserDefaults.standard.removeObject(forKey: "cachedWeatherData")
            UserDefaults.standard.removeObject(forKey: "weatherCacheTimestamp")
            UserDefaults.standard.removeObject(forKey: "deletedBuiltInLists")
            UserDefaults.standard.removeObject(forKey: "listOrder")
            UserDefaults.standard.removeObject(forKey: "customListNames")

            for rawValue in ["china", "europe", "asia", "northAmerica", "southAmerica", "africa", "australia"] {
                UserDefaults.standard.removeObject(forKey: "savedCitiesList_\(rawValue)")
                UserDefaults.standard.removeObject(forKey: "cachedWeatherData_\(rawValue)")
                UserDefaults.standard.removeObject(forKey: "weatherCacheTimestamp_\(rawValue)")
            }

            if UserDefaults.standard.string(forKey: "activeListID") == "china" {
                UserDefaults.standard.set(CityListID.europe.rawValue, forKey: "activeListID")
            }
            UserDefaults.standard.set(true, forKey: migrationKey)
        }

        // Daily weather metrics now come from WeatherKit's native daytime forecast.
        // Refresh weather snapshots once without affecting saved city lists or preferences.
        let weatherCacheMigrationKey = "weatherCacheDaytimeForecastMigrationV1"
        if !UserDefaults.standard.bool(forKey: weatherCacheMigrationKey) {
            let cacheKeyPrefixes = ["cachedWeatherData", "weatherCacheTimestamp"]
            for key in UserDefaults.standard.dictionaryRepresentation().keys where cacheKeyPrefixes.contains(where: { key.hasPrefix($0) }) {
                UserDefaults.standard.removeObject(forKey: key)
            }
            UserDefaults.standard.set(true, forKey: weatherCacheMigrationKey)
        }

        // Construct the shared model only after persistence migrations finish,
        // so every iPad scene starts from the migrated source of truth.
        _weatherService = State(initialValue: WeatherService())
    }

    /// Creates themed app windows backed by the shared weather service.
    var body: some Scene {
        WindowGroup {
            ThemeRoot(
                theme: theme,
                // Construct the locale directly from the app-specific preference.
                appLocale: Locale(identifier: appLanguage),
                weatherService: weatherService
            )
        }
    }
}

// MARK: - Root Environment

/// Outer layer that applies the preferred scheme before inner content reads it.
struct ThemeRoot: View {
    /// User-selected theme mode.
    let theme: AppTheme
    /// Locale chosen in Settings.
    let appLocale: Locale
    /// Shared observable weather and list model.
    let weatherService: WeatherService
    /// System scheme used to resolve automatic theme modes.
    @Environment(\.colorScheme) private var colorScheme

    /// Applies the theme's scheme preference before constructing inner content.
    var body: some View {
        ThemeContent(
            theme: theme,
            appLocale: appLocale,
            weatherService: weatherService
        )
        .preferredColorScheme(theme.preferredColorScheme(for: colorScheme))
    }
}

/// Reads the effective scheme after the outer preference has been applied.
private struct ThemeContent: View {
    /// User-selected theme mode inherited from the outer root.
    let theme: AppTheme
    /// Locale propagated to formatters and localization lookups.
    let appLocale: Locale
    /// Shared model supplied to the root application view.
    let weatherService: WeatherService
    /// Effective scheme after the outer preferred-scheme override.
    @Environment(\.colorScheme) private var colorScheme
    /// Propagates Increase Contrast into the app's custom color palettes.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// Current system text category before app-specific clamping.
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize
    /// Reads Reduce Motion once so every feature follows the same policy.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether typography should follow the system rather than the in-app slider.
    @AppStorage("useSystemTextSize") private var useSystemTextSize: Bool = true
    /// Persisted in-app text-size step used when system sizing is disabled.
    @AppStorage("appTextSizeLevel") private var appTextSizeLevel: Int = AppTextSizeLevel.defaultRawValue

    /// Injects locale, size, theme, tint, contrast, and motion behavior app-wide.
    var body: some View {
        let resolvedColors = theme.colors(for: colorScheme, contrast: colorSchemeContrast)
        ContentView(weatherService: weatherService)
            .environment(\.locale, appLocale)
            // Resolve the system or persisted slider step within the app's supported limits.
            .environment(
                \.dynamicTypeSize,
                min(
                    max(
                        useSystemTextSize
                            ? systemDynamicTypeSize
                            : AppTextSizeLevel.level(clamping: appTextSizeLevel).dynamicTypeSize,
                        AppTextSizeLevel.minimumDynamicTypeSize
                    ),
                    AppTextSizeLevel.maximumDynamicTypeSize
                )
            )
            .environment(\.appTheme, theme)
            .tint(resolvedColors.accent)
            // Disable app-supplied animation without altering state transitions.
            .transaction { transaction in
                if reduceMotion {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .onChange(of: colorScheme, initial: true) { _, newScheme in
                theme.systemScheme = newScheme
            }
            .onChange(of: colorSchemeContrast, initial: true) { _, newContrast in
                theme.systemContrast = newContrast
            }
    }
}
