//
//  FloatingCard.swift
//  Weather
//
//  Purpose: Renders the floating weather card shown from map markers, including
//  compact card content, expanded map-card content, and placement helpers.
//

import SwiftUI
import UIKit

private struct MapFloatingCardMetric {
    let value: String
    let label: String
    let iconName: String
}

extension ContentView {

    // MARK: - Expanded Card Content

    @ViewBuilder
    func mapExpandedCard(
        for cityWeather: CityWeather,
        forceExpandedStyle: Bool = false,
        hideCityName: Bool = false,
        plainBackground: Bool = false
    ) -> some View {
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

            if let issue {
                WeatherDataUnavailableNotice(
                    message: weatherDataIssueMessage(
                        issue,
                        cityName: localizedCityName(for: cityWeather.city),
                        locale: locale
                    )
                )
                .padding(16)
                .frame(maxWidth: .infinity)
                .frame(minHeight: floatingMapCardHeight)
                .themedGlass(in: .rect(cornerRadius: 24))
            } else if let metric, forceExpandedStyle {
                expandedFloatingWeatherCard(
                    for: cityWeather,
                    metric: metric,
                    tempUnit: tempUnit,
                    selectedDate: cardForecastDate,
                    hideCityName: hideCityName,
                    plainBackground: plainBackground
                )
            } else if let metric {
                let phoneCardSpacing: CGFloat = 16
                let phoneCardTemperatureSize: CGFloat = 32
                let phoneCardIconSize: CGFloat = 40
                let phoneCardIconFrame = CGSize(width: 56, height: 48)
                let phoneCardMetricFont = Font.caption.weight(.medium)
                let phoneCardTitleFont = Font.headline.weight(.semibold)

                Button {
                    presentDetail(for: cityWeather)
                } label: {
                    HStack(alignment: .center, spacing: phoneCardSpacing) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.value)
                                .font(.system(size: phoneCardTemperatureSize, weight: .semibold, design: .default))
                                .foregroundStyle(theme.colors.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.74)

                            Text(metric.label)
                                .font(phoneCardMetricFont)
                                .foregroundStyle(theme.colors.primaryText)
                                .lineLimit(1)
                                .padding(.top, 4)

                            if !hideCityName {
                                Text(localizedCityName(for: cityWeather.city))
                                    .font(phoneCardTitleFont)
                                    .foregroundStyle(theme.colors.primaryText)
                                    .lineLimit(1)
                                    .padding(.top, 5)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .center)

                        Spacer(minLength: 8)

                        floatingCardMetricIcon(metric, size: phoneCardIconSize)
                            .frame(width: phoneCardIconFrame.width, height: phoneCardIconFrame.height, alignment: .center)
                            .frame(maxHeight: .infinity, alignment: .center)
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
                WeatherDataUnavailableNotice(
                    message: weatherDataIssueMessage(
                        .missingForecastData,
                        cityName: localizedCityName(for: cityWeather.city),
                        locale: locale
                    )
                )
                .padding(16)
                .frame(maxWidth: .infinity)
                .frame(minHeight: floatingMapCardHeight)
                .themedGlass(in: .rect(cornerRadius: 24))
            }
        }
    }

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

    private func mapFloatingCardMetric(
        for cityWeather: CityWeather,
        forecast: DailyForecast,
        tempUnit: TemperatureUnit
    ) -> MapFloatingCardMetric? {
        guard let condition = SunninessScoring.condition(for: forecast.symbolName) else {
            return nil
        }
        let icon = condition.displayIcon
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
                value: percentageText(cloudCover),
                label: localizedString("Cloud Cover", locale: locale),
                iconName: icon
            )
        case "precipitation":
            guard let precipitationChance = forecast.precipitationChance else { return nil }
            return MapFloatingCardMetric(
                value: percentageText(precipitationChance),
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

    private func percentageText(_ value: Double) -> String {
        return "\(Int((value * 100).rounded()))%"
    }

}


// MARK: - Floating Card Icon Style

private func floatingCardMetricIcon(_ metric: MapFloatingCardMetric, size: CGFloat) -> some View {
    Image(systemName: metric.iconName)
        .font(.system(size: size, weight: .medium))
        .weatherIconStyle(for: metric.iconName)
}


// MARK: - Expanded Floating Card

