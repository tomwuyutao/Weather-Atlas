//
//  SunninessRanking.swift
//  Weather
//
//  Purpose: Defines the native Places sorting choices. Recommendation values
//  and grouping live in RecommendationEngine.
//

import Foundation

/// User-selectable ordering applied to saved-place and recommendation results.
enum WeatherListSortMode: String, CaseIterable, Identifiable {
    case sunny
    case temperature
    case feelsLike
    case cloud
    case rainChance
    case visibility
    case uvIndex

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .temperature: "thermometer.medium"
        case .feelsLike: "thermometer.variable"
        case .cloud: "cloud"
        case .rainChance: "cloud.rain"
        case .visibility: "eye"
        case .uvIndex: "sun.max.trianglebadge.exclamationmark"
        case .sunny: "sun.max.fill"
        }
    }

    func title(locale: Locale) -> String {
        switch self {
        case .sunny: localizedString("Sunniness", locale: locale)
        case .temperature: localizedString("Max Temperature", locale: locale)
        case .feelsLike: localizedString("Feels Like", locale: locale)
        case .cloud: localizedString("Cloud Cover", locale: locale)
        case .rainChance: localizedString("Rain Chance", locale: locale)
        case .visibility: localizedString("Visibility", locale: locale)
        case .uvIndex: localizedString("UV Index", locale: locale)
        }
    }
}
