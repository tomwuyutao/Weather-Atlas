//
//  SunninessRanking.swift
//  Weather
//
//  Purpose: Defines ranked city-weather values and the shared construction,
//  sorting, grouping, and validation operations used by app screens.
//

import Foundation

// MARK: - Sort Mode

/// User-selectable ordering applied to city lists and ranking surfaces.
enum WeatherListSortMode: String, CaseIterable, Identifiable {
    case sunny
    case temperature
    case cloud

    /// Stable identity used by SwiftUI selection controls.
    var id: String { rawValue }

    /// SF Symbol representing the ordering rule.
    var icon: String {
        switch self {
        case .temperature: return "thermometer.medium"
        case .cloud: return "cloud"
        case .sunny: return "sun.max.fill"
        }
    }

    /// Localized menu title for the ordering rule.
    func title(locale: Locale) -> String {
        switch self {
        case .temperature: return localizedString("Temperature", locale: locale)
        case .cloud: return localizedString("Cloud Cover", locale: locale)
        case .sunny: return localizedString("Sunniness", locale: locale)
        }
    }
}

// MARK: - Ranked Values

/// Complete, comparable weather inputs for one ranked city and date.
struct SunnyCandidate: Identifiable {
    /// Source city and its full forecast collection.
    let cityWeather: CityWeather
    /// Normalized condition used as the primary sunniness rank.
    let condition: AppWeatherCondition
    /// WeatherKit cloud fraction used for rank refinement.
    let cloudCover: Double
    /// Optional precipitation probability shown when the source supplies it.
    let precipitationChance: Double?
    /// Daily high displayed alongside the ranking.
    let temperature: Double

    /// Reuses city-weather identity so rows remain stable across sorting.
    var id: UUID { cityWeather.id }
}

/// Display section grouping candidates with similar weather conditions.
struct SunninessCandidateGroup: Identifiable {
    /// Localized section heading.
    let title: String
    /// SF Symbol representing the group's conditions.
    let icon: String
    /// Ordered candidates belonging to the section.
    let candidates: [SunnyCandidate]

    /// Uses the unique localized heading as the transient section identity.
    var id: String { title }
}

// MARK: - Candidate Construction and Sorting

extension ContentView {
    /// Validated list-ordering preference used by all ranked city surfaces.
    var selectedListSortMode: WeatherListSortMode {
        WeatherListSortMode(rawValue: listSortMode) ?? .sunny
    }

    /// Builds a candidate for the shared selected date when all inputs exist.
    func sunnyCandidate(for cityWeather: CityWeather) -> SunnyCandidate? {
        sunnyCandidate(for: cityWeather, on: selectedForecastDate)
    }

    /// Converts one city's forecast into a comparable ranking value.
    func sunnyCandidate(for cityWeather: CityWeather, on forecastDate: Date) -> SunnyCandidate? {
        guard let forecast = cityWeather.forecastIfAvailable(on: forecastDate) else {
            return nil
        }
        guard let condition = SunninessScoring.condition(for: forecast.symbolName),
              let cloudCover = forecast.cloudCover else {
            return nil
        }

        return SunnyCandidate(
            cityWeather: cityWeather,
            condition: condition,
            cloudCover: cloudCover,
            precipitationChance: forecast.precipitationChance,
            temperature: forecast.dailyHigh
        )
    }

    /// Valid ranking candidates from the active list on the selected date.
    var sunnyCandidates: [SunnyCandidate] {
        sunnyCandidates(for: mapCities)
    }

    /// Drops incomplete city data and returns candidates for a supplied collection.
    func sunnyCandidates(for cities: [CityWeather]) -> [SunnyCandidate] {
        cities
            .compactMap(sunnyCandidate(for:))
            // Compare condition rank, cloud cover, then localized name for stability.
            .sorted {
                if $0.condition.sunninessRank != $1.condition.sunninessRank {
                    return $0.condition.sunninessRank < $1.condition.sunninessRank
                }
                if $0.cloudCover != $1.cloudCover {
                    return $0.cloudCover < $1.cloudCover
                }
                return localizedCityName(for: $0.cityWeather.city)
                    .localizedStandardCompare(localizedCityName(for: $1.cityWeather.city)) == .orderedAscending
            }
    }

    /// Active-list candidates ordered by the user's current sort mode.
    var sortedListCandidates: [SunnyCandidate] {
        sortedCandidates(for: mapCities)
    }

    /// Orders candidate cities by sunniness or localized city name.
    func sortedCandidates(for cities: [CityWeather]) -> [SunnyCandidate] {
        let candidates = cities.compactMap(sunnyCandidate(for:))
        switch selectedListSortMode {
        case .temperature:
            return candidates.sorted { $0.temperature > $1.temperature }
        case .cloud:
            return candidates.sorted { lhs, rhs in
                if lhs.cloudCover != rhs.cloudCover {
                    return lhs.cloudCover < rhs.cloudCover
                }
                return localizedCityName(for: lhs.cityWeather.city)
                    .localizedStandardCompare(localizedCityName(for: rhs.cityWeather.city)) == .orderedAscending
            }
        case .sunny:
            return sunninessCandidateGroups(from: candidates).flatMap(\.candidates)
        }
    }

