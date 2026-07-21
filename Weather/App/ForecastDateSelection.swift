//
//  ForecastDateSelection.swift
//  Weather
//
//  Purpose: Owns forecast-date availability, date-switcher navigation, and
//  normalization shared by Home, List, Map, and Detail destinations.
//

import Foundation

// MARK: - Date Switcher Selection

extension ContentView {
    var dateSwitcherText: String {
        dateSwitcherText(for: dateSwitcherSelectedForecastDate)
    }

    var forecastDateToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    var dateSwitcherSelectedForecastDate: Date {
        get { selectedForecastDate }
        nonmutating set { selectedForecastDate = newValue }
    }

    /// The toolbar follows one city's real forecast range while its detail is
    /// open. Home, List, and Map retain the union across the active list.
    var dateSwitcherForecastSourceCities: [CityWeather] {
        detailDateSwitcherCity.map { [$0] } ?? forecastDateSourceCities
    }

    var dateSwitcherAvailableForecastDates: [Date] {
        availableForecastDates(for: dateSwitcherForecastSourceCities)
    }

    var dateSwitcherPreviousForecastDate: Date? {
        dateSwitcherAvailableForecastDates.last { $0 < dateSwitcherSelectedForecastDate }
    }

    var dateSwitcherNextForecastDate: Date? {
        dateSwitcherAvailableForecastDates.first { $0 > dateSwitcherSelectedForecastDate }
    }

    var dateSwitcherForecastDateRange: ClosedRange<Date>? {
        guard let firstDate = dateSwitcherAvailableForecastDates.first,
              let lastDate = dateSwitcherAvailableForecastDates.last else {
            return nil
        }
        return firstDate...lastDate
    }

    // MARK: Forecast-Date Availability

    /// Cities that define the app-wide date switcher. A temporary search result
    /// does not expand or contract the active list's forecast range.
    var forecastDateSourceCities: [CityWeather] {
        weatherService.cityWeatherData
    }

    var availableForecastDates: [Date] {
        availableForecastDates(for: forecastDateSourceCities)
    }

    func availableForecastDates(for cities: [CityWeather]) -> [Date] {
        Array(Set(cities.flatMap { cityWeather in
            cityWeather.dailyForecasts.compactMap { forecast in
                cityWeather.selectionDate(for: forecast)
            }
        })).sorted()
    }

    var previousForecastDate: Date? {
        availableForecastDates.last { $0 < selectedForecastDate }
    }

    var nextForecastDate: Date? {
        availableForecastDates.first { $0 > selectedForecastDate }
    }

    // MARK: Normalization

    func normalizeSelectedForecastDate() {
        selectedForecastDate = Calendar.current.startOfDay(for: selectedForecastDate)
    }

    func resetSelectedForecastDateToToday() {
        selectedForecastDate = forecastDateToday
    }
}
