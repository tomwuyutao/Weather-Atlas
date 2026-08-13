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

    /// Localized Settings label for this preference.
    func displayName(locale: Locale = .current) -> String {
        switch self {
        case .celsius: return localizedString("Celsius (°C)", locale: locale)
        case .fahrenheit: return localizedString("Fahrenheit (°F)", locale: locale)
        }
    }

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

    /// Localized label displayed in Settings.
    func displayName(locale: Locale = .current) -> String {
        switch self {
        case .kilometers: localizedString("Kilometers (km)", locale: locale)
        case .miles: localizedString("Miles (mi)", locale: locale)
        }
    }

    /// Converts and formats WeatherKit's kilometre-based visibility value.
    func display(_ kilometers: Double) -> String {
        switch self {
        case .kilometers:
            return "\(Int(kilometers.rounded())) km"
        case .miles:
            return "\(Int((kilometers * 0.621_371).rounded())) mi"
        }
    }

    /// Converts stored kilometre values into the selected display unit.
    func value(fromKilometers kilometers: Double) -> Double {
        switch self {
        case .kilometers: kilometers
        case .miles: kilometers * 0.621_371
        }
    }
}

// MARK: - App Text Size

    /// Supported steps for the app-specific text-size slider.
    ///
    /// These are deliberately semantic slider steps rather than font sizes.
    /// SwiftUI maps them to Dynamic Type categories, so text still follows the
    /// platform's scaling and accessibility behavior.
enum AppTextSizeLevel: Int, CaseIterable {
    case small = 1
    case medium = 2
    case large = 3
    case xLarge = 4
    case xxLarge = 5

    /// Default slider step for new preferences.
    static let defaultRawValue = AppTextSizeLevel.large.rawValue
    /// Lowest raw value selectable by the Settings slider.
    static let minimumSelectableRawValue = AppTextSizeLevel.small.rawValue
    /// Highest raw value selectable by the Settings slider.
    static let maximumSelectableRawValue = AppTextSizeLevel.xxLarge.rawValue

    /// Normalizes out-of-range or corrupt raw values into the supported range.
    /// This makes a future change to the slider range safe for old persisted
    /// values: an unexpected integer becomes the nearest supported choice.
    static func level(clamping rawValue: Int) -> AppTextSizeLevel {
        let clampedRawValue = min(
            max(rawValue, minimumSelectableRawValue),
            maximumSelectableRawValue
        )
        return AppTextSizeLevel(rawValue: clampedRawValue) ?? .large
    }

    /// Dynamic Type category represented by this slider step.
    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .xLarge
        case .xxLarge: return .xxLarge
        }
    }

    /// Localized Settings label for this slider step.
    func displayName(locale: Locale) -> String {
        switch self {
        case .small: return localizedString("Small", locale: locale)
        case .medium: return localizedString("Medium", locale: locale)
        case .large: return localizedString("Default", locale: locale)
        case .xLarge: return localizedString("Large", locale: locale)
        case .xxLarge: return localizedString("Extra Large", locale: locale)
        }
    }
}
