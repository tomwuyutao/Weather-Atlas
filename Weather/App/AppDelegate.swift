//
//  AppDelegate.swift
//  Weather
//
//  Purpose: Registers Home Screen shortcuts and forwards taps to SwiftUI.
//

import Foundation
import UIKit

// MARK: - Shortcut Destinations

/// Destinations exposed by the Home Screen shortcut menu.
enum HomeScreenShortcutDestination: String, CaseIterable {
    case findSunNearMe
    case map
    case places

    static var allCases: [Self] {
        [.findSunNearMe, .places, .map]
    }

    static func decode(_ rawValue: String) -> Self? {
        switch rawValue {
        case "findSunNearMe": .findSunNearMe
        case "map": .map
        case "places", "list": .places
        default: nil
        }
    }

    var iconName: String {
        switch self {
        case .findSunNearMe: "location.fill"
        case .map: "map"
        case .places: "bookmark"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .findSunNearMe:
            localizedString(
                HomeLocationStore.load() == nil ? "Find Sun Near Me" : "Find Sun",
                locale: locale
            )
        case .map:
            localizedString("Map", locale: locale)
        case .places:
            localizedString("Saved Places", locale: locale)
        }
    }
}

// MARK: - Application Delegate

/// Registers Home Screen shortcuts and forwards warm-app shortcut taps.
class AppDelegate: NSObject, UIApplicationDelegate {
    /// Rebuilds shortcut titles using the app's selected language.
    static func updateHomeScreenShortcuts() {
        let locale = Locale(
            identifier: UserDefaults.standard.string(forKey: AppLanguageDefaults.storageKey)
                ?? Locale.autoupdatingCurrent.identifier
        )

        UIApplication.shared.shortcutItems = HomeScreenShortcutDestination.allCases.map { destination in
            UIApplicationShortcutItem(
                type: "\(Bundle.main.bundleIdentifier ?? "Weather").openView.\(destination.rawValue)",
                localizedTitle: destination.localizedTitle(locale: locale),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: destination.iconName),
                userInfo: ["destination": destination.rawValue as NSString]
            )
        }
    }

    /// Lets the active SwiftUI scene receive Home Screen shortcut taps.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = AppSceneDelegate.self
        return configuration
    }

    /// Sends a recognized shortcut directly to the SwiftUI root.
    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(Self.handleShortcut(shortcutItem))
    }

    fileprivate static func handleShortcut(
        _ shortcutItem: UIApplicationShortcutItem
    ) -> Bool {
        guard let destination = destination(from: shortcutItem) else {
            return false
        }

        NotificationCenter.default.post(
            name: .weatherOpenMainViewShortcut,
            object: destination.rawValue
        )
        return true
    }

    private static func destination(
        from shortcutItem: UIApplicationShortcutItem
    ) -> HomeScreenShortcutDestination? {
        if let rawValue = shortcutItem.userInfo?["destination"] as? String,
           let destination = HomeScreenShortcutDestination.decode(rawValue) {
            return destination
        }

        let marker = ".openView."
        if let range = shortcutItem.type.range(of: marker) {
            return HomeScreenShortcutDestination.decode(
                String(shortcutItem.type[range.upperBound...])
            )
        }

        if shortcutItem.userInfo?["listID"] != nil
            || shortcutItem.type.contains(".openList.") {
            return .places
        }

        return nil
    }
}

/// Forwards shortcuts delivered to the active SwiftUI scene.
final class AppSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(AppDelegate.handleShortcut(shortcutItem))
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Sent when iOS delivers a Home Screen shortcut while the app is running.
    nonisolated static let weatherOpenMainViewShortcut = Notification.Name(
        "weatherOpenMainViewShortcut"
    )
}
