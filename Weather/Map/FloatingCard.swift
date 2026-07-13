//
//  FloatingCard.swift
//  Weather
//
//  Purpose: Renders the floating weather card shown from map markers, including
//  compact card content, expanded map-card content, and placement helpers.
//

import SwiftUI

private struct MapFloatingCardMetric {
    let value: String
    let label: String
    let iconName: String
    let tint: Color
    let usesWeatherIconStyle: Bool
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
        let forecast = cityWeather.forecast(for: selectedDayOffset)
        let tempUnit = TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic
        let distanceUnit = DistanceUnit(rawValue: distanceUnitRaw) ?? .automatic
        let metric = mapFloatingCardMetric(
            for: cityWeather,
            forecast: forecast,
            tempUnit: tempUnit,
            distanceUnit: distanceUnit
        )

        if forceExpandedStyle {
            expandedFloatingWeatherCard(
                for: cityWeather,
                metric: metric,
                tempUnit: tempUnit,
                hideCityName: hideCityName,
                plainBackground: plainBackground
            )
        } else {
            let phoneCardSpacing: CGFloat = 16
            let phoneCardTemperatureSize: CGFloat = 32
            let phoneCardIconSize: CGFloat = 40
            let phoneCardIconFrame = CGSize(width: 56, height: 48)
            let phoneCardMetricFont = Font.caption.weight(.medium)
            let phoneCardTitleFont = Font.headline.weight(.semibold)

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

    private func mapFloatingCardMetric(
        for cityWeather: CityWeather,
        forecast: DailyForecast,
        tempUnit: TemperatureUnit,
        distanceUnit: DistanceUnit
    ) -> MapFloatingCardMetric {
        switch mapOverlayMode {
        case "temperature":
            let temperature = selectedDayOffset == 0 ? cityWeather.temperature : forecast.dailyHigh
            return MapFloatingCardMetric(
                value: tempUnit.display(temperature),
                label: localizedString("Temperature", locale: locale),
                iconName: forecast.weatherIcon,
                tint: theme.colors.primaryText,
                usesWeatherIconStyle: true
            )
        case "cloudCover":
            return MapFloatingCardMetric(
                value: percentageText(forecast.cloudCover),
                label: localizedString("Cloud Cover", locale: locale),
                iconName: forecast.weatherIcon,
                tint: theme.colors.primaryText,
                usesWeatherIconStyle: true
            )
        case "precipitation":
            return MapFloatingCardMetric(
                value: percentageText(forecast.precipitationChance),
                label: localizedString("Rain", locale: locale),
                iconName: forecast.weatherIcon,
                tint: theme.colors.primaryText,
                usesWeatherIconStyle: true
            )
        case "windSpeed":
            let value = forecast.windSpeed.map { distanceUnit.displayWindSpeed($0, locale: locale) } ?? "-"
            return MapFloatingCardMetric(
                value: value,
                label: localizedString("Wind", locale: locale),
                iconName: forecast.weatherIcon,
                tint: theme.colors.primaryText,
                usesWeatherIconStyle: true
            )
        case "uvIndex":
            return MapFloatingCardMetric(
                value: forecast.uvIndex.map(String.init) ?? "-",
                label: localizedString("UV Index", locale: locale),
                iconName: forecast.weatherIcon,
                tint: theme.colors.primaryText,
                usesWeatherIconStyle: true
            )
        default:
            let icon = forecast.weatherIcon
            return MapFloatingCardMetric(
                value: mapSunnyHoursSummary(for: cityWeather, forecast: forecast),
                label: localizedString("Sunny Hours", locale: locale),
                iconName: icon,
                tint: theme.colors.primaryText,
                usesWeatherIconStyle: true
            )
        }
    }

    private func percentageText(_ value: Double?) -> String {
        guard let value else { return "-" }
        return "\(Int((value * 100).rounded()))%"
    }
}


// MARK: - Floating Card Icon Style

private func floatingCardIconName(for iconName: String) -> String {
    return iconName
}

@ViewBuilder
private func floatingCardMetricIcon(_ metric: MapFloatingCardMetric, size: CGFloat) -> some View {
    if metric.usesWeatherIconStyle {
        Image(systemName: floatingCardIconName(for: metric.iconName))
            .font(.system(size: size, weight: .medium))
            .floatingCardWeatherIconStyle(for: metric.iconName)
    } else {
        Image(systemName: metric.iconName)
            .font(.system(size: size, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(metric.tint)
    }
}

private extension View {
    @ViewBuilder
    func floatingCardWeatherIconStyle(for iconName: String) -> some View {
        let colors = AppTheme.shared.colors
        if iconName == "cloud" {
            self
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(colors.dotCloudy)
        } else if iconName == "cloud.sun" {
            self
                .symbolRenderingMode(.palette)
                .foregroundStyle(colors.dotCloudy, colors.sunIconColor)
        } else {
            self.weatherIconStyle(for: iconName)
        }
    }
}


// MARK: - Expanded Floating Card

extension ContentView {
    private func expandedFloatingWeatherCard(
        for cityWeather: CityWeather,
        metric: MapFloatingCardMetric,
        tempUnit: TemperatureUnit,
        hideCityName: Bool = false,
        plainBackground: Bool = false
    ) -> some View {
        let forecasts = Array(cityWeather.dailyForecasts.prefix(10))
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
                        .id("primary-\(mapOverlayMode)-\(selectedDayOffset)-\(metric.value)")
                        .transition(.scale(scale: 0.82).combined(with: .opacity))

                    floatingCardMetricIcon(metric, size: 44)
                        .compatSymbolReplaceTransition()
                        .id("icon-\(mapOverlayMode)-\(selectedDayOffset)-\(metric.iconName)")
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                        .frame(width: 60, height: 52)

                    Spacer(minLength: 0)
                }
                .padding(.bottom, 18)
                .animation(.snappy(duration: 0.28), value: selectedDayOffset)

                VStack(spacing: 10) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(0..<5, id: \.self) { column in
                                let index = row * 5 + column
                                if index < forecasts.count {
                                    expandedFloatingWeatherCardDayButton(
                                        index: index,
                                        forecast: forecasts[index],
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
                .animation(.snappy(duration: 0.24), value: selectedDayOffset)
                .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: cornerRadius))
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 8)
            .modifier(MapExpandedCardContainer(plainBackground: plainBackground, colorScheme: colorScheme))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func mapSunnyHoursSummary(for city: CityWeather, forecast: DailyForecast) -> String {
        let daytimeHours = SunninessScoring.daytimeHours(for: forecast, timeZone: city.timeZone)
        guard let range = SunninessScoring.longestSunnyHourRange(in: daytimeHours) else {
            return localizedString("No Sun", locale: locale)
        }

        let start = SunninessScoring.formattedHour(range.lowerBound, timeZone: city.timeZone, locale: locale)
        let end = SunninessScoring.formattedHour(range.upperBound + 1, timeZone: city.timeZone, locale: locale)
        return "\(start) - \(end)"
    }

    private func expandedFloatingWeatherCardDayButton(
        index: Int,
        forecast: DailyForecast,
        cityWeather: CityWeather,
        tempUnit: TemperatureUnit
    ) -> some View {
        let daySelectionOffset = index
        let isSelectedDay = selectedDayOffset == daySelectionOffset
        let condition = SunninessScoring.condition(for: forecast.symbolName)
        let dotColor = condition.dotColor
        let temperature = forecast.dailyHigh

        return Button {
            withAnimation(.snappy(duration: 0.24)) {
                selectedDayOffset = daySelectionOffset
            }
        } label: {
            VStack(spacing: 6) {
                Text(floatingCardDayLabel(for: daySelectionOffset))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)

                Circle()
                    .fill(dotColor)
                    .frame(width: isSelectedDay ? 11 : 10, height: isSelectedDay ? 11 : 10)
                    .shadow(color: dotColor.opacity(0.45), radius: 2)

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
    }

    private func floatingCardDayLabel(for offset: Int) -> String {
        if offset == 0 { return localizedString("Today", locale: locale).uppercased() }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "EEE"
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return formatter.string(from: date).uppercased()
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

    func body(content: Content) -> some View {
        let colors = AppTheme.shared.colors
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                colors.glassFill.opacity(colorScheme == .dark ? 0.48 : 0.62),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(colors.primaryText.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: colors.shadow.opacity(0.16), radius: 22, x: 0, y: 10)
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

    private var floatingMapCardOverlay: some View {
        Group {
            if isMapRoute, showingMapExpandedCard {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissMapExpandedCard()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(10)
            }

            if isMapRoute, showingMapExpandedCard, let city = tappedCity {
                mapExpandedCard(for: city, hideCityName: false)
                    .id(city.city.id)
                    .padding(.horizontal, floatingMapCardHorizontalPadding)
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
