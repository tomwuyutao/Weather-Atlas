//
//  MapOverlayMetric.swift
//  Weather
//
//  Purpose: Defines the optional metric displayed by Map without changing the
//  app-wide sunny-hours ranking used by Saved Places and Find Sun.
//

import Foundation

enum WeatherMetricMode: String, CaseIterable, Identifiable {
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
        case .sunny: "sun.max.fill"
        case .temperature: "thermometer.medium"
        case .feelsLike: "thermometer.variable"
        case .cloud: "cloud"
        case .rainChance: "cloud.rain"
        case .visibility: "eye"
        case .uvIndex: "sun.max.trianglebadge.exclamationmark"
        }
    }

    func title(locale: Locale) -> String {
        switch self {
        case .sunny: localizedString("Sunny Hours", locale: locale)
        case .temperature: localizedString("Max Temperature", locale: locale)
        case .feelsLike: localizedString("Feels Like", locale: locale)
        case .cloud: localizedString("Cloud Cover", locale: locale)
        case .rainChance: localizedString("Rain Chance", locale: locale)
        case .visibility: localizedString("Visibility", locale: locale)
        case .uvIndex: localizedString("UV Index", locale: locale)
        }
    }
}

/// Map-only ordering for a selected display overlay. This does not affect
/// Saved Places, nearby results, or Find Sun, which always rank by sunny hours.
enum MapOverlayOrdering {
    static func sorted(
        _ recommendations: [PlaceRecommendation],
        by mode: WeatherMetricMode,
        locale: Locale
    ) -> [PlaceRecommendation] {
        recommendations.sorted { lhs, rhs in
            switch mode {
            case .sunny:
                return SunnyPlacesRanking.ranked([lhs, rhs], locale: locale).first?.id == lhs.id
            case .temperature:
                return compare(
                    lhs.forecast.dailyHigh,
                    rhs.forecast.dailyHigh,
                    higherFirst: true,
                    lhs: lhs,
                    rhs: rhs,
                    locale: locale
                )
            case .feelsLike:
                return compare(
                    lhs.maximumFeelsLike,
                    rhs.maximumFeelsLike,
                    higherFirst: true,
                    lhs: lhs,
                    rhs: rhs,
                    locale: locale
                )
            case .cloud:
                return compare(
                    lhs.cloudCover,
                    rhs.cloudCover,
                    higherFirst: false,
                    lhs: lhs,
                    rhs: rhs,
                    locale: locale
                )
            case .rainChance:
                return compare(
                    lhs.precipitationChance,
                    rhs.precipitationChance,
                    higherFirst: true,
                    lhs: lhs,
                    rhs: rhs,
                    locale: locale
                )
            case .visibility:
                return compare(
                    lhs.maximumVisibilityKilometers,
                    rhs.maximumVisibilityKilometers,
                    higherFirst: true,
                    lhs: lhs,
                    rhs: rhs,
                    locale: locale
                )
            case .uvIndex:
                return compare(
                    lhs.forecast.uvIndex.map(Double.init),
                    rhs.forecast.uvIndex.map(Double.init),
                    higherFirst: true,
                    lhs: lhs,
                    rhs: rhs,
                    locale: locale
                )
            }
        }
    }

    private static func compare(
        _ lhsValue: Double?,
        _ rhsValue: Double?,
        higherFirst: Bool,
        lhs: PlaceRecommendation,
        rhs: PlaceRecommendation,
        locale: Locale
    ) -> Bool {
        switch (lhsValue, rhsValue) {
        case let (left?, right?) where left != right:
            return higherFirst ? left > right : left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return compareNames(lhs, rhs, locale: locale)
        }
    }

    private static func compareNames(
        _ lhs: PlaceRecommendation,
        _ rhs: PlaceRecommendation,
        locale: Locale
    ) -> Bool {
        let order = lhs.cityWeather.city.displayName.compare(
            rhs.cityWeather.city.displayName,
            options: [.caseInsensitive, .diacriticInsensitive, .numeric],
            locale: locale
        )
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
