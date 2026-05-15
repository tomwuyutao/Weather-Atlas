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

        #if os(macOS)
        return macMapExpandedCard(
            for: cityWeather,
            icon: icon,
            primaryText: isOverlayActive ? overlayLargeText : tempUnit.display(isNow ? cityWeather.temperature : forecast.dailyHigh),
            metricLabel: isOverlayActive ? overlayLabel : localizedString("Highest Temperature", locale: locale),
            tempUnit: tempUnit
        )
        #else
        return HStack(alignment: .bottom, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isOverlayActive ? overlayLargeText : tempUnit.display(isNow ? cityWeather.temperature : forecast.dailyHigh))
                        .font(.system(size: 40, weight: .semibold, design: .default))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())

                    Text(isOverlayActive ? overlayLabel : "Highest Temperature")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text(cityWeather.city.localizedName(locale: locale))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .animation(.smooth(duration: 0.4), value: mapOverlayMode)

                Spacer(minLength: 8)

                VStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 36, weight: .medium))
                        .weatherIconStyle(for: icon)
                        .frame(width: 54, height: 46)
                        .background(alignment: .top) {
                            WeatherEffectOverlay(condition: effectCondition, isCompact: false, iconHeight: 46, iconName: icon)
                        }
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
        }
        #endif
    }

    #if os(macOS)
    private func macMapExpandedCard(
        for cityWeather: CityWeather,
        icon: String,
        primaryText: String,
        metricLabel: String,
        tempUnit: TemperatureUnit
    ) -> some View {
        let forecasts = Array(cityWeather.dailyForecasts.prefix(10))

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cityWeather.city.localizedName(locale: locale))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(metricLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showingMapExpandedCard = false
                        tappedCity = nil
                        if previewCity != nil {
                            previewCity = nil
                            recenterOnAllCities = true
                        }
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
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

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.75)
                .padding(.horizontal, -14)
                .padding(.bottom, 12)

            Text(localizedString("10 Day Forecast", locale: locale))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.bottom, 12)

            VStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(0..<5, id: \.self) { column in
                            let index = row * 5 + column
                            if index < forecasts.count {
                                let forecast = forecasts[index]
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
                                .background {
                                    if index == selectedDayOffset {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.primary.opacity(0.09))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 14)

            HStack {
                if cityIsInSidebar(cityWeather) {
                    Button(role: .destructive) {
                        weatherService.removeCity(cityWeather)
                        showingMapExpandedCard = false
                        showingCityDetail = false
                        tappedCity = nil
                        if previewCity != nil { previewCity = nil }
                        recenterOnAllCities = true
                    } label: {
                        Text(localizedString("Remove", locale: locale))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                } else if CityListID.allLists.count > 1 {
                    Menu {
                        ForEach(CityListID.allLists) { listID in
                            Button(listID.localizedDisplayName(locale: locale)) {
                                Task {
                                    await weatherService.addCityToList(cityWeather.city, listID: listID)
                                    PlatformFeedback.lightImpact()
                                    showingMapExpandedCard = false
                                    tappedCity = nil
                                    if previewCity != nil { previewCity = nil }
                                    recenterOnAllCities = true
                                }
                            }
                        }
                    } label: {
                        Text(localizedString("Add", locale: locale))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.colors.accent)
                } else {
                    Button {
                        Task {
                            await weatherService.addCityToList(cityWeather.city, listID: weatherService.activeListID)
                            PlatformFeedback.lightImpact()
                            showingMapExpandedCard = false
                            tappedCity = nil
                            if previewCity != nil { previewCity = nil }
                            recenterOnAllCities = true
                        }
                    } label: {
                        Text(localizedString("Add", locale: locale))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.colors.accent)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showingCityDetail = true
                        showingMapExpandedCard = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(localizedString("Open Details", locale: locale))
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(theme.colors.accent)
            }
        }
        .padding(14)
        .background(
            (colorScheme == .dark
             ? theme.colors.mapOcean.opacity(0.96)
             : theme.colors.mapLand.opacity(0.96)),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 22, x: 0, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
