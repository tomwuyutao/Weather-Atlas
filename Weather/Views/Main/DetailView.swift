//
//  DetailView.swift
//  Weather
//
//  Purpose: Builds the city detail screen around its title, condition, sunny
//  factors, sunny-hour chart, and nearby-city context.
//

import SwiftUI
import MapKit
import UIKit

// MARK: - City Detail Routing

extension ContentView {
    /// Builds a city report route with city-specific date switching and toolbar.
    func cityDetailView(for city: CityWeather) -> some View {
        cityDetailScrollContent(for: city)
            .background {
                theme.colors.background
                    .ignoresSafeArea()
            }
            // Keep the compact native title absent while the large report title
            // is visible, then let the navigation bar take over as it scrolls away.
            .navigationTitle(
                isDetailLargeTitleVisible ? "" : localizedCityName(for: city.city)
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .tint(theme.colors.primaryText)
            .onAppear {
                isDetailLargeTitleVisible = true
            }
            .onChange(of: city.id) { _, _ in
                isDetailLargeTitleVisible = true
            }
    }

    /// Resolves the list that owns this detail route, preferring the active list.
    func detailSourceListID(for city: CityWeather) -> CityListID? {
        if weatherService.cityListCoordinates().contains(where: {
            weatherService.citiesMatch($0, city.city)
        }) {
            return weatherService.activeListID
        }
        return weatherService.listContainingCity(city.city)
    }

    /// Supplies Move to List and named Delete actions for a saved city.
    func detailCityMoreMenu(
        for city: CityWeather,
        sourceListID: CityListID
    ) -> some View {
        let destinationLists = managedLists.filter {
            $0.rawValue != sourceListID.rawValue
        }

        return Menu {
            Menu {
                ForEach(destinationLists) { destinationListID in
                    Button {
                        moveDetailCity(
                            city,
                            from: sourceListID,
                            to: destinationListID
                        )
                    } label: {
                        primaryMenuLabel(
                            destinationListID.localizedDisplayName(locale: locale),
                            systemImage: "list.bullet"
                        )
                    }
                }
            } label: {
                primaryMenuLabel(
                    localizedString("Move to List", locale: locale),
                    systemImage: "arrow.right"
                )
            }
            .disabled(destinationLists.isEmpty)

            Button {
                deleteDetailCity(city, from: sourceListID)
            } label: {
                Label {
                    Text(
                        String(
                            format: localizedString("Delete from %@", locale: locale),
                            locale: locale,
                            sourceListID.localizedDisplayName(locale: locale)
                        )
                    )
                } icon: {
                    Image(systemName: "trash")
                        .foregroundStyle(theme.colors.destructive)
                }
            }
            .tint(theme.colors.destructive)

            globalMoreMenuFooter
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(localizedString("Menu", locale: locale))
        .menuOrder(.fixed)
        .tint(theme.colors.accent)
    }

    /// Moves the represented city, switches lists, and keeps Detail valid.
    private func moveDetailCity(
        _ city: CityWeather,
        from sourceListID: CityListID,
        to destinationListID: CityListID
    ) {
        weatherService.moveCity(
            city,
            from: sourceListID,
            to: destinationListID
        )
        Haptics.lightImpact()

        Task {
            await switchToList(destinationListID)
            let movedCity = weatherService.cityWeatherData.first {
                weatherService.citiesMatch($0.city, city.city)
            } ?? city

            guard let routeIndex = navigationPath.indices.last,
                  case .cityDetail = navigationPath[routeIndex] else {
                return
            }
            navigationPath[routeIndex] = .cityDetail(movedCity)
            publishWidgetCatalog()
        }
    }

    /// Deletes the represented city from its list and closes Detail.
    private func deleteDetailCity(
        _ city: CityWeather,
        from sourceListID: CityListID
    ) {
        weatherService.removeCity(city, from: sourceListID)
        selectedMapCity = nil
        Haptics.lightImpact()
        publishWidgetCatalog()

        guard let route = navigationPath.last,
              case .cityDetail(let displayedCity) = route,
              weatherService.citiesMatch(displayedCity.city, city.city) else {
            return
        }
        navigationPath.removeLast()
    }

    /// Builds responsive scroll content and resolves the selected daily forecast.
    private func cityDetailScrollContent(for city: CityWeather) -> some View {
        GeometryReader { geometry in
            let usesLandscapeIPadLayout = usesIPadLandscapeLayout(for: geometry.size)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    detailSunninessReport(for: city, usesLandscapeIPadLayout: usesLandscapeIPadLayout)
                }
                // Keep report insets stable across phone and iPad.
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 16)
                // Give landscape iPad reports wider outer margins.
                .frame(maxWidth: usesLandscapeIPadLayout ? 680 : 760)
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
    /// Composes header, factors, timeline, and nearby-city context for one day.
    private func detailSunninessReport(
        for city: CityWeather,
        usesLandscapeIPadLayout: Bool
    ) -> some View {
        let detailForecastDate = selectedForecastDate
        if let forecast = city.forecastIfAvailable(on: detailForecastDate) {
            let condition = SunninessScoring.condition(for: forecast.symbolName)
            let rankingCandidate = sunnyCandidate(for: city, on: detailForecastDate)

            VStack(alignment: .leading, spacing: 14) {
                detailCityNameHeader(
                    city: city,
                    condition: condition
                )

                detailSunnyFactorGrid(
                    city: city,
                    forecast: forecast,
                    usesLandscapeIPadLayout: usesLandscapeIPadLayout
                )

                detailSunnyWindowOverview(city: city)

                if condition != nil,
                   rankingCandidate != nil,
                   weatherService.listContainingCity(city.city) != nil {
                    detailNearbyCities(city: city, selectedForecast: forecast)
                }
            }
        } else {
            VStack(spacing: 16) {
                Text(localizedCityName(for: city.city))
                    .font(.system(.largeTitle, design: .serif).weight(.bold))
                    .foregroundStyle(theme.colors.titleText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 52)
                    .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                        isDetailLargeTitleVisible = isVisible
                    }

            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Builds city, date, and primary weather summary at the top of the report.
    private func detailCityNameHeader(
        city: CityWeather,
        condition: AppWeatherCondition?
    ) -> some View {
        let cityName = localizedCityName(for: city.city)

        return VStack(spacing: 9) {
            Text(cityName)
                .font(.system(.largeTitle, design: .serif).weight(.bold))
                .foregroundStyle(theme.colors.titleText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 52)
                .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                    isDetailLargeTitleVisible = isVisible
                }

            if let condition {
                let icon = condition.displayIcon
                Image(systemName: icon)
                    .weatherIconStyle(for: icon)
                    .font(.system(size: 52, weight: .semibold))
                    .frame(width: 62, height: 58)
                    .padding(.vertical, 8)

                Text(condition.localizedDisplayName(locale: locale))
                    .font(.callout)
                    .foregroundStyle(theme.colors.primaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    /// Builds the six source-backed daily metric tiles.
    private func detailSunnyFactorGrid(
        city: CityWeather,
        forecast: DailyForecast,
        usesLandscapeIPadLayout: Bool
    ) -> some View {
        DetailMetricGrid(
            city: city,
            forecast: forecast,
            temperatureUnit: tempUnit,
            usesLandscapeIPadLayout: usesLandscapeIPadLayout,
            selectedForecastDate: $selectedForecastDate
        )
    }

    // MARK: Sunny Hours Overview

    @ViewBuilder
    /// Builds the selectable ten-day sunny-hours timeline from valid day rows.
    private func detailSunnyWindowOverview(city: CityWeather) -> some View {
        let forecasts = Array(city.dailyForecasts.prefix(10))
        let resolvedData = detailSunnyWindowData(for: city, forecasts: forecasts)

        if case .success(let days) = resolvedData {
            let windows = detailSunnyWindowRows(for: city, days: days)
            let chartBounds = SunnyHoursChartBounds.merged(days.map(\.sunnyHours.bounds))

            if !windows.isEmpty, let chartBounds {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: CityListLayout.columnSpacing) {
                        Image(systemName: "calendar.day.timeline.left")
                            .frame(width: CityListLayout.rankColumnWidth, alignment: .leading)
                        Text(localizedString("Sunny Hours", locale: locale))
                        Spacer(minLength: 8)
                        Text(sunnyWindowRangeText(for: city))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.colors.secondaryText)
                            .lineLimit(1)
                    }
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)

                    DetailSunnyWindowOverviewChart(
                        rows: windows,
                        selectedForecastDate: selectedForecastDate,
                        locale: locale,
                        timeZone: city.timeZone,
                        chartBounds: chartBounds,
                        sunnyColor: theme.colors.dotSun,
                        partlySunnyColor: theme.colors.dotPartlyCloudy,
                        // Chart tracks use the same subdued fill as settings rows.
                        trackColor: theme.colors.settingsRowFill,
                        gridColor: theme.colors.secondaryText.opacity(0.06),
                        primaryText: theme.colors.primaryText,
                        secondaryText: theme.colors.secondaryText,
                        onSelectDay: { date in
                            withAnimation(.smooth(duration: 0.2)) {
                                selectedForecastDate = date
                            }
                        }
                    )
                    .padding(.top, 8)

                    // Identify every palette color used by the timeline.
                    HStack(spacing: 14) {
                        sunnyWindowLegendItem(
                            title: localizedString("Sunny", locale: locale),
                            color: theme.colors.dotSun
                        )
                        sunnyWindowLegendItem(
                            title: localizedString("Partly Sunny", locale: locale),
                            color: theme.colors.dotPartlyCloudy
                        )
                        sunnyWindowLegendItem(
                            title: localizedString("No Sun", locale: locale),
                            color: theme.colors.settingsRowFill
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
                }
                .padding(14)
                .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: 20))
            }
        }
    }

    /// Formats the selected day's longest fully or partly sunny interval.
    private func sunnyWindowRangeText(for city: CityWeather) -> String {
        guard let forecast = city.forecastIfAvailable(on: selectedForecastDate),
              let range = SunninessScoring.longestSunnyHourRange(
                  in: forecast.hourlyForecasts,
                  timeZone: city.timeZone
              ) else {
            return localizedString("No Sun", locale: locale)
        }
        let start = SunninessScoring.compactHourLabel(range.lowerBound, locale: locale)
        let end = SunninessScoring.compactHourLabel(range.upperBound + 1, locale: locale)
        return "\(start) – \(end)"
    }

    /// Builds one timeline legend swatch and localized label.
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

    /// Builds the nearby comparison map and ranked nearby-city rows.
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
                    fallbackBackground: theme.colors.background
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
            // iPad can show more nearby-city context than the phone excerpt.
            .frame(height: UIDevice.current.userInterfaceIdiom == .pad ? 260 : 190)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(theme.colors.primaryText.opacity(0.10), lineWidth: 0.6)
                    .allowsHitTesting(false)
            }

            if !nearbyCities.isEmpty {
                VStack(spacing: 6) {
                    ForEach(nearbyCities) { nearbyCity in
                        Button {
                            // Replace the current detail with the selected nearby city.
                            pushRoute(.cityDetail(nearbyCity.cityWeather))
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

    /// Builds a consistent icon-and-title heading for report cards.
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
    /// Builds one nearby city comparison row and navigation action.
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
                        .background(theme.colors.dotSun, in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(width: 18, height: 24)
            }
            .padding(.horizontal, 10)
            .frame(height: 50)
            .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: 14))
        }
    }

    // MARK: - Nearby City Data

    /// Selects nearby valid cities and records whether each is sunnier.
    private func detailNearbyCityContexts(for city: CityWeather) -> [DetailNearbyCityContext] {
        let detailForecastDate = selectedForecastDate
        guard let selectedCandidate = sunnyCandidate(for: city, on: detailForecastDate) else { return [] }
        let selectedLocation = CLLocation(latitude: city.city.latitude, longitude: city.city.longitude)
        return mapCities
            .filter { $0.id != city.id }
            // Order by geodesic distance from the selected city.
            .sorted {
                selectedLocation.distance(from: CLLocation(latitude: $0.city.latitude, longitude: $0.city.longitude))
                    < selectedLocation.distance(from: CLLocation(latitude: $1.city.latitude, longitude: $1.city.longitude))
            }
            .prefix(3)
            .compactMap { nearbyCity in
                guard let candidate = sunnyCandidate(for: nearbyCity, on: detailForecastDate),
                      let forecast = nearbyCity.forecastIfAvailable(on: detailForecastDate) else {
                    return nil
                }
                return DetailNearbyCityContext(
                    cityWeather: nearbyCity,
                    forecast: forecast,
                    // Compare condition rank, then sunny-condition cloud cover.
                    isSunnier: {
                        if candidate.condition.sunninessRank != selectedCandidate.condition.sunninessRank {
                            return candidate.condition.sunninessRank < selectedCandidate.condition.sunninessRank
                        }
                        guard candidate.condition.isSunnyOrPartlySunny,
                              selectedCandidate.condition.isSunnyOrPartlySunny else {
                            return false
                        }
                        return candidate.cloudCover < selectedCandidate.cloudCover
                    }()
                )
            }
    }

    /// Returns to Map View centered on the detail city's marker.
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
            isMapCardPresented = false
            navigateToMap()
            centerMap(on: revealedCity)
            showMapMarkerCard(revealedCity)
        }
    }

