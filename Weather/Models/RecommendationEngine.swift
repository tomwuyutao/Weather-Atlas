//
//  RecommendationEngine.swift
//  Weather
//
//  Purpose: Converts place forecasts into explainable, stable recommendation
//  values without coupling ranking logic to any SwiftUI view.
//

import Foundation

enum RecommendationConditionGroup: String, CaseIterable, Identifiable {
    case sunny
    case partlySunny
    case mixed
    case wet

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .sunny:
            "sun.max.fill"
        case .partlySunny:
            WeatherIconSymbol.partlyCloudy
        case .mixed:
            "cloud"
        case .wet:
            "cloud.rain"
        }
    }

    func title(locale: Locale) -> String {
        switch self {
        case .sunny:
            localizedString("Sunny", locale: locale)
        case .partlySunny:
            localizedString("Partly Sunny", locale: locale)
        case .mixed:
            localizedString("Cloudy, Windy, Snowy, Foggy", locale: locale)
        case .wet:
            localizedString("Drizzle, Rain", locale: locale)
        }
    }
}

struct PlaceRecommendation: Identifiable {
    let cityWeather: CityWeather
    let forecast: DailyForecast
    let condition: AppWeatherCondition
    let cloudCover: Double
    let precipitationChance: Double?
    let sunnyHourCount: Int
    let bestSunnyWindow: ClosedRange<Int>?
    let maximumFeelsLike: Double?
    let maximumVisibilityKilometers: Double?

    var id: City.ID { cityWeather.city.id }

    var conditionGroup: RecommendationConditionGroup {
        switch condition {
        case .clear:
            .sunny
        case .partlySunny:
            .partlySunny
        case .drizzle, .rain:
            .wet
        case .partlyCloudy, .cloudy, .snow, .fog, .wind:
            .mixed
        }
    }
}

enum RecommendationEngine {
    static func recommendation(
        for cityWeather: CityWeather,
        on date: Date,
        selectionCalendar: Calendar = .current
    ) -> PlaceRecommendation? {
        guard let forecast = cityWeather.forecastIfAvailable(
            on: date,
            selectionCalendar: selectionCalendar
        ),
              let condition = SunninessScoring.condition(for: forecast),
              let cloudCover = forecast.cloudCover else {
            return nil
        }

        let daylightHours = SunninessScoring.daytimeHours(
            for: forecast,
            timeZone: cityWeather.timeZone
        ) ?? []
        let sunnyHourCount = daylightHours.reduce(into: 0) { count, hour in
            if SunninessScoring.condition(for: hour)?.isSunnyOrPartlySunny == true {
                count += 1
            }
        }

        return PlaceRecommendation(
            cityWeather: cityWeather,
            forecast: forecast,
            condition: condition,
            cloudCover: cloudCover,
            precipitationChance: forecast.precipitationChance,
            sunnyHourCount: sunnyHourCount,
            bestSunnyWindow: SunninessScoring.longestSunnyHourRange(
                in: daylightHours,
                timeZone: cityWeather.timeZone
            ),
            maximumFeelsLike: forecast.hourlyForecasts.compactMap(\.apparentTemperature).max(),
            maximumVisibilityKilometers: forecast.hourlyForecasts.compactMap(\.visibilityKilometers).max()
        )
    }

    static func ranked(_ recommendations: [PlaceRecommendation]) -> [PlaceRecommendation] {
        recommendations.sorted(by: isBetterRecommendation)
    }

    static func sorted(
        _ recommendations: [PlaceRecommendation],
        by mode: WeatherMetricMode,
        locale: Locale
    ) -> [PlaceRecommendation] {
        recommendations.sorted { lhs, rhs in
            switch mode {
            case .sunny:
                return isBetterRecommendation(lhs, rhs)
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
                return compareOptional(
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
                return compareOptional(
                    lhs.precipitationChance,
                    rhs.precipitationChance,
                    higherFirst: true,
                    lhs: lhs,
                    rhs: rhs,
                    locale: locale
                )
            case .visibility:
                return compareOptional(
                    lhs.maximumVisibilityKilometers,
                    rhs.maximumVisibilityKilometers,
                    higherFirst: true,
                    lhs: lhs,
                    rhs: rhs,
                    locale: locale
                )
            case .uvIndex:
                return compareOptional(
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

    nonisolated private static func isBetterRecommendation(
        _ lhs: PlaceRecommendation,
        _ rhs: PlaceRecommendation
    ) -> Bool {
        if lhs.condition.sunninessRank != rhs.condition.sunninessRank {
            return lhs.condition.sunninessRank < rhs.condition.sunninessRank
        }
        if lhs.sunnyHourCount != rhs.sunnyHourCount {
            return lhs.sunnyHourCount > rhs.sunnyHourCount
        }
        if lhs.cloudCover != rhs.cloudCover {
            return lhs.cloudCover < rhs.cloudCover
        }

        let lhsRain = lhs.precipitationChance ?? 0
        let rhsRain = rhs.precipitationChance ?? 0
        if lhsRain != rhsRain {
            return lhsRain < rhsRain
        }

        return lhs.cityWeather.city.id.uuidString < rhs.cityWeather.city.id.uuidString
    }

    private static func compare(
        _ lhsValue: Double,
        _ rhsValue: Double,
        higherFirst: Bool,
        lhs: PlaceRecommendation,
        rhs: PlaceRecommendation,
        locale: Locale
    ) -> Bool {
        guard lhsValue == rhsValue else {
            return higherFirst ? lhsValue > rhsValue : lhsValue < rhsValue
        }
        return compareNames(lhs, rhs, locale: locale)
    }

    private static func compareOptional(
        _ lhsValue: Double?,
        _ rhsValue: Double?,
        higherFirst: Bool,
        lhs: PlaceRecommendation,
        rhs: PlaceRecommendation,
        locale: Locale
    ) -> Bool {
        switch (lhsValue, rhsValue) {
        case let (left?, right?):
            return compare(
                left,
                right,
                higherFirst: higherFirst,
                lhs: lhs,
                rhs: rhs,
                locale: locale
            )
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return compareNames(lhs, rhs, locale: locale)
        }
    }

    private static func compareNames(
        _ lhs: PlaceRecommendation,
        _ rhs: PlaceRecommendation,
        locale: Locale
    ) -> Bool {
        lhs.cityWeather.city.displayName.compare(
            rhs.cityWeather.city.displayName,
            options: [.caseInsensitive, .diacriticInsensitive, .numeric],
            locale: locale
        ) == .orderedAscending
    }
}
