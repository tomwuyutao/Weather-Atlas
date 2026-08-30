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

// MARK: - Detail Report Section Order

/// The three movable sections below Detail View's pinned daily timeline.
/// Raw values are persisted so the same order applies to every city report.
enum DetailReportSection: String, CaseIterable, Identifiable {
    case tenDaySunnyHours
    case basicWeatherData
    case nearbySunnyPlaces

    static let storageKey = "detailReportSectionOrder"
    static let defaultOrder = Array(allCases)
    static let defaultStorageValue = storageValue(for: defaultOrder)

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .tenDaySunnyHours:
            "10-Day Sunny Hours"
        case .basicWeatherData:
            "Basic Weather Data"
        case .nearbySunnyPlaces:
            "Nearby Sunnier Places"
        }
    }

    var systemImage: String {
        switch self {
        case .tenDaySunnyHours:
            "calendar"
        case .basicWeatherData:
            "square.grid.2x2"
        case .nearbySunnyPlaces:
            "location.magnifyingglass"
        }
    }

    /// Ignores corrupt and duplicate values, then appends any sections added
    /// by a future app version in their default order.
    static func order(from storedValue: String) -> [DetailReportSection] {
        var seen = Set<DetailReportSection>()
        var result = storedValue
            .split(separator: ",")
            .compactMap { DetailReportSection(rawValue: String($0)) }
            .filter { seen.insert($0).inserted }

        result.append(
            contentsOf: defaultOrder.filter { seen.insert($0).inserted }
        )
        return result
    }

    static func storageValue(
        for sections: [DetailReportSection]
    ) -> String {
        sections.map(\.rawValue).joined(separator: ",")
    }
}

// MARK: - Saved Places View Mode

/// The three mutually exclusive ranking lenses on Saved Places. Persisting
/// only the selected lens replaces the previous nested section/card ordering
/// preferences while preserving the person's context across relaunches.
enum SavedPlacesViewMode: String, CaseIterable, Identifiable {
    case day
    case weekend
    case outlook

    static let storageKey = "savedPlacesViewMode"
    static let defaultRawValue = SavedPlacesViewMode.day.rawValue

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .day:
            "Best Sunny Places"
        case .weekend:
            "Best Weekend Escape"
        case .outlook:
            "Next Sunny Day"
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        case .day:
            "Places ranked by sunny daylight hours on the selected day."
        case .weekend:
            "Saturday and Sunday ranked separately by sunny daylight hours."
        case .outlook:
            "Each place’s next day with at least 80% sunny daylight."
        }
    }

    func displayName(locale: Locale) -> String {
        var resource = title
        resource.locale = locale
        return String(localized: resource)
    }
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
        "\(displayValue(kilometers)) \(symbol)"
    }

    /// Formats a visibility value without repeating its unit in a range.
    func displayValue(_ kilometers: Double) -> String {
        switch self {
        case .kilometers:
            return "\(Int(kilometers.rounded()))"
        case .miles:
            return "\(Int((kilometers * 0.621_371).rounded()))"
        }
    }

    var symbol: String {
        switch self {
        case .kilometers: "km"
        case .miles: "mi"
        }
    }

    /// Formats both ends of a visibility range with one trailing unit label.
    func displayRange(_ low: Double, _ high: Double) -> String {
        "\(displayValue(low)) – \(displayValue(high)) \(symbol)"
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
        }
    }

    /// Localized Settings label for this slider step.
    func displayName(locale: Locale) -> String {
        switch self {
        case .small: return localizedString("Small", locale: locale)
        case .medium: return localizedString("Medium", locale: locale)
        case .large: return localizedString("Large (System)", locale: locale)
        case .xLarge: return localizedString("Large", locale: locale)
        }
    }
}
