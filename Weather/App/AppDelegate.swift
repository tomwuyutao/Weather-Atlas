//
//  AppDelegate.swift
//  Weather
//
//  Purpose: Bridges UIKit lifecycle events and Home Screen quick actions into SwiftUI.
//

import Foundation
import UIKit

// MARK: - Shortcut Destinations

/// Stable destinations exposed through the app's dynamic Home Screen shortcuts.
enum HomeScreenShortcutDestination: String, CaseIterable {
    /// Raw values are persisted in `UserDefaults`, so keep them stable across
    /// releases even if the visible tab labels change.
    case findSunNearMe
    case map
    case places

    /// Retains decoding support for Home Screen shortcuts created by earlier
    /// app versions without publishing a fourth action in the current menu.
    case legacyHome = "home"

    static var allCases: [HomeScreenShortcutDestination] {
        [.findSunNearMe, .places, .map]
    }

    /// Decodes both current destination values and the pre-redesign `list`
    /// value. Legacy list shortcuts now land on the Saved Places dashboard,
    /// which is the closest equivalent after named city lists were removed.
    nonisolated static func decodePersistedValue(_ rawValue: String) -> Self? {
        switch rawValue {
        case "findSunNearMe": .findSunNearMe
        case "map": .map
        case "places", "list": .places
        case "home": .legacyHome
        default: nil
        }
    }

    /// The SF Symbol paired with this destination in the system shortcut menu.
    var iconName: String {
        switch self {
        case .findSunNearMe: return "location.fill"
        case .map: return "map"
        case .places: return "bookmark"
        case .legacyHome: return "location.fill"
        }
    }

    /// Returns the user-facing destination name in the app-selected locale.
    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .findSunNearMe:
            // A fixed Home is a named place, not the device-relative “Near Me”
            // scope. The app supplies the exact Home-centered query after launch.
            return localizedString(
                HomeLocationStore.load() == nil ? "Find Sun Near Me" : "Find Sun",
                locale: locale
            )
        case .map: return localizedString("Map", locale: locale)
        case .places: return localizedString("Saved Places", locale: locale)
        case .legacyHome: return localizedString("Your Location", locale: locale)
        }
    }
}

// MARK: - Application Delegate

/// Connects UIKit launch and shortcut callbacks to the SwiftUI navigation layer.
class AppDelegate: NSObject, UIApplicationDelegate {
    /// User-defaults key holding a shortcut until the SwiftUI app shell consumes it.
    nonisolated private static let pendingShortcutDestinationKey = "pendingShortcutDestination"
    /// Scene-qualified hand-offs keep a quick action delivered to one iPad
    /// window from being consumed by another window's independent router.
    nonisolated private static let pendingShortcutSceneKeyPrefix =
        "pendingShortcutDestination.scene."

    /// Installs current shortcuts and captures a shortcut supplied at cold launch.
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

