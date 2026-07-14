//
//  WeatherApp.swift
//  Weather
//
//  Purpose: App entry point, language bootstrapping, app delegate hooks,
//  shortcuts, and shared view/font helpers.
//

import SwiftUI
import UIKit

// MARK: - Language Defaults

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

// MARK: - App Delegate

class AppDelegate: NSObject, UIApplicationDelegate {
    private static let pendingListShortcutKey = "pendingListShortcutID"
    private static let listShortcutTypePrefix = "openList."

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Self.updateHomeScreenListShortcuts()
        if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            return !Self.handleShortcutItem(shortcutItem)
        }
        return true
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(Self.handleShortcutItem(shortcutItem))
    }

    static func updateHomeScreenListShortcuts() {
        UIApplication.shared.shortcutItems = CityListID.allLists.prefix(3).map { listID in
            UIApplicationShortcutItem(
                type: shortcutType(for: listID),
                localizedTitle: listID.localizedDisplayName(),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "list.bullet"),
                userInfo: ["listID": listID.rawValue as NSString]
            )
        }
    }

    static func takePendingListShortcutID() -> String? {
        guard let rawValue = UserDefaults.standard.string(forKey: pendingListShortcutKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: pendingListShortcutKey)
        return rawValue
    }

    private static func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let rawValue = listID(from: shortcutItem) else { return false }
        UserDefaults.standard.set(rawValue, forKey: pendingListShortcutKey)
        NotificationCenter.default.post(name: .weatherOpenListShortcut, object: rawValue)
        return true
    }

    private static func shortcutType(for listID: CityListID) -> String {
        "\(Bundle.main.bundleIdentifier ?? "Weather").\(listShortcutTypePrefix)\(listID.rawValue)"
    }

    private static func listID(from shortcutItem: UIApplicationShortcutItem) -> String? {
        if let rawValue = shortcutItem.userInfo?["listID"] as? String {
            return rawValue
        }
        let marker = ".\(listShortcutTypePrefix)"
        guard let range = shortcutItem.type.range(of: marker) else { return nil }
        return String(shortcutItem.type[range.upperBound...])
    }
}

// MARK: - App Entry Point

@main
struct WeatherApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @State private var theme = AppTheme.shared

    private var appLocale: Locale {
        Locale(identifier: appLanguage)
    }
    
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
        
    }

    var body: some Scene {
        WindowGroup {
            ThemeRoot(theme: theme, appLocale: appLocale)
        }
    }
}

// MARK: - App Notifications

extension Notification.Name {
    static let weatherOpenListShortcut = Notification.Name("weatherOpenListShortcut")
}

// MARK: - Theme Root Views

/// Outer layer: sets the preferred color scheme so the inner layer reads the correct one.
private struct ThemeRoot: View {
    let theme: AppTheme
    let appLocale: Locale
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ThemeContent(theme: theme, appLocale: appLocale)
            .preferredColorScheme(theme.preferredColorScheme(for: colorScheme))
    }
}

/// Inner layer: reads `colorScheme` *after* `preferredColorScheme` has been applied,
/// so automatic mode sees the correct system value and forced modes see their override.
/// Also keeps the shared theme's system scheme in sync for environment-driven modifiers.
private struct ThemeContent: View {
    let theme: AppTheme
    let appLocale: Locale
    @Environment(\.colorScheme) private var colorScheme
    // Accessibility: Propagate Increase Contrast into the app's custom color palettes.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize
    // Accessibility: Read Reduce Motion once at the app root so every screen follows it.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("useSystemTextSize") private var useSystemTextSize: Bool = true
    @AppStorage("appTextSizeLevel") private var appTextSizeLevel: Int = AppTextSizeLevel.defaultRawValue

    private var preferredDynamicTypeSize: DynamicTypeSize {
        (AppTextSizeLevel(rawValue: appTextSizeLevel) ?? .large).dynamicTypeSize
    }

    private var resolvedDynamicTypeSize: DynamicTypeSize {
        useSystemTextSize ? systemDynamicTypeSize : preferredDynamicTypeSize
    }

    var body: some View {
        let resolvedColors = theme.colors(for: colorScheme, contrast: colorSchemeContrast)
        ContentView()
            .environment(\.locale, appLocale)
            .environment(\.dynamicTypeSize, resolvedDynamicTypeSize)
            .environment(\.appTheme, theme)
            .tint(resolvedColors.accent)
            // Accessibility: Disable app-supplied animation without altering state transitions.
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
