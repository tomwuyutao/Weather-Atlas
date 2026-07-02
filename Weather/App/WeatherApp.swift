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
                localizedSubtitle: String(localized: "Open on Map"),
                icon: UIApplicationShortcutIcon(systemImageName: "map"),
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
        
        // Keep native bars transparent so Liquid Glass floats over app content.
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithTransparentBackground()
        navBarAppearance.backgroundColor = .clear
        navBarAppearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = navBarAppearance

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithTransparentBackground()
        tabBarAppearance.backgroundColor = .clear
        tabBarAppearance.shadowColor = .clear
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
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
/// Also keeps `AppTheme.shared.systemScheme` in sync so view modifiers update reactively.
private struct ThemeContent: View {
    let theme: AppTheme
    let appLocale: Locale
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let resolvedColors = theme.colors(for: colorScheme)
        ContentView()
            .environment(\.locale, appLocale)
            .defaultFont()
            .environment(\.appTheme, theme)
            .environment(\.themeColors, resolvedColors)
            .tint(resolvedColors.accent)
            .onChange(of: colorScheme, initial: true) { _, newScheme in
                theme.systemScheme = newScheme
            }
    }
}

// MARK: - Shared View and Font Helpers

extension View {
    func defaultFont() -> some View {
        self
    }
}

extension Font {
    static func avenir(_ style: TextStyle, weight: Font.Weight = .regular) -> Font {
        let size: CGFloat
        switch style {
        case .largeTitle: size = 34
        case .title: size = 28
        case .title2: size = 22
        case .title3: size = 20
        case .headline: size = 17
        case .subheadline: size = 15
        case .body: size = 17
        case .callout: size = 16
        case .footnote: size = 13
        case .caption: size = 12
        case .caption2: size = 11
        @unknown default: size = 17
        }
        return .system(size: size, weight: weight, design: .default)
    }
}