    // MARK: Sunny Hours Computation

    /// One forecast paired with fully validated daylight-hour source data.
    private struct DetailSunnyWindowDayData {
        /// Source daily forecast.
        let forecast: DailyForecast
        /// Validated daylight bounds and classified hourly records.
        let sunnyHours: SunninessScoring.SunnyHoursData
    }

    /// Render-ready row consumed by the in-app ten-day timeline.
    fileprivate struct DetailSunnyWindowRow: Identifiable {
        /// Literal selection date and stable row identity.
        let id: Date
        /// Localized compact date label.
        let dayLabel: String
        /// Contiguous fully sunny hour ranges.
        let sunnyRanges: [ClosedRange<Int>]
        /// Contiguous partly sunny hour ranges.
        let partlySunnyRanges: [ClosedRange<Int>]
    }

    /// Validates the chart as a continuous prefix of eight to ten days.
    /// WeatherKit may omit hourly data at the end of its forecast horizon, so
    /// one or two trailing days may be dropped. A gap inside the valid prefix,
    /// or any other source-data problem, still hides the complete chart.
    private func detailSunnyWindowData(
        for city: CityWeather,
        forecasts: [DailyForecast]
    ) -> Result<[DetailSunnyWindowDayData], WeatherDataIssue> {
        guard !forecasts.isEmpty else {
            return .failure(.missingForecastData)
        }

        var days: [DetailSunnyWindowDayData] = []
        var trailingHourlyDataIssue: WeatherDataIssue?
        for forecast in forecasts {
            switch SunninessScoring.sunnyHoursData(for: forecast, timeZone: city.timeZone) {
            case .success(let sunnyHours):
                // A valid day after a missing day would create an interior gap,
                // which is not an allowed forecast-horizon omission.
                if let trailingHourlyDataIssue {
                    return .failure(trailingHourlyDataIssue)
                }
                days.append(DetailSunnyWindowDayData(forecast: forecast, sunnyHours: sunnyHours))
            case .failure(let issue):
                guard issue.kind == .missingHourlyData else {
                    return .failure(issue)
                }
                trailingHourlyDataIssue = issue
            }
        }

        // Only the ninth and tenth rows may be absent. Earlier omissions still
        // invalidate the chart, even when every later day is also unavailable.
        guard days.count >= 8 else {
            return .failure(trailingHourlyDataIssue ?? .missingForecastData)
        }
        return .success(days)
    }

