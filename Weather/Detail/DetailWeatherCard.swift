//
//  DetailWeatherCard.swift
//  Weather
//
//  Purpose: Builds the expanded weather card used by city detail screens,
//  including forecast-day selection and embedded weather chart controls.
//

import SwiftUI

extension ContentView {

    func expandedWeatherCard(
        for cityWeather: CityWeather,
        icon: String,
        primaryText: String,
        metricLabel: String,
        tempUnit: TemperatureUnit,
        hideCityName: Bool = false,
        plainBackground: Bool = false
    ) -> some View {
        let forecasts = Array(cityWeather.dailyForecasts.prefix(10))
        let selectedForecast = cityWeather.forecast(for: max(0, selectedDayOffset))
        let distUnit = DistanceUnit(rawValue: distanceUnitRaw) ?? .automatic
        let detailCardCornerRadius: CGFloat = 28
        let titleFont = Font.title

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Spacer(minLength: 0)

                VStack(alignment: .center, spacing: 6) {
                    if !hideCityName {
                        Text(cityWeather.city.localizedName(locale: locale))
                            .font(titleFont.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    Text(metricLabel)
                        .font(Font.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, 10)

            HStack(alignment: .center, spacing: 2) {
                Spacer(minLength: 0)

                Text(primaryText)
                    .font(.system(size: 62, weight: .regular, design: .default))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .id("primary-\(selectedDayOffset)-\(primaryText)")
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.82).combined(with: .opacity),
                        removal: .scale(scale: 0.82).combined(with: .opacity)
                    ))

                Image(systemName: icon)
                    .font(.system(size: 44, weight: .medium))
                    .weatherIconStyle(for: icon)
                    .compatSymbolReplaceTransition()
                    .id("icon-\(selectedDayOffset)-\(icon)")
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.82).combined(with: .opacity),
                        removal: .scale(scale: 0.82).combined(with: .opacity)
                    ))
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
                                expandedWeatherCardDayButton(
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
            .background {
                RoundedRectangle(cornerRadius: detailCardCornerRadius, style: .continuous)
                    .fill(theme.colors.mapLand)
            }
            .overlay {
                RoundedRectangle(cornerRadius: detailCardCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .padding(.bottom, 18)

            if expandedWeatherCardShowsDetails {
                expandedWeatherCardDetails(for: cityWeather, forecast: selectedForecast, tempUnit: tempUnit, distUnit: distUnit)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .modifier(MapExpandedCardContainer(plainBackground: plainBackground, colorScheme: colorScheme))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    }

    private func expandedWeatherCardDayButton(
        index: Int,
        forecast: DailyForecast,
        cityWeather: CityWeather,
        tempUnit: TemperatureUnit
    ) -> some View {
        let representsNow = index == 0
        let daySelectionOffset = representsNow ? -1 : index
        let isSelectedDay = selectedDayOffset == daySelectionOffset
        let condition = representsNow ? cityWeather.condition : forecast.condition
        let icon = representsNow ? cityWeather.weatherIcon : forecast.weatherIcon
        let dotColor = icon.contains("moon") ? theme.colors.moonIconColor : condition.dotColor
        let temperature = representsNow ? cityWeather.temperature : forecast.dailyHigh

        return Button {
            withAnimation(.snappy(duration: 0.24)) {
                selectedDayOffset = daySelectionOffset
            }
        } label: {
            VStack(spacing: 6) {
                Text(forecastDayLabel(for: daySelectionOffset))
                    .font(Font.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Circle()
                    .fill(dotColor)
                    .frame(width: isSelectedDay ? 11 : 10, height: isSelectedDay ? 11 : 10)
                    .shadow(color: dotColor.opacity(0.45), radius: 2)

                Text(tempUnit.display(temperature))
                    .font(Font.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .padding(.vertical, 10)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background {
                if isSelectedDay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.09))
                        .matchedGeometryEffect(id: "detail-day-selection", in: detailDaySelectionNamespace)
                }
            }
        }
        .buttonStyle(.plain)
    }

    func expandedWeatherCardAddMenu(for cityWeather: CityWeather) -> some View {
        Menu {
            ForEach(managedLists) { listID in
                Button(listID.localizedDisplayName(locale: locale)) {
                    Task {
                        await weatherService.addCityToList(cityWeather.city, listID: listID)
                        PlatformFeedback.lightImpact()
                        if let addedCity = weatherService.weatherData(for: listID).first(where: {
                            $0.city.name == cityWeather.city.name && $0.city.country == cityWeather.city.country
                        }) {
                            tappedCity = addedCity
                        }
                        previewCity = nil
                        mapRecenterRequest = .listCoordinates
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showingMapExpandedCard = false
                            tappedCity = nil
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(theme.colors.accent, in: Circle())
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private func expandedWeatherCardDetails(
        for cityWeather: CityWeather,
        forecast: DailyForecast,
        tempUnit: TemperatureUnit,
        distUnit: DistanceUnit
    ) -> some View {
        let isNow = selectedDayOffset == -1
        let rows: [(String, String, String)] = [
            (
                "thermometer.medium",
                localizedString("Temperature", locale: locale),
                isNow ? tempUnit.display(cityWeather.temperature) : tempUnit.displaySlash(low: forecast.dailyLow, high: forecast.dailyHigh)
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

        let detailCardCornerRadius: CGFloat = 28
        let chartControlBottomPadding: CGFloat = 0
        return VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    expandedWeatherCardChartMetricMenu()
                    Spacer()
                    expandedWeatherCardChartRangeMenu()
                }
                .padding(.bottom, chartControlBottomPadding)

                GeometryReader { geo in
                    chartContent(
                        for: cityWeather,
                        forecast: forecast,
                        availableSize: geo.size
                    )
                }
                .frame(height: 220)
                .clipped()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: detailCardCornerRadius, style: .continuous)
                    .fill(theme.colors.mapLand)
            }
            .overlay {
                RoundedRectangle(cornerRadius: detailCardCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }

            VStack(spacing: 0) {
                ForEach(rows, id: \.1) { icon, label, value in
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        Text(label)
                            .font(Font.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(value)
                            .font(Font.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                if let sunrise = forecast.sunrise, let sunset = forecast.sunset {
                    HStack(spacing: 12) {
                        Image(systemName: "sunrise.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        Text(localizedString("Sun", locale: locale))
                            .font(Font.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(expandedWeatherCardTime(sunrise, in: cityWeather.timeZone))
                            .font(Font.callout.weight(.semibold))
                        Text("·")
                            .font(Font.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(expandedWeatherCardTime(sunset, in: cityWeather.timeZone))
                            .font(Font.callout.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: detailCardCornerRadius, style: .continuous)
                    .fill(theme.colors.mapLand)
            }
            .overlay {
                RoundedRectangle(cornerRadius: detailCardCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
    }

    private func expandedWeatherCardTime(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func forecastDayLabel(for offset: Int) -> String {
        if offset == -1 {
            return localizedString("Now", locale: locale).uppercased()
        }
        if offset == 0 {
            return localizedString("Today", locale: locale).uppercased()
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "EEE"
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return formatter.string(from: date).uppercased()
    }
}

private struct MapExpandedCardContainer: ViewModifier {
    let plainBackground: Bool
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        if plainBackground {
            content
        } else {
            content
                .modifier(MapGlassCardContainer(cornerRadius: 22, colorScheme: colorScheme))
        }
    }
}
