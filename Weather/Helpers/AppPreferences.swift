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

enum TemperatureUnit: String, CaseIterable {
    case automatic = "automatic"
    case celsius = "celsius"
    case fahrenheit = "fahrenheit"

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

    static let defaultRawValue = TemperatureUnit.systemDefault.rawValue

    static var settingsCases: [TemperatureUnit] {
        [.celsius, .fahrenheit]
    }

    var resolved: TemperatureUnit {
        switch self {
        case .automatic:
            return Self.systemDefault
        case .celsius, .fahrenheit:
            return self
        }
    }

    func displayName(locale: Locale = .current) -> String {
        switch resolved {
        case .celsius: return localizedString("Celsius (°C)", locale: locale)
        case .fahrenheit: return localizedString("Fahrenheit (°F)", locale: locale)
        case .automatic: return resolved.displayName(locale: locale)
        }
    }

    private var measurementUnit: UnitTemperature {
        switch resolved {
        case .celsius: return .celsius
        case .fahrenheit: return .fahrenheit
        case .automatic: return resolved.measurementUnit
        }
    }

    func display(_ celsius: Double) -> String {
        let temperature = Measurement(value: celsius, unit: UnitTemperature.celsius)
            .converted(to: measurementUnit)
            .value
        return "\(Int(temperature.rounded()))°"
    }
}

// MARK: - App Text Size

enum AppTextSizeLevel: Int, CaseIterable {
    case small = 1
    case medium = 2
    case large = 3
    case xLarge = 4
    case xxLarge = 5

    static let defaultRawValue = AppTextSizeLevel.large.rawValue
    static let minimumDynamicTypeSize: DynamicTypeSize = .small
    static let maximumDynamicTypeSize: DynamicTypeSize = .xxLarge
    static let minimumSelectableRawValue = AppTextSizeLevel.small.rawValue
    static let maximumSelectableRawValue = AppTextSizeLevel.xxLarge.rawValue

    static func level(clamping rawValue: Int) -> AppTextSizeLevel {
        let clampedRawValue = min(
            max(rawValue, minimumSelectableRawValue),
            maximumSelectableRawValue
        )
        return AppTextSizeLevel(rawValue: clampedRawValue) ?? .large
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .xLarge
        case .xxLarge: return .xxLarge
        }
    }

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
