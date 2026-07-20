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

enum HomeScreenShortcutDestination: String, CaseIterable {
    case home
    case map
    case list

    var iconName: String {
        switch self {
        case .home: return "house"
        case .map: return "map"
        case .list: return "list.bullet"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .home: return localizedString("Home", locale: locale)
        case .map: return localizedString("Map", locale: locale)
        case .list: return localizedString("List", locale: locale)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    nonisolated private static let pendingShortcutDestinationKey = "pendingShortcutDestination"
    nonisolated private static let shortcutTypePrefix = "openView."
    nonisolated private static let legacyListShortcutTypePrefix = "openList."

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Self.updateHomeScreenShortcuts()
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

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = AppSceneDelegate.self
        }
        return configuration
    }

    static func updateHomeScreenShortcuts() {
        let locale = Locale(
            identifier: UserDefaults.standard.string(forKey: AppLanguageDefaults.storageKey)
                ?? Locale.autoupdatingCurrent.identifier
        )
        UIApplication.shared.shortcutItems = HomeScreenShortcutDestination.allCases.map { destination in
            UIApplicationShortcutItem(
                type: shortcutType(for: destination),
                localizedTitle: destination.localizedTitle(locale: locale),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: destination.iconName),
                userInfo: ["destination": destination.rawValue as NSString]
            )
        }
    }

    static func takePendingHomeScreenShortcut() -> HomeScreenShortcutDestination? {
        guard let rawValue = UserDefaults.standard.string(forKey: pendingShortcutDestinationKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: pendingShortcutDestinationKey)
        return HomeScreenShortcutDestination(rawValue: rawValue)
    }

    /// Lets the first rendered frame respect a cold-launch shortcut without
    /// consuming it before `ContentView` performs the actual navigation.
    static func hasPendingHomeScreenShortcut() -> Bool {
        UserDefaults.standard.string(forKey: pendingShortcutDestinationKey) != nil
    }

    nonisolated fileprivate static func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let destination = destination(from: shortcutItem) else { return false }
        UserDefaults.standard.set(destination.rawValue, forKey: pendingShortcutDestinationKey)
        NotificationCenter.default.post(name: .weatherOpenMainViewShortcut, object: destination.rawValue)
        return true
    }

    private static func shortcutType(for destination: HomeScreenShortcutDestination) -> String {
        "\(Bundle.main.bundleIdentifier ?? "Weather").\(shortcutTypePrefix)\(destination.rawValue)"
    }

    nonisolated private static func destination(
        from shortcutItem: UIApplicationShortcutItem
    ) -> HomeScreenShortcutDestination? {
        if let rawValue = shortcutItem.userInfo?["destination"] as? String,
           let destination = HomeScreenShortcutDestination(rawValue: rawValue) {
            return destination
        }

        let marker = ".\(shortcutTypePrefix)"
        if let range = shortcutItem.type.range(of: marker) {
            return HomeScreenShortcutDestination(rawValue: String(shortcutItem.type[range.upperBound...]))
        }

        // An app update can leave an old dynamic list shortcut visible until the
        // new shortcut set is installed. Route that legacy action to the List view.
        if shortcutItem.userInfo?["listID"] != nil
            || shortcutItem.type.contains(".\(legacyListShortcutTypePrefix)") {
            return .list
        }
        return nil
    }
}

/// SwiftUI apps use the scene lifecycle, so Home Screen quick actions arrive
/// here rather than through UIApplicationDelegate on current iOS versions.
final class AppSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let shortcutItem = connectionOptions.shortcutItem else { return }
        _ = AppDelegate.handleShortcutItem(shortcutItem)
    }

    nonisolated func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem
    ) async -> Bool {
        AppDelegate.handleShortcutItem(shortcutItem)
    }
}

// MARK: - App Entry Point

@main
struct WeatherApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @State private var theme = AppTheme.shared
    // iPad: Share the observable model across WindowGroup scenes so list and
    // weather mutations remain consistent when multiple app windows are open.
    @State private var weatherService: WeatherService

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

        // Construct the shared model only after persistence migrations finish,
        // so every iPad scene starts from the migrated source of truth.
        _weatherService = State(initialValue: WeatherService())
    }

    var body: some Scene {
        WindowGroup {
            ThemeRoot(
                theme: theme,
                appLocale: appLocale,
                weatherService: weatherService
            )
        }
    }
}

// MARK: - App Notifications

extension Notification.Name {
    nonisolated static let weatherOpenMainViewShortcut = Notification.Name("weatherOpenMainViewShortcut")
}

// MARK: - Theme Root Views

/// Outer layer: sets the preferred color scheme so the inner layer reads the correct one.
private struct ThemeRoot: View {
    let theme: AppTheme
    let appLocale: Locale
    let weatherService: WeatherService
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ThemeContent(
            theme: theme,
            appLocale: appLocale,
            weatherService: weatherService
        )
            .preferredColorScheme(theme.preferredColorScheme(for: colorScheme))
    }
}

/// Inner layer: reads `colorScheme` *after* `preferredColorScheme` has been applied,
/// so automatic mode sees the correct system value and forced modes see their override.
/// Also keeps the shared theme's system scheme in sync for environment-driven modifiers.
private struct ThemeContent: View {
    let theme: AppTheme
    let appLocale: Locale
    let weatherService: WeatherService
    @Environment(\.colorScheme) private var colorScheme
    // Propagate Increase Contrast into the app's custom color palettes.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize
    // Read Reduce Motion once at the app root so every screen follows it.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("useSystemTextSize") private var useSystemTextSize: Bool = true
    @AppStorage("appTextSizeLevel") private var appTextSizeLevel: Int = AppTextSizeLevel.defaultRawValue

    private var preferredDynamicTypeSize: DynamicTypeSize {
        AppTextSizeLevel.level(clamping: appTextSizeLevel).dynamicTypeSize
    }

    private var resolvedDynamicTypeSize: DynamicTypeSize {
        min(
            max(
                useSystemTextSize ? systemDynamicTypeSize : preferredDynamicTypeSize,
                AppTextSizeLevel.minimumDynamicTypeSize
            ),
            AppTextSizeLevel.maximumDynamicTypeSize
        )
    }

    var body: some View {
        let resolvedColors = theme.colors(for: colorScheme, contrast: colorSchemeContrast)
        ContentView(weatherService: weatherService)
            .environment(\.locale, appLocale)
            .environment(\.dynamicTypeSize, resolvedDynamicTypeSize)
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
