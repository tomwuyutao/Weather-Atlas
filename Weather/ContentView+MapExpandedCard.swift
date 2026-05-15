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
        let selectedForecast = cityWeather.forecast(for: max(0, selectedDayOffset))
        let distUnit = DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers

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
                        .frame(width: 28, height: 28)
                        .background {
                            if macExpandedCardHoveringClose {
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .onHover { macExpandedCardHoveringClose = $0 }
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
            .padding(.bottom, 14)

            if macExpandedCardShowsDetails {
                macExpandedCardDetails(for: cityWeather, forecast: selectedForecast, tempUnit: tempUnit, distUnit: distUnit)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

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
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background {
                                if macExpandedCardHoveringRemove {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .onHover { macExpandedCardHoveringRemove = $0 }
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
                        macExpandedCardShowsDetails.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(macExpandedCardShowsDetails ? localizedString("Hide Details", locale: locale) : localizedString("Expand Details", locale: locale))
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(macExpandedCardShowsDetails ? 180 : 0))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(macExpandedCardHoveringOpenDetails ? theme.colors.accent.opacity(0.82) : theme.colors.accent)
                .onHover { macExpandedCardHoveringOpenDetails = $0 }
            }
        }
        .padding(14)
        .background(
            (colorScheme == .dark
             ? Color(red: 0.08, green: 0.08, blue: 0.12).opacity(0.98)
             : Color(red: 0.92, green: 0.90, blue: 0.86).opacity(0.98)),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 22, x: 0, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
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
