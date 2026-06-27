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
    var selectedCityDetailDestination: some View {
        if let city = tappedCity {
            #if os(iOS)
            if !shouldUseIPadLayout {
                iPhoneMapExpandedCardDetailDestination(for: city)
            } else {
                fullWeatherDetailDestination(for: city)
            }
            #else
            fullWeatherDetailDestination(for: city)
            #endif
        }
    }

    #if os(iOS)
    private func iPhoneMapExpandedCardDetailDestination(for city: CityWeather) -> some View {
        expandedCardDetailDestination(for: city, dismissAction: {
            dismissIPhoneRoute(.cityDetail)
            selectedDayOffset = -1
        })
    }
    #endif

    private func fullWeatherDetailDestination(for city: CityWeather) -> some View {
        expandedCardDetailDestination(for: city, dismissAction: {
            #if os(iOS)
            if !shouldUseIPadLayout {
                dismissIPhoneRoute(.cityDetail)
            } else {
                showingCityDetail = false
            }
            #else
            showingCityDetail = false
            #endif
            selectedDayOffset = -1
        })
    }

    func expandedCardDetailDestination(for city: CityWeather, dismissAction: @escaping () -> Void) -> some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    detailCityTitle(for: city)

                    detailSunninessReport(for: city)

                    mapExpandedCard(
                        for: city,
                        forceMacStyle: true,
                        forceIPhoneDetailSizing: detailViewUsesIPhoneSizing,
                        plainBackground: true
                    )
                }
                .padding(.horizontal, detailViewHorizontalPadding)
                .padding(.top, detailViewTopPadding)
                .padding(.bottom, detailViewBottomPadding)
                .frame(maxWidth: detailViewMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)

            #if os(iOS)
            if !showingInlineSearch {
                iPhoneBackDateBottomToolbar(.cityDetail)
                    .padding(.horizontal, 16)
                    .padding(.bottom, -2)
            }
            #endif
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("")
        #if os(iOS)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .tint(.primary)
        #endif
        .onAppear {
            if let overlayChartMetric {
                macExpandedCardChartMetric = overlayChartMetric
            }
            macExpandedCardShowsDetails = true
        }
        .onDisappear {
            macExpandedCardShowsDetails = false
        }
    }

    // MARK: Sunniness Report

    private func detailSunninessReport(for city: CityWeather) -> some View {
        let candidate = sunnyCandidate(for: city)
        let forecast = city.forecast(for: max(0, selectedDayOffset))
        let isNow = selectedDayOffset == -1
        let icon = sunnyCandidateIcon(for: candidate)
        let condition = isNow ? city.condition : forecast.condition

        return VStack(alignment: .leading, spacing: 14) {
            detailSunninessHero(
                candidate: candidate,
                icon: icon,
                condition: condition
            )

            detailSunnyFactorGrid(city: city, candidate: candidate, forecast: forecast, icon: icon)

            detailSunnyWindow(city: city)

            detailNearbyCities(city: city)
        }
    }

    private func detailCityTitle(for city: CityWeather) -> some View {
        Text(city.city.localizedName(locale: locale))
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(theme.colors.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }

    private func detailSunninessHero(candidate: SunnyCandidate, icon: String, condition: AppWeatherCondition) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .symbolRenderingMode(icon.contains("cloud.sun") ? .palette : .monochrome)
                    .foregroundStyle(theme.colors.cloudIconColor, theme.colors.dotSun)
                    .font(.system(size: 44, weight: .semibold))
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 5) {
                    Text(detailSunninessLabel(for: candidate, icon: icon))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(theme.colors.primaryText)

                    Text(detailSunninessVerdict(for: candidate, icon: icon, condition: condition))
                        .font(.callout)
                        .foregroundStyle(theme.colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .themedGlass(in: .rect(cornerRadius: 24))
    }

    private func detailSunnyFactorGrid(
        city: CityWeather,
        candidate: SunnyCandidate,
        forecast: DailyForecast,
        icon: String
    ) -> some View {
        let isNow = selectedDayOffset == -1
        let rainChance = candidate.precipitationChance
        let windSpeed = isNow ? city.currentWindSpeed : forecast.windSpeed
        let uvIndex = isNow ? city.currentUVIndex : forecast.uvIndex
        let distanceUnit = DistanceUnit(rawValue: distanceUnitRaw) ?? .automatic

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            detailSunnyFactorTile(
                title: localizedString("Sky", locale: locale),
                value: detailSkyText(icon: icon),
                systemImage: icon,
                tint: theme.colors.dotSun
            )

            detailSunnyFactorTile(
                title: localizedString("Cloud Cover", locale: locale),
                value: candidate.cloudCover.map { "\(Int($0 * 100))%" } ?? "-",
                systemImage: "cloud.fill",
                tint: theme.colors.cloudIconColor
            )

            detailSunnyFactorTile(
                title: localizedString("Rain", locale: locale),
                value: rainChance.map { "\(Int($0 * 100))%" } ?? "-",
                systemImage: "drop.fill",
                tint: theme.colors.rainIconColor
            )

            detailSunnyFactorTile(
                title: localizedString("Comfort", locale: locale),
                value: tempUnit.display(candidate.temperature),
                systemImage: "thermometer.sun.fill",
                tint: theme.colors.accent
            )

            detailSunnyFactorTile(
                title: localizedString("UV Index", locale: locale),
                value: uvIndex.map(String.init) ?? "-",
                systemImage: "sun.max.fill",
                tint: theme.colors.dotSun
            )

            detailSunnyFactorTile(
                title: localizedString("Wind", locale: locale),
                value: windSpeed.map { distanceUnit.displayWindSpeed($0) } ?? "-",
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
        .themedGlass(in: .rect(cornerRadius: 18))
    }

    // MARK: Sunny Windows

    private func detailSunnyWindow(city: CityWeather) -> some View {
        let periods = detailSunnyPeriods(for: city)
        let selectedDay = max(0, selectedDayOffset)
        let selectedPeriod = periods.first { $0.id == selectedDay }
        let strongAlternatives = periods
            .filter { $0.id != selectedDay && $0.level >= 2 }
            .sorted {
                if $0.level == $1.level {
                    return $0.sunnyHourCount > $1.sunnyHourCount
                }
                return $0.level > $1.level
            }
            .prefix(4)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(localizedString("Sunny Window", locale: locale), systemImage: "sun.max.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)

                Spacer(minLength: 0)

                Text(selectedPeriod?.summary ?? localizedString("No strong window", locale: locale))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
            }

            if periods.isEmpty {
                Text(localizedString("No hourly data", locale: locale))
                    .font(.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                if let selectedPeriod {
                    detailSunnyPeriodRow(selectedPeriod, isSelected: true)
                }

                if !strongAlternatives.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(localizedString("Other strong days", locale: locale))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.colors.secondaryText)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                            ForEach(Array(strongAlternatives)) { period in
                                Button {
                                    withAnimation(.smooth(duration: 0.2)) {
                                        selectedDayOffset = period.id
                                    }
                                } label: {
                                    detailSunnyPeriodChip(period)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .themedGlass(in: .rect(cornerRadius: 20))
    }

    private func detailSunnyPeriodRow(_ period: DetailSunnyPeriod, isSelected: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: period.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(period.level >= 2 ? theme.colors.dotSun : theme.colors.cloudIconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(period.dayLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)

                Text(period.verdict)
                    .font(.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            Text(period.summary)
                .font(.caption.weight(.semibold))
                .foregroundStyle(period.level >= 2 ? theme.colors.dotSun : theme.colors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background((period.level >= 2 ? theme.colors.dotSun : theme.colors.secondaryText).opacity(period.level >= 2 ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func detailSunnyPeriodChip(_ period: DetailSunnyPeriod) -> some View {
        HStack(spacing: 7) {
            Image(systemName: period.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.colors.dotSun)

            VStack(alignment: .leading, spacing: 1) {
                Text(period.dayLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                Text(period.summary)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.colors.dotSun.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func detailSunnyHourPill(_ hour: HourlyForecast, timeZone: TimeZone) -> some View {
        let level = detailHourlySunnyLevel(hour)
        return VStack(spacing: 6) {
            Text(detailFormattedHour(hour.hour, timeZone: timeZone))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme.colors.secondaryText)

            Image(systemName: hour.weatherIcon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(level >= 2 ? theme.colors.dotSun : theme.colors.cloudIconColor)

            Text(hour.cloudCover.map { "\(Int($0 * 100))%" } ?? "-")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(theme.colors.secondaryText)
        }
        .frame(width: 58, height: 82)
        .background((level >= 2 ? theme.colors.dotSun : theme.colors.secondaryText).opacity(level >= 2 ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                locale: locale,
                tempUnit: tempUnit,
                accent: theme.colors.accent,
                contextDot: theme.colors.secondaryText,
                water: theme.colors.mapOcean,
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
        .themedGlass(in: .rect(cornerRadius: 20))
    }

    private func detailNearbyCityRow(_ nearbyCity: DetailNearbyCityContext) -> some View {
        HStack(spacing: 9) {
            Image(systemName: nearbyCity.cityWeather.weatherIcon)
                .font(.system(size: 15, weight: .semibold))
                .weatherIconStyle(for: nearbyCity.cityWeather.weatherIcon)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(nearbyCity.cityWeather.city.localizedName(locale: locale))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)

                Text("\(tempUnit.display(nearbyCity.cityWeather.temperature))  \(Int(nearbyCity.score.rounded())) sunny")
                    .font(.caption)
                    .foregroundStyle(theme.colors.secondaryText)
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
        .background(theme.colors.secondaryText.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    isSunnier: score > selectedScore + 4
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
        showingCityDetail = true
        #if os(iOS)
        if !shouldUseIPadLayout {
            pushIPhoneRoute(.cityDetail)
        } else {
            iPadInspectorPresentedCityID = city.id
        }
        #endif
    }

    // MARK: Verdict Text Helpers

    private func detailSunninessLabel(for candidate: SunnyCandidate, icon: String) -> String {
        if icon.contains("moon") { return localizedString("Sun is down", locale: locale) }
        switch candidate.score {
        case 82...:
            return localizedString("Perfectly sunny", locale: locale)
        case 66..<82:
            return localizedString("Mostly sunny", locale: locale)
        case 45..<66:
            return localizedString("Limited sun", locale: locale)
        default:
            return localizedString("Not a sunny pick", locale: locale)
        }
    }

    private func detailSunninessVerdict(for candidate: SunnyCandidate, icon: String, condition: AppWeatherCondition) -> String {
        if icon.contains("moon") {
            return localizedString("It may be clear, but this is not a useful sunshine window right now.", locale: locale)
        }
        let cloud = candidate.cloudCover.map { Int($0 * 100) }
        let rain = candidate.precipitationChance.map { Int($0 * 100) }

        if candidate.score >= 82 {
            return "Clear sky, low cloud, and little rain risk make this one of the strongest sunny choices."
        }
        if candidate.score >= 66 {
            return "A strong sunny option, with only a few conditions keeping it from the very top."
        }
        if candidate.score >= 45 {
            return "There should be some usable sun, but cloud cover\(cloud.map { " around \($0)%" } ?? "") keeps it mixed."
        }
        if [.rain, .drizzle, .snow].contains(condition) || (rain ?? 0) > 45 {
            return "Rain risk is too high for this to be a good sunshine choice."
        }
        return "Cloud and weak sunshine conditions make this a poor sunny candidate for the selected date."
    }

    private func detailSkyText(icon: String) -> String {
        if icon.contains("moon") { return localizedString("Night", locale: locale) }
        if icon.contains("sun.max") { return localizedString("Clear", locale: locale) }
        if icon.contains("cloud.sun") { return localizedString("Partly sunny", locale: locale) }
        if icon.contains("rain") { return localizedString("Rain", locale: locale) }
        if icon.contains("cloud") { return localizedString("Cloudy", locale: locale) }
        return localizedString("Mixed", locale: locale)
    }

    private func detailDisplayHours(for city: CityWeather, forecast: DailyForecast) -> [HourlyForecast] {
        detailDisplayHours(for: city, forecast: forecast, filtersPastToday: selectedDayOffset == -1)
    }

    private func detailDisplayHours(for city: CityWeather, forecast: DailyForecast, filtersPastToday: Bool) -> [HourlyForecast] {
        let currentHour: Int? = filtersPastToday && forecast.dayOffset == 0 ? Calendar.current.component(.hour, from: Date()) : nil
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
        let summary: String
        let verdict: String
        let icon: String
        let level: Int
        let sunnyHourCount: Int
    }

    private func detailSunnyPeriods(for city: CityWeather) -> [DetailSunnyPeriod] {
        (0..<10).compactMap { dayOffset in
            let forecast = city.forecast(for: dayOffset)
            let hours = detailDisplayHours(for: city, forecast: forecast, filtersPastToday: true)
            guard !hours.isEmpty else { return nil }

            let sunnyHours = hours.filter { detailHourlySunnyLevel($0) >= 2 }
            let moderateHours = hours.filter { detailHourlySunnyLevel($0) >= 1 }
            let level = sunnyHours.count >= 4 ? 3 : sunnyHours.isEmpty ? (moderateHours.isEmpty ? 0 : 1) : 2
            let day = ForecastDay(date: forecastDate(dayOffset: dayOffset, timeZone: city.timeZone), dayOffset: dayOffset)

            return DetailSunnyPeriod(
                id: dayOffset,
                dayLabel: day.shortDisplayText(locale: locale),
                summary: detailSunnyWindowSummary(for: city, hours: hours),
                verdict: detailSunnyPeriodVerdict(level: level, sunnyHours: sunnyHours.count, moderateHours: moderateHours.count),
                icon: detailSunnyPeriodIcon(level: level, fallback: forecast.weatherIcon),
                level: level,
                sunnyHourCount: sunnyHours.count
            )
        }
    }

    private func detailSunnyPeriodVerdict(level: Int, sunnyHours: Int, moderateHours: Int) -> String {
        switch level {
        case 3:
            return "\(sunnyHours) strong sunny hours"
        case 2:
            return "\(sunnyHours) usable sunny hours"
        case 1:
            return "\(moderateHours) mixed bright hours"
        default:
            return localizedString("Limited sunshine", locale: locale)
        }
    }

    private func detailSunnyPeriodIcon(level: Int, fallback: String) -> String {
        switch level {
        case 3:
            return "sun.max.fill"
        case 2:
            return "cloud.sun.fill"
        case 1:
            return fallback
        default:
            return "cloud.fill"
        }
    }

    private func forecastDate(dayOffset: Int, timeZone: TimeZone) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
    }

    private func detailHourlySunnyLevel(_ hour: HourlyForecast) -> Int {
        if hour.weatherIcon.contains("moon") { return 0 }
        let cloud = hour.cloudCover ?? 0.5
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

    private var detailViewUsesIPhoneSizing: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    private var detailViewHorizontalPadding: CGFloat {
        #if os(iOS)
        shouldUseIPadLayout ? 24 : 16
        #else
        16
        #endif
    }

    private var detailViewTopPadding: CGFloat {
        #if os(iOS)
        12
        #else
        16
        #endif
    }

    private var detailViewBottomPadding: CGFloat {
        #if os(iOS)
        112
        #else
        16
        #endif
    }

    private var detailViewMaxWidth: CGFloat? {
        #if os(iOS)
        shouldUseIPadLayout ? 560 : nil
        #else
        460
        #endif
    }

}

// MARK: - Nearby Map Context Models

private struct DetailNearbyCityContext: Identifiable {
    let cityWeather: CityWeather
    let score: Double
    let isSunnier: Bool

    var id: UUID { cityWeather.id }
}

private struct DetailMapContextView: View {
    let selectedCity: CityWeather
    let nearbyCities: [DetailNearbyCityContext]
    let locale: Locale
    let tempUnit: TemperatureUnit
    let accent: Color
    let contextDot: Color
    let water: Color
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
                selectedCityMarker
            }

            ForEach(nearbyCities) { nearbyCity in
                Annotation(
                    "",
                    coordinate: CLLocationCoordinate2D(latitude: nearbyCity.cityWeather.city.latitude, longitude: nearbyCity.cityWeather.city.longitude),
                    anchor: .center
                ) {
                    Button {
                        onSelectCity(nearbyCity.cityWeather)
                    } label: {
                        nearbyWeatherMarker(for: nearbyCity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .background(water)
        .onAppear {
            fitCities()
        }
        .onChange(of: displayedCities.map(\.id)) { _, _ in
            fitCities()
        }
    }

    private var selectedCityMarker: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(accent)
                .frame(width: 10, height: 10)

            Text(selectedCity.city.localizedName(locale: locale))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(accent.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: accent.opacity(0.20), radius: 8, y: 2)
    }

    private func nearbyWeatherMarker(for nearbyCity: DetailNearbyCityContext) -> some View {
        HStack(spacing: 5) {
            Image(systemName: nearbyCity.cityWeather.weatherIcon)
                .font(.system(size: 10, weight: .semibold))
                .weatherIconStyle(for: nearbyCity.cityWeather.weatherIcon)

            Text(nearbyCity.cityWeather.city.localizedName(locale: locale))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(tempUnit.display(nearbyCity.cityWeather.temperature))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if nearbyCity.isSunnier {
                Image(systemName: "sun.max.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
        .accessibilityLabel("\(nearbyCity.cityWeather.city.localizedName(locale: locale)), \(tempUnit.display(nearbyCity.cityWeather.temperature))")
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
            : unionRect.insetBy(dx: -max(unionRect.width * 0.10, 36_000), dy: -max(unionRect.height * 0.10, 36_000))
        cameraPosition = .rect(fittedRect)
    }
}
