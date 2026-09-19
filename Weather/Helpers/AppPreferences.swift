//
//  AppPreferences.swift
//  Weather
//
//  Purpose: Defines the small, raw-value-backed preference types consumed
//  across the app, independently of the Settings screen that edits them.
//
//  Reading guide: these enums describe *what* is stored in UserDefaults. The
//  SwiftUI Settings views own the actual `@AppStorage` properties; keeping the
//  types here lets formatting code share the same choices without depending on
//  any one screen.
//

import Foundation
import SwiftUI

// MARK: - Full Reset

/// Restores every lightweight display preference to its first-launch value.
enum AppPreferences {
  static func reset(defaults: UserDefaults = .standard) {
    defaults.set(TemperatureUnit.defaultRawValue, forKey: "temperatureUnit")
    defaults.set(DistanceUnit.defaultRawValue, forKey: "distanceUnit")
    defaults.set(
      Locale.preferredLanguages.lazy.compactMap {
        AppLanguageDefaults.supportedLanguageCode(for: $0)
      }.first ?? "en",
      forKey: AppLanguageDefaults.storageKey
    )
    defaults.set(true, forKey: AppTextSizePolicy.useSystemKey)
    defaults.set(
      AppTextSizeLevel.defaultRawValue,
      forKey: AppTextSizePolicy.appLevelKey
    )
    defaults.set(true, forKey: "showsMapSunnyHoursLegend")
    defaults.set(
      DetailReportSection.defaultStorageValue,
      forKey: DetailReportSection.storageKey
    )
    defaults.set(
      SavedPlacesViewMode.defaultRawValue,
      forKey: SavedPlacesViewMode.storageKey
    )
    defaults.set(
      SavedPlacesViewMode.defaultRawValue,
      forKey: SavedPlacesViewMode.mapResultsStorageKey
    )
    defaults.removeObject(forKey: "savedPlaceNameAutoTranslationEnabled")
  }
}

// MARK: - Detail Report Section Order

/// The three movable sections below Detail View's pinned daily timeline.
/// Raw values are persisted so the same order applies to every city report.
enum DetailReportSection: String, CaseIterable, Identifiable {
  case tenDaySunnyHours
  case basicWeatherData
  case nearbySunnyPlaces

  static let storageKey = "detailReportSectionOrder"
  static let defaultOrder = Array(allCases)
  static let defaultStorageValue =
    defaultOrder
    .map(\.rawValue)
    .joined(separator: ",")

  var id: String { rawValue }

  /// Ignores corrupt and duplicate values, then appends any sections added
  /// by a future app version in their default order.
  static func order(from storedValue: String) -> [DetailReportSection] {
    var seen = Set<DetailReportSection>()
    var result =
      storedValue
      .split(separator: ",")
      .compactMap { DetailReportSection(rawValue: String($0)) }
      .filter { seen.insert($0).inserted }

    result.append(
      contentsOf: defaultOrder.filter { seen.insert($0).inserted }
    )
    return result
  }

}

// MARK: - Saved Places View Mode

/// The three mutually exclusive ranking lenses shared by Saved Places and Map
/// results. Each surface persists its own selection so changing one never
/// changes the mode shown by the other.
enum SavedPlacesViewMode: String, CaseIterable, Identifiable {
  case day
  case weekend
  case outlook

  /// Existing key retained so current Saved Places preferences keep working.
  static let storageKey = "savedPlacesViewMode"
  /// Independent key for the transient Map Find Sun results screen.
  static let mapResultsStorageKey = "mapFindSunResultsViewMode"
  static let defaultRawValue = SavedPlacesViewMode.day.rawValue

  var id: String { rawValue }

}

// MARK: - Temperature Unit

/// Persistable temperature preference exposed in Settings.
enum TemperatureUnit: String, CaseIterable {
  case celsius = "celsius"
  case fahrenheit = "fahrenheit"

  /// Unit inferred from the device's current measurement system.
  ///
  /// Foundation does not expose a direct "weather temperature unit" setting.
  /// Formatting a harmless sample value with `.weather` therefore lets the
  /// current locale tell us whether it conventionally displays °C or °F.
  static var systemDefault: TemperatureUnit {
    let sample = Measurement(value: 0, unit: UnitTemperature.celsius)
      .formatted(.measurement(width: .abbreviated, usage: .weather).locale(.autoupdatingCurrent))
    if sample.localizedCaseInsensitiveContains("F") {
      return .fahrenheit
    }
    if sample.localizedCaseInsensitiveContains("C") {
      return .celsius
    }
    return .celsius
  }

  /// Initial persisted value for installations without a saved preference.
  static let defaultRawValue = TemperatureUnit.systemDefault.rawValue

  /// Converts Celsius source data and formats a rounded localized value.
  /// WeatherKit values are normalized to Celsius before they reach this
  /// layer, so every caller can use one consistent source unit.
  func display(_ celsius: Double) -> String {
    let temperature = Measurement(value: celsius, unit: UnitTemperature.celsius)
      .converted(to: self == .fahrenheit ? .fahrenheit : .celsius)
      .value
    return "\(Int(temperature.rounded()))°"
  }
}

// MARK: - Distance Unit

/// Persisted distance preference used for visibility values and charts.
enum DistanceUnit: String, CaseIterable {
  case kilometers
  case miles

  /// Existing visibility data is stored in kilometres, preserving that as the
  /// default for people who have not chosen a distance preference yet.
  /// Persisting a canonical unit avoids accumulating conversion errors when a
  /// person toggles between kilometres and miles.
  static let defaultRawValue = DistanceUnit.kilometers.rawValue

  /// Converts stored kilometre values into the selected display unit.
  func value(fromKilometers kilometers: Double) -> Double {
    switch self {
    case .kilometers: kilometers
    case .miles: kilometers * 0.621_371
    }
  }
}

// MARK: - App Text Size

/// Supported steps for the app-specific text-size menu.
///
/// These are deliberately semantic menu choices rather than font sizes.
/// SwiftUI maps them to Dynamic Type categories, so text still follows the
/// platform's scaling behavior.
enum AppTextSizeLevel: Int, CaseIterable {
  case small = 1
  case medium = 2
  case large = 3
  case xLarge = 4

  /// Default text-size choice for new preferences.
  static let defaultRawValue = AppTextSizeLevel.large.rawValue
  /// Lowest raw value selectable by the Settings menu.
  static let minimumSelectableRawValue = AppTextSizeLevel.small.rawValue
  /// Highest raw value selectable by the Settings menu.
  static let maximumSelectableRawValue = AppTextSizeLevel.xLarge.rawValue

  /// Dynamic Type category represented by this slider step.
  var dynamicTypeSize: DynamicTypeSize {
    switch self {
    case .small: return .small
    case .medium: return .medium
    case .large: return .large
    case .xLarge: return .xLarge
    }
  }

}
