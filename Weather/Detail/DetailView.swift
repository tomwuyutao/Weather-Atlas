//
//  DetailView.swift
//  Weather
//
//  Purpose: Builds the city detail screen around sunniness: verdict, factors,
//  sunny windows, nearby comparisons, and the expanded weather card.
//

import SwiftUI
import MapKit

// MARK: - City Detail Routing

extension ContentView {
    @ViewBuilder
    func cityDetailDestination(for cityID: UUID) -> some View {
        if let city = cityWeatherForDetailRoute(cityID) {
            cityDetailView(for: city, route: .cityDetail(city.id))
        }
    }

    func cityDetailView(for city: CityWeather, route: AppNavigationRoute) -> some View {
        ZStack(alignment: .bottom) {
            cityDetailScrollContent(for: city)

            if !showingSearchSheet {
                Color.clear
                    .frame(height: 104)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .zIndex(90)

                floatingBottomToolbar
                    .padding(.horizontal, 16)
                    .padding(.bottom, -2)
                    .zIndex(100)
            }
        }
        .background {
            theme.colors.background
                .ignoresSafeArea()
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .tint(theme.colors.primaryText)
        .onDisappear {
            guard case .cityDetail = route else { return }
            selectedDayOffset = 0
        }
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

    func cityWeatherForDetailRoute(_ cityID: UUID) -> CityWeather? {
        if let city = mapCities.first(where: { $0.id == cityID }) {
            return city
        }
        if tappedCity?.id == cityID {
            return tappedCity
        }
        if temporaryMapSearchCity?.id == cityID {
            return temporaryMapSearchCity
        }
        if addCityDetailCity?.id == cityID {
            return addCityDetailCity
        }
        return nil
    }

    // MARK: Sunniness Report

    private func detailSunninessReport(for city: CityWeather) -> some View {
        let candidate = sunnyCandidate(for: city)
        let forecast = city.forecast(for: max(0, selectedDayOffset))
        let isNow = selectedDayOffset == -1
        let icon = sunnyCandidateIcon(for: candidate)
        let condition = isNow ? city.condition : forecast.condition

        return VStack(alignment: .leading, spacing: 14) {
            detailCityNameHeader(
                city: city,
                icon: icon,
                condition: condition
            )

            detailSunnyFactorGrid(city: city, candidate: candidate, forecast: forecast)

            detailCloudCover(city: city)

            detailBestFutureDates(city: city)

            detailNearbyCities(city: city)
        }
    }

    private func detailCityNameHeader(city: CityWeather, icon: String, condition: AppWeatherCondition) -> some View {
        VStack(spacing: 9) {
            Text(city.city.localizedName(locale: locale))
                .font(.system(.largeTitle, design: .serif).weight(.bold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)

            Image(systemName: icon)
                .weatherIconStyle(for: icon)
                .font(.system(size: 52, weight: .semibold))
                .frame(width: 62, height: 58)
                .padding(.vertical, 8)

            Text(detailConditionText(icon: icon, condition: condition))
                .font(.callout)
                .foregroundStyle(theme.colors.primaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    private func detailConditionText(icon: String, condition: AppWeatherCondition) -> String {
        if icon.contains("moon") { return localizedString("Night", locale: locale) }
        return condition.localizedDisplayName(locale: locale)
    }

    private func detailSunnyFactorGrid(
        city: CityWeather,
        candidate: SunnyCandidate,
        forecast: DailyForecast
    ) -> some View {
        let isNow = selectedDayOffset == -1
        let rainChance = candidate.precipitationChance
        let windSpeed = isNow ? city.currentWindSpeed : forecast.windSpeed
        let uvIndex = isNow ? city.currentUVIndex : forecast.uvIndex
        let distanceUnit = DistanceUnit(rawValue: distanceUnitRaw) ?? .automatic
        let selectedHours = detailDisplayHours(for: city, forecast: forecast, filtersPastToday: false)

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            detailSunnyFactorTile(
                title: localizedString("Sunny Window", locale: locale),
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
                title: localizedString("Wind", locale: locale),
                value: windSpeed.map { distanceUnit.displayWindSpeed($0, locale: locale) } ?? "-",
                systemImage: "wind",
                tint: theme.colors.secondaryText
            )
        }
    }

    private func detailSunnyFactorTile(title: String, value: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 10) {
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
        .padding(12)
        .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: 18))
    }

    // MARK: Future Date Discovery

    private func detailBestFutureDates(city: CityWeather) -> some View {
        let periods = detailSunnyPeriods(for: city)
        let recommendations = periods
            .filter { $0.id > 0 }
            .filter { ($0.score ?? 0) >= homeSunnyScoreThreshold }
            .sorted { $0.id < $1.id }
            .prefix(5)

        return VStack(alignment: .leading, spacing: 10) {
            Label(localizedString("Best Future Dates", locale: locale), systemImage: "sparkles")
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)

            if recommendations.isEmpty {
                Text(localizedString("No strong future dates", locale: locale))
                    .font(.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recommendations.enumerated()), id: \.element.id) { index, period in
                        Button {
                            withAnimation(.smooth(duration: 0.2)) {
                                selectedDayOffset = period.id
                            }
                        } label: {
                            detailFutureDateRow(
                                period,
                                city: city,
                                isSelected: period.id == max(0, selectedDayOffset)
                            )
                        }
                        .buttonStyle(.plain)

                        if index < recommendations.count - 1 {
                            Divider()
                                .background(theme.colors.secondaryText.opacity(0.16))
                                .padding(.leading, 30)
                        }
                    }
                }
            }
        }
        .padding(14)
        .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: 20))
    }

    private func detailFutureDateRow(_ period: DetailSunnyPeriod, city: CityWeather, isSelected: Bool) -> some View {
        let forecast = city.forecast(for: period.id)
        let hours = detailDisplayHours(for: city, forecast: forecast, filtersPastToday: false)
        let window = detailSunnyWindowSummary(for: city, hours: hours)

        return HStack(spacing: 10) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.colors.dotSun)
                .frame(width: 22)

            Text(period.dayLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)

            Spacer(minLength: 8)

            Text(window)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Image(systemName: "checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? theme.colors.accent : .clear)
                .frame(width: 14)
        }
        .padding(.vertical, 9)
    }

    // MARK: Cloud Cover

    private func detailCloudCover(city: CityWeather) -> some View {
        let selectedDay = max(0, selectedDayOffset)
        let selectedForecast = city.forecast(for: selectedDay)
        let selectedHours = detailDisplayHours(
            for: city,
            forecast: selectedForecast,
            filtersPastToday: false
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(localizedString("Cloud Cover", locale: locale), systemImage: "cloud")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)

                Spacer(minLength: 0)
            }

            if selectedHours.isEmpty {
                Text(localizedString("No hourly data", locale: locale))
                    .font(.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                detailSunnyTimeline(hours: selectedHours, timeZone: city.timeZone)
            }
        }
        .padding(14)
        .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: 20))
    }

    private func detailSunnyDayDotColor(for period: DetailSunnyPeriod) -> Color {
        guard let score = period.score else {
            return theme.colors.dotCloudy
        }
        let normalizedScore = min(max(score / 100, 0), 1)
        return theme.colors.dotCloudy.compatMix(with: theme.colors.dotSun, by: normalizedScore)
    }

    private func detailSunnyTimeline(hours: [HourlyForecast], timeZone: TimeZone) -> some View {
        VStack(alignment: .center, spacing: 12) {
            HourlyTimelineChart(
                hourlyForecasts: hours.filter { $0.hour.isMultiple(of: 2) },
                chartMetric: .cloudCover,
                dayOffset: max(0, selectedDayOffset),
                cityTimeZone: timeZone,
                lineColor: theme.colors.dotRain,
                showAllHours: true,
                compactLayout: true,
                placesLabelsBelowChart: true,
                showsPointValueLabels: true,
                showsSelectedIndicator: false,
                showsValueRow: false,
                labelStride: 1,
                showsYAxis: false,
                showsChartBackground: true,
                chartBottomSpacing: 22
            )
            .frame(height: 224)
        }
    }

    // MARK: Nearby Cities

    private func detailNearbyCities(city: CityWeather) -> some View {
        let nearbyCities = detailNearbyCityContexts(for: city)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(localizedString("Nearby Cities", locale: locale), systemImage: "map.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                Spacer(minLength: 0)
            }

            DetailMapContextView(
                selectedCity: city,
                nearbyCities: nearbyCities,
                selectedDayOffset: selectedDayOffset,
                locale: locale,
                accent: theme.colors.accent,
                water: theme.colors.mapOcean,
                onSelectMapCity: openDetailCityOnMap,
                onSelectCity: selectDetailNearbyCity
            )
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 0.6)
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

    private func detailNearbyCityRow(_ nearbyCity: DetailNearbyCityContext) -> some View {
        let icon = nearbyCityWeatherIcon(for: nearbyCity.cityWeather)
        return HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .nearbyCityIconStyle(for: icon)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(nearbyCity.cityWeather.city.localizedName(locale: locale))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if nearbyCity.isSunnier {
                Text(localizedString("Sunnier", locale: locale))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.dotSun)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.colors.dotSun.opacity(0.12), in: Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.colors.secondaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: 14))
    }

    private func nearbyCityWeatherIcon(for city: CityWeather) -> String {
        selectedDayOffset == -1
            ? city.weatherIcon
            : city.forecast(for: max(0, selectedDayOffset)).weatherIcon
    }

    private func detailNearbyCityContexts(for city: CityWeather) -> [DetailNearbyCityContext] {
        let selectedScore = sunnyCandidate(for: city).score
        return mapCities
            .filter { $0.id != city.id }
            .sorted { detailDistance(from: city, to: $0) < detailDistance(from: city, to: $1) }
            .prefix(3)
            .map { nearbyCity in
                let score = sunnyCandidate(for: nearbyCity).score
                return DetailNearbyCityContext(
                    cityWeather: nearbyCity,
                    score: score,
                    isSunnier: score.map { nearbyScore in
                        nearbyScore > (selectedScore ?? Double.greatestFiniteMagnitude) + 4
                    } ?? false
                )
            }
    }

    private func detailDistance(from first: CityWeather, to second: CityWeather) -> CLLocationDistance {
        let firstLocation = CLLocation(latitude: first.city.latitude, longitude: first.city.longitude)
        let secondLocation = CLLocation(latitude: second.city.latitude, longitude: second.city.longitude)
        return firstLocation.distance(from: secondLocation)
    }

    private func selectDetailNearbyCity(_ city: CityWeather) {
        tappedCity = city
        pushRoute(.cityDetail(city.id))
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

            centerOnCityTrigger = nil
            tappedCity = revealedCity
            showingMapExpandedCard = false
            pushRoute(.map)

            await Task.yield()
            mapRecenterRequest = .listCoordinates
            showMapMarkerCard(revealedCity, expanded: false, focusesMarker: true)
        }
    }

    private func detailDisplayHours(for city: CityWeather, forecast: DailyForecast) -> [HourlyForecast] {
        detailDisplayHours(for: city, forecast: forecast, filtersPastToday: selectedDayOffset == -1)
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
                guard (6...21).contains(forecast.hour) else { return false }
                if let currentHour {
                    return forecast.hour >= currentHour
                }
                return true
            }
            .sorted { $0.hour < $1.hour }
    }

    // MARK: Sunny Window Computation

    private struct DetailSunnyPeriod: Identifiable {
        let id: Int
        let dayLabel: String
        let score: Double?
    }

    private func detailSunnyPeriods(for city: CityWeather) -> [DetailSunnyPeriod] {
        (0..<10).compactMap { dayOffset in
            let forecast = city.forecast(for: dayOffset)
            let hours = detailDisplayHours(for: city, forecast: forecast, filtersPastToday: true)
            guard !hours.isEmpty else { return nil }

            return DetailSunnyPeriod(
                id: dayOffset,
                dayLabel: detailSunnyDayLabel(dayOffset: dayOffset, timeZone: city.timeZone),
                score: SunninessScoring.score(
                    condition: forecast.condition,
                    icon: forecast.weatherIcon,
                    cloudCover: forecast.cloudCover
                )
            )
        }
    }

    private func detailSunnyDayLabel(dayOffset: Int, timeZone: TimeZone) -> String {
        if dayOffset == 0 {
            return localizedString("Today", locale: locale)
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "dMMM", options: 0, locale: locale)
        return formatter.string(from: forecastDate(dayOffset: dayOffset, timeZone: timeZone))
    }

    private func forecastDate(dayOffset: Int, timeZone: TimeZone) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
    }

    private func detailHourlySunnyLevel(_ hour: HourlyForecast) -> Int {
        if hour.weatherIcon.contains("moon") { return 0 }
        guard let cloud = hour.cloudCover else {
            weatherService.reportDeveloperWarning(
                title: "Hourly Cloud Cover Missing",
                message: "An hourly sunny-window level could not be calculated because WeatherKit returned no cloud cover value."
            )
            return 0
        }
        let rain = hour.precipitationChance ?? 0
        if rain > 0.45 { return 0 }
        if hour.weatherIcon.contains("sun.max") && cloud < 0.25 { return 3 }
        if hour.weatherIcon.contains("sun") && cloud < 0.55 { return 2 }
        if cloud < 0.70 && rain < 0.20 { return 1 }
        return 0
    }

    private func detailSunnyWindowSummary(for city: CityWeather, hours: [HourlyForecast]) -> String {
        let sunnyHours = hours.filter { detailHourlySunnyLevel($0) >= 2 }
        guard !sunnyHours.isEmpty else {
            return localizedString("No strong window", locale: locale)
        }

        var bestStart = sunnyHours[0].hour
        var bestEnd = sunnyHours[0].hour
        var currentStart = sunnyHours[0].hour
        var currentEnd = sunnyHours[0].hour

        for hour in sunnyHours.dropFirst().map(\.hour) {
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

        return "\(detailFormattedHour(bestStart, timeZone: city.timeZone))-\(detailFormattedHour(bestEnd + 1, timeZone: city.timeZone))"
    }

    private func detailFormattedHour(_ hour: Int, timeZone: TimeZone) -> String {
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

    // MARK: Detail Layout Metrics

    private var detailViewHorizontalPadding: CGFloat {
        16
    }

    private var detailViewTopPadding: CGFloat {
        20
    }

    private var detailViewBottomPadding: CGFloat {
        112
    }

    private var detailViewMaxWidth: CGFloat? {
        nil
    }

}

// MARK: - Nearby Map Context Models

private struct DetailNearbyCityContext: Identifiable {
    let cityWeather: CityWeather
    let score: Double?
    let isSunnier: Bool

    var id: UUID { cityWeather.id }
}

private struct DetailMapContextView: View {
    let selectedCity: CityWeather
    let nearbyCities: [DetailNearbyCityContext]
    let selectedDayOffset: Int
    let locale: Locale
    let accent: Color
    let water: Color
    let onSelectMapCity: (CityWeather) -> Void
    let onSelectCity: (CityWeather) -> Void

    @State private var cameraPosition: MapCameraPosition = .automatic

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
                Button {
                    onSelectMapCity(selectedCity)
                } label: {
                    selectedCityMarker
                }
                .buttonStyle(.plain)
            }

            ForEach(nearbyCities) { nearbyCity in
                Annotation(
                    "",
                    coordinate: CLLocationCoordinate2D(latitude: nearbyCity.cityWeather.city.latitude, longitude: nearbyCity.cityWeather.city.longitude),
                    anchor: .center
                ) {
                    Button {
                        onSelectMapCity(nearbyCity.cityWeather)
                    } label: {
                        nearbyWeatherMarker(for: nearbyCity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .background(water)
        .onTapGesture {
            onSelectMapCity(selectedCity)
        }
        .onAppear {
            fitCities()
        }
        .onChange(of: displayedCities.map(\.id)) { _, _ in
            fitCities()
        }
    }

    private var selectedCityMarker: some View {
        let icon = weatherIcon(for: selectedCity)
        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .nearbyCityIconStyle(for: icon)

            Text(selectedCity.city.localizedName(locale: locale))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.shared.colors.primaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(accent.opacity(0.50), lineWidth: 2)
        }
        .shadow(color: accent.opacity(0.20), radius: 8, y: 2)
    }

    private func nearbyWeatherMarker(for nearbyCity: DetailNearbyCityContext) -> some View {
        let icon = weatherIcon(for: nearbyCity.cityWeather)
        return HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .nearbyCityIconStyle(for: icon)

            Text(nearbyCity.cityWeather.city.localizedName(locale: locale))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.shared.colors.primaryText)
                .lineLimit(1)

        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
        .accessibilityLabel(nearbyCity.cityWeather.city.localizedName(locale: locale))
    }

    private func weatherIcon(for city: CityWeather) -> String {
        selectedDayOffset == -1
            ? city.weatherIcon
            : city.forecast(for: max(0, selectedDayOffset)).weatherIcon
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
