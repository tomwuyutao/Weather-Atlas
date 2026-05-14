//
//  ContentView+MapExpandedCard.swift
//  Weather
//
//  Extracted from ContentView.swift
//

import SwiftUI

extension ContentView {

    // MARK: - Map Expanded Card

    func mapExpandedCard(for cityWeather: CityWeather) -> some View {
        let isNow = selectedDayOffset == -1
        let forecast = cityWeather.forecast(for: max(0, selectedDayOffset))
        let tempUnit = TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
        let distUnit = DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
        let baseCondition = isNow ? cityWeather.condition : forecast.condition
        let baseIcon = isNow ? cityWeather.weatherIcon : forecast.weatherIcon
        let icon: String = {
            switch baseCondition {
            case .rain, .drizzle, .snow: return "cloud.fill"
            default: return baseIcon
            }
        }()
        // Match effect condition to the displayed icon
        let effectCondition: AppWeatherCondition = {
            if icon == "cloud.fill" {
                switch baseCondition {
                case .rain: return .rain
                case .drizzle: return .drizzle
                case .snow: return .snow
                default: return .cloudy
                }
            }
            return baseCondition
        }()
        let isOverlayActive = !["weather", "temperature"].contains(mapOverlayMode)
        let overlayLargeText: String = {
            switch mapOverlayMode {
            case "cloudCover":
                if isNow {
                    guard let cc = cityWeather.currentCloudCover else { return "—" }
                    return "\(Int(cc * 100))%"
                }
                guard let cc = forecast.cloudCoverPercent else { return "—" }
                return "\(cc)%"
            case "precipitation":
                if isNow {
                    let isRaining = [.rain, .drizzle, .snow].contains(cityWeather.condition)
                    return isRaining ? "100%" : "0%"
                }
                guard let pc = forecast.precipitationChance else { return "—" }
                return "\(Int(pc * 100))%"
            case "windSpeed":
                if isNow {
                    guard let ws = cityWeather.currentWindSpeed else { return "—" }
                    return distUnit.displayWindSpeed(ws)
                }
                guard let ws = forecast.windSpeed else { return "—" }
                return distUnit.displayWindSpeed(ws)
            case "uvIndex":
                if isNow {
                    guard let uv = cityWeather.currentUVIndex else { return "—" }
                    return "\(uv)"
                }
                guard let uv = forecast.uvIndex else { return "—" }
                return "\(uv)"
            case "humidity":
                if isNow {
                    guard let hum = cityWeather.currentHumidity else { return "—" }
                    return "\(Int(hum * 100))%"
                }
                guard let hum = forecast.maxHumidity else { return "—" }
                return "\(Int(hum * 100))%"
            case "visibility":
                if isNow {
                    guard let km = cityWeather.currentVisibility else { return "—" }
                    return distUnit.display(km)
                }
                guard let km = forecast.maxVisibility else { return "—" }
                return distUnit.display(km)
            default: return ""
            }
        }()
        let overlayLabel: String = {
            switch mapOverlayMode {
            case "cloudCover": return "Cloud Cover"
            case "precipitation": return "Precipitation Chance"
            case "windSpeed": return "Wind Speed"
            case "uvIndex": return "UV Index"
            case "humidity": return "Humidity"
            case "visibility": return "Visibility"
            default: return ""
            }
        }()
        return HStack(alignment: .bottom, spacing: 0) {
            // Left: temperature, city, details
            VStack(alignment: .leading, spacing: 10) {
                // Large value: overlay data or temperature
                VStack(alignment: .leading, spacing: 4) {
                    Text(isOverlayActive ? overlayLargeText : tempUnit.display(isNow ? cityWeather.temperature : forecast.dailyHigh))
                        .font(.system(size: 42, weight: .medium, design: .default))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    Text(isOverlayActive ? overlayLabel : "Highest Temperature")
                        .font(.avenir(.subheadline, weight: .medium))
                        .foregroundStyle(.secondary)
                        .offset(x: 4, y: -4)
                }
                .offset(x: -4, y: -4)
                .animation(.smooth(duration: 0.4), value: mapOverlayMode)

                // City name
                Text(cityWeather.city.localizedName(locale: locale))
                    .font(.avenir(.body, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

            }

            Spacer()

            // Right: weather icon + 10-day dots
            VStack(spacing: 30) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .weatherIconStyle(for: icon)
                    .frame(width: 56, height: 48)
                    .background(alignment: .top) {
                        WeatherEffectOverlay(condition: effectCondition, isCompact: false, iconHeight: 48, iconName: icon)
                    }

                // 10-day forecast dots in 2 rows of 5
                VStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 6) {
                            ForEach(0..<5, id: \.self) { col in
                                let i = row * 5 + col
                                if i < cityWeather.dailyForecasts.count {
                                    let dayForecast = cityWeather.dailyForecasts[i]
                                    Circle()
                                        .fill(dayForecast.condition.dotColor)
                                        .frame(width: i == selectedDayOffset ? 8 : 6, height: i == selectedDayOffset ? 8 : 6)
                                        .shadow(color: dayForecast.condition.dotColor.opacity(0.6), radius: 3)
                                        .opacity(i == selectedDayOffset ? 1 : 0.6)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.trailing, 10)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.shared.isDetailedMapMode && colorScheme == .light
                    ? Color(hex: 0xF5F1EC)
                    : theme.colors.glassFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .fill(.white.opacity(0.08))
                .allowsHitTesting(false)
        }
        .onTapGesture {
            showingCityDetail = true
        }
    }
}
