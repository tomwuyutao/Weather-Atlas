//
//  ErrorAlert.swift
//  Weather
//
//  Purpose: Routes unexpected data-integrity failures to one visible alert
//  instead of silently replacing missing values with fallbacks.

import Foundation

// MARK: - Warning Model

struct DeveloperWarning: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - Warning Delivery

enum DeveloperWarningCenter {
    static let notification = Notification.Name("WeatherAtlasDeveloperWarning")
    @MainActor private static var reportedKeys: Set<String> = []

    static func show(title: String, message: String) {
        Task { @MainActor in
            post(title: title, message: message)
        }
    }

    static func showOnce(key: String, title: String, message: String) {
        Task { @MainActor in
            guard reportedKeys.insert(key).inserted else { return }
            post(title: title, message: message)
        }
    }

    @MainActor
    private static func post(title: String, message: String) {
        #if DEBUG
        print("[DeveloperWarning] \(title): \(message)")
        #endif

        let locale = Locale(identifier: UserDefaults.standard.string(forKey: "appLanguage") ?? Locale.autoupdatingCurrent.identifier)
        NotificationCenter.default.post(
            name: notification,
            object: DeveloperWarning(
                title: localizedString("Something went wrong", locale: locale),
                message: [
                    localizedString("We couldn't complete that action. Please try again.", locale: locale),
                    localizedString("If the problem continues, contact the developer.", locale: locale)
                ].joined(separator: "\n\n")
            )
        )
    }
}
