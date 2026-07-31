//
//  RecommendationEngine.swift
//  Weather
//
//  Purpose: Converts place forecasts into explainable, stable recommendation
//  values without coupling ranking logic to any SwiftUI view.
//

import Foundation

enum RecommendationSource: String, Codable, Hashable {
    case saved
    case nearby
}

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
            localizedString("Mixed Conditions", locale: locale)
        case .wet:
            localizedString("Rain and Drizzle", locale: locale)
        }
    }
}

struct PlaceRecommendation: Identifiable {
    let cityWeather: CityWeather
    let forecast: DailyForecast
    let condition: AppWeatherCondition
    let source: RecommendationSource
    let cloudCover: Double
    let precipitationChance: Double?
    let sunnyHourCount: Int
    let bestSunnyWindow: ClosedRange<Int>?
    let maximumFeelsLike: Double?
    let maximumVisibilityKilometers: Double?
    let distanceKilometers: Double?
    let population: Int?

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

struct RecommendationGroup: Identifiable {
    let condition: RecommendationConditionGroup
    let recommendations: [PlaceRecommendation]

    var id: RecommendationConditionGroup { condition }
}

enum RecommendationEngine {
    static func availableDates(in weather: [CityWeather]) -> [Date] {
        let dates = weather.flatMap { cityWeather in
            cityWeather.dailyForecasts.map { forecast in
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = cityWeather.timeZone
                let components = calendar.dateComponents([.year, .month, .day], from: forecast.date)
                var selectionCalendar = Calendar.current
                selectionCalendar.timeZone = .current
                return selectionCalendar.date(from: components)
            }
        }
        let today = Calendar.current.startOfDay(for: Date())
        return Array(
            Set(dates.compactMap { $0 })
                .filter { $0 >= today }
        )
        .sorted()
    }

    static func recommendation(
        for cityWeather: CityWeather,
        on date: Date,
        source: RecommendationSource,
        distanceKilometers: Double? = nil,
        population: Int? = nil
    ) -> PlaceRecommendation? {
        guard let forecast = cityWeather.forecastIfAvailable(on: date),
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
            source: source,
            cloudCover: cloudCover,
            precipitationChance: forecast.precipitationChance,
            sunnyHourCount: sunnyHourCount,
            bestSunnyWindow: SunninessScoring.longestSunnyHourRange(
                in: daylightHours,
                timeZone: cityWeather.timeZone
            ),
            maximumFeelsLike: forecast.hourlyForecasts.compactMap(\.apparentTemperature).max(),
            maximumVisibilityKilometers: forecast.hourlyForecasts.compactMap(\.visibilityKilometers).max(),
            distanceKilometers: distanceKilometers,
            population: population
        )
    }

    static func recommendations(
        for weather: [CityWeather],
        on date: Date,
        source: RecommendationSource
    ) -> [PlaceRecommendation] {
        weather.compactMap {
            recommendation(for: $0, on: date, source: source)
        }
    }

    static func ranked(_ recommendations: [PlaceRecommendation]) -> [PlaceRecommendation] {
        recommendations.sorted(by: isBetterRecommendation)
    }

    static func sorted(
        _ recommendations: [PlaceRecommendation],
        by mode: WeatherListSortMode,
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

    static func groups(from recommendations: [PlaceRecommendation]) -> [RecommendationGroup] {
        let rankedRecommendations = ranked(recommendations)
        return RecommendationConditionGroup.allCases.compactMap { condition in
            let matches = rankedRecommendations.filter { $0.conditionGroup == condition }
            return matches.isEmpty
                ? nil
                : RecommendationGroup(condition: condition, recommendations: matches)
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

        let lhsDistance = lhs.distanceKilometers ?? .greatestFiniteMagnitude
        let rhsDistance = rhs.distanceKilometers ?? .greatestFiniteMagnitude
        if lhsDistance != rhsDistance {
            return lhsDistance < rhsDistance
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
        lhs.cityWeather.city.localizedName(locale: locale)
            .localizedStandardCompare(rhs.cityWeather.city.localizedName(locale: locale))
            == .orderedAscending
    }
}
