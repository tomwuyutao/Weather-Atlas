//
//  WeatherDetailView+StatsGrid.swift
//  Weather
//
//  Extracted from WeatherDetailView.swift
//

import SwiftUI

extension WeatherDetailView {

    // MARK: - Stats List

    var statsGrid: some View {
        let rows: [(String, String, String)] = [
            (
                "thermometer.medium",
                localizedString("Temperature", locale: locale),
                isNow
                    ? tempUnit.display(cityWeather.temperature)
                    : tempUnit.displaySlash(low: forecast.dailyLow, high: forecast.dailyHigh)
            ),
            (
                "thermometer.variable.and.figure",
                localizedString("Feels Like", locale: locale),
                isNow
                    ? (cityWeather.currentFeelsLike.map { tempUnit.display($0) } ?? "—")
                    : {
                        if let low = forecast.feelsLikeLow, let high = forecast.feelsLikeHigh {
                            return tempUnit.displaySlash(low: low, high: high)
                        }
                        return "—"
                    }()
            ),
            (
                "cloud",
                localizedString("Cloud Cover", locale: locale),
                (isNow ? cityWeather.currentCloudCover : forecast.cloudCover).map { "\(Int($0 * 100))%" } ?? "—"
            ),
            (
                "drop.fill",
                localizedString("Precipitation", locale: locale),
                isNow
                    ? ([.rain, .drizzle, .snow].contains(cityWeather.condition) ? "100%" : "0%")
                    : (forecast.precipitationChance.map { "\(Int($0 * 100))%" } ?? "—")
            ),
            (
                "wind",
                localizedString("Wind Speed", locale: locale),
                (isNow ? cityWeather.currentWindSpeed : forecast.windSpeed).map { distUnit.displayWindSpeed($0) } ?? "—"
            ),
            (
                "sun.max.fill",
                localizedString("UV Index", locale: locale),
                (isNow ? cityWeather.currentUVIndex : forecast.uvIndex).map { "\($0)" } ?? "—"
            ),
            (
                "humidity.fill",
                localizedString("Humidity", locale: locale),
                (isNow ? cityWeather.currentHumidity : forecast.maxHumidity).map { "\(Int($0 * 100))%" } ?? "—"
            ),
            (
                "eye",
                localizedString("Visibility", locale: locale),
                (isNow ? cityWeather.currentVisibility : forecast.maxVisibility).map { distUnit.display($0) } ?? "—"
            )
        ]

        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 10) {
                    Image(systemName: row.0)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)

                    Text(row.1)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Text(row.2)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                if index < rows.count - 1 {
                    Divider()
                        .opacity(0.18)
                        .padding(.leading, 40)
                }
            }
        }
        .background(AppTheme.shared.colors.listCardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 8)
    }
}
