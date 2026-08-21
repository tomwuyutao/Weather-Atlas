//
//  WeatherCondition.swift
//  Weather
//
//  Purpose: Defines the app's normalized weather-condition domain model and
//  its localized/icon/color presentation mappings.
//
//  Reading guide: WeatherKit exposes many detailed conditions and SF Symbol
//  names. The rest of the app uses this deliberately smaller vocabulary so
//  ranking, cards, maps, and widgets all make the same interpretation.
//

import WeatherKit

// MARK: - Normalized Weather Conditions

/// Finite condition vocabulary shared by analysis and presentation code.
/// Sunny-place recommendation policy lives with `CityWeather`.
/// The raw string makes the enum `Codable`, so cached and widget data can store
/// a condition without depending on WeatherKit's own type at decode time.
nonisolated enum AppWeatherCondition: String, Codable, Sendable {
    case clear
    /// Legacy persisted value retained so older forecast caches remain
    /// decodable. New WeatherKit data never creates this case.
    case partlySunny
    case partlyCloudy
    case cloudy
    case rain
    case drizzle
    case snow
    case fog
    case wind

    /// Chooses the weather symbol's semantic tint. Map markers deliberately
    /// use sunny-hour totals instead of the condition category. `partlySunny`
    /// remains decodable for legacy snapshots, but shares the neutral cloudy
    /// presentation because WeatherKit's partly-cloudy condition is not sun.
    var iconTone: WeatherIconTone {
        switch self {
        case .clear: return .clear
        case .partlySunny, .partlyCloudy, .cloudy: return .cloudy
        case .rain: return .rain
        case .drizzle: return .drizzle
        // Snow, fog, and wind share the neutral cloudy mark.
        case .snow, .fog, .wind: return .cloudy
        }
    }

    // MARK: - Sunny Predicates

    /// Whether this condition contributes to a favorable sunny window. The
    /// name remains source-compatible with persisted snapshots, but only clear
    /// conditions count: partly-cloudy weather is never treated as sun.
    nonisolated var isSunnyOrPartlySunny: Bool {
        self == .clear
    }

    // MARK: - Source Classification

    /// Resolves a WeatherKit symbol without inventing a default classification.
    /// The tests run from specific to broad because a symbol such as a rainy
    /// cloud must match rain before the generic "cloud" fallback.
    nonisolated static func fromWeatherSymbol(_ symbolName: String) -> AppWeatherCondition? {
        // Normalize case once so the following substring checks are predictable.
        let symbol = symbolName.lowercased()

        if symbol.contains("drizzle") { return .drizzle }
        if symbol.contains("rain")
            || symbol.contains("thunderstorm")
            || symbol.contains("storm") {
            return .rain
        }
        if symbol.contains("snow")
            || symbol.contains("sleet")
            || symbol.contains("flurr") {
            return .snow
        }
        if symbol.contains("wind")
            || symbol.contains("hurricane")
            || symbol.contains("tropicalstorm") {
            return .wind
        }
        if symbol.contains("fog")
            || symbol.contains("haze")
            || symbol.contains("smoke") {
            return .fog
        }
        // Moon symbols describe nighttime equivalents. The app's daytime
        // presentation treats them as the comparable clear/cloudy condition.
        if symbol.contains("moon") {
            return symbol.contains("cloud") ? .partlyCloudy : .clear
        }
        // A source symbol with both a cloud and sun is still partly cloudy. It
        // uses the gray cloud.sun presentation and contributes no sunny hours.
        if symbol.contains("cloud") && symbol.contains("sun") { return .partlyCloudy }
        if symbol.contains("sun.max") || symbol == "sun" || symbol == "sun.fill" {
            return .clear
        }
        if symbol.contains("partly") && symbol.contains("cloud") { return .partlyCloudy }
        if symbol.contains("cloud") { return .cloudy }
        // Returning nil is intentional: guessing "cloudy" would make rankings
        // look confident even though the source symbol was not understood.
        return nil
    }

    /// Maps WeatherKit's semantic condition into the app's smaller presentation
    /// vocabulary. Source-symbol parsing handles conditions outside this map.
    /// WeatherKit's partly-cloudy condition always remains partly cloudy; the
    /// daylight flag is used separately for chart bounds and never changes sky
    /// classification or sunny-hour eligibility.
    nonisolated static func fromWeatherKit(
        _ condition: WeatherKit.WeatherCondition
    ) -> AppWeatherCondition? {
        switch condition {
        case .clear, .mostlyClear:
            return .clear
        case .partlyCloudy:
            return .partlyCloudy
        case .cloudy, .mostlyCloudy:
            return .cloudy
        case .drizzle, .freezingDrizzle:
            return .drizzle
        case .rain, .heavyRain, .freezingRain, .sunShowers:
            return .rain
        case .blizzard, .blowingSnow, .flurries, .hail, .heavySnow,
                .sleet, .snow, .sunFlurries, .wintryMix:
            return .snow
        case .blowingDust, .foggy, .haze, .smoky:
            return .fog
        case .breezy, .windy:
            return .wind
        case .hurricane, .isolatedThunderstorms, .scatteredThunderstorms,
                .strongStorms, .thunderstorms, .tropicalStorm:
            return .rain
        case .frigid, .hot:
            // Temperature extremes don't describe the sky or precipitation.
            // Let the source symbol provide the presentation classification.
            return nil
        // Future WeatherKit cases land here until the app deliberately decides
        // how they should affect ranking and presentation.
        @unknown default:
            return nil
        }
    }

    /// Resolves a complete WeatherKit condition at the provider boundary.
    ///
    /// WeatherKit's semantic enum is authoritative because it distinguishes
    /// phenomena that can share similar SF Symbols. The separately supplied
    /// symbol is used only for semantic cases the app has not classified yet.
    /// Both the app and widget call this method so their cached condition,
    /// sunny-hour eligibility, icon, and tint cannot drift apart.
    nonisolated static func resolve(
        weatherKit condition: WeatherKit.WeatherCondition,
        symbolName: String
    ) -> AppWeatherCondition? {
        fromWeatherKit(condition)
            ?? fromWeatherSymbol(symbolName)
    }

    // MARK: - Canonical Icon

    /// Canonical SF Symbol used to display the normalized condition. The icon
    /// mapping is centralized so views never embed their own condition switch.
    var displayIcon: String {
        switch self {
        case .clear: return WeatherIconSymbol.clear
        case .partlySunny, .partlyCloudy: return WeatherIconSymbol.partlyCloudy
        case .cloudy: return WeatherIconSymbol.cloudy
        case .rain: return WeatherIconSymbol.rain
        case .drizzle: return WeatherIconSymbol.drizzle
        case .snow: return WeatherIconSymbol.snow
        case .fog: return WeatherIconSymbol.fog
        case .wind: return WeatherIconSymbol.wind
        }
    }
}
