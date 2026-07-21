//
//  WidgetLocalization.swift
//  Weather
//
//  Purpose: Resolves widget strings using the language selected in the main app.
//

import Foundation

func widgetLocalizedString(_ key: String.LocalizationValue, locale: Locale) -> String {
    var resource = LocalizedStringResource(key)
    resource.locale = locale
    return String(localized: resource)
}
