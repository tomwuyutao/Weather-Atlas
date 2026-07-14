//
//  DetailView.swift
//  Weather
//
//  Purpose: Builds the city detail screen around sunniness: verdict, factors,
//  sunny hours, nearby comparisons, and the expanded weather card.
//

import SwiftUI
import MapKit

// MARK: - City Detail Routing

extension ContentView {
    func cityDetailView(for city: CityWeather) -> some View {
        cityDetailScrollContent(for: city)
            .background {
                theme.colors.background
                    .ignoresSafeArea()
            }
            // Accessibility: The navigation bar is visually hidden, but a
            // meaningful title still identifies this destination semantically.
            .navigationTitle(localizedCityName(for: city.city))
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .tint(theme.colors.primaryText)
    }

    private func cityDetailScrollContent(for city: CityWeather) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                detailSunninessReport(for: city)
            }
            .padding(.horizontal, detailViewHorizontalPadding)
            .padding(.top, detailViewTopPadding)
            .padding(.bottom, detailViewBottomPadding)
            .frame(maxWidth: detailViewMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .id(city.id)
        .transition(.opacity)
        .animation(.smooth(duration: 0.24), value: city.id)
        .scrollContentBackground(.hidden)
    }

    // MARK: Sunniness Report

    private func detailSunninessReport(for city: CityWeather) -> some View {
        let candidate = sunnyCandidate(for: city)
        let forecast = city.forecast(for: selectedDayOffset)
        let icon = sunnyCandidateIcon(for: candidate)

        return VStack(alignment: .leading, spacing: 14) {
            detailCityNameHeader(
                city: city,
                icon: icon,
                symbolName: forecast.symbolName
            )

            detailSunnyFactorGrid(city: city, candidate: candidate, forecast: forecast)

            detailSunnyWindowOverview(city: city)

            detailNearbyCities(city: city)
        }
    }

    private func detailCityNameHeader(city: CityWeather, icon: String, symbolName: String) -> some View {
        let cityName = localizedCityName(for: city.city)
        let condition = detailConditionText(for: symbolName)

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
                .accessibilityHidden(true)

            Text(condition)
                .font(.callout)
                .foregroundStyle(theme.colors.primaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cityName)
        .accessibilityValue(condition)
        .accessibilityAddTraits(.isHeader)
    }

    private func detailConditionText(for symbolName: String) -> String {
        SunninessScoring.condition(for: symbolName).localizedDisplayName(locale: locale)
    }

    private func detailSunnyFactorGrid(
        city: CityWeather,
        candidate: SunnyCandidate,
        forecast: DailyForecast
    ) -> some View {
        let rainChance = candidate.precipitationChance
        let uvIndex = forecast.uvIndex
        let selectedHours = detailDisplayHours(for: city, forecast: forecast, filtersPastToday: false)

        // Accessibility: Factor tiles become a single column so their labels and
        // values remain readable at accessibility Dynamic Type sizes.
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]

        return LazyVGrid(columns: columns, spacing: 10) {
            detailSunnyFactorTile(
                title: localizedString("Sunny Hours", locale: locale),
                value: detailSunnyWindowSummary(for: city, hours: selectedHours),
                systemImage: "sun.max.fill",
                tint: theme.colors.dotSun
            )

            detailSunnyFactorTile(
                title: localizedString("Rain", locale: locale),
                value: rainChance.map { "\(Int($0 * 100))%" } ?? "-",
                systemImage: "drop.fill",
                tint: theme.colors.accent
            )

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

            detailSunnyFactorTile(
                title: localizedString("UV Index", locale: locale),
                value: uvIndex.map(String.init) ?? "-",
                systemImage: "sun.max.trianglebadge.exclamationmark",
                tint: theme.colors.dotSun
            )

            detailSunnyFactorTile(
                title: localizedString("Cloud Cover", locale: locale),
                value: forecast.cloudCoverPercent.map { "\($0)%" } ?? "-",
                systemImage: "cloud",
                tint: theme.colors.accent
            )
        }
    }

    @ViewBuilder
    private func detailSunnyFactorTile(
        title: String,
        value: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        // Accessibility: Replace the visual placeholder with a spoken explanation
        // while leaving the compact dash unchanged on screen.
        let accessibilityValue = value == "-"
            ? localizedString("No forecast", locale: locale)
            : value
        let tile = HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
                .accessibilityHidden(true)

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
            // Accessibility: Expose each visual tile as one concise label/value pair.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(accessibilityValue)
    }

    // MARK: Sunny Hours Overview

    private func detailSunnyWindowOverview(city: CityWeather) -> some View {
        let windows = detailSunnyWindowRows(for: city)
        return VStack(alignment: .leading, spacing: 10) {
            detailSectionHeader(
                title: localizedString("Sunny Hours", locale: locale),
                systemImage: "sun.max.fill"
            )

            if windows.isEmpty {
                Text(localizedString("No hourly data", locale: locale))
                    .font(.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                DetailSunnyWindowOverviewChart(
                    rows: windows,
                    selectedDayOffset: selectedDayOffset,
                    locale: locale,
                    timeZone: city.timeZone,
                    sunnyColor: theme.colors.dotSun,
                    partlySunnyColor: theme.colors.dotPartlyCloudy,
                    trackColor: theme.colors.chartPanelFill,
                    gridColor: theme.colors.secondaryText.opacity(0.06),
                    primaryText: theme.colors.primaryText,
                    secondaryText: theme.colors.secondaryText,
                    onSelectDay: { dayOffset in
                        withAnimation(.smooth(duration: 0.2)) {
                            selectedDayOffset = dayOffset
                        }
                    }
                )

                sunnyWindowLegend
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
        // Accessibility: Each chart row already describes both sunny states and
        // their ranges, so hiding the visual key avoids duplicate announcements.
        .accessibilityHidden(true)
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

    private func detailNearbyCities(city: CityWeather) -> some View {
        let nearbyCities = detailNearbyCityContexts(for: city)

        return VStack(alignment: .leading, spacing: 10) {
            detailSectionHeader(
                title: localizedString("Nearby Cities", locale: locale),
                systemImage: "map.fill"
            )

            ZStack {
                DetailMapContextView(
                    selectedCity: city,
                    nearbyCities: nearbyCities,
                    selectedCityName: localizedCityName(for: city.city),
                    nearbyCityNames: Dictionary(uniqueKeysWithValues: nearbyCities.map {
                        ($0.cityWeather.id, localizedCityName(for: $0.cityWeather.city))
                    }),
                    selectedDayOffset: selectedDayOffset,
                    locale: locale,
                    accent: theme.colors.accent,
                    water: theme.colors.mapOcean
                )
                .allowsHitTesting(false)
                // Accessibility: The map image is represented by the full-card
                // semantic button layered immediately below.
                .accessibilityHidden(true)

                Button {
                    openDetailCityOnMap(city)
                } label: {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localizedCityName(for: city.city))
                .accessibilityValue(localizedString("Maps", locale: locale))
                .accessibilityInputLabels([Text(localizedCityName(for: city.city))])
                .accessibilityHint(localizedString("Opens map", locale: locale))
            }
            .frame(height: 190)
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
                        // Accessibility: Apply semantics to the actionable Button
                        // itself so Voice Control uses the visibly rendered city name.
                        .accessibilityLabel(localizedCityName(for: nearbyCity.cityWeather.city))
                        .accessibilityValue(detailNearbyCityAccessibilityValue(nearbyCity))
                        .accessibilityInputLabels([
                            Text(localizedCityName(for: nearbyCity.cityWeather.city))
                        ])
                    }
                }
            }
        }
        .padding(14)
        .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: 20))
    }

    private func detailSectionHeader(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline.weight(.semibold))
            .foregroundStyle(theme.colors.primaryText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }

    private func detailNearbyCityRow(_ nearbyCity: DetailNearbyCityContext) -> some View {
        let icon = nearbyCityWeatherIcon(for: nearbyCity.cityWeather)
        return HStack(spacing: CityListLayout.columnSpacing) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .nearbyCityIconStyle(for: icon)
                .frame(width: CityListLayout.rankColumnWidth, height: 24)
                .accessibilityHidden(true)

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
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
        .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localizedCityName(for: nearbyCity.cityWeather.city))
        .accessibilityValue(detailNearbyCityAccessibilityValue(nearbyCity))
    }

    // MARK: - Accessibility - Nearby City Descriptions

    private func detailNearbyCityAccessibilityValue(_ nearbyCity: DetailNearbyCityContext) -> String {
        let forecast = nearbyCity.cityWeather.forecast(for: selectedDayOffset)
        let condition = SunninessScoring.condition(for: forecast.symbolName).localizedDisplayName(locale: locale)
        guard nearbyCity.isSunnier else { return condition }
        return "\(condition), \(localizedString("Sunnier", locale: locale))"
    }

    // MARK: - Nearby City Data

    private func nearbyCityWeatherIcon(for city: CityWeather) -> String {
        city.forecast(for: selectedDayOffset).weatherIcon
    }

    private func detailNearbyCityContexts(for city: CityWeather) -> [DetailNearbyCityContext] {
        let selectedCandidate = sunnyCandidate(for: city)
        return mapCities
            .filter { $0.id != city.id }
            .sorted { detailDistance(from: city, to: $0) < detailDistance(from: city, to: $1) }
            .prefix(3)
            .map { nearbyCity in
                let candidate = sunnyCandidate(for: nearbyCity)
                return DetailNearbyCityContext(
                    cityWeather: nearbyCity,
                    isSunnier: isNearbyCandidate(candidate, sunnierThan: selectedCandidate)
                )
            }
    }

    private func isNearbyCandidate(_ nearby: SunnyCandidate, sunnierThan selected: SunnyCandidate) -> Bool {
        if nearby.condition.sunninessRank != selected.condition.sunninessRank {
            return nearby.condition.sunninessRank < selected.condition.sunninessRank
        }

        guard nearby.condition.isSunnyOrPartlySunny,
              selected.condition.isSunnyOrPartlySunny,
              let nearbyCloud = nearby.cloudCover,
              let selectedCloud = selected.cloudCover else {
            return false
        }

        return nearbyCloud < selectedCloud
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
                abs($0.city.latitude - city.city.latitude) < 0.001
                    && abs($0.city.longitude - city.city.longitude) < 0.001
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

    private func detailDisplayHours(for city: CityWeather, forecast: DailyForecast) -> [HourlyForecast] {
        detailDisplayHours(for: city, forecast: forecast, filtersPastToday: false)
    }

    private func detailDisplayHours(for city: CityWeather, forecast: DailyForecast, filtersPastToday: Bool) -> [HourlyForecast] {
        let currentHour: Int? = {
            guard filtersPastToday && forecast.dayOffset == 0 else { return nil }
            var calendar = Calendar.current
            calendar.timeZone = city.timeZone
            return calendar.component(.hour, from: Date())
        }()
        return forecast.hourlyForecasts
            .filter { forecast in
                let hour = forecast.hour(in: city.timeZone)
                guard (6...21).contains(hour) else { return false }
                if let currentHour {
                    return hour >= currentHour
                }
                return true
            }
            .sorted { $0.date < $1.date }
    }

    // MARK: Sunny Hours Computation

    fileprivate struct DetailSunnyWindowRow: Identifiable {
        let id: Int
        let dayLabel: String
        let sunnyRanges: [ClosedRange<Int>]
        let partlySunnyRanges: [ClosedRange<Int>]
    }

    private func detailSunnyWindowRows(for city: CityWeather) -> [DetailSunnyWindowRow] {
        (0..<10).compactMap { dayOffset in
            let forecast = city.forecast(for: dayOffset)
            let daylightHours = SunninessScoring.daytimeHours(for: forecast, timeZone: city.timeZone)
            let sunnyHours = daylightHours.compactMap { hour -> Int? in
                detailHourlySunnyLevel(hour) == 2 ? hour.hour(in: city.timeZone) : nil
            }
            let partlySunnyHours = daylightHours.compactMap { hour -> Int? in
                detailHourlySunnyLevel(hour) == 1 ? hour.hour(in: city.timeZone) : nil
            }
            return DetailSunnyWindowRow(
                id: dayOffset,
                dayLabel: detailSunnyDayLabel(dayOffset: dayOffset, timeZone: city.timeZone),
                sunnyRanges: SunninessScoring.contiguousHourRanges(sunnyHours),
                partlySunnyRanges: SunninessScoring.contiguousHourRanges(partlySunnyHours)
            )
        }
    }

    private func detailSunnyDayLabel(dayOffset: Int, timeZone: TimeZone) -> String {
        if dayOffset == 0 {
            return localizedString("Today", locale: locale)
        }
        var format = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(locale)
        format.timeZone = timeZone
        return forecastDate(dayOffset: dayOffset, timeZone: timeZone).formatted(format)
    }

    private func forecastDate(dayOffset: Int, timeZone: TimeZone) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
    }

    private func detailHourlySunnyLevel(_ hour: HourlyForecast) -> Int {
        switch SunninessScoring.condition(for: hour.symbolName) {
        case .clear:
            return 2
        case .partlySunny:
            return 1
        default:
            return 0
        }
    }

    private func detailSunnyWindowSummary(for city: CityWeather, hours: [HourlyForecast]) -> String {
        guard let range = SunninessScoring.longestSunnyHourRange(in: hours, timeZone: city.timeZone) else {
            return localizedString("No Sun", locale: locale)
        }

        let start = SunninessScoring.formattedHour(range.lowerBound, timeZone: city.timeZone, locale: locale)
        let end = SunninessScoring.formattedHour(range.upperBound + 1, timeZone: city.timeZone, locale: locale)
        return "\(start) - \(end)"
    }

    // MARK: Detail Layout Metrics

    private var detailViewHorizontalPadding: CGFloat {
        16
    }

    private var detailViewTopPadding: CGFloat {
        20
    }

    private var detailViewBottomPadding: CGFloat {
        16
    }

    private var detailViewMaxWidth: CGFloat? {
        nil
    }

}

