//
//  Localization.swift
//  Weather
//
//  Purpose: Provides locale-explicit string lookup for views and services that
//  follow the app's in-app language rather than only the device locale.
//

import Foundation

/// Looks up a localized string for a specific locale supplied by SwiftUI.
func localizedString(_ key: String.LocalizationValue, locale: Locale) -> String {
    var resource = LocalizedStringResource(key)
    resource.locale = locale
    return String(localized: resource)
}
