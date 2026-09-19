//
//  Localization.swift
//  Weather
//
//  Purpose: Resolves String Catalog entries against the locale selected inside
//  the app rather than relying solely on the device locale.
//

import Foundation

func localizedString(_ key: String.LocalizationValue, locale: Locale) -> String {
  var resource = LocalizedStringResource(key)
  resource.locale = locale
  return String(localized: resource)
}
