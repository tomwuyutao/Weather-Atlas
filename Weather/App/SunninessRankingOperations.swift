//
//  SunninessRankingOperations.swift
//  Weather
//
//  Purpose: Builds, sorts, groups, and validates ranked cities for app screens.
//

import Foundation

// MARK: - Candidate Construction and Sorting

extension ContentView {
    var selectedListSortMode: WeatherListSortMode {
        WeatherListSortMode(rawValue: listSortMode) ?? .sunny
    }

    func sunnyCandidate(for cityWeather: CityWeather) -> SunnyCandidate? {
        sunnyCandidate(for: cityWeather, on: selectedForecastDate)
    }

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

    var sunnyCandidates: [SunnyCandidate] {
        sunnyCandidates(for: mapCities)
    }

    func sunnyCandidates(for cities: [CityWeather]) -> [SunnyCandidate] {
        cities
            .compactMap(sunnyCandidate(for:))
            .sorted(by: isBetterSunnyCandidate)
    }

    var sortedListCandidates: [SunnyCandidate] {
        sortedCandidates(for: mapCities)
    }

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

    /// Clear-sky cities come first, and each weather group is ordered by lower
    /// cloud cover with localized city name as the stable tie-breaker.
    var sunninessCandidateGroups: [SunninessCandidateGroup] {
        sunninessCandidateGroups(from: mapCities.compactMap(sunnyCandidate(for:)))
    }

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

    private func isBetterSunnyCandidate(_ lhs: SunnyCandidate, than rhs: SunnyCandidate) -> Bool {
        if lhs.condition.sunninessRank != rhs.condition.sunninessRank {
            return lhs.condition.sunninessRank < rhs.condition.sunninessRank
        }

        if lhs.cloudCover != rhs.cloudCover {
            return lhs.cloudCover < rhs.cloudCover
        }
        return localizedCityName(for: lhs.cityWeather.city)
            .localizedStandardCompare(localizedCityName(for: rhs.cityWeather.city)) == .orderedAscending
    }

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
        let configuredCityOmissions = missingConfiguredCityCount(comparedTo: cities)
        return loadedCityOmissions + configuredCityOmissions
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
