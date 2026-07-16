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

            // Accessibility: A semantic Button makes the entire compact card available to
            // VoiceOver, Voice Control, and switch input without changing its appearance.
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
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            .padding(.top, 4)

                        if !hideCityName {
                            Text(localizedCityName(for: cityWeather.city))
                                .font(phoneCardTitleFont)
                                .foregroundStyle(theme.colors.primaryText)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(localizedCityName(for: cityWeather.city))
            .accessibilityValue("\(metric.label), \(metric.value)")
            // Accessibility: Search and marker selection can insert this card away from
            // the current reading position, so ContentView explicitly moves focus here.
            .accessibilityFocused($mapCardAccessibilityFocused)
        }
    }

    var floatingMapCardHeight: CGFloat {
        // Accessibility: Reserve extra vertical space only at accessibility Dynamic Type sizes.
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
                iconName: forecast.weatherIcon
            )
        case "cloudCover":
            return MapFloatingCardMetric(
                value: percentageText(forecast.cloudCover),
                label: localizedString("Cloud Cover", locale: locale),
                iconName: forecast.weatherIcon
            )
        case "precipitation":
            return MapFloatingCardMetric(
                value: percentageText(forecast.precipitationChance),
                label: localizedString("Rain", locale: locale),
                iconName: forecast.weatherIcon
            )
        case "windSpeed":
            let value = forecast.windSpeed.map { distanceUnit.displayWindSpeed($0) } ?? "-"
            return MapFloatingCardMetric(
                value: value,
                label: localizedString("Wind", locale: locale),
                iconName: forecast.weatherIcon
            )
        case "uvIndex":
            return MapFloatingCardMetric(
                value: forecast.uvIndex.map(String.init) ?? "-",
                label: localizedString("UV Index", locale: locale),
                iconName: forecast.weatherIcon
            )
        default:
            let icon = forecast.weatherIcon
            return MapFloatingCardMetric(
                value: mapSunnyHoursSummary(for: cityWeather, forecast: forecast),
                label: localizedString("Sunny Hours", locale: locale),
                iconName: icon
            )
        }
    }

    private func percentageText(_ value: Double?) -> String {
        guard let value else { return "-" }
        return "\(Int((value * 100).rounded()))%"
    }
}


// MARK: - Floating Card Icon Style

private func floatingCardMetricIcon(_ metric: MapFloatingCardMetric, size: CGFloat) -> some View {
    Image(systemName: metric.iconName)
        .font(.system(size: size, weight: .medium))
        .modifier(FloatingCardWeatherIconStyle(iconName: metric.iconName))
        .accessibilityHidden(true)
}

private struct FloatingCardWeatherIconStyle: ViewModifier {
    @Environment(\.appTheme) private var theme
    let iconName: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if iconName == "cloud" {
            content
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(theme.colors.dotCloudy)
        } else if iconName == "cloud.sun" {
            content
                .symbolRenderingMode(.palette)
                .foregroundStyle(theme.colors.dotCloudy, theme.colors.sunIconColor)
        } else {
            content.weatherIconStyle(for: iconName)
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
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    }

                    Text(metric.label)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(theme.colors.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)
                // Accessibility: Expose one concise city heading instead of its styled children.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(localizedCityName(for: cityWeather.city))
                .accessibilityAddTraits(.isHeader)
                .accessibilityHidden(hideCityName)

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
                        .symbolReplaceTransition()
                        .id("icon-\(mapOverlayMode)-\(selectedDayOffset)-\(metric.iconName)")
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                        .frame(width: 60, height: 52)

                    Spacer(minLength: 0)
                }
                .padding(.bottom, 18)
                .animation(.snappy(duration: 0.28), value: selectedDayOffset)
                // Accessibility: Read the metric name and value as one meaningful element.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(metric.label)
                .accessibilityValue(metric.value)

                // Accessibility: Replace the dense ten-column forecast with a roomy grid at
                // accessibility Dynamic Type sizes; the normal card layout is unchanged.
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 10
                        ) {
                            ForEach(forecasts.indices, id: \.self) { index in
                                expandedFloatingWeatherCardDayButton(
                                    index: index,
                                    forecast: forecasts[index],
                                    cityWeather: cityWeather,
                                    tempUnit: tempUnit
                                )
                            }
                        }
                    } else {
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
        guard let range = SunninessScoring.longestSunnyHourRange(in: daytimeHours, timeZone: city.timeZone) else {
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
        let dotColor = condition.dotColor(for: theme.colors)
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

                // Accessibility: Symbols supplement color when Differentiate Without Color is on.
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
                .accessibilityHidden(true)

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
        // Accessibility: Each forecast choice announces its day, condition, value, and selection.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(floatingCardDayLabel(for: daySelectionOffset))
        .accessibilityValue(
            "\(condition.localizedDisplayName(locale: locale)), \(tempUnit.display(temperature))"
        )
        .accessibilityAddTraits(isSelectedDay ? [.isSelected] : [])
    }

    private func floatingCardDayLabel(for offset: Int) -> String {
        if offset == 0 { return localizedString("Today", locale: locale).uppercased() }

        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
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
        // Accessibility: Reduce Transparency and Increase Contrast substitute an
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

    private var floatingMapCardOverlay: some View {
        Group {
            if isMapRoute, showingMapExpandedCard {
                // Accessibility: The visual dismissal backdrop stays out of the focus order;
                // assistive technologies dismiss the modal with the escape action below.
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 120)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissMapExpandedCard()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityHidden(true)
                }
                    .zIndex(10)
            }

            if isMapRoute, showingMapExpandedCard, let city = selectedMapCity {
                mapExpandedCard(for: city, hideCityName: false)
                    .id(city.city.id)
                    .padding(.horizontal, floatingMapCardHorizontalPadding)
                    // iPad: Keep the selected-city card readable and bottom-centred
                    // instead of allowing it to span a regular-width map window.
                    // This cap is wider than every supported iPhone window, so the
                    // compact layout remains unchanged.
                    .frame(maxWidth: 580)
                    .padding(.bottom, floatingMapCardBottomPadding)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.4, anchor: .bottom).combined(with: .opacity).combined(with: .offset(y: 20)),
                            removal: .scale(scale: 0.4, anchor: .bottom).combined(with: .opacity).combined(with: .offset(y: 20))
                        )
                    )
                    // Accessibility: Present the expanded card as a modal and support escape.
                    .accessibilityAddTraits(.isModal)
                    .accessibilityAction(.escape) {
                        dismissMapExpandedCard()
                    }
                    // Accessibility: Also expose dismissal in the actions rotor and to
                    // Voice Control users who invoke the selected control's actions.
                    .accessibilityAction(named: Text(localizedString("Cancel", locale: locale))) {
                        dismissMapExpandedCard()
                    }
                    .zIndex(12)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showingMapExpandedCard)
    }
}
