//
//  ContentView+MapExpandedCard.swift
//  Weather
//
//  Extracted from ContentView.swift
//

import SwiftUI

extension ContentView {

    // MARK: - Map Expanded Card

    func mapExpandedCard(
        for cityWeather: CityWeather,
        forceMacStyle: Bool = false,
        hideCityName: Bool = false,
        plainBackground: Bool = false
    ) -> AnyView {
        let isNow = selectedDayOffset == -1
        let forecast = cityWeather.forecast(for: max(0, selectedDayOffset))
        let tempUnit = TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
        let distUnit = DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
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

        #if os(macOS) || os(iOS)
        if usesFloatingMapCardLayout || forceMacStyle {
            return AnyView(macMapExpandedCard(
                for: cityWeather,
                icon: icon,
                primaryText: isOverlayActive ? overlayLargeText : tempUnit.display(isNow ? cityWeather.temperature : forecast.dailyHigh),
                metricLabel: isOverlayActive ? overlayLabel : localizedString("Highest Temperature", locale: locale),
                tempUnit: tempUnit,
                hideCityName: hideCityName,
                plainBackground: plainBackground
            ))
        }
#endif

        return AnyView(HStack(alignment: .bottom, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isOverlayActive ? overlayLargeText : tempUnit.display(isNow ? cityWeather.temperature : forecast.dailyHigh))
                        .font(.system(size: 40, weight: .semibold, design: .default))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())

                    Text(isOverlayActive ? overlayLabel : "Highest Temperature")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    if !hideCityName {
                        Text(cityWeather.city.localizedName(locale: locale))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }
                .animation(.smooth(duration: 0.4), value: mapOverlayMode)

                Spacer(minLength: 8)

                VStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 36, weight: .medium))
                        .weatherIconStyle(for: icon)
                        .frame(width: 54, height: 46)
                        .offset(y: -6)

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
                                            .shadow(color: dayForecast.condition.dotColor.opacity(0.55), radius: 3)
                                            .opacity(i == selectedDayOffset ? 1 : 0.58)
                                    }
                                }
                            }
                        }
                    }
                }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .themedGlass(in: .rect(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture {
            showingCityDetail = true
        })
    }

    #if os(macOS) || os(iOS)
    private func macMapExpandedCard(
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
        let distUnit = DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if !hideCityName {
                        Text(cityWeather.city.localizedName(locale: locale))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    Text(metricLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if cityIsInSidebar(cityWeather) {
                    Button {
                        dismissMapExpandedCard()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                } else {
                    macExpandedCardAddMenu(for: cityWeather)
                }
            }
            .padding(.bottom, 14)

            HStack(alignment: .center, spacing: 12) {
                Text(primaryText)
                    .font(.system(size: 42, weight: .regular, design: .default))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .lineLimit(1)

                Image(systemName: icon)
                    .font(.system(size: 30, weight: .medium))
                    .weatherIconStyle(for: icon)
                    .frame(width: 36, height: 32)

                Spacer(minLength: 8)
            }
            .padding(.bottom, 14)

            macExpandedCardDivider
                .padding(.bottom, 10)

            VStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(0..<5, id: \.self) { column in
                            let index = row * 5 + column
                            if index < forecasts.count {
                                let forecast = forecasts[index]
                                Button {
                                    withAnimation(.smooth(duration: 0.18)) {
                                        selectedDayOffset = index
                                    }
                                } label: {
                                    VStack(spacing: 7) {
                                        Text(macForecastDayLabel(for: index))
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)

                                        Circle()
                                            .fill(forecast.condition.dotColor)
                                            .frame(width: index == selectedDayOffset ? 8 : 7, height: index == selectedDayOffset ? 8 : 7)
                                            .shadow(color: forecast.condition.dotColor.opacity(0.45), radius: 2)

                                        Text(tempUnit.display(forecast.dailyHigh))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .background {
                                        if index == selectedDayOffset {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(Color.primary.opacity(0.09))
                                        } else if macExpandedCardHoveredDay == index {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .onHover { hovering in
                                    macExpandedCardHoveredDay = hovering ? index : (macExpandedCardHoveredDay == index ? nil : macExpandedCardHoveredDay)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, macExpandedCardShowsDetails ? 14 : 10)

            if macExpandedCardShowsDetails {
                macExpandedCardDetails(for: cityWeather, forecast: selectedForecast, tempUnit: tempUnit, distUnit: distUnit)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack {
                Spacer()

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        macExpandedCardShowsDetails.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .rotationEffect(.degrees(macExpandedCardShowsDetails ? 180 : 0))
                        .frame(width: 24, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()
            }
        }
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .modifier(MapExpandedCardContainer(plainBackground: plainBackground, colorScheme: colorScheme))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func macExpandedCardAddMenu(for cityWeather: CityWeather) -> some View {
        Menu {
            ForEach(CityListID.allLists) { listID in
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
                        recenterOnAllCities = true
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

    private func macExpandedCardDetails(
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

        return VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                macExpandedCardDivider
                    .padding(.bottom, 10)

                HStack(spacing: 8) {
                    macExpandedCardChartMetricMenu
                    Spacer()
                    macExpandedCardChartRangeMenu
                }
                .padding(.bottom, 6)

                GeometryReader { geo in
                    if macExpandedCardChartRange == .tenDay {
                        ScrollView(.horizontal, showsIndicators: false) {
                            DailyTimelineChart(
                                dailyForecasts: cityWeather.dailyForecasts,
                                chartMetric: macExpandedCardChartMetric,
                                selectedDayOffset: selectedDayOffset,
                                cityTimeZone: cityWeather.timeZone,
                                lineColor: macExpandedCardChartLineColor(macExpandedCardChartMetric),
                                compactLayout: true
                            )
                            .frame(width: max(geo.size.width * 1.1, 270), height: geo.size.height)
                        }
                    } else if macExpandedCardChartRange == .entireDay {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HourlyTimelineChart(
                                hourlyForecasts: forecast.hourlyForecasts,
                                chartMetric: macExpandedCardChartMetric,
                                dayOffset: max(0, selectedDayOffset),
                                cityTimeZone: cityWeather.timeZone,
                                previewCurrentHour: nil,
                                lineColor: macExpandedCardChartLineColor(macExpandedCardChartMetric),
                                showAllHours: true,
                                compactLayout: true
                            )
                            .frame(width: max(geo.size.width * 1.6, 390), height: geo.size.height)
                        }
                    } else {
                        HourlyTimelineChart(
                            hourlyForecasts: forecast.hourlyForecasts,
                            chartMetric: macExpandedCardChartMetric,
                            dayOffset: max(0, selectedDayOffset),
                            cityTimeZone: cityWeather.timeZone,
                            previewCurrentHour: nil,
                            lineColor: macExpandedCardChartLineColor(macExpandedCardChartMetric),
                            compactLayout: true
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .frame(height: 184)
                .clipped()

                macExpandedCardDivider
                    .padding(.top, -12)
            }

            ForEach(rows, id: \.1) { icon, label, value in
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(value)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }

            if let sunrise = forecast.sunrise, let sunset = forecast.sunset {
                HStack(spacing: 10) {
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(localizedString("Sunrise", locale: locale))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(macExpandedCardTime(sunrise, in: cityWeather.timeZone))
                        .font(.caption.weight(.semibold))
                    Text("·")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(macExpandedCardTime(sunset, in: cityWeather.timeZone))
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
        }
    }

    private var macExpandedCardDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.75)
            .padding(.horizontal, -14)
    }

    private var macExpandedCardChartMetricMenu: some View {
        Menu {
            ForEach(macExpandedCardChartMetrics, id: \.0) { metric, icon, label in
                Button {
                    macExpandedCardChartMetric = metric
                } label: {
                    HStack {
                        Image(systemName: macExpandedCardChartMetric == metric ? "checkmark" : "")
                            .foregroundStyle(.primary)
                            .frame(width: 14)
                        Text(label)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: macExpandedCardChartMetricIcon(macExpandedCardChartMetric))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(macExpandedCardChartLineColor(macExpandedCardChartMetric))
                Text(macExpandedCardChartMetricLabel(macExpandedCardChartMetric))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 22)
            .padding(.horizontal, 8)
            .background(Color.primary.opacity(0.07), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var macExpandedCardChartRangeMenu: some View {
        Menu {
            ForEach(macExpandedCardChartRanges, id: \.0) { range, label in
                Button {
                    macExpandedCardChartRange = range
                } label: {
                    HStack {
                        Image(systemName: macExpandedCardChartRange == range ? "checkmark" : "")
                            .foregroundStyle(.primary)
                            .frame(width: 14)
                        Text(label)
                    }
                }
            }
        } label: {
            Text(macExpandedCardChartRangeLabel(macExpandedCardChartRange))
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .frame(height: 22)
                .padding(.horizontal, 8)
                .background(Color.primary.opacity(0.07), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var macExpandedCardChartRanges: [(WeatherDetailView.ChartTimeRange, String)] {
        [
            (.daytime, localizedString("Daytime", locale: locale)),
            (.entireDay, localizedString("Entire Day", locale: locale)),
            (.tenDay, localizedString("10 Days", locale: locale))
        ]
    }

    private var macExpandedCardChartMetrics: [(WeatherDetailView.ChartMetric, String, String)] {
        [
            (.temperature, "thermometer.medium", localizedString("Temperature", locale: locale)),
            (.feelsLike, "thermometer.variable.and.figure", localizedString("Feels Like", locale: locale)),
            (.cloudCover, "cloud", localizedString("Cloud Cover", locale: locale)),
            (.precipitation, "drop.fill", localizedString("Precipitation", locale: locale)),
            (.windSpeed, "wind", localizedString("Wind Speed", locale: locale)),
            (.uvIndex, "sun.max.fill", localizedString("UV Index", locale: locale)),
            (.humidity, "humidity.fill", localizedString("Humidity", locale: locale)),
            (.visibility, "eye", localizedString("Visibility", locale: locale))
        ]
    }

    private func macExpandedCardChartMetricIcon(_ metric: WeatherDetailView.ChartMetric) -> String {
        macExpandedCardChartMetrics.first(where: { $0.0 == metric })?.1 ?? "chart.xyaxis.line"
    }

    private func macExpandedCardChartMetricLabel(_ metric: WeatherDetailView.ChartMetric) -> String {
        macExpandedCardChartMetrics.first(where: { $0.0 == metric })?.2 ?? localizedString("Forecast", locale: locale)
    }

    private func macExpandedCardChartRangeLabel(_ range: WeatherDetailView.ChartTimeRange) -> String {
        switch range {
        case .daytime: return localizedString("Daytime", locale: locale)
        case .entireDay: return localizedString("Entire Day", locale: locale)
        case .tenDay: return localizedString("10 Days", locale: locale)
        }
    }

    private func macExpandedCardChartLineColor(_ metric: WeatherDetailView.ChartMetric) -> Color {
        switch metric {
        case .temperature:   return Color(hex: 0xE8536B)
        case .feelsLike:     return Color(hex: 0xED8988)
        case .cloudCover:    return Color(hex: 0x9ABCCE)
        case .precipitation: return Color(hex: 0x57D3E5)
        case .windSpeed:     return Color(hex: 0xFDA409)
        case .uvIndex:       return Color(hex: 0xFB4368)
        case .humidity:      return Color(hex: 0xBE9AED)
        case .visibility:    return Color(hex: 0x1579C7)
        }
    }

    private func macExpandedCardChartCurrentValue(
        for cityWeather: CityWeather,
        forecast: DailyForecast,
        metric: WeatherDetailView.ChartMetric,
        tempUnit: TemperatureUnit,
        distUnit: DistanceUnit
    ) -> String {
        let isNow = selectedDayOffset == -1
        switch metric {
        case .temperature:
            return isNow ? tempUnit.display(cityWeather.temperature) : tempUnit.displaySlash(low: forecast.dailyLow, high: forecast.dailyHigh)
        case .feelsLike:
            if isNow {
                return cityWeather.currentFeelsLike.map { tempUnit.display($0) } ?? "-"
            }
            if let low = forecast.feelsLikeLow, let high = forecast.feelsLikeHigh {
                return tempUnit.displaySlash(low: low, high: high)
            }
            return "-"
        case .cloudCover:
            return (isNow ? cityWeather.currentCloudCover : forecast.cloudCover).map { "\(Int($0 * 100))%" } ?? "-"
        case .precipitation:
            if isNow {
                return [.rain, .drizzle, .snow].contains(cityWeather.condition) ? "100%" : "0%"
            }
            return forecast.precipitationChance.map { "\(Int($0 * 100))%" } ?? "-"
        case .windSpeed:
            return (isNow ? cityWeather.currentWindSpeed : forecast.windSpeed).map { distUnit.displayWindSpeed($0) } ?? "-"
        case .uvIndex:
            return (isNow ? cityWeather.currentUVIndex : forecast.uvIndex).map { "\($0)" } ?? "-"
        case .humidity:
            return (isNow ? cityWeather.currentHumidity : forecast.maxHumidity).map { "\(Int($0 * 100))%" } ?? "-"
        case .visibility:
            return (isNow ? cityWeather.currentVisibility : forecast.maxVisibility).map { distUnit.display($0) } ?? "-"
        }
    }

    private func macExpandedCardTime(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func macForecastDayLabel(for offset: Int) -> String {
        if offset == 0 {
            return localizedString("Today", locale: locale).uppercased()
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "EEE"
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return formatter.string(from: date).uppercased()
    }
    #endif
}

private struct MapExpandedCardContainer: ViewModifier {
    let plainBackground: Bool
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        if plainBackground {
            content
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .background(
                    (colorScheme == .dark
                     ? Color(red: 0.08, green: 0.08, blue: 0.12).opacity(0.48)
                     : Color.white.opacity(0.62)),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.16), radius: 22, x: 0, y: 10)
        }
    }
}
