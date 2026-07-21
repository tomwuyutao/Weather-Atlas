//
//  DeveloperWarnings.swift
//  Weather
//
//  Purpose: Delivers unexpected data-integrity failures to the app shell so
//  they remain visible instead of being silently replaced with fallbacks.
//

import Foundation

// MARK: - Warning Model

struct DeveloperWarning: Identifiable, Equatable {
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

    /// Routes missing source data through the same queued system alert used by
    /// developer warnings, with a title localized for the selected app language.
    static func showMissingData(message: String, locale: Locale) {
        show(
            title: localizedString("Weather Data Missing", locale: locale),
            message: message
        )
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

        NotificationCenter.default.post(
            name: notification,
            object: DeveloperWarning(
                title: title,
                message: message
            )
        )
    }
}
