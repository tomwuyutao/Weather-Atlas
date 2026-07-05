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

    static func show(title: String, message: String) {
        Task { @MainActor in
            NotificationCenter.default.post(
                name: notification,
                object: DeveloperWarning(title: title, message: "\(message)\n\nContact developer regarding this alert.")
            )
        }
    }
}