    /// Converts validated days into labels and contiguous render ranges.
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
                // Format Today or a city-local abbreviated date for this row.
                dayLabel: {
                    if Calendar.current.isDate(selectionDate, inSameDayAs: forecastDateToday) {
                        return localizedString("Today", locale: locale)
                    }
                    var format = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(locale)
                    format.timeZone = city.timeZone
                    return forecast.date.formatted(format)
                }(),
                sunnyRanges: SunnyHoursFormatting.contiguousRanges(in: sunnyHours),
                partlySunnyRanges: SunnyHoursFormatting.contiguousRanges(in: partlySunnyHours)
            )
        }
    }

    /// Maps a recognized hourly symbol to sunny, partly sunny, or unfavorable.
    private func detailHourlySunnyLevel(_ hour: HourlyForecast) -> Int? {
        switch SunninessScoring.condition(for: hour.symbolName) {
        case .clear:
            return 2
        case .partlySunny:
            return 1
        case .partlyCloudy, .cloudy, .rain, .drizzle, .snow, .fog, .wind:
            return 0
        case nil:
            return nil
        }
    }

}

// MARK: - Sunny Hours Overview Chart

/// In-app selectable multi-day daylight timeline; widgets use separate views.
private struct DetailSunnyWindowOverviewChart: View {
    /// Render-ready rows for every valid forecast day.
    let rows: [ContentView.DetailSunnyWindowRow]
    /// Literal date whose label and capsule receive selection emphasis.
    let selectedForecastDate: Date
    /// App-selected locale retained for chart formatting context.
    let locale: Locale
    /// City timezone used by the current-local-time marker.
    let timeZone: TimeZone
    /// Merged real daylight domain shared by all rows.
    let chartBounds: SunnyHoursChartBounds
    /// Fully sunny segment color.
    let sunnyColor: Color
    /// Partly sunny segment color.
    let partlySunnyColor: Color
    /// Empty daylight track color.
    let trackColor: Color
    /// Vertical hour-grid color.
    let gridColor: Color
    /// Primary label and current-time marker color.
    let primaryText: Color
    /// Secondary label and selected-outline color.
    let secondaryText: Color
    /// Callback selecting a row's literal date.
    let onSelectDay: (Date) -> Void
    /// Replaces color-only chart distinctions with line patterns when enabled.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    /// Whether layout metrics should use iPad density.
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Integer tick hours selected for the real daylight domain.
    private var axisHours: [Int] { chartBounds.axisHours() }
    /// Height allocated to each forecast row.
    private var rowHeight: CGFloat { isIPad ? 32 : 26 }
    /// Visible timeline capsule thickness.
    private var capsuleHeight: CGFloat { isIPad ? 14 : 12 }

