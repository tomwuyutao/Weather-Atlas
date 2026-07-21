//
//  SunninessRanking.swift
//  Weather
//
//  Purpose: Defines the sort modes and ranked city-weather value types.
//

import Foundation

// MARK: - Sort Mode

enum WeatherListSortMode: String, CaseIterable, Identifiable {
    case sunny
    case temperature
    case cloud

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .temperature: return "thermometer.medium"
        case .cloud: return "cloud"
        case .sunny: return "sun.max.fill"
        }
    }

    func title(locale: Locale) -> String {
        switch self {
        case .temperature: return localizedString("Temperature", locale: locale)
        case .cloud: return localizedString("Cloud Cover", locale: locale)
        case .sunny: return localizedString("Sunniness", locale: locale)
        }
    }
}

// MARK: - Ranked Values

struct SunnyCandidate: Identifiable {
    let cityWeather: CityWeather
    let condition: AppWeatherCondition
    let cloudCover: Double
    let precipitationChance: Double?
    let temperature: Double

    var id: UUID { cityWeather.id }
}

struct SunninessCandidateGroup: Identifiable {
    let title: String
    let icon: String
    let candidates: [SunnyCandidate]

    var id: String { title }
}
