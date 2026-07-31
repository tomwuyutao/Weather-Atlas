//
//  AppPreferences.swift
//  Weather
//
//  Purpose: Defines persisted preference value types that are consumed across
//  the app, independently of the Settings screen that edits them.
//

import Foundation
import SwiftUI

// MARK: - Temperature Unit

/// Persistable temperature preference exposed in Settings.
enum TemperatureUnit: String, CaseIterable {
    case automatic = "automatic"
    case celsius = "celsius"
    case fahrenheit = "fahrenheit"

    /// Unit inferred from the device's current measurement system.
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

    /// Converts Automatic into the current system choice.
    var resolved: TemperatureUnit {
        switch self {
        case .automatic:
            return Self.systemDefault
        case .celsius, .fahrenheit:
            return self
        }
    }

    /// Localized Settings label for this preference.
    func displayName(locale: Locale = .current) -> String {
        switch resolved {
        case .celsius: return localizedString("Celsius (°C)", locale: locale)
        case .fahrenheit: return localizedString("Fahrenheit (°F)", locale: locale)
        case .automatic: return resolved.displayName(locale: locale)
        }
    }

    /// Converts Celsius source data and formats a rounded localized value.
    func display(_ celsius: Double) -> String {
        let temperature = Measurement(value: celsius, unit: UnitTemperature.celsius)
            // `resolved` converts the legacy Automatic case before formatting.
            .converted(to: resolved == .fahrenheit ? .fahrenheit : .celsius)
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
enum AppTextSizeLevel: Int, CaseIterable {
    case small = 1
    case medium = 2
    case large = 3
    case xLarge = 4
    case xxLarge = 5

    /// Default slider step for new preferences.
    static let defaultRawValue = AppTextSizeLevel.large.rawValue
    /// Smallest Dynamic Type category offered by the optional in-app slider.
    static let minimumDynamicTypeSize: DynamicTypeSize = .small
    /// Largest Dynamic Type category offered by the optional in-app slider.
    /// System text sizing is not constrained to this value.
    static let maximumDynamicTypeSize: DynamicTypeSize = .xxLarge
    /// Lowest raw value selectable by the Settings slider.
    static let minimumSelectableRawValue = AppTextSizeLevel.small.rawValue
    /// Highest raw value selectable by the Settings slider.
    static let maximumSelectableRawValue = AppTextSizeLevel.xxLarge.rawValue

    /// Normalizes migrated or corrupt raw values into the supported range.
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
