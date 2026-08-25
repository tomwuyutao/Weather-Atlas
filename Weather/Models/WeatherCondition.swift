//
//  WeatherCondition.swift
//  Weather
//
//  Purpose: Preserves WeatherKit's condition exactly while providing the two
//  app-wide interpretations that are still needed: icon tint and sunny-hour
//  eligibility.
//

import WeatherKit

/// A persistable WeatherKit condition value.
///
/// WeatherKit's `WeatherCondition` is a `String`-backed, Codable enum, but it
/// is not Sendable before iOS 26. Keeping its raw value lets the app cache and
/// pass the API condition across isolation boundaries without changing it.
/// The source `symbolName` remains separate on each forecast and is always the
/// source of the displayed SF Symbol.
nonisolated struct AppWeatherCondition: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    // MARK: - WeatherKit Bridging

    /// Retains an exact raw value, including a value introduced by a newer
    /// WeatherKit release that this app has not yet compiled against.
    init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Captures WeatherKit's authoritative semantic condition without trying
    /// to infer it from the condition symbol.
    init(weatherKit condition: WeatherKit.WeatherCondition) {
        rawValue = condition.rawValue
    }

    /// Restores the SDK value when this build recognizes it. A stale cache or
    /// future API value remains displayable through its original symbol even
    /// when it has no known tint mapping yet.
    var weatherKitCondition: WeatherKit.WeatherCondition? {
        WeatherKit.WeatherCondition(rawValue: rawValue)
    }

    // MARK: - Presentation Semantics

    /// Selects only a color family for the API-provided symbol. This never
    /// changes the condition or substitutes another symbol.
    var iconTone: WeatherIconTone {
        guard let weatherKitCondition else { return .cloudy }

        switch weatherKitCondition {
        case .clear, .hot:
            return .clear
        case .mostlyClear:
            // This is the app's genuine partly-sunny category. Preserve
            // WeatherKit's supplied symbol, but give its API condition the
            // lighter sunny tint and sunny-hour eligibility below.
            return .partlySunny
        case .partlyCloudy:
            // Preserve WeatherKit's cloud-and-sun symbol, but keep this
            // non-sunny condition visually neutral.
            return .cloudy
        case .drizzle, .freezingDrizzle:
            return .drizzle
        case .hurricane, .isolatedThunderstorms, .scatteredThunderstorms,
                .strongStorms, .thunderstorms, .tropicalStorm,
                .rain, .heavyRain, .freezingRain, .sunShowers:
            return .rain
        case .blizzard, .blowingDust, .blowingSnow, .breezy, .cloudy,
                .flurries, .foggy, .frigid, .hail, .haze, .heavySnow,
                .mostlyCloudy, .sleet, .smoky, .snow, .sunFlurries, .windy,
                .wintryMix:
            return .cloudy
        @unknown default:
            return .cloudy
        }
    }

    /// Sunny-hour totals use WeatherKit's semantic condition directly. This
    /// preserves the existing policy that clear and mostly-clear daylight hours
    /// count, while partly cloudy and all precipitation do not.
    var countsAsSunnyHour: Bool {
        switch weatherKitCondition {
        case .clear?, .mostlyClear?:
            true
        default:
            false
        }
    }

    // MARK: - Codable Compatibility

    /// Maintains the historic JSON representation: a condition is encoded as
    /// one string rather than an object containing `rawValue`.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
