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
    case home
    case map
    case list

    /// The SF Symbol paired with this destination in the system shortcut menu.
    var iconName: String {
        switch self {
        case .home: return "house"
        case .map: return "map"
        case .list: return "mappin.and.ellipse"
        }
    }

    /// Returns the user-facing destination name in the app-selected locale.
    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .home: return localizedString("Home", locale: locale)
        case .map: return localizedString("Map", locale: locale)
        // Keep the legacy raw value so installed shortcuts continue to decode.
        case .list: return localizedString("Places", locale: locale)
        }
    }
}

// MARK: - Application Delegate

/// Connects UIKit launch and shortcut callbacks to the SwiftUI navigation layer.
class AppDelegate: NSObject, UIApplicationDelegate {
    /// User-defaults key holding a shortcut until the SwiftUI app shell consumes it.
    nonisolated private static let pendingShortcutDestinationKey = "pendingShortcutDestination"

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

    /// Rebuilds the dynamic shortcut set using the app's selected language.
    static func updateHomeScreenShortcuts() {
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
    static func takePendingHomeScreenShortcut() -> HomeScreenShortcutDestination? {
        guard let rawValue = UserDefaults.standard.string(forKey: pendingShortcutDestinationKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: pendingShortcutDestinationKey)
        return HomeScreenShortcutDestination(rawValue: rawValue)
    }

    /// Decodes, stores, and broadcasts a shortcut received outside the main actor.
    nonisolated fileprivate static func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let destination = destination(from: shortcutItem) else { return false }
        UserDefaults.standard.set(destination.rawValue, forKey: pendingShortcutDestinationKey)
        NotificationCenter.default.post(name: .weatherOpenMainViewShortcut, object: destination.rawValue)
        return true
    }

    /// Resolves current and legacy shortcut payloads into a supported destination.
    nonisolated private static func destination(
        from shortcutItem: UIApplicationShortcutItem
    ) -> HomeScreenShortcutDestination? {
        if let rawValue = shortcutItem.userInfo?["destination"] as? String,
           let destination = HomeScreenShortcutDestination(rawValue: rawValue) {
            return destination
        }

        // Current destination shortcuts follow the bundle-qualified openView marker.
        let marker = ".openView."
        if let range = shortcutItem.type.range(of: marker) {
            return HomeScreenShortcutDestination(rawValue: String(shortcutItem.type[range.upperBound...]))
        }

        // An app update can leave an old dynamic list shortcut visible until the
        // new shortcut set is installed. Route that legacy action to Places.
        if shortcutItem.userInfo?["listID"] != nil
            || shortcutItem.type.contains(".openList.") {
            return .list
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
        guard let shortcutItem = connectionOptions.shortcutItem else { return }
        _ = AppDelegate.handleShortcutItem(shortcutItem)
    }

    /// Handles a shortcut delivered to an existing window scene.
    nonisolated func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem
    ) async -> Bool {
        AppDelegate.handleShortcutItem(shortcutItem)
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Broadcast emitted after UIKit has persisted a main-view shortcut request.
    nonisolated static let weatherOpenMainViewShortcut = Notification.Name("weatherOpenMainViewShortcut")
}