    /// Refreshes the local-time marker once per minute.
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            chart(currentDate: context.date)
        }
    }

    /// Composes axis, rows, grid, selection, and current-time marker.
    private func chart(currentDate: Date) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let labelWidth: CGFloat = 64
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
            // Include the iPad- or phone-sized hour-label lane above the rows.
            .frame(height: (isIPad ? 24 : 20) + CGFloat(rows.count) * rowHeight)
        }
    }

    /// Positions hour tick labels along the shared timeline width.
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
            // Allocate the hour-label lane according to device density.
            .frame(width: timelineWidth, height: isIPad ? 24 : 20)
        }
    }

    /// Draws vertical guides spanning only the visible capsule region.
    private func gridLines(labelWidth: CGFloat, timelineWidth: CGFloat) -> some View {
        let rowsHeight = CGFloat(rows.count) * rowHeight
        // Center guides within the iPad- or phone-sized hit lane.
        let verticalInset = ((isIPad ? 22 : 18) - capsuleHeight) / 2
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
    /// Draws city-local current time only on today's row and inside daylight.
    private func currentTimeMarker(
        at currentDate: Date,
        labelWidth: CGFloat,
        timelineWidth: CGFloat
    ) -> some View {
        let rowsHeight = CGFloat(rows.count) * rowHeight
        if let todayRowIndex = currentLocalRowIndex(at: currentDate),
           let markerX = chartBounds.currentTimeXPosition(
               at: currentDate,
               timeZone: timeZone,
               width: timelineWidth
           ) {
            HStack(spacing: 0) {
                Color.clear.frame(width: labelWidth)
                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(primaryText.opacity(0.78))
                            .frame(width: 2, height: capsuleHeight)
                            .offset(x: markerX - 1)
                    }
                    .frame(
                        width: timelineWidth,
                        height: capsuleHeight,
                        alignment: .leading
                    )
                    .clipShape(Capsule())
                    .offset(
                        y: CGFloat(todayRowIndex) * rowHeight
                            + (rowHeight - capsuleHeight) / 2
                    )
                }
                .frame(width: timelineWidth, height: rowsHeight, alignment: .topLeading)
            }
            .frame(height: rowsHeight)
        }
    }

    /// Finds the row representing the city's local day at an absolute instant.
    private func currentLocalRowIndex(at currentDate: Date) -> Int? {
        var cityCalendar = Calendar.current
        cityCalendar.timeZone = timeZone
        let localComponents = cityCalendar.dateComponents(
            [.year, .month, .day],
            from: currentDate
        )
        guard let selectionDate = Calendar.current.date(from: localComponents) else {
            return nil
        }
        return rows.firstIndex {
            Calendar.current.isDate($0.id, inSameDayAs: selectionDate)
        }
    }

    /// Builds selectable date labels, tracks, segments, and selected outlines.
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
                        .frame(width: timelineWidth, height: isIPad ? 22 : 18)
                        .overlay {
                            if Calendar.current.isDate(row.id, inSameDayAs: selectedForecastDate) {
                                Capsule()
                                    .stroke(primaryText, lineWidth: 1.5)
                                    .frame(
                                        width: timelineWidth,
                                        height: capsuleHeight
                                    )
                            }
                        }
                    }
                    .frame(height: rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Chart Labels and Formatting

    /// Builds a date label with selected-state emphasis.
    private func dayLabel(_ row: ContentView.DetailSunnyWindowRow) -> some View {
        let selected = Calendar.current.isDate(row.id, inSameDayAs: selectedForecastDate)

        return Text(row.dayLabel)
            .font(.caption.weight(selected ? .bold : .medium))
            .foregroundStyle(selected ? primaryText : secondaryText)
            .lineLimit(1)
    }

}

