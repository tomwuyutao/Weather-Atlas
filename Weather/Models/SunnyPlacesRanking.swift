//
//  SunnyPlacesRanking.swift
//  Weather
//
//  Purpose: Builds and ranks sunny-place summaries from available forecast data.
//

import Foundation

/// One city’s available weather facts for a selected local date.
///
/// A recommendation is valid when the app has a daily condition and usable
/// daylight hourly data. Optional Map metrics remain optional so a missing
/// secondary field never becomes a made-up value or removes an otherwise valid
/// sunny-hours comparison.
struct PlaceRecommendation: Identifiable {
    let cityWeather: CityWeather
    let forecast: DailyForecast
    let condition: AppWeatherCondition
    let cloudCover: Double?
    let precipitationChance: Double?
    let sunnyHourCount: Double
    let bestSunnyWindow: ClosedRange<Int>?
    let maximumFeelsLike: Double?
    let maximumVisibilityKilometers: Double?

    var id: City.ID { cityWeather.city.id }
}

/// The result of assessing one city without treating missing source data as a
/// zero-hour forecast.
struct PlaceRecommendationAssessment {
    let recommendation: PlaceRecommendation?
    let issues: [WeatherDataIssue]
}

/// Shared sunny-hours calculation and deterministic ranking.
///
/// Clear and Partly Sunny each count as one full sunny hour. All comparison
/// surfaces use the same order: sunny hours descending, then city name, then
/// stable city ID.
enum SunnyPlacesRanking {
    static func assessment(
        for cityWeather: CityWeather,
        on date: Date,
        selectionCalendar: Calendar = .current
    ) -> PlaceRecommendationAssessment {
        guard let forecast = cityWeather.forecastIfAvailable(
            on: date,
            selectionCalendar: selectionCalendar
        ) else {
            return PlaceRecommendationAssessment(
                recommendation: nil,
                issues: [.missingForecastData(at: date)]
            )
        }

        var issues = ForecastValidation.dailyFieldIssues(for: forecast)
        guard let condition = forecast.condition else {
            return PlaceRecommendationAssessment(
                recommendation: nil,
                issues: WeatherDataIssue.deduplicated(issues)
            )
        }

        let sunnyHoursData: SunnyHoursCalculation.SunnyHoursData
        switch SunnyHoursCalculation.sunnyHoursData(
            for: forecast,
            timeZone: cityWeather.timeZone
        ) {
        case .success(let data):
            sunnyHoursData = data
        case .failure(let issue):
            issues.append(issue)
            return PlaceRecommendationAssessment(
                recommendation: nil,
                issues: WeatherDataIssue.deduplicated(issues)
            )
        }

        let maximumFeelsLike = strictMaximum(
            in: forecast,
            keyPath: \.apparentTemperature
        )
        let maximumVisibility = strictMaximum(
            in: forecast,
            keyPath: \.visibilityKilometers
        )
        if maximumFeelsLike == nil {
            issues.append(
                .missing(
                    .missingApparentTemperatureData,
                    at: forecast.hourlyForecasts.first(where: {
                        $0.apparentTemperature == nil
                    })?.date ?? forecast.date
                )
            )
        }
        if maximumVisibility == nil {
            issues.append(
                .missing(
                    .missingVisibilityData,
                    at: forecast.hourlyForecasts.first(where: {
                        $0.visibilityKilometers == nil
                    })?.date ?? forecast.date
                )
            )
        }

        return PlaceRecommendationAssessment(
            recommendation: PlaceRecommendation(
                cityWeather: cityWeather,
                forecast: forecast,
                condition: condition,
                cloudCover: forecast.cloudCover,
                precipitationChance: forecast.precipitationChance,
                sunnyHourCount: SunnyHoursCalculation.sunnyHourCount(
                    in: sunnyHoursData
                ),
                bestSunnyWindow: SunnyHoursCalculation.longestSunnyHourRange(
                    in: sunnyHoursData.hours,
                    timeZone: cityWeather.timeZone
                ),
                maximumFeelsLike: maximumFeelsLike,
                maximumVisibilityKilometers: maximumVisibility
            ),
            issues: WeatherDataIssue.deduplicated(issues)
        )
    }

    static func ranked(
        _ recommendations: [PlaceRecommendation],
        locale: Locale = .current
    ) -> [PlaceRecommendation] {
        recommendations.sorted {
            comesBefore($0, $1, locale: locale)
        }
    }

    static func savedPlacesBySunnyHours(
        _ savedPlaces: [SavedPlace],
        recommendations: [PlaceRecommendation],
        locale: Locale
    ) -> [SavedPlace] {
        let sunnyHoursByID = Dictionary(
            uniqueKeysWithValues: recommendations.map {
                ($0.id, $0.sunnyHourCount)
            }
        )
        return savedPlaces
            .filter { sunnyHoursByID[$0.id] != nil }
            .sorted { lhs, rhs in
                let leftHours = sunnyHoursByID[lhs.id] ?? -Double.infinity
                let rightHours = sunnyHoursByID[rhs.id] ?? -Double.infinity
                if leftHours != rightHours { return leftHours > rightHours }
                let order = lhs.displayName.compare(
                    rhs.displayName,
                    options: [.caseInsensitive, .diacriticInsensitive, .numeric],
                    locale: locale
                )
                if order != .orderedSame { return order == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private static func strictMaximum(
        in forecast: DailyForecast,
        keyPath: KeyPath<HourlyForecast, Double?>
    ) -> Double? {
        guard !forecast.hourlyForecasts.isEmpty,
              forecast.hourlyForecasts.allSatisfy({ $0[keyPath: keyPath] != nil }) else {
            return nil
        }
        return forecast.hourlyForecasts.compactMap { $0[keyPath: keyPath] }.max()
    }

    private static func comesBefore(
        _ lhs: PlaceRecommendation,
        _ rhs: PlaceRecommendation,
        locale: Locale
    ) -> Bool {
        if lhs.sunnyHourCount != rhs.sunnyHourCount {
            return lhs.sunnyHourCount > rhs.sunnyHourCount
        }
        let order = lhs.cityWeather.city.displayName.compare(
            rhs.cityWeather.city.displayName,
            options: [.caseInsensitive, .diacriticInsensitive, .numeric],
            locale: locale
        )
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
