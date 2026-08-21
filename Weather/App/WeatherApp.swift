//
//  WeatherApp.swift
//  Weather
//
//  Purpose: Defines app launch, first-run language defaults, and the root
//  environment applied to every window.
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
        // Do this once only. From then on, Settings owns the explicit choice.
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
        // iOS may return either underscore or hyphen locale separators. Work
        // with one normalized form before comparing the bundled languages.
        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
        if normalized.hasPrefix("zh-Hans") { return "zh-Hans" }
        if normalized.hasPrefix("zh-Hant") { return "zh-Hant" }

        let components = normalized.split(separator: "-").map(String.init)
        guard let languageCode = components.first else { return nil }
        if languageCode == "zh" {
            // Bare Chinese preferences need a region-based script choice.
            let regionCode = components.dropFirst().first?.uppercased()
            return ["TW", "HK", "MO"].contains(regionCode) ? "zh-Hant" : "zh-Hans"
        }
        return supportedLanguageCodes.contains(languageCode) ? languageCode : nil
    }
}

// MARK: - App Entry Point

/// Process entry point that creates shared state before opening themed windows.
@main
struct WeatherApp: App {
    /// UIKit delegate bridge used for Home Screen quick actions.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    /// Persisted language identifier selected within the app.
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    /// Shared observable theme mode.
    @State private var theme = AppTheme.shared
    /// Shared place, weather, and current-location recommendation model.
    @State private var appModel: WeatherModel
    /// Shared tab, navigation, and modal presentation coordinator.
    @State private var router: AppNavigation
    /// Single queue for native alerts describing data that remains blank.
    @State private var missingDataAlerts: MissingDataAlertCenter
    /// Shared system reachability state used by the offline-cache presentation.
    @State private var networkConnectivity: NetworkConnectivity
    /// Shared first-run and contextual-tip state for every app window.
    @State private var tutorial: TutorialPresentationState

    /// Creates the app's shared stores and navigation state.
    init() {
        // Both stores are created once and injected into the app-wide model,
        // so Your Location, Saved Places, Map, and widgets read the same data.
        AppLanguageDefaults.configureInitialLanguage()

        let placesStore = SavedPlacesStore()
        let missingDataAlerts = MissingDataAlertCenter()
        let networkConnectivity = NetworkConnectivity()

        let weatherStore = SavedPlacesWeatherStore(
            networkConnectivity: networkConnectivity
        )
        _appModel = State(
            initialValue: WeatherModel(
                placesStore: placesStore,
                weatherStore: weatherStore
            )
        )
        _router = State(initialValue: AppNavigation())
        _missingDataAlerts = State(initialValue: missingDataAlerts)
        _networkConnectivity = State(initialValue: networkConnectivity)
        _tutorial = State(initialValue: TutorialPresentationState())
    }

    /// Creates themed app windows backed by the shared place-owned model.
    var body: some Scene {
        // A `WindowGroup` supplies a separate SwiftUI window when the platform
        // supports it, while all windows receive the same app-level services.
        WindowGroup {
            ThemeRoot(
                theme: theme,
                appLocale: Locale(identifier: appLanguage),
                appModel: appModel,
                router: router,
                missingDataAlerts: missingDataAlerts,
                networkConnectivity: networkConnectivity,
                tutorial: tutorial
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
    /// Shared place and weather model.
    let appModel: WeatherModel
    /// Shared native navigation coordinator.
    let router: AppNavigation
    /// Shared native missing-data alert queue.
    let missingDataAlerts: MissingDataAlertCenter
    /// Shared system reachability state.
    let networkConnectivity: NetworkConnectivity
    /// Shared first-run and contextual-tip state.
    let tutorial: TutorialPresentationState
    /// Applies the theme's scheme preference before constructing inner content.
    var body: some View {
        // Apply the preferred scheme outside `ThemeContent`. That lets the
        // inner environment read the final light/dark value, not a stale one.
        ThemeContent(
            theme: theme,
            appLocale: appLocale,
            appModel: appModel,
            router: router,
            missingDataAlerts: missingDataAlerts,
            networkConnectivity: networkConnectivity,
            tutorial: tutorial
        )
        .preferredColorScheme(theme.preferredColorScheme)
    }
}

/// Reads the effective scheme after the outer preference has been applied.
private struct ThemeContent: View {
    /// User-selected theme mode inherited from the outer root.
    let theme: AppTheme
    /// Locale propagated to formatters and localization lookups.
    let appLocale: Locale
    /// Shared model supplied to the redesigned root application view.
    let appModel: WeatherModel
    /// Shared navigation coordinator supplied to the redesigned root.
    let router: AppNavigation
    /// Shared native missing-data alert queue.
    let missingDataAlerts: MissingDataAlertCenter
    /// Shared system reachability state injected into every root screen.
    let networkConnectivity: NetworkConnectivity
    /// Shared first-run and contextual-tip state.
    let tutorial: TutorialPresentationState
    /// Effective scheme after the outer preferred-scheme override.
    @Environment(\.colorScheme) private var colorScheme
    /// Propagates Increase Contrast into the app's custom color palettes.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// Current system text category.
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize
    /// Whether typography should follow the system rather than the in-app menu.
    @AppStorage("useSystemTextSize") private var useSystemTextSize: Bool = true
    /// Persisted in-app text-size step used when system sizing is disabled.
    @AppStorage("appTextSizeLevel") private var appTextSizeLevel: Int = AppTextSizeLevel.defaultRawValue

    /// Injects locale, size, theme, tint, contrast, and motion behavior app-wide.
    var body: some View {
        // Resolve the custom palette after reading the system scheme and
        // contrast setting. Every descendant then receives matching colors.
        let resolvedColors = theme.colors(for: colorScheme, contrast: colorSchemeContrast)
        ContentView(
            model: appModel,
            router: router,
            missingDataAlerts: missingDataAlerts,
            networkConnectivity: networkConnectivity,
            tutorial: tutorial
        )
            .environment(\.locale, appLocale)
            // Preserve the complete system Dynamic Type range. Only the explicit
            // in-app menu uses the app's smaller set of custom steps.
            .environment(
                \.dynamicTypeSize,
                useSystemTextSize
                    ? systemDynamicTypeSize
                    : AppTextSizeLevel.level(clamping: appTextSizeLevel).dynamicTypeSize
            )
            .environment(\.appTheme, theme)
            .environment(missingDataAlerts)
            .environment(networkConnectivity)
            .tint(resolvedColors.accent)
            .onChange(of: colorScheme, initial: true) { _, newScheme in
                // Retain the latest resolved system inputs so `AppTheme` can
                // compute its palette consistently outside this view as well.
                theme.systemScheme = newScheme
            }
            .onChange(of: colorSchemeContrast, initial: true) { _, newContrast in
                theme.systemContrast = newContrast
            }
    }
}
