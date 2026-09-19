//
//  AppTheme.swift
//  Weather
//
//  Purpose: Stores the selected appearance and resolves the semantic palette
//  supplied to SwiftUI views.
//

import Foundation
import SwiftUI

// MARK: - Theme Style

/// Persisted appearance modes offered by the Theme settings screen.
enum AppThemeStyle: String, CaseIterable {
  case automatic = "automatic"
  case automaticBlack = "automaticBlack"
  case light = "light"
  case dark = "dark"
  case black = "black"

  static let defaultRawValue = AppThemeStyle.automatic.rawValue

  func displayName(locale: Locale) -> String {
    switch self {
    case .automatic: return localizedString("Automatic", locale: locale)
    case .automaticBlack: return localizedString("Automatic (Black)", locale: locale)
    case .light: return localizedString("Light", locale: locale)
    case .dark: return localizedString("Dark", locale: locale)
    case .black: return localizedString("Black", locale: locale)
    }
  }
}

// MARK: - Theme Manager

@Observable
/// Observable theme manager shared across every app window.
class AppTheme {
  static let shared = AppTheme()

  var style: AppThemeStyle {
    didSet {
      UserDefaults.standard.set(style.rawValue, forKey: "appThemeStyle")
    }
  }

  var systemScheme: ColorScheme = .light
  var systemContrast: ColorSchemeContrast = .standard

  var colors: ThemeColors {
    if systemScheme == .dark && (style == .black || style == .automaticBlack) {
      return systemContrast == .increased ? .increasedContrastBlack : .black
    }
    if systemContrast == .increased {
      return systemScheme == .dark ? .increasedContrastDark : .increasedContrastLight
    }
    return systemScheme == .dark ? .dark : .light
  }

  func colors(
    for scheme: ColorScheme,
    contrast: ColorSchemeContrast? = nil
  ) -> ThemeColors {
    let contrast = contrast ?? systemContrast
    if scheme == .dark && (style == .black || style == .automaticBlack) {
      return contrast == .increased ? .increasedContrastBlack : .black
    }
    if contrast == .increased {
      return scheme == .dark ? .increasedContrastDark : .increasedContrastLight
    }
    return scheme == .dark ? .dark : .light
  }

  private init() {
    let raw =
      UserDefaults.standard.string(forKey: "appThemeStyle")
      ?? AppThemeStyle.defaultRawValue
    style = AppThemeStyle(rawValue: raw) ?? .automatic
  }
}

extension EnvironmentValues {
  @Entry var appTheme: AppTheme = .shared
}
