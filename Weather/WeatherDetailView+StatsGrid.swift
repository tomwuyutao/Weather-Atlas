//
//  WeatherDetailView+StatsGrid.swift
//  Weather
//
//  Extracted from WeatherDetailView.swift
//

import SwiftUI

extension WeatherDetailView {

    // MARK: - Stats Grid

    var statsGrid: some View {
        let feelsLikeValue: String? = (forecast.feelsLikeLow != nil && forecast.feelsLikeHigh != nil)
            ? tempUnit.displaySlash(low: forecast.feelsLikeLow!, high: forecast.feelsLikeHigh!)
            : nil

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
            WeatherStatCard(
                label: "Temperature",
                value: isNow
                    ? tempUnit.display(cityWeather.temperature)
                    : tempUnit.displaySlash(low: forecast.dailyLow, high: forecast.dailyHigh),
                valueOffset: 3
            )

            if isNow {
                if let fl = cityWeather.currentFeelsLike {
                    WeatherStatCard(
                        label: "Feels Like",
                        value: tempUnit.display(fl),
                        valueOffset: 3
                    )
                }
            } else if let feelsLike = feelsLikeValue {
                WeatherStatCard(
                    label: "Feels Like",
                    value: feelsLike,
                    valueOffset: 3
                )
            }

            WeatherStatCard(
                label: "Cloud Cover",
                value: (isNow ? cityWeather.currentCloudCover : forecast.cloudCover).map { "\(Int($0 * 100))%" } ?? "—"
            )

            WeatherStatCard(
                label: "Precipitation",
                value: isNow
                    ? ([.rain, .drizzle, .snow].contains(cityWeather.condition) ? "100%" : "0%")
                    : (forecast.precipitationChance.map { "\(Int($0 * 100))%" } ?? "—")
            )

            WeatherStatCard(
                label: "Wind Speed",
                value: (isNow ? cityWeather.currentWindSpeed : forecast.windSpeed).map { "\(Int($0)) km/h" } ?? "—"
            )

            WeatherStatCard(
                label: "UV Index",
                value: (isNow ? cityWeather.currentUVIndex : forecast.uvIndex).map { "\($0)" } ?? "—"
            )

            WeatherStatCard(
                label: "Humidity",
                value: (isNow ? cityWeather.currentHumidity : forecast.maxHumidity).map { "\(Int($0 * 100))%" } ?? "—"
            )

            WeatherStatCard(
                label: "Visibility",
                value: (isNow ? cityWeather.currentVisibility : forecast.maxVisibility).map { distUnit.display($0) } ?? "—"
            )
        }
        .padding(.horizontal, 8)
    }
}
