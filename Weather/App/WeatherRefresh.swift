//
//  WeatherRefresh.swift
//  Weather
//
//  Purpose: Coordinates manual refreshes, refresh-age labels, and targeted
//  refetches for cities whose daytime hourly data is incomplete.
//

import SwiftUI

// MARK: - Refresh Status

extension ContentView {
    func timeSinceRefreshText() -> String {
        guard let lastFetch = weatherService.lastFetchDate else {
            return ""
        }
        let elapsed = Date().timeIntervalSince(lastFetch)
        let minutes = Int(elapsed / 60)
        if minutes < 1 {
            return localizedString("Now", locale: locale)
        } else if minutes < 60 {
            return "\(minutes) m"
        } else {
            let hours = minutes / 60
            return "\(hours) h"
        }
    }

    // MARK: Manual Refresh

    func refreshWeather() {
        dismissMapSelectionForRefresh()
        daytimeScoreRefetchKeys.removeAll()
        Task {
            await weatherService.refreshWeather()
            if !mapCities.isEmpty {
                centerMapOnDots(useListCoordinates: true)
            }
        }
    }

    private func dismissMapSelectionForRefresh() {
        guard showingMapExpandedCard || selectedMapCity != nil else { return }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingMapExpandedCard = false
            selectedMapCity = nil
            citySearchState.temporaryMapCity = nil
        }
    }

    // MARK: Missing Daytime Data

    func scheduleDaytimeSunninessRefetch() {
        Task {
            await refreshCitiesMissingDaytimeSunninessData()
        }
    }

    func refreshCitiesMissingDaytimeSunninessData() async {
        let selectedDate = selectedForecastDate
        let citiesToRefresh = mapCities.filter { cityWeather in
            // A shorter per-city WeatherKit forecast horizon is expected and
            // cannot be repaired by repeatedly fetching the same city.
            guard let forecast = cityWeather.forecastIfAvailable(on: selectedDate) else {
                return false
            }
            return !SunninessScoring.hasDaytimeHourlyScoreData(
                for: forecast,
                timeZone: cityWeather.timeZone
            )
        }

        for cityWeather in citiesToRefresh {
            let refetchKey = "\(cityWeather.id.uuidString)-\(selectedDate.timeIntervalSinceReferenceDate)"
            guard !daytimeScoreRefetchKeys.contains(refetchKey) else { continue }
            daytimeScoreRefetchKeys.insert(refetchKey)
            _ = await weatherService.refreshWeatherForCity(cityWeather)
        }
    }
}
