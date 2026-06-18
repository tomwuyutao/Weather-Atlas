//
//  FloatingCard.swift
//  Weather
//
//  Floating map card placement and rendering.
//

import SwiftUI

extension ContentView {

    // MARK: - Map Expanded Card

    func mapExpandedCard(
        for cityWeather: CityWeather,
        forceMacStyle: Bool = false,
        forceIPhoneStyle: Bool = false,
        forceIPhoneDetailSizing: Bool = false,
        hideCityName: Bool = false,
        plainBackground: Bool = false
    ) -> AnyView {
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

        #if os(macOS) || os(iOS)
        if !forceIPhoneStyle && (usesFloatingMapCardLayout || forceMacStyle) {
            return AnyView(macMapExpandedCard(
                for: cityWeather,
                icon: icon,
                primaryText: isOverlayActive ? overlayLargeText : tempUnit.display(isNow ? cityWeather.temperature : forecast.dailyHigh),
                metricLabel: isOverlayActive ? overlayLabel : localizedString(isNow ? "Current Temperature" : "Highest Temperature", locale: locale),
                tempUnit: tempUnit,
                hideCityName: hideCityName,
                plainBackground: plainBackground,
                usesIPhoneDetailSizing: forceIPhoneDetailSizing || (forceMacStyle && !usesFloatingMapCardLayout)
            ))
        }
#endif

        #if os(macOS)
        let compactForcedMacFloatingCard = forceIPhoneStyle
        #else
        let compactForcedMacFloatingCard = false
        #endif
        let phoneCardSpacing: CGFloat = compactForcedMacFloatingCard ? 10 : 16
        let phoneCardTemperatureSize: CGFloat = compactForcedMacFloatingCard ? 32 : 38
        let phoneCardIconSize: CGFloat = compactForcedMacFloatingCard ? 32 : 40
        let phoneCardIconFrame = CGSize(width: compactForcedMacFloatingCard ? 48 : 56, height: compactForcedMacFloatingCard ? 42 : 48)
        let phoneCardMetricFont = compactForcedMacFloatingCard ? Font.caption2.weight(.medium) : Font.caption.weight(.medium)
        let phoneCardTitleFont = compactForcedMacFloatingCard ? Font.subheadline.weight(.semibold) : Font.headline.weight(.semibold)
        let phoneCardSelectedDotSize: CGFloat = compactForcedMacFloatingCard ? 6.5 : 8
        let phoneCardDotSize: CGFloat = compactForcedMacFloatingCard ? 5 : 6

        return AnyView(HStack(alignment: .bottom, spacing: phoneCardSpacing) {
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
                        .padding(.top, compactForcedMacFloatingCard ? 2 : 4)

                    if !hideCityName {
                        Text(cityWeather.city.localizedName(locale: locale))
                            .font(phoneCardTitleFont)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .padding(.top, compactForcedMacFloatingCard ? 3 : 5)
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

                    Spacer(minLength: compactForcedMacFloatingCard ? 6 : 8)

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
                    .frame(height: compactForcedMacFloatingCard ? 26 : 30, alignment: .bottom)
                    .offset(y: -1)
                }
                .frame(maxHeight: .infinity, alignment: .topTrailing)
        }
        .padding(.horizontal, compactForcedMacFloatingCard ? 20 : 22)
        .padding(.vertical, compactForcedMacFloatingCard ? 14 : 16)
        .frame(maxWidth: .infinity)
        .frame(height: iOSFloatingMapCardHeight)
        .themedGlass(in: .rect(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture {
            #if os(iOS)
            if !shouldUseIPadLayout {
                showingCityDetail = true
                pushIPhoneRoute(.cityDetail)
            } else {
                withAnimation(iPadInspectorMorphAnimation) {
                    showingMapExpandedCard = false
                    showingCityDetail = true
                    iPadInspectorPresentedCityID = cityWeather.id
                }
            }
            #else
            showingCityDetail = true
            #endif
        })
    }

    private var iOSFloatingMapCardHeight: CGFloat {
        #if os(iOS)
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
        #else
        return 108
        #endif
    }

    #if os(macOS) || os(iOS)
    private func macMapExpandedCard(
        for cityWeather: CityWeather,
        icon: String,
        primaryText: String,
        metricLabel: String,
        tempUnit: TemperatureUnit,
        hideCityName: Bool = false,
        plainBackground: Bool = false,
        usesIPhoneDetailSizing: Bool = false
    ) -> some View {
        let forecasts = Array(cityWeather.dailyForecasts.prefix(10))
        let selectedForecast = cityWeather.forecast(for: max(0, selectedDayOffset))
        let distUnit = DistanceUnit(rawValue: distanceUnitRaw) ?? .automatic
        let usesDetailCardLayout = usesIPhoneDetailSizing || plainBackground || macExpandedCardShowsDetails
        let centersHeroContent = usesIPhoneDetailSizing || plainBackground
        let detailCardCornerRadius: CGFloat = usesIPhoneDetailSizing ? 28 : 20
        #if os(macOS)
        let compactMacFloatingCard = !usesIPhoneDetailSizing && !plainBackground && !macExpandedCardShowsDetails
        #else
        let compactMacFloatingCard = false
        #endif
        let floatingTitleFont = compactMacFloatingCard ? Font.headline : Font.title3
        let floatingMetricFont = compactMacFloatingCard ? Font.caption2 : Font.caption
        let floatingTemperatureSize: CGFloat = compactMacFloatingCard ? 34 : 42
        let floatingIconSize: CGFloat = compactMacFloatingCard ? 24 : 30
        let floatingIconFrame = CGSize(width: compactMacFloatingCard ? 30 : 36, height: compactMacFloatingCard ? 28 : 32)
        let floatingForecastDotSize: CGFloat = compactMacFloatingCard ? 5.5 : 7
        let floatingSelectedForecastDotSize: CGFloat = compactMacFloatingCard ? 6.5 : 8
        let floatingHeaderBottomPadding: CGFloat = compactMacFloatingCard ? 8 : 14
        let floatingTemperatureBottomPadding: CGFloat = compactMacFloatingCard ? 8 : 14
        let floatingOuterHorizontalPadding: CGFloat = compactMacFloatingCard ? 20 : 14
        let floatingOuterTopPadding: CGFloat = compactMacFloatingCard ? 16 : 18
        let titleFont = usesIPhoneDetailSizing ? Font.title : (plainBackground ? Font.title2 : floatingTitleFont)
        #if os(macOS)
        let hidesMacInspectorBottomChrome = plainBackground
        #else
        let hidesMacInspectorBottomChrome = false
        #endif

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                if centersHeroContent {
                    Spacer(minLength: 0)
                }

                VStack(alignment: centersHeroContent ? .center : .leading, spacing: usesIPhoneDetailSizing ? 6 : 2) {
                    if usesIPhoneDetailSizing {
                        Text(iPadDebugLocalTimeText(for: cityWeather))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if !hideCityName {
                        Text(cityWeather.city.localizedName(locale: locale))
                            .font(titleFont.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    Text(metricLabel)
                        .font((usesIPhoneDetailSizing ? Font.callout : floatingMetricFont).weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: centersHeroContent ? 0 : 8)

                if !centersHeroContent {
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
            }
            .multilineTextAlignment(centersHeroContent ? .center : .leading)
            .padding(.bottom, usesIPhoneDetailSizing ? 10 : floatingHeaderBottomPadding)

            HStack(alignment: .center, spacing: usesIPhoneDetailSizing ? 2 : (compactMacFloatingCard ? 8 : 12)) {
                if centersHeroContent {
                    Spacer(minLength: 0)
                }

                Text(primaryText)
                    .font(.system(size: usesIPhoneDetailSizing ? 62 : floatingTemperatureSize, weight: .regular, design: .default))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .id("primary-\(selectedDayOffset)-\(primaryText)")
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.82).combined(with: .opacity),
                        removal: .scale(scale: 0.82).combined(with: .opacity)
                    ))

                Image(systemName: icon)
                    .font(.system(size: usesIPhoneDetailSizing ? 44 : floatingIconSize, weight: .medium))
                    .weatherIconStyle(for: icon)
                    .compatSymbolReplaceTransition()
                    .id("icon-\(selectedDayOffset)-\(icon)")
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.82).combined(with: .opacity),
                        removal: .scale(scale: 0.82).combined(with: .opacity)
                    ))
                    .frame(width: usesIPhoneDetailSizing ? 60 : floatingIconFrame.width, height: usesIPhoneDetailSizing ? 52 : floatingIconFrame.height)

                Spacer(minLength: centersHeroContent ? 0 : 8)
            }
            .padding(.bottom, usesIPhoneDetailSizing ? 18 : floatingTemperatureBottomPadding)
            .animation(.snappy(duration: 0.28), value: selectedDayOffset)

            if !usesIPhoneDetailSizing {
                Group {
                    if plainBackground {
                        Color.clear
                            .frame(height: 1)
                    } else {
                        macExpandedCardDivider
                    }
                }
                .padding(.bottom, 10)
            }

            VStack(spacing: usesIPhoneDetailSizing ? 10 : (usesDetailCardLayout ? 12 : (compactMacFloatingCard ? 5 : 8))) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(alignment: .top, spacing: usesIPhoneDetailSizing ? 12 : (compactMacFloatingCard ? 5 : 6)) {
                        ForEach(0..<5, id: \.self) { column in
                            let index = row * 5 + column
                            if index < forecasts.count {
                                let forecast = forecasts[index]
                                let representsNow = index == 0
                                let daySelectionOffset = representsNow ? -1 : index
                                let isSelectedDay = selectedDayOffset == daySelectionOffset
                                let dayCondition = representsNow ? cityWeather.condition : forecast.condition
                                let dayIcon = representsNow ? cityWeather.weatherIcon : forecast.weatherIcon
                                let dayDotColor = dayIcon.contains("moon") ? theme.colors.moonIconColor : dayCondition.dotColor
                                let dayTemperature = representsNow ? cityWeather.temperature : forecast.dailyHigh

                                Button {
                                    withAnimation(.snappy(duration: 0.24)) {
                                        selectedDayOffset = daySelectionOffset
                                    }
                                } label: {
                                    VStack(spacing: usesIPhoneDetailSizing ? 6 : 7) {
                                        Text(macForecastDayLabel(for: daySelectionOffset))
                                            .font((usesIPhoneDetailSizing ? Font.caption : Font.caption2).weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)

                                        Circle()
                                            .fill(dayDotColor)
                                            .frame(width: isSelectedDay ? (usesIPhoneDetailSizing ? 11 : floatingSelectedForecastDotSize) : (usesIPhoneDetailSizing ? 10 : floatingForecastDotSize), height: isSelectedDay ? (usesIPhoneDetailSizing ? 11 : floatingSelectedForecastDotSize) : (usesIPhoneDetailSizing ? 10 : floatingForecastDotSize))
                                            .shadow(color: dayDotColor.opacity(0.45), radius: 2)

                                        Text(tempUnit.display(dayTemperature))
                                            .font((usesIPhoneDetailSizing ? Font.headline : Font.caption).weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, usesIPhoneDetailSizing ? 6 : 0)
                                    .padding(.vertical, usesIPhoneDetailSizing ? 10 : 6)
                                    .contentShape(RoundedRectangle(cornerRadius: usesIPhoneDetailSizing ? 12 : 8, style: .continuous))
                                    .background {
                                        if isSelectedDay {
                                            RoundedRectangle(cornerRadius: usesIPhoneDetailSizing ? 12 : 8, style: .continuous)
                                                .fill(Color.primary.opacity(0.09))
                                                .matchedGeometryEffect(id: "detail-day-selection", in: detailDaySelectionNamespace)
                                        } else if macExpandedCardHoveredDay == index {
                                            RoundedRectangle(cornerRadius: usesIPhoneDetailSizing ? 12 : 8, style: .continuous)
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
            .padding(.horizontal, usesIPhoneDetailSizing ? 18 : (usesDetailCardLayout ? 12 : 0))
            .padding(.vertical, usesIPhoneDetailSizing ? 16 : (usesDetailCardLayout ? 12 : 0))
            .animation(.snappy(duration: 0.24), value: selectedDayOffset)
            .background {
                if usesDetailCardLayout {
                    RoundedRectangle(cornerRadius: detailCardCornerRadius, style: .continuous)
                        .fill(theme.colors.mapLand)
                }
            }
            .overlay {
                if usesDetailCardLayout {
                    RoundedRectangle(cornerRadius: detailCardCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }
            .padding(.bottom, usesIPhoneDetailSizing ? 18 : (usesDetailCardLayout ? 12 : (macExpandedCardShowsDetails ? 14 : 10)))

            if macExpandedCardShowsDetails {
                macExpandedCardDetails(for: cityWeather, forecast: selectedForecast, tempUnit: tempUnit, distUnit: distUnit, usesIPhoneDetailSizing: usesIPhoneDetailSizing, usesDetailCardLayout: usesDetailCardLayout)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !usesIPhoneDetailSizing && !hidesMacInspectorBottomChrome {
                VStack(spacing: 6) {
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
                                .frame(width: 32, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)

                        Spacer()
                    }

                    macExpandedCardDivider
                }
            }
        }
        }
        .padding(.horizontal, usesIPhoneDetailSizing ? 16 : floatingOuterHorizontalPadding)
        .padding(.top, usesIPhoneDetailSizing ? 24 : floatingOuterTopPadding)
        .padding(.bottom, usesIPhoneDetailSizing ? 8 : 8)
        .modifier(MapExpandedCardContainer(plainBackground: plainBackground, colorScheme: colorScheme))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private func chartContent(for cityWeather: CityWeather, forecast: DailyForecast, availableSize: CGSize) -> some View {
        let refreshKey = hourlyRefreshKey(for: cityWeather, dayOffset: forecast.dayOffset)
        let isRefreshingHourlyData = hourlyRefreshKeys.contains(refreshKey)

        if shouldRefreshHourlyData(for: cityWeather, forecast: forecast), isRefreshingHourlyData {
            ProgressView()
                .controlSize(.regular)
                .frame(width: availableSize.width, height: availableSize.height)
        } else if macExpandedCardChartRange == .tenDay {
            ScrollView(.horizontal, showsIndicators: false) {
                DailyTimelineChart(
                    dailyForecasts: cityWeather.dailyForecasts,
                    chartMetric: macExpandedCardChartMetric,
                    selectedDayOffset: selectedDayOffset,
                    cityTimeZone: cityWeather.timeZone,
                    lineColor: macExpandedCardChartLineColor(macExpandedCardChartMetric),
                    compactLayout: true
                )
                .frame(width: max(availableSize.width * 1.1, 270), height: availableSize.height)
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
                    compactLayout: true,
                    transitionDirection: detailChartSwipeDirection
                )
                .frame(width: entireDayChartWidth(for: forecast, availableWidth: availableSize.width), height: availableSize.height)
            }
            .task(id: refreshKey) {
                await refreshHourlyDataIfNeeded(for: cityWeather, forecast: forecast)
            }
        } else {
            HourlyTimelineChart(
                hourlyForecasts: forecast.hourlyForecasts,
                chartMetric: macExpandedCardChartMetric,
                dayOffset: max(0, selectedDayOffset),
                cityTimeZone: cityWeather.timeZone,
                previewCurrentHour: nil,
                lineColor: macExpandedCardChartLineColor(macExpandedCardChartMetric),
                compactLayout: true,
                transitionDirection: detailChartSwipeDirection,
                onHorizontalSwipe: { direction in
                    shiftExpandedCardChartDate(by: direction)
                }
            )
            .frame(width: availableSize.width, height: availableSize.height)
            .task(id: refreshKey) {
                await refreshHourlyDataIfNeeded(for: cityWeather, forecast: forecast)
            }
        }
    }

    private func entireDayChartWidth(for forecast: DailyForecast, availableWidth: CGFloat) -> CGFloat {
        let hourCount = max(forecast.hourlyForecasts.count, 24)
        return max(availableWidth * 2.4, CGFloat(hourCount) * 46)
    }

    private func iPadDebugLocalTimeText(for cityWeather: CityWeather) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = cityWeather.timeZone
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "j:mm z", options: 0, locale: locale)
        return "Local time: \(formatter.string(from: Date())) · \(cityWeather.timeZone.identifier)"
    }

    private func macExpandedCardAddMenu(for cityWeather: CityWeather) -> some View {
        Menu {
            ForEach(sidebarLists) { listID in
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
        distUnit: DistanceUnit,
        usesIPhoneDetailSizing: Bool = false,
        usesDetailCardLayout: Bool = false
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

        let detailCardCornerRadius: CGFloat = usesIPhoneDetailSizing ? 28 : 20
        #if os(macOS)
        let chartControlBottomPadding: CGFloat = usesDetailCardLayout ? 14 : 6
        #else
        let chartControlBottomPadding: CGFloat = usesIPhoneDetailSizing ? 0 : 6
        #endif

        return VStack(spacing: usesIPhoneDetailSizing ? 18 : (usesDetailCardLayout ? 12 : 8)) {
            VStack(alignment: .leading, spacing: 0) {
                if !usesDetailCardLayout {
                    macExpandedCardDivider
                        .padding(.bottom, 10)
                }

                HStack(spacing: usesIPhoneDetailSizing ? 12 : 8) {
                    macExpandedCardChartMetricMenu(usesIPhoneDetailSizing: usesIPhoneDetailSizing)
                    Spacer()
                    macExpandedCardChartRangeMenu(usesIPhoneDetailSizing: usesIPhoneDetailSizing)
                }
                .padding(.bottom, chartControlBottomPadding)

                GeometryReader { geo in
                    chartContent(
                        for: cityWeather,
                        forecast: forecast,
                        availableSize: geo.size
                    )
                }
                .frame(height: usesIPhoneDetailSizing ? 220 : 184)
                .clipped()

                if !usesDetailCardLayout {
                    macExpandedCardDivider
                        .padding(.top, -12)
                }
            }
            .padding(.horizontal, usesIPhoneDetailSizing ? 16 : (usesDetailCardLayout ? 12 : 0))
            .padding(.vertical, usesIPhoneDetailSizing ? 16 : (usesDetailCardLayout ? 12 : 0))
            .background {
                if usesDetailCardLayout {
                    RoundedRectangle(cornerRadius: detailCardCornerRadius, style: .continuous)
                        .fill(theme.colors.mapLand)
                }
            }
            .overlay {
                if usesDetailCardLayout {
                    RoundedRectangle(cornerRadius: detailCardCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }

            VStack(spacing: 0) {
                ForEach(rows, id: \.1) { icon, label, value in
                    HStack(spacing: usesIPhoneDetailSizing ? 12 : 10) {
                        Image(systemName: icon)
                            .font(.system(size: usesIPhoneDetailSizing ? 16 : 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: usesIPhoneDetailSizing ? 22 : 16)
                        Text(label)
                            .font((usesIPhoneDetailSizing ? Font.callout : Font.caption).weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(value)
                            .font((usesIPhoneDetailSizing ? Font.callout : Font.caption).weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, usesIPhoneDetailSizing ? 14 : 10)
                    .padding(.vertical, usesIPhoneDetailSizing ? 10 : 7)
                }

                if let sunrise = forecast.sunrise, let sunset = forecast.sunset {
                    HStack(spacing: usesIPhoneDetailSizing ? 12 : 10) {
                        Image(systemName: "sunrise.fill")
                            .font(.system(size: usesIPhoneDetailSizing ? 16 : 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: usesIPhoneDetailSizing ? 22 : 16)
                        Text(localizedString("Sun", locale: locale))
                            .font((usesIPhoneDetailSizing ? Font.callout : Font.caption).weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(macExpandedCardTime(sunrise, in: cityWeather.timeZone))
                            .font((usesIPhoneDetailSizing ? Font.callout : Font.caption).weight(.semibold))
                        Text("·")
                            .font((usesIPhoneDetailSizing ? Font.callout : Font.caption).weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(macExpandedCardTime(sunset, in: cityWeather.timeZone))
                            .font((usesIPhoneDetailSizing ? Font.callout : Font.caption).weight(.semibold))
                    }
                    .padding(.horizontal, usesIPhoneDetailSizing ? 14 : 10)
                    .padding(.vertical, usesIPhoneDetailSizing ? 10 : 7)
                }
            }
            .padding(.horizontal, usesIPhoneDetailSizing ? 8 : (usesDetailCardLayout ? 8 : 0))
            .padding(.vertical, usesIPhoneDetailSizing ? 10 : (usesDetailCardLayout ? 8 : 0))
            .background {
                if usesDetailCardLayout {
                    RoundedRectangle(cornerRadius: detailCardCornerRadius, style: .continuous)
                        .fill(theme.colors.mapLand)
                }
            }
            .overlay {
                if usesDetailCardLayout {
                    RoundedRectangle(cornerRadius: detailCardCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }
        }
    }

    private var macExpandedCardDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.75)
            .padding(.horizontal, -14)
    }

    private func macExpandedCardChartMetricMenu(usesIPhoneDetailSizing: Bool = false) -> some View {
        Menu {
            ForEach(macExpandedCardChartMetrics, id: \.0) { metric, icon, label in
                Button {
                    macExpandedCardChartMetric = metric
                } label: {
                    HStack {
                        if macExpandedCardChartMetric == metric {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.primary)
                                .frame(width: 14)
                        } else {
                            Color.clear.frame(width: 14)
                        }
                        Text(label)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: macExpandedCardChartMetricIcon(macExpandedCardChartMetric))
                    .font(.system(size: usesIPhoneDetailSizing ? 15 : 10, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(macExpandedCardChartMetricLabel(macExpandedCardChartMetric))
                    .font((usesIPhoneDetailSizing ? Font.callout : Font.caption2).weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: usesIPhoneDetailSizing ? 9 : 7, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(height: usesIPhoneDetailSizing ? 30 : 22)
            .padding(.horizontal, usesIPhoneDetailSizing ? 11 : 8)
            .background(Color.primary.opacity(0.07), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private func macExpandedCardChartRangeMenu(usesIPhoneDetailSizing: Bool = false) -> some View {
        Menu {
            ForEach(macExpandedCardChartRanges, id: \.0) { range, label in
                Button {
                    macExpandedCardChartRange = range
                } label: {
                    HStack {
                        if macExpandedCardChartRange == range {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.primary)
                                .frame(width: 14)
                        } else {
                            Color.clear.frame(width: 14)
                        }
                        Text(label)
                    }
                }
            }
        } label: {
            Text(macExpandedCardChartRangeLabel(macExpandedCardChartRange))
                .font(.system(size: usesIPhoneDetailSizing ? 15 : 10, weight: usesIPhoneDetailSizing ? .medium : .semibold))
                .lineLimit(1)
                .frame(height: usesIPhoneDetailSizing ? 30 : 22)
                .padding(.horizontal, usesIPhoneDetailSizing ? 11 : 8)
                .background(Color.primary.opacity(0.07), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var macExpandedCardChartRanges: [(WeatherChartTimeRange, String)] {
        [
            (.daytime, localizedString("Daytime", locale: locale)),
            (.entireDay, localizedString("Entire Day", locale: locale)),
            (.tenDay, localizedString("10 Days", locale: locale))
        ]
    }

    private var macExpandedCardChartMetrics: [(WeatherChartMetric, String, String)] {
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

    private func macExpandedCardChartMetricIcon(_ metric: WeatherChartMetric) -> String {
        macExpandedCardChartMetrics.first(where: { $0.0 == metric })?.1 ?? "chart.xyaxis.line"
    }

    private func macExpandedCardChartMetricLabel(_ metric: WeatherChartMetric) -> String {
        macExpandedCardChartMetrics.first(where: { $0.0 == metric })?.2 ?? localizedString("Forecast", locale: locale)
    }

    private func macExpandedCardChartRangeLabel(_ range: WeatherChartTimeRange) -> String {
        switch range {
        case .daytime: return localizedString("Daytime", locale: locale)
        case .entireDay: return localizedString("Entire Day", locale: locale)
        case .tenDay: return localizedString("10 Days", locale: locale)
        }
    }

    private func macExpandedCardChartLineColor(_ metric: WeatherChartMetric) -> Color {
        theme.colors.dotRain
    }

    private func shiftExpandedCardChartDate(by direction: Int) {
        let currentDay = max(0, selectedDayOffset)
        let nextDay = min(9, max(0, currentDay + direction))
        guard nextDay != selectedDayOffset else { return }
        detailChartSwipeDirection = direction
        dateSwitcherForward = direction > 0
        PlatformFeedback.lightImpact()
        withAnimation(.snappy(duration: 0.28)) {
            selectedDayOffset = nextDay
        }
    }

    private func macExpandedCardChartCurrentValue(
        for cityWeather: CityWeather,
        forecast: DailyForecast,
        metric: WeatherChartMetric,
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
                .modifier(MapGlassCardContainer(cornerRadius: 22, colorScheme: colorScheme))
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

#if os(iOS)
extension ContentView {
    var iOSMainOverlays: some View {
        AnyView(iOSFloatingMapCardOverlay)
    }

    private var iOSFloatingMapCardHorizontalPadding: CGFloat {
        if #available(iOS 26.0, *) {
            return 26
        } else {
            return 18
        }
    }

    private var iOSFloatingMapCardBottomPadding: CGFloat {
        if #available(iOS 26.0, *) {
            return 14
        } else {
            return 70
        }
    }

    private var iOSFloatingMapCardOverlay: some View {
        Group {
            if selectedTab == 1, !isMapSpecialMode, showingMapExpandedCard {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissMapExpandedCard()
                    }
                    .zIndex(10)
            }

            if selectedTab == 1, !isMapSpecialMode, showingMapExpandedCard, let city = tappedCity {
                mapExpandedCard(for: city, hideCityName: shouldHideInlineMapCardCityName)
                    .id(city.city.id)
                    .padding(.horizontal, iOSFloatingMapCardHorizontalPadding)
                    .padding(.vertical, shouldAddInlineMapCardVerticalPadding ? 8 : 0)
                    .padding(.bottom, iOSFloatingMapCardBottomPadding)
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

#endif
