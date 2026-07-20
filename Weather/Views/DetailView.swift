//
//  DetailView.swift
//  Weather
//
//  Purpose: Builds the city detail screen around sunniness: verdict, factors,
//  sunny hours, nearby comparisons, and the expanded weather card.
//

import SwiftUI
import MapKit
import UIKit

// MARK: - City Detail Routing

extension ContentView {
    func cityDetailView(for city: CityWeather) -> some View {
        cityDetailScrollContent(for: city)
            .background {
                theme.colors.background
                    .ignoresSafeArea()
            }
            .navigationTitle(localizedCityName(for: city.city))
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .tint(theme.colors.primaryText)
    }

    private func cityDetailScrollContent(for city: CityWeather) -> some View {
        GeometryReader { geometry in
            let usesLandscapeIPadLayout = usesIPadLandscapeLayout(for: geometry.size)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    detailSunninessReport(for: city, usesLandscapeIPadLayout: usesLandscapeIPadLayout)
                }
                .padding(.horizontal, detailViewHorizontalPadding)
                .padding(.top, detailViewTopPadding)
                .padding(.bottom, detailViewBottomPadding)
                .frame(maxWidth: detailViewMaxWidth(usesLandscapeIPadLayout: usesLandscapeIPadLayout))
                .frame(maxWidth: .infinity)
            }
        }
        .id(city.id)
        .transition(.opacity)
        .animation(.smooth(duration: 0.24), value: city.id)
        .scrollContentBackground(.hidden)
    }

    // MARK: Sunniness Report

    @ViewBuilder
    private func detailSunninessReport(
        for city: CityWeather,
        usesLandscapeIPadLayout: Bool
    ) -> some View {
        let detailForecastDate = selectedForecastDate
        if let forecast = city.forecastIfAvailable(on: detailForecastDate),
           let candidate = sunnyCandidate(for: city, on: detailForecastDate) {
            let icon = sunnyCandidateIcon(for: candidate)

            VStack(alignment: .leading, spacing: 14) {
                detailCityNameHeader(
                    city: city,
                    icon: icon,
                    condition: candidate.condition
                )

                detailSunnyFactorGrid(
                    city: city,
                    candidate: candidate,
                    forecast: forecast,
                    usesLandscapeIPadLayout: usesLandscapeIPadLayout
                )

                detailSunnyWindowOverview(city: city)

                // Unsaved search results are not part of a list-backed map data
                // source, so their Nearby Cities card is intentionally omitted.
                if weatherService.listContainingCity(city.city) != nil {
                    detailNearbyCities(city: city, selectedForecast: forecast)
                }
            }
        } else if let forecast = city.forecastIfAvailable(on: detailForecastDate) {
            let issue = SunninessScoring.condition(for: forecast.symbolName) == nil
                ? WeatherDataIssue.unknownWeatherSymbol(forecast.symbolName)
                : .missingCloudCoverData
            VStack(spacing: 16) {
                Text(localizedCityName(for: city.city))
                    .font(.system(.largeTitle, design: .serif).weight(.bold))
                    .foregroundStyle(theme.colors.titleText)

                WeatherDataUnavailableNotice(
                    message: weatherDataIssueMessage(
                        issue,
                        cityName: localizedCityName(for: city.city),
                        locale: locale
                    )
                )
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 16) {
                Text(localizedCityName(for: city.city))
                    .font(.system(.largeTitle, design: .serif).weight(.bold))
                    .foregroundStyle(theme.colors.titleText)

                if isExpectedForecastBoundaryOmission(
                    for: city,
                    among: mapCities,
                    on: detailForecastDate
                ) {
                    ForecastOmissionNotice(droppedCityCount: 1)
                } else {
                    WeatherDataUnavailableNotice(
                        message: weatherDataIssueMessage(
                            .missingForecastData,
                            cityName: localizedCityName(for: city.city),
                            locale: locale
                        )
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func detailCityNameHeader(
        city: CityWeather,
        icon: String,
        condition: AppWeatherCondition
    ) -> some View {
        let cityName = localizedCityName(for: city.city)
        let conditionName = condition.localizedDisplayName(locale: locale)

        return VStack(spacing: 9) {
            Text(cityName)
                .font(.system(.largeTitle, design: .serif).weight(.bold))
                .foregroundStyle(theme.colors.titleText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)

            Image(systemName: icon)
                .weatherIconStyle(for: icon)
                .font(.system(size: 52, weight: .semibold))
                .frame(width: 62, height: 58)
                .padding(.vertical, 8)

            Text(conditionName)
                .font(.callout)
                .foregroundStyle(theme.colors.primaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    private func detailSunnyFactorGrid(
        city: CityWeather,
        candidate: SunnyCandidate,
        forecast: DailyForecast,
        usesLandscapeIPadLayout: Bool
    ) -> some View {
        let rainChance = candidate.precipitationChance
        let uvIndex = forecast.uvIndex
        let sunnyHoursResult = SunninessScoring.sunnyHoursData(
            for: forecast,
            timeZone: city.timeZone
        )
        let cityName = localizedCityName(for: city.city)

        let columns: [GridItem]
        if usesLandscapeIPadLayout {
            // Adaptive sizing adds a third factor tile only when it can retain
            // a 200-point minimum width; narrower Stage Manager windows use two.
            columns = [GridItem(.adaptive(minimum: 200), spacing: 10)]
        } else {
            columns = [GridItem(.flexible()), GridItem(.flexible())]
        }

        return LazyVGrid(columns: columns, spacing: 10) {
            switch sunnyHoursResult {
            case .success(let sunnyHoursData):
                detailSunnyFactorTile(
                    title: localizedString("Sunny Hours", locale: locale),
                    value: detailSunnyWindowSummary(for: city, hours: sunnyHoursData.hours),
                    systemImage: "sun.max.fill",
                    tint: theme.colors.dotSun
                )
            case .failure(let issue):
                detailSunnyFactorIssueTile(
                    title: localizedString("Sunny Hours", locale: locale),
                    issue: issue,
                    cityName: cityName
                )
            }

            if let rainChance {
                detailSunnyFactorTile(
                    title: localizedString("Rain Chance", locale: locale),
                    value: "\(Int((rainChance * 100).rounded()))%",
                    systemImage: "drop.fill",
                    tint: theme.colors.accent
                )
            } else {
                detailSunnyFactorIssueTile(
                    title: localizedString("Rain Chance", locale: locale),
                    issue: .missingPrecipitationData,
                    cityName: cityName
                )
            }

            detailSunnyFactorTile(
                title: localizedString("Min Temp", locale: locale),
                value: tempUnit.display(forecast.dailyLow),
                systemImage: "thermometer.low",
                tint: theme.colors.accent
            )

            detailSunnyFactorTile(
                title: localizedString("Max Temp", locale: locale),
                value: tempUnit.display(forecast.dailyHigh),
                systemImage: "thermometer.high",
                tint: theme.colors.dotSun
            )

            if let uvIndex {
                detailSunnyFactorTile(
                    title: localizedString("UV Index", locale: locale),
                    value: String(uvIndex),
                    systemImage: "sun.max.trianglebadge.exclamationmark",
                    tint: theme.colors.dotSun
                )
            } else {
                detailSunnyFactorIssueTile(
                    title: localizedString("UV Index", locale: locale),
                    issue: .missingUVIndexData,
                    cityName: cityName
                )
            }

            if let cloudCoverPercent = forecast.cloudCoverPercent {
                detailSunnyFactorTile(
                    title: localizedString("Cloud Cover", locale: locale),
                    value: "\(cloudCoverPercent)%",
                    systemImage: "cloud",
                    tint: theme.colors.accent
                )
            } else {
                detailSunnyFactorIssueTile(
                    title: localizedString("Cloud Cover", locale: locale),
                    issue: .missingCloudCoverData,
                    cityName: cityName
                )
            }
        }
    }

    @ViewBuilder
    private func detailSunnyFactorTile(
        title: String,
        value: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        let tile = HStack(spacing: CityListLayout.columnSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)
        }

        tile
            .padding(12)
            .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: 18))
    }

    private func detailSunnyFactorIssueTile(
        title: String,
        issue: WeatherDataIssue,
        cityName: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.colors.secondaryText)

            WeatherDataUnavailableNotice(
                message: weatherDataIssueMessage(issue, cityName: cityName, locale: locale)
            )
        }
        .padding(12)
        .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: 18))
    }

    // MARK: Sunny Hours Overview

    private func detailSunnyWindowOverview(city: CityWeather) -> some View {
        let forecasts = Array(city.dailyForecasts.prefix(10))
        let resolvedData = detailSunnyWindowData(for: city, forecasts: forecasts)

        return VStack(alignment: .leading, spacing: 10) {
            detailSectionHeader(
                title: localizedString("Sunny Hours", locale: locale),
                systemImage: "sun.max.fill"
            )

            switch resolvedData {
            case .failure(let issue):
                WeatherDataUnavailableNotice(
                    message: weatherDataIssueMessage(
                        issue,
                        cityName: localizedCityName(for: city.city),
                        locale: locale
                    )
                )
            case .success(let days):
                let windows = detailSunnyWindowRows(for: city, days: days)
                let chartBounds = SunnyHoursChartBounds.merged(days.map(\.sunnyHours.bounds))

                if windows.isEmpty {
                    WeatherDataUnavailableNotice(
                        message: weatherDataIssueMessage(
                            .missingForecastData,
                            cityName: localizedCityName(for: city.city),
                            locale: locale
                        )
                    )
                } else if let chartBounds {
                    DetailSunnyWindowOverviewChart(
                        rows: windows,
                        selectedForecastDate: selectedForecastDate,
                        locale: locale,
                        timeZone: city.timeZone,
                        chartBounds: chartBounds,
                        sunnyColor: theme.colors.dotSun,
                        partlySunnyColor: theme.colors.dotPartlyCloudy,
                        trackColor: theme.colors.chartPanelFill,
                        gridColor: theme.colors.secondaryText.opacity(0.06),
                        primaryText: theme.colors.primaryText,
                        secondaryText: theme.colors.secondaryText,
                        onSelectDay: { date in
                            withAnimation(.smooth(duration: 0.2)) {
                                selectedForecastDate = date
                            }
                        }
                    )

                    sunnyWindowLegend
                } else {
                    WeatherDataUnavailableNotice(
                        message: weatherDataIssueMessage(
                            .missingSunriseOrSunset,
                            cityName: localizedCityName(for: city.city),
                            locale: locale
                        )
                    )
                }
            }
        }
        .padding(14)
        .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: 20))
    }

    private var sunnyWindowLegend: some View {
        HStack(spacing: 14) {
            sunnyWindowLegendItem(
                title: localizedString("Sunny", locale: locale),
                color: theme.colors.dotSun
            )
            sunnyWindowLegendItem(
                title: localizedString("Partly Sunny", locale: locale),
                color: theme.colors.dotPartlyCloudy
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
    }

    private func sunnyWindowLegendItem(title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Group {
                if differentiateWithoutColor, title == localizedString("Partly Sunny", locale: locale) {
                    Circle()
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                } else {
                    Circle()
                        .fill(color)
                }
            }
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.35), radius: 2)

            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
        }
    }

    // MARK: Nearby Cities

    private func detailNearbyCities(city: CityWeather, selectedForecast: DailyForecast) -> some View {
        let nearbyCities = detailNearbyCityContexts(for: city)

        return VStack(alignment: .leading, spacing: 10) {
            detailSectionHeader(
                title: localizedString("Nearby Cities", locale: locale),
                systemImage: "map.fill"
            )

            ZStack {
                DetailMapContextView(
                    selectedCity: city,
                    selectedForecast: selectedForecast,
                    nearbyCities: nearbyCities,
                    selectedCityName: localizedCityName(for: city.city),
                    nearbyCityNames: Dictionary(uniqueKeysWithValues: nearbyCities.map {
                        ($0.cityWeather.id, localizedCityName(for: $0.cityWeather.city))
                    }),
                    locale: locale,
                    accent: theme.colors.accent,
                    water: theme.colors.mapOcean
                )
                .allowsHitTesting(false)

                Button {
                    openDetailCityOnMap(city)
                } label: {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: detailNearbyMapHeight)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 0.6)
                    .allowsHitTesting(false)
            }

            if !nearbyCities.isEmpty {
                VStack(spacing: 6) {
                    ForEach(nearbyCities) { nearbyCity in
                        Button {
                            selectDetailNearbyCity(nearbyCity.cityWeather)
                        } label: {
                            detailNearbyCityRow(nearbyCity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: 20))
    }

    private func detailSectionHeader(title: String, systemImage: String) -> some View {
        HStack(spacing: CityListLayout.columnSpacing) {
            Image(systemName: systemImage)
                .frame(width: CityListLayout.rankColumnWidth, alignment: .leading)
            Text(title)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.headline.weight(.semibold))
        .foregroundStyle(theme.colors.primaryText)
    }

    @ViewBuilder
    private func detailNearbyCityRow(_ nearbyCity: DetailNearbyCityContext) -> some View {
        if let condition = SunninessScoring.condition(for: nearbyCity.forecast.symbolName) {
            let icon = condition.displayIcon
            HStack(spacing: CityListLayout.columnSpacing) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .nearbyCityIconStyle(for: icon)
                    .frame(width: CityListLayout.rankColumnWidth, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(localizedCityName(for: nearbyCity.cityWeather.city))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if nearbyCity.isSunnier {
                    Text(localizedString("Sunnier", locale: locale))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(theme.colors.dotSun.opacity(0.12), in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(width: 18, height: 24)
            }
            .padding(.horizontal, 10)
            .frame(height: 50)
            .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: 14))
        } else {
            WeatherDataUnavailableNotice(
                message: weatherDataIssueMessage(
                    .unknownWeatherSymbol(nearbyCity.forecast.symbolName),
                    cityName: localizedCityName(for: nearbyCity.cityWeather.city),
                    locale: locale
                )
            )
        }
    }

    // MARK: - Nearby City Data

    private func detailNearbyCityContexts(for city: CityWeather) -> [DetailNearbyCityContext] {
        let detailForecastDate = selectedForecastDate
        guard let selectedCandidate = sunnyCandidate(for: city, on: detailForecastDate) else { return [] }
        return mapCities
            .filter { $0.id != city.id }
            .sorted { detailDistance(from: city, to: $0) < detailDistance(from: city, to: $1) }
            .prefix(3)
            .compactMap { nearbyCity in
                guard let candidate = sunnyCandidate(for: nearbyCity, on: detailForecastDate),
                      let forecast = nearbyCity.forecastIfAvailable(on: detailForecastDate) else {
                    return nil
                }
                return DetailNearbyCityContext(
                    cityWeather: nearbyCity,
                    forecast: forecast,
                    isSunnier: isNearbyCandidate(candidate, sunnierThan: selectedCandidate)
                )
            }
    }

    private func isNearbyCandidate(_ nearby: SunnyCandidate, sunnierThan selected: SunnyCandidate) -> Bool {
        if nearby.condition.sunninessRank != selected.condition.sunninessRank {
            return nearby.condition.sunninessRank < selected.condition.sunninessRank
        }

        guard nearby.condition.isSunnyOrPartlySunny,
              selected.condition.isSunnyOrPartlySunny else {
            return false
        }

        return nearby.cloudCover < selected.cloudCover
    }

    private func detailDistance(from first: CityWeather, to second: CityWeather) -> CLLocationDistance {
        let firstLocation = CLLocation(latitude: first.city.latitude, longitude: first.city.longitude)
        let secondLocation = CLLocation(latitude: second.city.latitude, longitude: second.city.longitude)
        return firstLocation.distance(from: secondLocation)
    }

    private func selectDetailNearbyCity(_ city: CityWeather) {
        pushRoute(.cityDetail(city))
    }

    private func openDetailCityOnMap(_ city: CityWeather) {
        Task { @MainActor in
            if let listID = weatherService.listContainingCity(city.city) {
                await switchToList(listID)
            }

            guard let revealedCity = weatherService.cityWeatherData.first(where: {
                weatherService.citiesMatch($0.city, city.city)
            }) else {
                weatherService.reportDeveloperWarning(
                    title: "Map Reveal Failed",
                    message: "After switching lists, the requested city \(city.city.localizedName()) was not found in fetched weather data."
                )
                return
            }

            selectedMapCity = revealedCity
            showingMapExpandedCard = false
            navigateToMap()
            centerMap(on: revealedCity)
            showMapMarkerCard(revealedCity)
        }
    }

    // MARK: Sunny Hours Computation

    private struct DetailSunnyWindowDayData {
        let forecast: DailyForecast
        let sunnyHours: SunninessScoring.SunnyHoursData
    }

    fileprivate struct DetailSunnyWindowRow: Identifiable {
        let id: Date
        let dayLabel: String
        let sunnyRanges: [ClosedRange<Int>]
        let partlySunnyRanges: [ClosedRange<Int>]
    }

    private func detailSunnyWindowData(
        for city: CityWeather,
        forecasts: [DailyForecast]
    ) -> Result<[DetailSunnyWindowDayData], WeatherDataIssue> {
        guard !forecasts.isEmpty else {
            return .failure(.missingForecastData)
        }

        var days: [DetailSunnyWindowDayData] = []
        for forecast in forecasts {
            switch SunninessScoring.sunnyHoursData(for: forecast, timeZone: city.timeZone) {
            case .success(let sunnyHours):
                days.append(DetailSunnyWindowDayData(forecast: forecast, sunnyHours: sunnyHours))
            case .failure(let issue):
                return .failure(issue)
            }
        }
        return .success(days)
    }

    private func detailSunnyWindowRows(
        for city: CityWeather,
        days: [DetailSunnyWindowDayData]
    ) -> [DetailSunnyWindowRow] {
        days.compactMap { day in
            let forecast = day.forecast
            guard let selectionDate = city.selectionDate(for: forecast) else {
                return nil
            }
            let sunnyHours = day.sunnyHours.hours.compactMap { hour -> Int? in
                detailHourlySunnyLevel(hour) == 2 ? hour.hour(in: city.timeZone) : nil
            }
            let partlySunnyHours = day.sunnyHours.hours.compactMap { hour -> Int? in
                detailHourlySunnyLevel(hour) == 1 ? hour.hour(in: city.timeZone) : nil
            }
            return DetailSunnyWindowRow(
                id: selectionDate,
                dayLabel: detailSunnyDayLabel(
                    forecast: forecast,
                    selectionDate: selectionDate,
                    timeZone: city.timeZone
                ),
                sunnyRanges: SunnyHoursFormatting.contiguousRanges(in: sunnyHours),
                partlySunnyRanges: SunnyHoursFormatting.contiguousRanges(in: partlySunnyHours)
            )
        }
    }

    private func detailSunnyDayLabel(
        forecast: DailyForecast,
        selectionDate: Date,
        timeZone: TimeZone
    ) -> String {
        if Calendar.current.isDate(selectionDate, inSameDayAs: forecastDateToday) {
            return localizedString("Today", locale: locale)
        }
        var format = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(locale)
        format.timeZone = timeZone
        return forecast.date.formatted(format)
    }

    private func detailHourlySunnyLevel(_ hour: HourlyForecast) -> Int? {
        switch SunninessScoring.condition(for: hour.symbolName) {
        case .clear:
            return 2
        case .partlySunny:
            return 1
        case .partlyCloudy, .cloudy, .rain, .drizzle, .snow, .fog, .wind, .night:
            return 0
        case nil:
            return nil
        }
    }

    private func detailSunnyWindowSummary(for city: CityWeather, hours: [HourlyForecast]) -> String {
        guard let range = SunninessScoring.longestSunnyHourRange(in: hours, timeZone: city.timeZone) else {
            return localizedString("No Sun", locale: locale)
        }

        let start = SunninessScoring.compactHourLabel(range.lowerBound, locale: locale)
        let end = SunninessScoring.compactHourLabel(range.upperBound + 1, locale: locale)
        return "\(start) - \(end)"
    }

    // MARK: Detail Layout Metrics

    private var detailViewHorizontalPadding: CGFloat {
        16
    }

    // iPad: The larger screen can show meaningful nearby-city context instead of
    // the phone-height map excerpt. This applies in both portrait and landscape.
    private var detailNearbyMapHeight: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 260 : 190
    }

    private var detailViewTopPadding: CGFloat {
        20
    }

    private var detailViewBottomPadding: CGFloat {
        16
    }

    private func detailViewMaxWidth(usesLandscapeIPadLayout: Bool) -> CGFloat {
        // Give iPad landscape reports wider outer margins. Portrait and iPhone
        // windows retain the existing content width.
        usesLandscapeIPadLayout ? 680 : 760
    }

}

// MARK: - Sunny Hours Overview Chart

private struct DetailSunnyWindowOverviewChart: View {
    let rows: [ContentView.DetailSunnyWindowRow]
    let selectedForecastDate: Date
    let locale: Locale
    let timeZone: TimeZone
    let chartBounds: SunnyHoursChartBounds
    let sunnyColor: Color
    let partlySunnyColor: Color
    let trackColor: Color
    let gridColor: Color
    let primaryText: Color
    let secondaryText: Color
    let onSelectDay: (Date) -> Void
    // Replace color-only chart distinctions with line patterns
    // when the system's Differentiate Without Color setting is enabled.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var axisHours: [Int] { chartBounds.axisHours() }
    private var rowHeight: CGFloat { isIPad ? 32 : 26 }
    private var axisHeight: CGFloat { isIPad ? 24 : 20 }
    private var capsuleHeight: CGFloat { isIPad ? 14 : 12 }
    private var timelineLaneHeight: CGFloat { isIPad ? 22 : 18 }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            chart(currentDate: context.date)
        }
    }

    private func chart(currentDate: Date) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let labelWidth: CGFloat = 72
                let timelineWidth = max(geometry.size.width - labelWidth, 1)
                let rowsHeight = CGFloat(rows.count) * rowHeight

                VStack(spacing: 2) {
                    axisRow(labelWidth: labelWidth, timelineWidth: timelineWidth)
                    ZStack(alignment: .center) {
                        rowsView(labelWidth: labelWidth, timelineWidth: timelineWidth)
                        gridLines(labelWidth: labelWidth, timelineWidth: timelineWidth)
                            .allowsHitTesting(false)
                        currentTimeMarker(
                            at: currentDate,
                            labelWidth: labelWidth,
                            timelineWidth: timelineWidth
                        )
                        .allowsHitTesting(false)
                    }
                    .frame(height: rowsHeight)
                    .clipped()
                }
            }
            .frame(height: axisHeight + CGFloat(rows.count) * rowHeight)
        }
    }

    private func axisRow(labelWidth: CGFloat, timelineWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: labelWidth)
            ZStack(alignment: .leading) {
                ForEach(axisHours, id: \.self) { hour in
                    Text(SunnyHoursFormatting.chartHourLabel(hour))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(secondaryText)
                        .position(
                            x: chartBounds.xPosition(for: Double(hour), width: timelineWidth),
                            y: 8
                        )
                }
            }
            .frame(width: timelineWidth, height: axisHeight)
        }
    }

    private func gridLines(labelWidth: CGFloat, timelineWidth: CGFloat) -> some View {
        let rowsHeight = CGFloat(rows.count) * rowHeight
        let verticalInset = (timelineLaneHeight - capsuleHeight) / 2
        let gridHeight = max(rowsHeight - verticalInset * 2, 0)

        return HStack(spacing: 0) {
            Color.clear.frame(width: labelWidth)

            Path { path in
                for hour in axisHours {
                    let x = chartBounds.xPosition(for: Double(hour), width: timelineWidth)
                    path.move(to: CGPoint(x: x, y: verticalInset))
                    path.addLine(to: CGPoint(x: x, y: verticalInset + gridHeight))
                }
            }
            .stroke(gridColor, lineWidth: 1)
            .frame(width: timelineWidth, height: rowsHeight)
        }
        .frame(height: rowsHeight)
    }

    @ViewBuilder
    private func currentTimeMarker(
        at currentDate: Date,
        labelWidth: CGFloat,
        timelineWidth: CGFloat
    ) -> some View {
        let rowsHeight = CGFloat(rows.count) * rowHeight
        if containsCurrentLocalDay(at: currentDate),
           let markerX = chartBounds.currentTimeXPosition(
               at: currentDate,
               timeZone: timeZone,
               width: timelineWidth
           ) {
            HStack(spacing: 0) {
                Color.clear.frame(width: labelWidth)
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(primaryText.opacity(0.78))
                        .frame(width: 2, height: rowsHeight)
                        .offset(x: markerX - 1)
                }
                .frame(width: timelineWidth, height: rowsHeight, alignment: .leading)
            }
            .frame(height: rowsHeight)
        }
    }

    private func containsCurrentLocalDay(at currentDate: Date) -> Bool {
        var cityCalendar = Calendar.current
        cityCalendar.timeZone = timeZone
        let localComponents = cityCalendar.dateComponents(
            [.year, .month, .day],
            from: currentDate
        )
        guard let selectionDate = Calendar.current.date(from: localComponents) else {
            return false
        }
        return rows.contains {
            Calendar.current.isDate($0.id, inSameDayAs: selectionDate)
        }
    }

    private func rowsView(labelWidth: CGFloat, timelineWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                Button {
                    onSelectDay(row.id)
                } label: {
                    HStack(spacing: 0) {
                        dayLabel(row)
                            .frame(width: labelWidth, alignment: .leading)

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(trackColor)
                                .frame(height: capsuleHeight)

                            ForEach(
                                SunnyHoursTimelineLayout.spans(
                                    sunnyRanges: row.sunnyRanges,
                                    partlySunnyRanges: row.partlySunnyRanges
                                )
                            ) { span in
                                let spanStartX = chartBounds.xPosition(
                                    for: Double(span.range.lowerBound),
                                    width: timelineWidth
                                )

                                ZStack(alignment: .leading) {
                                    ForEach(span.segments) { segment in
                                        Rectangle()
                                            .fill(segment.isPartlySunny ? partlySunnyColor : sunnyColor)
                                            .frame(
                                                width: chartBounds.width(
                                                    for: segment.range,
                                                    timelineWidth: timelineWidth
                                                ),
                                                height: capsuleHeight
                                            )
                                            .overlay {
                                                if differentiateWithoutColor {
                                                    // Solid and dashed outlines distinguish
                                                    // sunny and partly sunny intervals without relying on hue.
                                                    Rectangle()
                                                        .stroke(
                                                            primaryText.opacity(0.82),
                                                            style: StrokeStyle(
                                                                lineWidth: 1,
                                                                dash: segment.isPartlySunny ? [2, 2] : []
                                                            )
                                                        )
                                                }
                                            }
                                            .offset(
                                                x: chartBounds.xPosition(
                                                    for: Double(segment.range.lowerBound),
                                                    width: timelineWidth
                                                ) - spanStartX
                                            )
                                    }
                                }
                                .frame(
                                    width: chartBounds.width(
                                        for: span.range,
                                        timelineWidth: timelineWidth
                                    ),
                                    height: capsuleHeight,
                                    alignment: .leading
                                )
                                .clipShape(Capsule())
                                .offset(x: spanStartX)
                            }
                        }
                        .frame(width: timelineWidth, height: timelineLaneHeight)
                    }
                    .frame(height: rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Chart Labels and Formatting

    private func dayLabel(_ row: ContentView.DetailSunnyWindowRow) -> some View {
        let isSelected = Calendar.current.isDate(row.id, inSameDayAs: selectedForecastDate)

        return Text(row.dayLabel)
            .font(.caption.weight(isSelected ? .bold : .medium))
            .foregroundStyle(isSelected ? primaryText : secondaryText)
            .lineLimit(1)
    }

}

// MARK: - Nearby Map Context Models

private struct DetailNearbyCityContext: Identifiable {
    let cityWeather: CityWeather
    let forecast: DailyForecast
    let isSunnier: Bool

    var id: UUID { cityWeather.id }
}

private struct DetailMapContextView: View {
    let selectedCity: CityWeather
    let selectedForecast: DailyForecast
    let nearbyCities: [DetailNearbyCityContext]
    let selectedCityName: String
    let nearbyCityNames: [UUID: String]
    let locale: Locale
    let accent: Color
    let water: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.appTheme) private var theme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var cameraPosition: MapCameraPosition = .automatic
    private let mapSaturation: Double = 0.72

    // Allow map labels and their padding to grow with Dynamic Type
    // while keeping the compact marker treatment at the default text size.
    private var usesExpandedMarkers: Bool {
        dynamicTypeSize > .large
    }

    private var selectedMarkerHorizontalPadding: CGFloat {
        usesExpandedMarkers ? 12 : 9
    }

    private var selectedMarkerVerticalPadding: CGFloat {
        usesExpandedMarkers ? 8 : 6
    }

    private var nearbyMarkerHorizontalPadding: CGFloat {
        usesExpandedMarkers ? 10 : 7
    }

    private var nearbyMarkerVerticalPadding: CGFloat {
        usesExpandedMarkers ? 7 : 5
    }

    private var markerSpacing: CGFloat {
        usesExpandedMarkers ? 7 : 5
    }

    private var markerSaturationCompensation: Double {
        mapSaturation == 0 ? 1 : 1 / mapSaturation
    }

    private var displayedCities: [CityWeather] {
        [selectedCity] + nearbyCities.map(\.cityWeather)
    }

    var body: some View {
        Map(position: $cameraPosition, interactionModes: []) {
            Annotation(
                "",
                coordinate: CLLocationCoordinate2D(latitude: selectedCity.city.latitude, longitude: selectedCity.city.longitude),
                anchor: .center
            ) {
                selectedCityMarker
            }

            ForEach(nearbyCities) { nearbyCity in
                Annotation(
                    "",
                    coordinate: CLLocationCoordinate2D(latitude: nearbyCity.cityWeather.city.latitude, longitude: nearbyCity.cityWeather.city.longitude),
                    anchor: .center
                ) {
                    nearbyWeatherMarker(for: nearbyCity)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .saturation(mapSaturation)
        .background(water)
        .onAppear {
            fitCities()
        }
        .onChange(of: displayedCities.map(\.id)) { _, _ in
            fitCities()
        }
    }

    @ViewBuilder
    private var selectedCityMarker: some View {
        if let condition = SunninessScoring.condition(for: selectedForecast.symbolName) {
            let icon = condition.displayIcon
            HStack(spacing: markerSpacing) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .nearbyCityIconStyle(for: icon)

                Text(selectedCityName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, selectedMarkerHorizontalPadding)
            .padding(.vertical, selectedMarkerVerticalPadding)
            .background {
                if colorSchemeContrast == .increased {
                    Capsule().fill(theme.colors.glassFill)
                } else {
                    Capsule().fill(.thinMaterial)
                }
            }
            .overlay {
                Capsule()
                    .stroke(
                        colorSchemeContrast == .increased ? theme.colors.primaryText : accent.opacity(0.50),
                        lineWidth: 2
                    )
            }
            .shadow(color: accent.opacity(0.20), radius: 8, y: 2)
            .saturation(markerSaturationCompensation)
        } else {
            missingSymbolMarker()
        }
    }

    @ViewBuilder
    private func nearbyWeatherMarker(for nearbyCity: DetailNearbyCityContext) -> some View {
        let cityName = nearbyCityNames[nearbyCity.cityWeather.id]
            ?? localizedCityDisplayName(for: nearbyCity.cityWeather.city, locale: locale)
        if let condition = SunninessScoring.condition(for: nearbyCity.forecast.symbolName) {
            let icon = condition.displayIcon
            HStack(spacing: markerSpacing) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .nearbyCityIconStyle(for: icon)

                Text(cityName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)

            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, nearbyMarkerHorizontalPadding)
            .padding(.vertical, nearbyMarkerVerticalPadding)
            .background {
                if colorSchemeContrast == .increased {
                    Capsule().fill(theme.colors.glassFill)
                } else {
                    Capsule().fill(.thinMaterial)
                }
            }
            .overlay {
                if colorSchemeContrast == .increased {
                    Capsule().stroke(theme.colors.primaryText, lineWidth: 1.5)
                }
            }
            .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
            .saturation(markerSaturationCompensation)
        } else {
            missingSymbolMarker()
        }
    }

    private func missingSymbolMarker() -> some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(theme.colors.destructive)
            .padding(9)
            .background(.thinMaterial, in: Circle())
            .overlay {
                Circle().stroke(theme.colors.destructive.opacity(0.7), lineWidth: 1.5)
            }
            .saturation(markerSaturationCompensation)
    }

    private func fitCities() {
        let sourceCities = displayedCities.isEmpty ? [selectedCity] : displayedCities
        let points = sourceCities.map {
            MKMapPoint(CLLocationCoordinate2D(latitude: $0.city.latitude, longitude: $0.city.longitude))
        }
        let unionRect = points.reduce(MKMapRect.null) { rect, point in
            rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        let fittedRect = sourceCities.count == 1
            ? unionRect.insetBy(dx: -80_000, dy: -80_000)
            : unionRect.insetBy(dx: -max(unionRect.width * 0.22, 52_000), dy: -max(unionRect.height * 0.22, 52_000))
        cameraPosition = .rect(fittedRect)
    }
}

private extension View {
    @ViewBuilder
    func nearbyCityIconStyle(for iconName: String) -> some View {
        self.weatherIconStyle(for: iconName)
    }
}

private let detailPreviewCity: CityWeather = {
    let city = City(
        name: "Barcelona",
        country: "Spain",
        latitude: 41.3874,
        longitude: 2.1686,
        timeZoneIdentifier: "Europe/Madrid"
    )
    let forecasts = (0..<10).map { detailPreviewForecast(dayOffset: $0) }

    return CityWeather(
        city: city,
        temperature: 28,
        dailyForecasts: forecasts,
        timeZone: TimeZone(identifier: "Europe/Madrid") ?? .current
    )
}()

private func detailPreviewForecast(dayOffset: Int) -> DailyForecast {
    let cloudPattern: [[Double]] = [
        [0.18, 0.28, 0.41, 0.72, 0.86, 0.90, 0.95, 0.83],
        [0.02, 0.06, 0.10, 0.26, 0.53, 0.46, 0.52, 0.27],
        [0.12, 0.14, 0.20, 0.33, 0.62, 0.74, 0.70, 0.49],
        [0.58, 0.64, 0.72, 0.80, 0.85, 0.78, 0.66, 0.60],
        [0.08, 0.09, 0.14, 0.22, 0.25, 0.18, 0.16, 0.20],
        [0.44, 0.38, 0.32, 0.28, 0.36, 0.42, 0.50, 0.48],
        [0.76, 0.70, 0.64, 0.60, 0.58, 0.62, 0.70, 0.74],
        [0.18, 0.16, 0.12, 0.15, 0.20, 0.28, 0.35, 0.42],
        [0.28, 0.24, 0.18, 0.20, 0.34, 0.44, 0.38, 0.30],
        [0.68, 0.55, 0.40, 0.34, 0.28, 0.30, 0.46, 0.58]
    ]
    let axisHours = [6, 8, 10, 12, 14, 16, 18, 20]
    let selectedPattern = cloudPattern[dayOffset % cloudPattern.count]
    let pairedClouds = Dictionary(uniqueKeysWithValues: zip(axisHours, selectedPattern))
    let baseDate = Calendar.current.startOfDay(for: Date())
    let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: baseDate) ?? baseDate
    let hourly = (0..<24).map { hour -> HourlyForecast in
        let nearestAxisHour = axisHours.min { abs($0 - hour) < abs($1 - hour) } ?? 12
        let cloud = pairedClouds[nearestAxisHour] ?? 0.4
        let symbol: String
        if hour < 6 || hour > 21 {
            symbol = cloud > 0.55 ? "cloud.moon" : "moon.fill"
        } else if cloud < 0.28 {
            symbol = "sun.max.fill"
        } else if cloud < 0.62 {
            symbol = "cloud.sun"
        } else {
            symbol = "cloud"
        }

        return HourlyForecast(
            date: Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date,
            symbolName: symbol
        )
    }

    let averageCloud = selectedPattern.reduce(0, +) / Double(selectedPattern.count)
    let sunnyDay = averageCloud < 0.42
    let symbol = sunnyDay ? "sun.max.fill" : averageCloud < 0.65 ? "cloud.sun" : "cloud"

    return DailyForecast(
        date: date,
        dayOffset: dayOffset,
        dailyLow: 20 + Double(dayOffset % 3),
        dailyHigh: 28 + Double(dayOffset % 6),
        symbolName: symbol,
        hourlyForecasts: hourly,
        cloudCover: averageCloud,
        precipitationChance: averageCloud > 0.70 ? 0.22 : 0.04,
        uvIndex: sunnyDay ? 8 : 5,
        sunrise: Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: date),
        sunset: Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: date)
    )
}

#Preview("Detail View") {
    ContentView(initialRoute: .cityDetail(detailPreviewCity))
}
