//
//  FloatingCard.swift
//  Weather
//
//  Purpose: Renders the floating weather card shown from map markers, including
//  compact card content, expanded map-card content, and placement helpers.
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
        let forecast = cityWeather.forecast(for: selectedDayOffset)
        let tempUnit = TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic
        let icon = forecast.weatherIcon
        let sunnyHoursText = mapSunnyHoursSummary(for: cityWeather, forecast: forecast)
        let sunnyHoursLabel = localizedString("Sunny Hours", locale: locale)

        if forceExpandedStyle {
            expandedFloatingWeatherCard(
                for: cityWeather,
                icon: icon,
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
                    Text(sunnyHoursText)
                        .font(.system(size: phoneCardTemperatureSize, weight: .semibold, design: .default))
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)

                    Text(sunnyHoursLabel)
                        .font(phoneCardMetricFont)
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(1)
                        .padding(.top, 4)

                    if !hideCityName {
                        Text(cityWeather.city.localizedName(locale: locale))
                            .font(phoneCardTitleFont)
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)
                            .padding(.top, 5)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottomLeading)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 0) {
                    Image(systemName: floatingCardIconName(for: icon))
                        .font(.system(size: phoneCardIconSize, weight: .medium))
                        .floatingCardWeatherIconStyle(for: icon)
                        .frame(width: phoneCardIconFrame.width, height: phoneCardIconFrame.height, alignment: .center)

                    Spacer(minLength: 8)

                    VStack(spacing: 4) {
                        ForEach(0..<2, id: \.self) { row in
                            HStack(spacing: 4) {
                                ForEach(0..<5, id: \.self) { column in
                                    let index = row * 5 + column
                                    if index < cityWeather.dailyForecasts.count {
                                        let dayForecast = cityWeather.dailyForecasts[index]
                                        let dayDotColor = SunninessScoring.condition(for: dayForecast.symbolName).dotColor
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


// MARK: - Floating Card Icon Style

private func floatingCardIconName(for iconName: String) -> String {
    if iconName == "cloud" {
        return "cloud.fill"
    }
    if iconName == "cloud.sun" {
        return "cloud.sun.fill"
    }
    return iconName
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
                .foregroundStyle(colors.dotCloudy, colors.dotPartlyCloudy)
        } else {
            self.weatherIconStyle(for: iconName)
        }
    }
}


// MARK: - Expanded Floating Card

extension ContentView {
    func expandedFloatingWeatherCard(
        for cityWeather: CityWeather,
        icon: String,
        tempUnit: TemperatureUnit,
        hideCityName: Bool = false,
        plainBackground: Bool = false
    ) -> some View {
        let forecast = cityWeather.forecast(for: selectedDayOffset)
        let sunnyHoursText = mapSunnyHoursSummary(for: cityWeather, forecast: forecast)
        let sunnyHoursLabel = localizedString("Sunny Hours", locale: locale)
        let forecasts = Array(cityWeather.dailyForecasts.prefix(10))
        let cornerRadius: CGFloat = 28

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .center, spacing: 6) {
                    if !hideCityName {
                        Text(cityWeather.city.localizedName(locale: locale))
                            .font(.title.weight(.semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)
                    }

                    Text(sunnyHoursLabel)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(theme.colors.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)

                HStack(alignment: .center, spacing: 2) {
                    Spacer(minLength: 0)

                    Text(sunnyHoursText)
                        .font(.system(size: 62, weight: .regular, design: .default))
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.48)
                        .id("primary-\(selectedDayOffset)-\(sunnyHoursText)")
                        .transition(.scale(scale: 0.82).combined(with: .opacity))

                    Image(systemName: floatingCardIconName(for: icon))
                        .font(.system(size: 44, weight: .medium))
                        .floatingCardWeatherIconStyle(for: icon)
                        .compatSymbolReplaceTransition()
                        .id("icon-\(selectedDayOffset)-\(icon)")
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
        let sunnyHours = SunninessScoring.daytimeHours(for: forecast, timeZone: city.timeZone)
            .filter { SunninessScoring.condition(for: $0.symbolName) == .clear }
            .map(\.hour)
            .sorted()

        guard !sunnyHours.isEmpty else {
            return localizedString("No Sun", locale: locale)
        }

        var bestStart = sunnyHours[0]
        var bestEnd = sunnyHours[0]
        var currentStart = sunnyHours[0]
        var currentEnd = sunnyHours[0]

        for hour in sunnyHours.dropFirst() {
            if hour == currentEnd + 1 {
                currentEnd = hour
            } else {
                if currentEnd - currentStart > bestEnd - bestStart {
                    bestStart = currentStart
                    bestEnd = currentEnd
                }
                currentStart = hour
                currentEnd = hour
            }
        }

        if currentEnd - currentStart > bestEnd - bestStart {
            bestStart = currentStart
            bestEnd = currentEnd
        }

        return "\(mapFormattedHour(bestStart, timeZone: city.timeZone)) - \(mapFormattedHour(bestEnd + 1, timeZone: city.timeZone))"
    }

    private func mapFormattedHour(_ hour: Int, timeZone: TimeZone) -> String {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = 0
        let date = calendar.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)
        return formatter.string(from: date)
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
