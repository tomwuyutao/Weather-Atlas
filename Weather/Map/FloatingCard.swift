//
//  FloatingCard.swift
//  Weather
//
//  Purpose: Renders the floating weather card shown from map markers, including
//  compact card content, expanded charts, and card placement helpers.
//

import SwiftUI

extension ContentView {

    // MARK: - Expanded Card Content

    @ViewBuilder
    func mapExpandedCard(
        for cityWeather: CityWeather,
        forceExpandedStyle: Bool = false,
        hideCityName: Bool = false,
        plainBackground: Bool = false
    ) -> some View {
        let isNow = selectedDayOffset == -1
        let forecast = cityWeather.forecast(for: max(0, selectedDayOffset))
        let tempUnit = TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic
        let distUnit = DistanceUnit(rawValue: distanceUnitRaw) ?? .automatic
        let icon = isNow ? cityWeather.weatherIcon : forecast.weatherIcon
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

        if forceExpandedStyle {
            expandedWeatherCard(
                for: cityWeather,
                icon: icon,
                primaryText: isOverlayActive ? overlayLargeText : tempUnit.display(isNow ? cityWeather.temperature : forecast.dailyHigh),
                metricLabel: isOverlayActive ? overlayLabel : localizedString(isNow ? "Current Temperature" : "Highest Temperature", locale: locale),
                tempUnit: tempUnit,
                hideCityName: hideCityName,
                plainBackground: plainBackground
            )
        } else {
            let phoneCardSpacing: CGFloat = 16
            let phoneCardTemperatureSize: CGFloat = 38
            let phoneCardIconSize: CGFloat = 40
            let phoneCardIconFrame = CGSize(width: 56, height: 48)
            let phoneCardMetricFont = Font.caption.weight(.medium)
            let phoneCardTitleFont = Font.headline.weight(.semibold)
            let phoneCardSelectedDotSize: CGFloat = 8
            let phoneCardDotSize: CGFloat = 6

            HStack(alignment: .bottom, spacing: phoneCardSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isOverlayActive ? overlayLargeText : tempUnit.display(isNow ? cityWeather.temperature : forecast.dailyHigh))
                        .font(.system(size: phoneCardTemperatureSize, weight: .semibold, design: .default))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .lineLimit(1)

                    Text(isOverlayActive ? overlayLabel : localizedString(isNow ? "Current Temperature" : "Highest Temperature", locale: locale))
                        .font(phoneCardMetricFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.top, 4)

                    if !hideCityName {
                        Text(cityWeather.city.localizedName(locale: locale))
                            .font(phoneCardTitleFont)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .padding(.top, 5)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottomLeading)
                .animation(.smooth(duration: 0.4), value: mapOverlayMode)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 0) {
                    Image(systemName: icon)
                        .font(.system(size: phoneCardIconSize, weight: .medium))
                        .weatherIconStyle(for: icon)
                        .frame(width: phoneCardIconFrame.width, height: phoneCardIconFrame.height, alignment: .center)

                    Spacer(minLength: 8)

                    VStack(spacing: 4) {
                        ForEach(0..<2, id: \.self) { row in
                            HStack(spacing: 4) {
                                ForEach(0..<5, id: \.self) { column in
                                    let index = row * 5 + column
                                    if index < cityWeather.dailyForecasts.count {
                                        let dayForecast = cityWeather.dailyForecasts[index]
                                        let dayDotColor = dayForecast.weatherIcon.contains("moon") ? theme.colors.moonIconColor : dayForecast.condition.dotColor
                                        Circle()
                                            .fill(dayDotColor)
                                            .frame(width: index == selectedDayOffset ? phoneCardSelectedDotSize : phoneCardDotSize, height: index == selectedDayOffset ? phoneCardSelectedDotSize : phoneCardDotSize)
                                            .frame(width: phoneCardSelectedDotSize, height: phoneCardSelectedDotSize, alignment: .center)
                                            .shadow(color: dayDotColor.opacity(0.55), radius: 3)
                                            .opacity(index == selectedDayOffset ? 1 : 0.58)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 30, alignment: .bottom)
                    .offset(y: -1)
                }
                .frame(maxHeight: .infinity, alignment: .topTrailing)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .frame(height: floatingMapCardHeight)
            .themedGlass(in: .rect(cornerRadius: 24))
            .contentShape(RoundedRectangle(cornerRadius: 24))
            .onTapGesture {
                presentDetail(for: cityWeather)
            }
        }
    }

    var floatingMapCardHeight: CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return 178
        }

        switch dynamicTypeSize {
        case .xSmall, .small, .medium, .large:
            return 128
        case .xLarge:
            return 138
        case .xxLarge:
            return 150
        case .xxxLarge:
            return 162
        default:
            return 178
        }
    }
}

struct MapGlassCardContainer: ViewModifier {
    let cornerRadius: CGFloat
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                (colorScheme == .dark
                 ? Color(red: 0.08, green: 0.08, blue: 0.12).opacity(0.48)
                 : Color.white.opacity(0.62)),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 22, x: 0, y: 10)
    }
}

extension ContentView {
    var mainOverlays: some View {
        floatingMapCardOverlay
    }
    var floatingMapCardHorizontalPadding: CGFloat {
        if #available(iOS 26.0, *) {
            return 18
        } else {
            return 14
        }
    }

    var floatingMapCardBottomPadding: CGFloat {
        if #available(iOS 26.0, *) {
            return 58
        } else {
            return 48
        }
    }

    private var dateSliderDismissPassthroughWidth: CGFloat {
        160
    }

    private var floatingMapCardOverlay: some View {
        Group {
            if isMapRoute, showingMapExpandedCard {
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissMapExpandedCard()
                        }

                    Color.clear
                        .frame(width: dateSliderDismissPassthroughWidth)
                        .allowsHitTesting(false)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(10)
            }

            if isMapRoute, showingMapExpandedCard, let city = tappedCity {
                mapExpandedCard(for: city, hideCityName: shouldHideInlineMapCardCityName)
                    .id(city.city.id)
                    .padding(.horizontal, floatingMapCardHorizontalPadding)
                    .padding(.vertical, shouldAddInlineMapCardVerticalPadding ? 8 : 0)
                    .padding(.bottom, floatingMapCardBottomPadding)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.4, anchor: .bottom).combined(with: .opacity).combined(with: .offset(y: 20)),
                            removal: .scale(scale: 0.4, anchor: .bottom).combined(with: .opacity).combined(with: .offset(y: 20))
                        )
                    )
                    .zIndex(12)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showingMapExpandedCard)
    }
}
