//
//  AppDelegate.swift
//  Weather
//
//  Purpose: Bridges UIKit lifecycle events and Home Screen quick actions into SwiftUI.
//

import Foundation
import UIKit

// MARK: - Shortcut Destinations

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

// MARK: - Application Delegate

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

// MARK: - Scene Delegate

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

// MARK: - Notifications

extension Notification.Name {
    nonisolated static let weatherOpenMainViewShortcut = Notification.Name("weatherOpenMainViewShortcut")
}
