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

// MARK: - Saved Places Dashboard Order

/// The two movable planning sections on the Saved Places dashboard.
/// Raw values are persisted so a person's preferred order survives relaunches.
enum SavedPlacesDashboardSection: String, CaseIterable, Identifiable {
    case selectedDay
    case planAhead

    static let storageKey = "savedPlacesDashboardSectionOrder"
    static let defaultOrder = Array(allCases)
    static let defaultStorageValue = storageValue(for: defaultOrder)

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .selectedDay:
            "Selected Day"
        case .planAhead:
            "Plan Ahead"
        }
    }

    var systemImage: String {
        switch self {
        case .selectedDay:
            "calendar"
        case .planAhead:
            "calendar.badge.checkmark"
        }
    }

    /// Ignores corrupt and duplicate values, then appends sections introduced
    /// by a future app version in their default order.
    static func order(
        from storedValue: String
    ) -> [SavedPlacesDashboardSection] {
        var seen = Set<SavedPlacesDashboardSection>()
        var result = storedValue
            .split(separator: ",")
            .compactMap {
                SavedPlacesDashboardSection(rawValue: String($0))
            }
            .filter { seen.insert($0).inserted }

        result.append(
            contentsOf: defaultOrder.filter { seen.insert($0).inserted }
        )
        return result
    }

    static func storageValue(
        for sections: [SavedPlacesDashboardSection]
    ) -> String {
        sections.map(\.rawValue).joined(separator: ",")
    }
}

/// Movable cards within the Saved Places dashboard's Selected Day section.
enum SavedPlacesSelectedDayCard: String, CaseIterable, Identifiable {
    case bestSunnyPlaces

    static let storageKey = "savedPlacesSelectedDayCardOrder"
    static let defaultOrder = Array(allCases)
    static let defaultStorageValue = storageValue(for: defaultOrder)

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .bestSunnyPlaces:
            "Best Sunny Places"
        }
    }

    var systemImage: String {
        switch self {
        case .bestSunnyPlaces:
            "mappin.and.ellipse"
        }
    }

    /// Ignores corrupt and duplicate values, then appends cards introduced by
    /// a future app version in their default order.
    static func order(
        from storedValue: String
    ) -> [SavedPlacesSelectedDayCard] {
        var seen = Set<SavedPlacesSelectedDayCard>()
        var result = storedValue
            .split(separator: ",")
            .compactMap {
                SavedPlacesSelectedDayCard(rawValue: String($0))
            }
            .filter { seen.insert($0).inserted }

        result.append(
            contentsOf: defaultOrder.filter { seen.insert($0).inserted }
        )
        return result
    }

    static func storageValue(
        for cards: [SavedPlacesSelectedDayCard]
    ) -> String {
        cards.map(\.rawValue).joined(separator: ",")
    }
}

/// Movable cards within the Saved Places dashboard's Plan Ahead section.
enum SavedPlacesPlanAheadCard: String, CaseIterable, Identifiable {
    case bestWeekendEscape
    case sunnyOutlookByPlace

    static let storageKey = "savedPlacesPlanAheadCardOrder"
    static let defaultOrder = Array(allCases)
    static let defaultStorageValue = storageValue(for: defaultOrder)

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .bestWeekendEscape:
            "Best Weekend Escape"
        case .sunnyOutlookByPlace:
            "Sunny Outlook by Place"
        }
    }

    var systemImage: String {
        switch self {
        case .bestWeekendEscape:
            "suitcase.rolling"
        case .sunnyOutlookByPlace:
            "sun.max"
        }
    }

    /// Ignores corrupt and duplicate values, then appends cards introduced by
    /// a future app version in their default order.
    static func order(
        from storedValue: String
    ) -> [SavedPlacesPlanAheadCard] {
        var seen = Set<SavedPlacesPlanAheadCard>()
        var result = storedValue
            .split(separator: ",")
            .compactMap {
                SavedPlacesPlanAheadCard(rawValue: String($0))
            }
            .filter { seen.insert($0).inserted }

        result.append(
            contentsOf: defaultOrder.filter { seen.insert($0).inserted }
        )
        return result
    }

    static func storageValue(
        for cards: [SavedPlacesPlanAheadCard]
    ) -> String {
        cards.map(\.rawValue).joined(separator: ",")
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