extension ContentView {
    private func expandedFloatingWeatherCard(
        for cityWeather: CityWeather,
        metric: MapFloatingCardMetric,
        tempUnit: TemperatureUnit,
        selectedDate: Date,
        hideCityName: Bool = false,
        plainBackground: Bool = false
    ) -> some View {
        let forecasts = cityWeather.dailyForecasts.compactMap { forecast -> (forecast: DailyForecast, selectionDate: Date)? in
            guard let selectionDate = cityWeather.selectionDate(for: forecast) else {
                return nil
            }
            return (forecast, selectionDate)
        }
        let cornerRadius: CGFloat = 28

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .center, spacing: 6) {
                    if !hideCityName {
                        Text(localizedCityName(for: cityWeather.city))
                            .font(.title.weight(.semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)
                    }

                    Text(metric.label)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(theme.colors.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)

                HStack(alignment: .center, spacing: 2) {
                    Spacer(minLength: 0)

                    Text(metric.value)
                        .font(.system(size: 62, weight: .regular, design: .default))
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.48)
                        .id("primary-\(mapOverlayMode)-\(selectedDate.timeIntervalSinceReferenceDate)-\(metric.value)")
                        .transition(.scale(scale: 0.82).combined(with: .opacity))

                    floatingCardMetricIcon(metric, size: 44)
                        .symbolReplaceTransition()
                        .id("icon-\(mapOverlayMode)-\(selectedDate.timeIntervalSinceReferenceDate)-\(metric.iconName)")
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                        .frame(width: 60, height: 52)

                    Spacer(minLength: 0)
                }
                .padding(.bottom, 18)
                .animation(.snappy(duration: 0.28), value: selectedDate)

                VStack(spacing: 10) {
                    let rowCount = Int(ceil(Double(forecasts.count) / 5.0))
                    ForEach(0..<rowCount, id: \.self) { row in
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(0..<5, id: \.self) { column in
                                let index = row * 5 + column
                                if index < forecasts.count {
                                    expandedFloatingWeatherCardDayButton(
                                        forecast: forecasts[index].forecast,
                                        selectionDate: forecasts[index].selectionDate,
                                        selectedDate: selectedDate,
                                        cityWeather: cityWeather,
                                        tempUnit: tempUnit
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .animation(.snappy(duration: 0.24), value: selectedDate)
                .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: cornerRadius))
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 8)
            .modifier(MapExpandedCardContainer(plainBackground: plainBackground, colorScheme: colorScheme))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

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

    @ViewBuilder
    private func expandedFloatingWeatherCardDayButton(
        forecast: DailyForecast,
        selectionDate: Date,
        selectedDate: Date,
        cityWeather: CityWeather,
        tempUnit: TemperatureUnit
    ) -> some View {
        let isSelectedDay = Calendar.current.isDate(selectionDate, inSameDayAs: selectedDate)
        if let condition = SunninessScoring.condition(for: forecast.symbolName) {
            let dotColor = condition.dotColor(for: theme.colors)
            let temperature = forecast.dailyHigh

            Button {
                withAnimation(.snappy(duration: 0.24)) {
                    selectedForecastDate = selectionDate
                }
            } label: {
                VStack(spacing: 6) {
                    Text(floatingCardDayLabel(for: selectionDate))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)

                    // Symbols supplement color when Differentiate Without Color is on.
                    Group {
                        if differentiateWithoutColor {
                            Image(systemName: condition.displayIcon)
                                .font(.caption.weight(.semibold))
                                .weatherIconStyle(for: condition.displayIcon)
                        } else {
                            Circle()
                                .fill(dotColor)
                                .frame(width: isSelectedDay ? 11 : 10, height: isSelectedDay ? 11 : 10)
                                .shadow(color: dotColor.opacity(0.45), radius: 2)
                        }
                    }
                    .frame(height: 12)

                    Text(tempUnit.display(temperature))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)
                .padding(.vertical, 10)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .background {
                    if isSelectedDay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(theme.colors.primaryText.opacity(0.09))
                            .matchedGeometryEffect(id: "detail-day-selection", in: detailDaySelectionNamespace)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            WeatherDataUnavailableNotice(
                message: weatherDataIssueMessage(
                    .unknownWeatherSymbol(forecast.symbolName),
                    cityName: localizedCityName(for: cityWeather.city),
                    locale: locale
                )
            )
        }
    }

    private func floatingCardDayLabel(for date: Date) -> String {
        if Calendar.current.isDate(date, inSameDayAs: forecastDateToday) {
            return localizedString("Today", locale: locale).uppercased()
        }
        return date.formatted(
            Date.FormatStyle.dateTime
                .weekday(.abbreviated)
                .locale(locale)
        ).uppercased()
    }
}

// MARK: - Expanded Floating Card Container

private struct MapExpandedCardContainer: ViewModifier {
    let plainBackground: Bool
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        if plainBackground {
            content
        } else {
            content.modifier(MapGlassCardContainer(cornerRadius: 22, colorScheme: colorScheme))
        }
    }
}

struct MapGlassCardContainer: ViewModifier {
    let cornerRadius: CGFloat
    let colorScheme: ColorScheme
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @ViewBuilder
    func body(content: Content) -> some View {
        // Reduce Transparency and Increase Contrast substitute an
        // opaque themed fill for material without changing the standard card.
        if reduceTransparency || colorSchemeContrast == .increased {
            styledContainer(
                content.background(
                    theme.colors.glassFill,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
            )
        } else {
            styledContainer(
                content
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .background(
                        theme.colors.glassFill.opacity(colorScheme == .dark ? 0.48 : 0.62),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
            )
        }
    }

    private func styledContainer<Container: View>(_ content: Container) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        theme.colors.primaryText.opacity(colorSchemeContrast == .increased ? 0.90 : 0.10),
                        lineWidth: colorSchemeContrast == .increased ? 1.25 : 1
                    )
            }
            .shadow(color: theme.colors.shadow.opacity(0.16), radius: 22, x: 0, y: 10)
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
            return 24
        } else {
            return 22
        }
    }

    private var floatingMapCardMaxWidth: CGFloat {
        // Keep iPad's selected-city card at the same visual width as the phone
        // presentation; iPhone still expands naturally to its available width.
        UIDevice.current.userInterfaceIdiom == .pad ? 390 : 580
    }

    private var floatingMapCardOverlay: some View {
        Group {
            if isMapRoute, showingMapExpandedCard {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 120)
                        .allowsHitTesting(false)

                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissMapExpandedCard()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                    .zIndex(10)
            }

            if isMapRoute, showingMapExpandedCard, let city = selectedMapCity {
                ZStack(alignment: .topTrailing) {
                    mapExpandedCard(for: city, hideCityName: false)

                    Button {
                        dismissMapExpandedCard()
                    } label: {
                        Color.clear
                            .frame(width: 44, height: 44)
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(theme.colors.secondaryText.opacity(0.65))
                                    .padding(7)
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .id(city.city.id)
                .padding(.horizontal, floatingMapCardHorizontalPadding)
                .frame(maxWidth: floatingMapCardMaxWidth)
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