// MARK: - Sunny Hours Overview Chart

private struct DetailSunnyWindowOverviewChart: View {
    let rows: [ContentView.DetailSunnyWindowRow]
    let selectedDayOffset: Int
    let locale: Locale
    let timeZone: TimeZone
    let sunnyColor: Color
    let partlySunnyColor: Color
    let trackColor: Color
    let gridColor: Color
    let primaryText: Color
    let secondaryText: Color
    let onSelectDay: (Int) -> Void
    // Accessibility: Replace color-only chart distinctions with line patterns
    // when the system's Differentiate Without Color setting is enabled.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private let axisHours = [6, 8, 10, 12, 14, 16, 18, 20]
    private let timelineStartHour = 6.0
    private let timelineEndHour = 21.0
    private let rowHeight: CGFloat = 26
    private let axisHeight: CGFloat = 20
    private let capsuleHeight: CGFloat = 12
    private let timelineLaneHeight: CGFloat = 18

    private struct TimelineSegment: Identifiable {
        let id: String
        let range: ClosedRange<Int>
        let color: Color
        let isPartlySunny: Bool
    }

    private struct TimelineSpan: Identifiable {
        let id: String
        let range: ClosedRange<Int>
        let segments: [TimelineSegment]
    }

    var body: some View {
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
                    Text(formattedAxisHour(hour))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(secondaryText)
                        .position(
                            x: xPosition(for: Double(hour), width: timelineWidth),
                            y: 8
                        )
                }
            }
            .frame(width: timelineWidth, height: axisHeight)
        }
        .accessibilityHidden(true)
    }

    private func gridLines(labelWidth: CGFloat, timelineWidth: CGFloat) -> some View {
        let rowsHeight = CGFloat(rows.count) * rowHeight
        let verticalInset = (timelineLaneHeight - capsuleHeight) / 2
        let gridHeight = max(rowsHeight - verticalInset * 2, 0)

        return HStack(spacing: 0) {
            Color.clear.frame(width: labelWidth)

            Path { path in
                for hour in axisHours {
                    let x = xPosition(for: Double(hour), width: timelineWidth)
                    path.move(to: CGPoint(x: x, y: verticalInset))
                    path.addLine(to: CGPoint(x: x, y: verticalInset + gridHeight))
                }
            }
            .stroke(gridColor, lineWidth: 1)
            .frame(width: timelineWidth, height: rowsHeight)
        }
        .frame(height: rowsHeight)
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

                            ForEach(timelineSpans(for: row)) { span in
                                let spanStartX = xPosition(for: Double(span.range.lowerBound), width: timelineWidth)

                                ZStack(alignment: .leading) {
                                    ForEach(span.segments) { segment in
                                        Rectangle()
                                            .fill(segment.color)
                                            .frame(
                                                width: rangeWidth(for: segment.range, timelineWidth: timelineWidth),
                                                height: capsuleHeight
                                            )
                                            .overlay {
                                                if differentiateWithoutColor {
                                                    // Accessibility: Solid and dashed outlines distinguish
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
                                            .offset(x: xPosition(for: Double(segment.range.lowerBound), width: timelineWidth) - spanStartX)
                                    }
                                }
                                .frame(
                                    width: rangeWidth(for: span.range, timelineWidth: timelineWidth),
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.dayLabel)
                .accessibilityValue(accessibilitySummary(for: row))
                .accessibilityAddTraits(row.id == selectedDayOffset ? [.isSelected] : [])
            }
        }
    }

    // MARK: - Accessibility - Chart Descriptions

    private func accessibilitySummary(for row: ContentView.DetailSunnyWindowRow) -> String {
        var summaries: [String] = []

        if !row.sunnyRanges.isEmpty {
            summaries.append(
                "\(localizedString("Sunny", locale: locale)): \(accessibilityRanges(row.sunnyRanges))"
            )
        }

        if !row.partlySunnyRanges.isEmpty {
            summaries.append(
                "\(localizedString("Partly Sunny", locale: locale)): \(accessibilityRanges(row.partlySunnyRanges))"
            )
        }

        return summaries.isEmpty
            ? localizedString("No Sun", locale: locale)
            : summaries.joined(separator: "; ")
    }

    private func accessibilityRanges(_ ranges: [ClosedRange<Int>]) -> String {
        ranges.map { range in
            // Accessibility: Speak localized clock times instead of terse numeric
            // chart-axis labels such as "06 - 09".
            let start = SunninessScoring.formattedHour(
                range.lowerBound,
                timeZone: timeZone,
                locale: locale
            )
            let end = SunninessScoring.formattedHour(
                range.upperBound + 1,
                timeZone: timeZone,
                locale: locale
            )
            return "\(start) - \(end)"
        }
        .joined(separator: ", ")
    }

    // MARK: - Chart Labels and Formatting

    private func dayLabel(_ row: ContentView.DetailSunnyWindowRow) -> some View {
        let isSelected = row.id == selectedDayOffset

        return Text(row.dayLabel)
            .font(.caption.weight(isSelected ? .bold : .medium))
            .foregroundStyle(isSelected ? primaryText : secondaryText)
            .lineLimit(1)
    }

    private func formattedAxisHour(_ hour: Int) -> String {
        // Chart axes must remain unambiguous regardless of the device's 12-hour setting.
        String(format: "%02d", hour % 24)
    }

    private func timelineSpans(for row: ContentView.DetailSunnyWindowRow) -> [TimelineSpan] {
        let segments = timelineSegments(for: row)
        guard let firstSegment = segments.first else { return [] }

        var spans: [TimelineSpan] = []
        var currentSegments = [firstSegment]
        var currentStart = firstSegment.range.lowerBound
        var currentEnd = firstSegment.range.upperBound

        for segment in segments.dropFirst() {
            if segment.range.lowerBound <= currentEnd + 1 {
                currentSegments.append(segment)
                currentEnd = max(currentEnd, segment.range.upperBound)
            } else {
                spans.append(
                    TimelineSpan(
                        id: "\(currentStart)-\(currentEnd)-\(spans.count)",
                        range: currentStart...currentEnd,
                        segments: currentSegments
                    )
                )
                currentSegments = [segment]
                currentStart = segment.range.lowerBound
                currentEnd = segment.range.upperBound
            }
        }

        spans.append(
            TimelineSpan(
                id: "\(currentStart)-\(currentEnd)-\(spans.count)",
                range: currentStart...currentEnd,
                segments: currentSegments
            )
        )

        return spans
    }

    private func timelineSegments(for row: ContentView.DetailSunnyWindowRow) -> [TimelineSegment] {
        let partlySunnySegments = row.partlySunnyRanges.enumerated().map { index, range in
            TimelineSegment(
                id: "partly-\(index)-\(range.lowerBound)-\(range.upperBound)",
                range: range,
                color: partlySunnyColor,
                isPartlySunny: true
            )
        }
        let sunnySegments = row.sunnyRanges.enumerated().map { index, range in
            TimelineSegment(
                id: "sunny-\(index)-\(range.lowerBound)-\(range.upperBound)",
                range: range,
                color: sunnyColor,
                isPartlySunny: false
            )
        }

        return (partlySunnySegments + sunnySegments).sorted {
            if $0.range.lowerBound == $1.range.lowerBound {
                return $0.range.upperBound < $1.range.upperBound
            }
            return $0.range.lowerBound < $1.range.lowerBound
        }
    }

    private func xPosition(for hour: Double, width: CGFloat) -> CGFloat {
        let clampedHour = min(max(hour, timelineStartHour), timelineEndHour)
        let fraction = (clampedHour - timelineStartHour) / (timelineEndHour - timelineStartHour)
        return CGFloat(fraction) * width
    }

    private func rangeWidth(for range: ClosedRange<Int>, timelineWidth: CGFloat) -> CGFloat {
        let start = xPosition(for: Double(range.lowerBound), width: timelineWidth)
        let end = xPosition(for: Double(range.upperBound + 1), width: timelineWidth)
        return max(end - start, 8)
    }
}

