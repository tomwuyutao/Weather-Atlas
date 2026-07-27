//
//  MapFloatingCard.swift
//  Weather
//
//  Purpose: Renders and positions the compact weather card shown from map markers.
//

import SwiftUI
import UIKit

/// Fully formatted primary metric displayed by a selected map city card.
private struct MapFloatingCardMetric {
    /// Localized main value.
    let value: String
    /// Localized metric description.
    let label: String
    /// Optional semantic SF Symbol accompanying the value.
    let iconName: String?
}

extension ContentView {

    // MARK: - Floating Card Content

    @ViewBuilder
    /// Builds compact, omission-notice, or empty content for a selected map city.
    func mapFloatingCard(for cityWeather: CityWeather) -> some View {
        let cardForecastDate = selectedForecastDate
        if let forecast = cityWeather.forecastIfAvailable(on: cardForecastDate) {
            let tempUnit = TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic
            let issue = mapWeatherDataIssue(
                forecast: forecast,
                cityWeather: cityWeather,
                overlayMode: mapOverlayMode
            )
            let metric = mapFloatingCardMetric(
                for: cityWeather,
                forecast: forecast,
                tempUnit: tempUnit
            )

            if issue == nil, let metric {
                Button {
                    presentDetail(for: cityWeather)
                } label: {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.value)
                                .font(.system(size: 32, weight: .semibold, design: .default))
                                .foregroundStyle(theme.colors.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.74)

                            Text("\(localizedCityName(for: cityWeather.city)) · \(metric.label)")
                                .font(.headline.weight(.regular))
                                .foregroundStyle(theme.colors.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .padding(.top, 5)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)

                        Spacer(minLength: 8)

                        if let iconName = metric.iconName {
                            // Keep the current weather condition visible for every metric.
                            Image(systemName: iconName)
                                .font(.system(size: 40, weight: .medium))
                                .weatherIconStyle(for: iconName)
                                .frame(width: 56, height: 48, alignment: .center)
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .frame(height: floatingMapCardHeight)
                    .themedGlass(in: .rect(cornerRadius: 24))
                    .contentShape(RoundedRectangle(cornerRadius: 24))
                }
                .buttonStyle(.plain)
            }
        } else {
            if isExpectedForecastBoundaryOmission(
                for: cityWeather,
                among: mapCities,
                on: cardForecastDate
            ) {
                // ForecastOmissionNotice owns the shared Liquid Glass surface;
                // avoid wrapping it in a second glass card on the map.
                ForecastOmissionNotice(droppedCityCount: 1)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: floatingMapCardHeight)
            } else {
                EmptyView()
            }
        }
    }

    /// Compact card height adapted to supported Dynamic Type categories.
    var floatingMapCardHeight: CGFloat {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium, .large:
            return 128
        case .xLarge:
            return 138
        default:
            return 150
        }
    }

    /// Formats the selected overlay's source value without synthesizing data.
    private func mapFloatingCardMetric(
        for cityWeather: CityWeather,
        forecast: DailyForecast,
        tempUnit: TemperatureUnit
    ) -> MapFloatingCardMetric? {
        // The card icon always describes weather, independent of the active metric.
        let icon = forecast.weatherIcon
        switch mapOverlayMode {
        case "temperature":
            return MapFloatingCardMetric(
                value: tempUnit.display(forecast.dailyHigh),
                label: localizedString("Max Temperature", locale: locale),
                iconName: icon
            )
        case "cloudCover":
            guard let cloudCover = forecast.cloudCover else { return nil }
            return MapFloatingCardMetric(
                value: "\(Int((cloudCover * 100).rounded()))%",
                label: localizedString("Cloud Cover", locale: locale),
                iconName: icon
            )
        case "precipitation":
            guard let precipitationChance = forecast.precipitationChance else { return nil }
            return MapFloatingCardMetric(
                value: "\(Int((precipitationChance * 100).rounded()))%",
                label: localizedString("Rain Chance", locale: locale),
                iconName: icon
            )
        case "uvIndex":
            guard let uvIndex = forecast.uvIndex else { return nil }
            return MapFloatingCardMetric(
                value: String(uvIndex),
                label: localizedString("UV Index", locale: locale),
                iconName: icon
            )
        default:
            guard case .success(let data) = SunninessScoring.sunnyHoursData(
                for: forecast,
                timeZone: cityWeather.timeZone
            ) else {
                return nil
            }
            return MapFloatingCardMetric(
                value: mapSunnyHoursSummary(for: cityWeather, data: data),
                label: localizedString("Sunny Hours", locale: locale),
                iconName: icon
            )
        }
    }

    /// Returns localized favorable-hour copy or the precise source data issue.
    private func mapSunnyHoursSummary(
        for city: CityWeather,
        data: SunninessScoring.SunnyHoursData
    ) -> String {
        guard let range = SunninessScoring.longestSunnyHourRange(
            in: data.hours,
            timeZone: city.timeZone
        ) else {
            return localizedString("No Sun", locale: locale)
        }

        let start = SunninessScoring.compactHourLabel(range.lowerBound, locale: locale)
        let end = SunninessScoring.compactHourLabel(range.upperBound + 1, locale: locale)
        return "\(start) - \(end)"
    }

}

extension ContentView {
    /// Positions selected-city card content and its dismiss action over the map.
    var floatingMapCardOverlay: some View {
        // Native bottom-bar geometry needs slightly different card clearance.
        let cardPadding: (horizontal: CGFloat, bottom: CGFloat)
        if #available(iOS 26.0, *) {
            cardPadding = (18, 24)
        } else {
            cardPadding = (14, 22)
        }

        return Group {
            if isMapRoute, isMapCardPresented {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 120)
                        .allowsHitTesting(false)

                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissMapCard()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                    .zIndex(10)
            }

            if isMapRoute, isMapCardPresented, let city = selectedMapCity {
                ZStack(alignment: .topTrailing) {
                    mapFloatingCard(for: city)

                    Button {
                        dismissMapCard()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.colors.secondaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(-8)
                    .padding(.top, 4)
                    .padding(.trailing, 4)
                }
                .id(city.city.id)
                .padding(.horizontal, cardPadding.horizontal)
                // Keep iPad's selected-city card at the phone's visual width.
                .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 390 : 580)
                .padding(.bottom, cardPadding.bottom)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.4, anchor: .bottom).combined(with: .opacity).combined(with: .offset(y: 20)),
                        removal: .scale(scale: 0.4, anchor: .bottom).combined(with: .opacity).combined(with: .offset(y: 20))
                    )
                )
                .zIndex(12)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isMapCardPresented)
    }
}