// MARK: - Nearby Map Context

/// Nearby city plus selected-date forecast and relative sunniness result.
private struct DetailNearbyCityContext: Identifiable {
    /// Nearby city weather aggregate.
    let cityWeather: CityWeather
    /// Forecast matching the detail's literal selected date.
    let forecast: DailyForecast
    /// Whether this city ranks better than the selected detail city.
    let isSunnier: Bool

    /// Reuses stable city identity for map and row diffing.
    var id: UUID { cityWeather.id }
}

/// Noninteractive nearby-city map embedded in the Detail report card.
private struct DetailMapContextView: View {
    /// City owning the current detail report.
    let selectedCity: CityWeather
    /// Selected city's forecast for the literal date.
    let selectedForecast: DailyForecast
    /// Nearby valid city comparisons.
    let nearbyCities: [DetailNearbyCityContext]
    /// Localized selected-city marker label.
    let selectedCityName: String
    /// Localized nearby marker labels keyed by stable identity.
    let nearbyCityNames: [UUID: String]
    /// App-selected locale used by marker labels.
    let locale: Locale
    /// Accent color used for selected emphasis.
    let accent: Color
    /// Theme color revealed while MapKit has no drawable content.
    let fallbackBackground: Color

    /// Text category controlling expanded marker labels.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Active semantic palette.
    @Environment(\.appTheme) private var theme
    /// Contrast preference controlling opaque marker alternatives.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// Internal fitted camera for this noninteractive map.
    @State private var cameraPosition: MapCameraPosition = .automatic
    /// Tile saturation used by the embedded map.
    private let mapSaturation: Double = 0.72

