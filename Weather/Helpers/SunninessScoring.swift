//
//  SunninessScoring.swift
//  Weather
//
//  Purpose: Provides the shared, minimal sunniness score used by home,
//  list ranking, and city detail.
//

import Foundation

enum SunninessScoring {
    static func score(
        condition: AppWeatherCondition,
        icon: String,
        cloudCover: Double?
    ) -> Double? {
        guard let cloudCover else {
            DeveloperWarningCenter.show(
                title: "Cloud Cover Missing",
                message: "A sunniness score could not be calculated because WeatherKit returned no cloud cover value."
            )
            return nil
        }

        if icon.contains("moon") {
            return 0
        }

        let conditionBase: Double
        switch condition {
        case .clear:
            conditionBase = 100
        case .partlySunny:
            conditionBase = 82
        case .partlyCloudy:
            conditionBase = 66
        case .cloudy, .fog, .wind:
            conditionBase = 34
        case .rain, .drizzle, .snow:
            conditionBase = 12
        }

        let cloud = min(max(cloudCover, 0), 1)
        let cloudPenalty = cloud * 42
        return max(0, min(100, conditionBase - cloudPenalty))
    }
}