// MARK: - Nearby Map Context Models

private struct DetailNearbyCityContext: Identifiable {
    let cityWeather: CityWeather
    let isSunnier: Bool

    var id: UUID { cityWeather.id }
}

private struct DetailMapContextView: View {
    let selectedCity: CityWeather
    let nearbyCities: [DetailNearbyCityContext]
    let selectedCityName: String
    let nearbyCityNames: [UUID: String]
    let selectedDayOffset: Int
    let locale: Locale
    let accent: Color
    let water: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.appTheme) private var theme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var cameraPosition: MapCameraPosition = .automatic
    private let mapSaturation: Double = 0.72

    // Accessibility: Allow map labels and their padding to grow with Dynamic Type
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

    private var selectedCityMarker: some View {
        let icon = weatherIcon(for: selectedCity)
        return HStack(spacing: markerSpacing) {
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
    }

    private func nearbyWeatherMarker(for nearbyCity: DetailNearbyCityContext) -> some View {
        let icon = weatherIcon(for: nearbyCity.cityWeather)
        return HStack(spacing: markerSpacing) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .nearbyCityIconStyle(for: icon)

            Text(nearbyCityNames[nearbyCity.cityWeather.id] ?? nearbyCity.cityWeather.city.localizedName(locale: locale))
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
        .accessibilityLabel(nearbyCityNames[nearbyCity.cityWeather.id] ?? nearbyCity.cityWeather.city.localizedName(locale: locale))
    }

    private func weatherIcon(for city: CityWeather) -> String {
        city.forecast(for: selectedDayOffset).weatherIcon
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
        windSpeed: 9,
        uvIndex: sunnyDay ? 8 : 5,
        sunrise: Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: date),
        sunset: Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: date)
    )
}

#Preview("Detail View") {
    ContentView(initialRoute: .cityDetail(detailPreviewCity))
}