    /// Whether larger text requires fully expanded marker padding.
    private var usesExpandedMarkers: Bool {
        dynamicTypeSize > .large
    }

    /// Selected and nearby cities used for camera fitting.
    private var displayedCities: [CityWeather] {
        [selectedCity] + nearbyCities.map(\.cityWeather)
    }

    /// Builds the noninteractive MapKit context and its annotations.
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
        .background(fallbackBackground)
        .onAppear {
            fitCities()
        }
        .onChange(of: displayedCities.map(\.id)) { _, _ in
            fitCities()
        }
    }

    @ViewBuilder
    /// Builds the visually dominant marker for the detail city.
    private var selectedCityMarker: some View {
        if let condition = SunninessScoring.condition(for: selectedForecast.symbolName) {
            let icon = condition.displayIcon
            HStack(spacing: usesExpandedMarkers ? 7 : 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .nearbyCityIconStyle(for: icon)

                Text(selectedCityName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            // Expanded Dynamic Type gets roomier selected-marker insets.
            .padding(.horizontal, usesExpandedMarkers ? 12 : 9)
            .padding(.vertical, usesExpandedMarkers ? 8 : 6)
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
            // Counteract tile desaturation so semantic marker colors stay stable.
            .saturation(mapSaturation == 0 ? 1 : 1 / mapSaturation)
        }
    }

    @ViewBuilder
    /// Builds a nearby marker styled by relative condition context.
    private func nearbyWeatherMarker(for nearbyCity: DetailNearbyCityContext) -> some View {
        let cityName = nearbyCityNames[nearbyCity.cityWeather.id]
            ?? localizedCityDisplayName(for: nearbyCity.cityWeather.city, locale: locale)
        if let condition = SunninessScoring.condition(for: nearbyCity.forecast.symbolName) {
            let icon = condition.displayIcon
            HStack(spacing: usesExpandedMarkers ? 7 : 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .nearbyCityIconStyle(for: icon)

                Text(cityName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)

            }
            .fixedSize(horizontal: true, vertical: false)
            // Nearby markers stay compact while respecting larger text.
            .padding(.horizontal, usesExpandedMarkers ? 10 : 7)
            .padding(.vertical, usesExpandedMarkers ? 7 : 5)
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
            .shadow(color: theme.colors.shadow.opacity(0.10), radius: 6, y: 2)
            // Counteract tile desaturation so semantic marker colors stay stable.
            .saturation(mapSaturation == 0 ? 1 : 1 / mapSaturation)
        }
    }

    /// Fits the map to every displayed city coordinate.
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
    /// Applies semantic palette rendering to a nearby weather symbol.
    func nearbyCityIconStyle(for iconName: String) -> some View {
        self.weatherIconStyle(for: iconName)
    }
}

/// Deterministic multi-day city fixture used only by Xcode previews.
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

/// Builds one visually varied deterministic Xcode preview forecast.
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
            symbol = cloud > 0.55 ? WeatherIconSymbol.cloudy : WeatherIconSymbol.clear
        } else if cloud < 0.28 {
            symbol = "sun.max.fill"
        } else if cloud < 0.62 {
            symbol = WeatherIconSymbol.partlyCloudy
        } else {
            symbol = "cloud"
        }

        return HourlyForecast(
            date: Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date,
            symbolName: symbol,
            temperature: 20 + Double(dayOffset % 3) + Double(max(0, 12 - abs(14 - hour))) * 0.65,
            apparentTemperature: 21 + Double(dayOffset % 3) + Double(max(0, 12 - abs(14 - hour))) * 0.72,
            cloudCover: cloud,
            precipitationChance: cloud > 0.72 ? 0.35 : 0.04,
            uvIndex: hour < 7 || hour > 19 ? 0 : max(0, 9 - abs(13 - hour)),
            visibilityKilometers: max(2, 32 - cloud * 24)
        )
    }

    let averageCloud = selectedPattern.reduce(0, +) / Double(selectedPattern.count)
    let sunnyDay = averageCloud < 0.42
    let symbol = sunnyDay ? "sun.max.fill" : averageCloud < 0.65 ? WeatherIconSymbol.partlyCloudy : "cloud"

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