    /// Condition groups shown by List View's grouped sunny ordering.
    var sunninessCandidateGroups: [SunninessCandidateGroup] {
        sunninessCandidateGroups(from: mapCities.compactMap(sunnyCandidate(for:)))
    }

    /// Partitions candidates into display groups while preserving rank order.
    func sunninessCandidateGroups(from candidates: [SunnyCandidate]) -> [SunninessCandidateGroup] {
        let sunny = candidates.filter { $0.condition == .clear }.sorted(by: isLowerCloudCover)
        let partlySunny = candidates.filter { $0.condition == .partlySunny }.sorted(by: isLowerCloudCover)
        let remaining = candidates.filter {
            $0.condition != .clear
                && $0.condition != .partlySunny
                && $0.condition != .drizzle
                && $0.condition != .rain
        }
        .sorted(by: isLowerCloudCover)
        let rainy = candidates.filter { $0.condition == .drizzle || $0.condition == .rain }
            .sorted(by: isLowerCloudCover)

        return [
            SunninessCandidateGroup(
                title: localizedString("Sunny", locale: locale),
                icon: "sun.max.fill",
                candidates: sunny
            ),
            SunninessCandidateGroup(
                title: localizedString("Partly Sunny", locale: locale),
                icon: WeatherIconSymbol.partlyCloudy,
                candidates: partlySunny
            ),
            SunninessCandidateGroup(
                title: localizedString("Cloudy, Windy, Snowy, Foggy", locale: locale),
                icon: "cloud",
                candidates: remaining
            ),
            SunninessCandidateGroup(
                title: localizedString("Drizzle, Rain", locale: locale),
                icon: "cloud.rain",
                candidates: rainy
            )
        ].filter { !$0.candidates.isEmpty }
    }

    /// Orders a condition group by cloud cover with localized-name tie-breaking.
    private func isLowerCloudCover(_ lhs: SunnyCandidate, _ rhs: SunnyCandidate) -> Bool {
        if lhs.cloudCover != rhs.cloudCover {
            return lhs.cloudCover < rhs.cloudCover
        }
        return localizedCityName(for: lhs.cityWeather.city)
            .localizedStandardCompare(localizedCityName(for: rhs.cityWeather.city)) == .orderedAscending
    }
}

// MARK: - Ranking Input Validation

extension ContentView {
    /// Expected list-boundary omissions are summarized by the compact notice.
    func expectedForecastBoundaryOmissionCount(in cities: [CityWeather]) -> Int {
        cities.filter {
            isExpectedForecastBoundaryOmission(
                for: $0,
                among: cities,
                on: selectedForecastDate
            )
        }.count
    }

    /// Ranking rows require a forecast, a recognized condition, and cloud cover.
    /// Any city missing one of those inputs is omitted and included in the compact
    /// dropped-city notice; no replacement value is synthesized.
    func rankingOmissionCount(in cities: [CityWeather]) -> Int {
        let loadedCityOmissions = cities.filter {
            rankingDataIssue(for: $0, on: selectedForecastDate) != nil
        }.count
        return loadedCityOmissions + missingConfiguredCityCount(comparedTo: cities)
    }

    /// A city that failed before producing `CityWeather` still belongs to the
    /// configured list, so include it in the dropped-city count.
    func missingConfiguredCityCount(comparedTo loadedCities: [CityWeather]) -> Int {
        // Onboarding intentionally delays the first fetch until the user chooses
        // a list. Do not misreport that expected empty state as missing weather.
        guard !weatherService.isLoading,
              hasCompletedInitialWeatherLoad,
              !tutorialState.showsFirstLaunch,
              !tutorialState.showsReplay else { return 0 }
        return weatherService.cityListCoordinates(for: weatherService.activeListID)
            .filter { configuredCity in
                !loadedCities.contains { loadedCity in
                    weatherService.citiesMatch(loadedCity.city, configuredCity)
                }
            }
            .count
    }

    /// Ranking and list rows require all three inputs. A city with incomplete
    /// source data is omitted from the ranking and named in the visible notice.
    func rankingDataIssue(for cityWeather: CityWeather, on date: Date) -> WeatherDataIssue? {
        guard let forecast = cityWeather.forecastIfAvailable(on: date) else {
            return .missingForecastData
        }
        guard SunninessScoring.condition(for: forecast.symbolName) != nil else {
            return .unknownWeatherSymbol(forecast.symbolName)
        }
        guard forecast.cloudCover != nil else {
            return .missingCloudCoverData
        }
        return nil
    }
}
