//
//  PlaceRecommendationRow.swift
//  Weather
//
//  Purpose: Presents a ranked place with native typography, SF Symbols, and
//  accessibility semantics shared by Home, Places, and map previews.
//

import SwiftUI

/// Compact, image-free summary for one ranked place and selected date.
struct PlaceRecommendationRow: View {
    /// Complete explainable ranking value.
    let recommendation: PlaceRecommendation
    /// Optional saved-place label, preserving canonical weather metadata.
    var displayName: String?

    /// App-selected language used for place and hour formatting.
    @Environment(\.locale) private var locale
    /// Accessibility categories use a vertical layout instead of truncating
    /// weather and place context into the compact row geometry.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Persisted temperature preference shared by every forecast surface.
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic
    }

    private var cityName: String {
        displayName ?? recommendation.cityWeather.city.localizedName(locale: locale)
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                compactLayout
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var compactLayout: some View {
        HStack(alignment: .center, spacing: 14) {
            conditionIcon

            VStack(alignment: .leading, spacing: 4) {
                placeIdentity
                recommendationReason
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(temperatureUnit.display(recommendation.forecast.dailyHigh))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()

                Text(recommendation.condition.localizedDisplayName(locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                conditionIcon
                placeIdentity
            }

            recommendationReason
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(recommendation.condition.localizedDisplayName(locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text(temperatureUnit.display(recommendation.forecast.dailyHigh))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
        }
    }

    private var conditionIcon: some View {
        Image(systemName: recommendation.condition.displayIcon)
            .font(.title2)
            .weatherIconStyle(for: recommendation.condition.displayIcon)
            .frame(minWidth: 32, minHeight: 32)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var placeIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(cityName)
                .font(.headline)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

            if !recommendation.cityWeather.city.country.isEmpty {
                Text(recommendation.cityWeather.city.country)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
        }
    }

    /// Explains the useful differentiator instead of exposing an opaque score.
    private var recommendationReason: some View {
        Label(recommendationReasonText, systemImage: recommendationReasonIcon)
    }

    private func sunnyWindowLabel(_ range: ClosedRange<Int>) -> String {
        let start = SunninessScoring.compactHourLabel(range.lowerBound, locale: locale)
        let end = SunninessScoring.compactHourLabel(range.upperBound + 1, locale: locale)
        return localizedString("\(start)–\(end) sunny window", locale: locale)
    }

    private var recommendationReasonText: String {
        if let bestSunnyWindow = recommendation.bestSunnyWindow {
            return sunnyWindowLabel(bestSunnyWindow)
        }
        if recommendation.sunnyHourCount > 0 {
            return localizedString(
                "\(recommendation.sunnyHourCount) sunny hours",
                locale: locale
            )
        }
        if let rainChance = recommendation.precipitationChance {
            let percentage = Int((rainChance * 100).rounded())
            return localizedString(
                "\(percentage)% chance of rain",
                locale: locale
            )
        }
        let percentage = Int((recommendation.cloudCover * 100).rounded())
        return localizedString(
            "\(percentage)% cloud cover",
            locale: locale
        )
    }

    private var recommendationReasonIcon: String {
        if recommendation.bestSunnyWindow != nil {
            return "clock"
        }
        if recommendation.sunnyHourCount > 0 {
            return "sun.max"
        }
        if recommendation.precipitationChance != nil {
            return "drop"
        }
        return "cloud"
    }

    private var accessibilitySummary: String {
        var parts = [
            cityName,
        ]
        if !recommendation.cityWeather.city.country.isEmpty {
            parts.append(recommendation.cityWeather.city.country)
        }
        parts.append(contentsOf: [
            recommendation.condition.localizedDisplayName(locale: locale),
            temperatureUnit.display(recommendation.forecast.dailyHigh),
            recommendationReasonText
        ])
        return parts.joined(separator: ", ")
    }
}

/// Native placeholder that preserves row geometry during forecast loading.
struct PlaceWeatherLoadingRow: View {
    var body: some View {
        HStack(spacing: 14) {
            ProgressView()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 5) {
                Text("Loading forecast…")
                    .font(.headline)
                Text("Comparing sunny conditions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