    /// Routes a shortcut selected while the application process is already alive.
    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(Self.handleShortcutItem(shortcutItem))
    }

    /// Installs the scene delegate needed for modern quick-action delivery.
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

    /// Removes an undelivered scene-qualified action when iOS permanently
    /// discards that window session.
    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {
        let defaults = UserDefaults.standard
        for session in sceneSessions {
            defaults.removeObject(
                forKey: Self.pendingShortcutSceneKey(
                    for: session.persistentIdentifier
                )
            )
        }
    }

    /// Rebuilds the dynamic shortcut set using the app's selected language.
    static func updateHomeScreenShortcuts() {
        // UIKit builds shortcut titles outside SwiftUI's environment, so read
        // the stored language directly instead of relying on `@Environment`.
        let locale = Locale(
            identifier: UserDefaults.standard.string(forKey: AppLanguageDefaults.storageKey)
                ?? Locale.autoupdatingCurrent.identifier
        )
        UIApplication.shared.shortcutItems = HomeScreenShortcutDestination.allCases.map { destination in
            // SpringBoard requires a bundle-qualified shortcut identifier.
            UIApplicationShortcutItem(
                type: "\(Bundle.main.bundleIdentifier ?? "Weather").openView.\(destination.rawValue)",
                localizedTitle: destination.localizedTitle(locale: locale),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: destination.iconName),
                userInfo: ["destination": destination.rawValue as NSString]
            )
        }
    }

    /// Atomically consumes the destination saved by a UIKit shortcut callback.
    static func takePendingHomeScreenShortcut(
        for sceneSessionIdentifier: String? = nil,
        includeGlobalFallback: Bool = true
    ) -> HomeScreenShortcutDestination? {
        // Removing before returning makes this a one-shot hand-off: reopening
        // the app later does not repeat an already handled shortcut.
        let defaults = UserDefaults.standard
        if let sceneSessionIdentifier {
            let sceneKey = pendingShortcutSceneKey(
                for: sceneSessionIdentifier
            )
            if let rawValue = defaults.string(forKey: sceneKey) {
                defaults.removeObject(forKey: sceneKey)
                return HomeScreenShortcutDestination.decodePersistedValue(
                    rawValue
                )
            }
        }
        guard includeGlobalFallback else { return nil }
        guard let rawValue = defaults.string(
            forKey: pendingShortcutDestinationKey
        ) else {
            return nil
        }
        defaults.removeObject(forKey: pendingShortcutDestinationKey)
        return HomeScreenShortcutDestination.decodePersistedValue(rawValue)
    }

    /// Removes any stored external navigation intent during a full app reset,
    /// so onboarding starts at the same blank root as a first installation.
    static func clearPendingHomeScreenShortcut() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: pendingShortcutDestinationKey)
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(pendingShortcutSceneKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Decodes, stores, and broadcasts a shortcut received outside the main actor.
    nonisolated fileprivate static func handleShortcutItem(
        _ shortcutItem: UIApplicationShortcutItem,
        sceneSessionIdentifier: String? = nil
    ) -> Bool {
        guard let destination = destination(from: shortcutItem) else { return false }
        // UIKit callbacks can arrive before the SwiftUI root exists. Persist
        // first, then broadcast so either lifecycle timing can consume it.
        let defaults = UserDefaults.standard
        let key = sceneSessionIdentifier.map {
            pendingShortcutSceneKey(for: $0)
        } ?? pendingShortcutDestinationKey
        if sceneSessionIdentifier != nil {
            // Scene lifecycle delivery supersedes a duplicate application-level
            // cold-launch hand-off for the same system action.
            defaults.removeObject(forKey: pendingShortcutDestinationKey)
        }
        defaults.set(destination.rawValue, forKey: key)
        NotificationCenter.default.post(
            name: .weatherOpenMainViewShortcut,
            object: sceneSessionIdentifier
        )
        return true
    }

    nonisolated private static func pendingShortcutSceneKey(
        for sceneSessionIdentifier: String
    ) -> String {
        pendingShortcutSceneKeyPrefix + sceneSessionIdentifier
    }

    /// Resolves current and legacy shortcut payloads into a supported destination.
    nonisolated private static func destination(
        from shortcutItem: UIApplicationShortcutItem
    ) -> HomeScreenShortcutDestination? {
        // Prefer the explicit payload added by current versions of the app,
        // while translating the pre-redesign `list` value to Saved Places.
        if let rawValue = shortcutItem.userInfo?["destination"] as? String,
           let destination = HomeScreenShortcutDestination.decodePersistedValue(rawValue) {
            return destination
        }

        // Fall back to the identifier shape so older installed shortcuts still
        // work even when they do not contain the `userInfo` dictionary.
        let marker = ".openView."
        if let range = shortcutItem.type.range(of: marker) {
            let rawValue = String(shortcutItem.type[range.upperBound...])
            if let destination = HomeScreenShortcutDestination.decodePersistedValue(rawValue) {
                return destination
            }
        }

        // The oldest builds published one action per named city list. Those
        // lists no longer exist, so both payload shapes open the current Saved
        // Places dashboard instead of leaving a stale SpringBoard item inert.
        if shortcutItem.userInfo?["listID"] != nil
            || shortcutItem.type.contains(".openList.") {
            return .places
        }

        return nil
    }
}

// MARK: - Scene Delegate

/// SwiftUI apps use the scene lifecycle, so Home Screen quick actions arrive
/// here rather than through UIApplicationDelegate on current iOS versions.
final class AppSceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Captures a shortcut that accompanied creation of a new window scene.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let windowScene = scene as? UIWindowScene {
            AppTextSizePolicy.applyCurrentPreferences(to: windowScene)
        }
        if let shortcutItem = connectionOptions.shortcutItem {
            _ = AppDelegate.handleShortcutItem(
                shortcutItem,
                sceneSessionIdentifier: session.persistentIdentifier
            )
        }
    }

    /// Reconciles the cap before a suspended window becomes interactive again.
    func sceneWillEnterForeground(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        AppTextSizePolicy.applyCurrentPreferences(to: windowScene)
    }

    /// Handles a shortcut delivered to an existing window scene.
    nonisolated func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem
    ) async -> Bool {
        // The same static handler keeps cold-launch and warm-scene behavior
        // identical; its Boolean result is the system's completion signal.
        let sceneSessionIdentifier = await MainActor.run {
            windowScene.session.persistentIdentifier
        }
        return AppDelegate.handleShortcutItem(
            shortcutItem,
            sceneSessionIdentifier: sceneSessionIdentifier
        )
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Broadcast emitted after UIKit has persisted a main-view shortcut request.
    nonisolated static let weatherOpenMainViewShortcut = Notification.Name("weatherOpenMainViewShortcut")
}
