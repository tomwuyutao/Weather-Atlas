//
//  WeatherSymbols.swift
//  Weather
//
//  Purpose: Defines the small semantic tint vocabulary used to color
//  WeatherKit-provided symbols.
//

// MARK: - Weather Symbol Tones

/// Color families for WeatherKit symbols.
///
/// This type intentionally controls color only. Forecast views render the
/// exact `symbolName` supplied by WeatherKit instead of choosing a canonical
/// replacement symbol.
nonisolated enum WeatherIconTone: Sendable {
    case clear
    /// WeatherKit's `.mostlyClear` condition: favorable enough to count as
    /// sun, but visually distinct from an entirely clear sky.
    case partlySunny
    case cloudy
    case rain
    case drizzle
}
