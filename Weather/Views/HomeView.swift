//
//  HomeView.swift
//  Weather
//
//  Purpose: Defines the Home-first experience, including the static map
//  preview, sunniness ranking, list switching, and ranked city list surface.
//

import SwiftUI
import MapKit

// MARK: - Static Home Map

struct HomeStaticMapPreview: View {
    let cities: [CityWeather]
    let previewCities: [City]
    let fitCities: [City]
    let selectedDayOffset: Int
    let previewDot: Color
    let land: Color
    let water: Color
    let mapSaturation: Double
    @Environment(\.colorScheme) private var colorScheme
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 48, longitude: 12),
        span: MKCoordinateSpan(latitudeDelta: 28, longitudeDelta: 38)
    ))

    private var markerSaturationCompensation: Double {
        mapSaturation == 0 ? 1 : 1 / mapSaturation
    }

    var body: some View {
        appleMapPreview
            .background(water)
    }

    private var appleMapPreview: some View {
        Map(position: $cameraPosition, interactionModes: []) {
            ForEach(cities) { cityWeather in
                Annotation(
                    "",
                    coordinate: CLLocationCoordinate2D(
                        latitude: cityWeather.city.latitude,
                        longitude: cityWeather.city.longitude
                    ),
                    anchor: .center
                ) {
                    Circle()
                        .fill(markerColor(for: cityWeather))
                        .frame(width: 8, height: 8)
                        .shadow(color: markerColor(for: cityWeather).opacity(0.42), radius: 5, y: 1)
                        .saturation(markerSaturationCompensation)
                }
            }

            ForEach(previewCities) { city in
                Annotation(
                    "",
                    coordinate: CLLocationCoordinate2D(
                        latitude: city.latitude,
                        longitude: city.longitude
                    ),
                    anchor: .center
                ) {
                    Circle()
                        .fill(previewDot)
                        .frame(width: 8, height: 8)
                        .shadow(color: previewDot.opacity(0.36), radius: 5, y: 1)
                        .saturation(markerSaturationCompensation)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .saturation(mapSaturation)
        .allowsHitTesting(false)
        .background(water)
        .onAppear {
            refitApplePreview()
        }
        .onChange(of: fitCities.map(\.id)) { _, _ in
            refitApplePreview()
        }
        .onChange(of: selectedDayOffset) { _, _ in
            refitApplePreview()
        }
    }

    private func markerColor(for cityWeather: CityWeather) -> Color {
        let forecast = cityWeather.forecast(for: selectedDayOffset)
        return SunninessScoring.condition(for: forecast.symbolName).dotColor
    }

    private func fitAllCities() {
        let citiesForFitting = fitCities.isEmpty ? cities.map(\.city) : fitCities
        guard !citiesForFitting.isEmpty else { return }
        let points = citiesForFitting.map {
            MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
        }
        let cityRect = points.reduce(MKMapRect.null) { rect, point in
            rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }

        // A geographic degree span does not translate directly to the visible map area.
        // Fit MapKit's projected coordinates instead, with extra breathing room for lists
        // that span several regions (for example, Africa plus Australia).
        let widestRelativeSpan = max(
            cityRect.width / MKMapSize.world.width,
            cityRect.height / MKMapSize.world.height
        )
        let paddingMultiplier: Double = widestRelativeSpan > 0.22 ? 0.62 : 0.34
        let minimumPadding = widestRelativeSpan > 0.22 ? 1_400_000.0 : 650_000.0
        let fittedRect = cityRect.insetBy(
            dx: -max(cityRect.width * paddingMultiplier, minimumPadding),
            dy: -max(cityRect.height * paddingMultiplier, minimumPadding)
        )
        cameraPosition = .rect(fittedRect)
    }

    private func refitApplePreview() {
        DispatchQueue.main.async {
            fitAllCities()
        }
    }
}

struct SunnyCandidateRow: View {
    let candidate: SunnyCandidate
    var rank: Int? = nil
    var compact: Bool = false
    var showsConditionIcon: Bool = true
    var showsWeatherMetrics: Bool = true
    let tempUnit: TemperatureUnit
    var cityNameOverride: String? = nil
    var cityRenameAction: (() -> Void)? = nil

    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let icon = candidate.condition.displayIcon
        let cloudText = candidate.cloudCover.map { "\(Int($0 * 100))%" } ?? "-"
        let verticalPadding: CGFloat = compact ? 8 : 9

        HStack(spacing: CityListLayout.columnSpacing) {
            if let rank {
                CityRankLabel(rank: rank)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(cityNameOverride ?? candidate.cityWeather.city.localizedName(locale: locale))
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if showsWeatherMetrics {
                HStack(spacing: 0) {
                    HStack(spacing: 3) {
                        Image(systemName: "thermometer.medium")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(theme.colors.dotSun)
                        Text(tempUnit.display(candidate.temperature))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(theme.colors.dotSun)
                            .monospacedDigit()
                    }
                    .frame(width: temperatureMetricWidth, alignment: .leading)

                    HStack(spacing: 3) {
                        Image(systemName: "cloud")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(theme.colors.secondaryText.opacity(0.50))
                        Text(cloudText)
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                    }
                    .frame(width: cloudMetricWidth, alignment: .leading)
                    .padding(.trailing, 5)

                    if showsConditionIcon {
                        Image(systemName: icon)
                            .font(.caption.weight(.medium))
                            .weatherIconStyle(for: icon)
                            .frame(width: conditionMetricWidth, alignment: .trailing)
                    }
                }
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }

            if let cityRenameAction {
                Button(action: cityRenameAction) {
                    Image(systemName: "pencil")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(theme.colors.primaryText)
                        .frame(width: 32, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localizedString("Rename", locale: locale))
            }
        }
        .padding(.horizontal, 0)
        .padding(.vertical, verticalPadding)
        .contentShape(Rectangle())
    }

    private var temperatureMetricWidth: CGFloat {
        dynamicTypeSize > .large ? 72 : 58
    }

    private var cloudMetricWidth: CGFloat {
        dynamicTypeSize > .large ? 68 : 56
    }

    private var conditionMetricWidth: CGFloat {
        dynamicTypeSize > .large ? 26 : 22
    }
}

struct CityRankLabel: View {
    let rank: Int

    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Text(verbatim: String(rank))
            .font(.system(size: rankFontSize, weight: .semibold, design: .default))
            .foregroundStyle(theme.colors.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.leading, 5)
            .frame(width: CityListLayout.rankColumnWidth, alignment: .leading)
    }

    private var rankFontSize: CGFloat {
        switch dynamicTypeSize {
        case .xSmall: return 13
        case .small: return 14
        case .medium: return 15
        case .large: return 16
        case .xLarge: return 18
        case .xxLarge: return 20
        case .xxxLarge: return 22
        case .accessibility1, .accessibility2: return 24
        case .accessibility3, .accessibility4, .accessibility5: return 26
        @unknown default: return 16
        }
    }
}

struct SunnyCandidateRows: View {
    let candidates: [SunnyCandidate]
    let tempUnit: TemperatureUnit

    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                SunnyCandidateRow(
                    candidate: candidate,
                    rank: index + 1,
                    compact: true,
                    tempUnit: tempUnit,
                    cityNameOverride: CityNameLocalizationCatalog.localizedName(for: candidate.cityWeather.city, locale: locale)
                        ?? candidate.cityWeather.city.localizedName(locale: locale)
                )

                if index < candidates.count - 1 {
                    Divider()
                        .background(theme.colors.secondaryText.opacity(0.16))
                        .padding(.leading, CityListLayout.cityNameLeadingInset)
                }
            }
        }
    }
}

struct SunnyPlacesSectionHeader: View {
    let icon: String
    let title: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: CityListLayout.columnSpacing) {
            Image(systemName: icon)
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: CityListLayout.rankColumnWidth, alignment: .leading)
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
            Spacer(minLength: 8)
        }
    }
}

struct CityNameListRow: View {
    let rank: Int
    let cityName: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: CityListLayout.columnSpacing) {
            CityRankLabel(rank: rank)

            Text(cityName)
                .font(.body.weight(.medium))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

enum CityListLayout {
    static let rankColumnWidth: CGFloat = 32
    static let columnSpacing: CGFloat = 8
    static let cityNameLeadingInset = rankColumnWidth + columnSpacing
}

#Preview("Home View") {
    ContentView()
}

// MARK: - List Sorting

enum WeatherListSortMode: String, CaseIterable, Identifiable {
    case sunny
    case temperature
    case cloud

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .temperature: return "thermometer.medium"
        case .cloud: return "cloud"
        case .sunny: return "sun.max.fill"
        }
    }

    func title(locale: Locale) -> String {
        switch self {
        case .temperature: return localizedString("Temperature", locale: locale)
        case .cloud: return localizedString("Cloud Cover", locale: locale)
        case .sunny: return localizedString("Sunniness", locale: locale)
        }
    }
}

// MARK: - Sunniness Ranking Model

struct SunnyCandidate: Identifiable {
    let cityWeather: CityWeather
    let score: Double
    let condition: AppWeatherCondition
    let cloudCover: Double?
    let precipitationChance: Double?
    let temperature: Double

    var id: UUID { cityWeather.id }
}

struct SunninessCandidateGroup: Identifiable {
    let title: String
    let icon: String
    let candidates: [SunnyCandidate]

    var id: String { title }
}

struct HomeSunnyDayRecommendation: Identifiable {
    let id: Int
    let sunnyCityCount: Int
    let averageSunnyCloudCover: Double?
}

private struct HomeSunnyCalendarDate: Identifiable {
    let id: Int
    let dayOffset: Int
    let recommendation: HomeSunnyDayRecommendation?

    var isForecastDate: Bool {
        recommendation != nil
    }
}

// MARK: - Home and List Logic

extension ContentView {
    var selectedListSortMode: WeatherListSortMode {
        WeatherListSortMode(rawValue: listSortMode) ?? .sunny
    }

    func sunnyCandidate(for cityWeather: CityWeather) -> SunnyCandidate {
        let forecast = cityWeather.forecast(for: selectedDayOffset)
        let condition = SunninessScoring.condition(for: forecast.symbolName)

        return SunnyCandidate(
            cityWeather: cityWeather,
            score: condition.sunninessScore,
            condition: condition,
            cloudCover: forecast.cloudCover,
            precipitationChance: forecast.precipitationChance,
            temperature: forecast.dailyHigh
        )
    }

    func sunnyCandidateIcon(for candidate: SunnyCandidate) -> String {
        candidate.condition.displayIcon
    }

    var sunnyCandidates: [SunnyCandidate] {
        sunnyCandidates(for: mapCities)
    }

    func sunnyCandidates(for cities: [CityWeather]) -> [SunnyCandidate] {
        cities
            .map(sunnyCandidate(for:))
            .sorted(by: isBetterSunnyCandidate)
    }

    var recommendedSunnyCandidates: [SunnyCandidate] {
        sunnyCandidates.filter { $0.condition.isSunnyOrPartlySunny }
    }

    var homeVisibleCandidates: [SunnyCandidate] {
        isListPreviewActive ? sunnyCandidates : recommendedSunnyCandidates
    }

    var sortedListCandidates: [SunnyCandidate] {
        sortedCandidates(for: mapCities)
    }

    func sortedCandidates(for cities: [CityWeather]) -> [SunnyCandidate] {
        let candidates = cities.map(sunnyCandidate(for:))
        switch selectedListSortMode {
        case .temperature:
            return candidates.sorted { $0.temperature > $1.temperature }
        case .cloud:
            return candidates.sorted { lhs, rhs in
                switch (lhs.cloudCover, rhs.cloudCover) {
                case let (lhsCloud?, rhsCloud?):
                    return lhsCloud < rhsCloud
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.cityWeather.city.localizedName(locale: locale) < rhs.cityWeather.city.localizedName(locale: locale)
                }
            }
        case .sunny:
            return sunninessCandidateGroups(from: candidates).flatMap(\.candidates)
        }
    }

    /// Keeps the ranking rule visible in the UI: clear-sky cities come first,
    /// and each displayed weather group is ordered by lower cloud cover.
    var sunninessCandidateGroups: [SunninessCandidateGroup] {
        sunninessCandidateGroups(from: mapCities.map(sunnyCandidate(for:)))
    }

    func sunninessCandidateGroups(from candidates: [SunnyCandidate]) -> [SunninessCandidateGroup] {
        let sunny = candidates.filter { $0.condition == .clear }.sorted(by: isLowerCloudCover)
        let partlySunny = candidates.filter { $0.condition == .partlySunny }.sorted(by: isLowerCloudCover)
        let remaining = candidates.filter {
            $0.condition != .clear
                && $0.condition != .partlySunny
                && $0.condition != .drizzle
                && $0.condition != .rain
        }
        .sorted(by: isLowerCloudCover)
        let rainy = candidates.filter { $0.condition == .drizzle || $0.condition == .rain }
            .sorted(by: isLowerCloudCover)

        return [
            SunninessCandidateGroup(
                title: localizedString("Sunny", locale: locale),
                icon: "sun.max.fill",
                candidates: sunny
            ),
            SunninessCandidateGroup(
                title: localizedString("Partly Sunny", locale: locale),
                icon: "cloud.sun",
                candidates: partlySunny
            ),
            SunninessCandidateGroup(
                title: localizedString("Cloudy, Windy,\nSnowy, Foggy", locale: locale),
                icon: "cloud",
                candidates: remaining
            ),
            SunninessCandidateGroup(
                title: localizedString("Drizzle / Rain", locale: locale),
                icon: "cloud.rain",
                candidates: rainy
            )
        ].filter { !$0.candidates.isEmpty }
    }

    var homeSunnyDayRecommendations: [HomeSunnyDayRecommendation] {
        homeSunnyDayRecommendations(for: mapCities)
    }

    func homeSunnyDayRecommendations(for cities: [CityWeather]) -> [HomeSunnyDayRecommendation] {
        guard !cities.isEmpty else { return [] }

        return (0..<10).map { dayOffset in
            let sunnyForecasts = cities.compactMap { cityWeather -> DailyForecast? in
                let forecast = cityWeather.forecast(for: dayOffset)
                return SunninessScoring.condition(for: forecast.symbolName).isSunny ? forecast : nil
            }

            let cloudCovers = sunnyForecasts.compactMap(\.cloudCover)

            return HomeSunnyDayRecommendation(
                id: dayOffset,
                sunnyCityCount: sunnyForecasts.count,
                averageSunnyCloudCover: cloudCovers.isEmpty ? nil : cloudCovers.reduce(0, +) / Double(cloudCovers.count)
            )
        }
    }

    private func isBetterSunnyCandidate(_ lhs: SunnyCandidate, than rhs: SunnyCandidate) -> Bool {
        if lhs.condition.sunninessRank != rhs.condition.sunninessRank {
            return lhs.condition.sunninessRank < rhs.condition.sunninessRank
        }

        switch (lhs.cloudCover, rhs.cloudCover) {
        case let (lhsCloud?, rhsCloud?) where lhsCloud != rhsCloud:
            return lhsCloud < rhsCloud
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.cityWeather.city.localizedName(locale: locale) < rhs.cityWeather.city.localizedName(locale: locale)
        }
    }

    private func isLowerCloudCover(_ lhs: SunnyCandidate, _ rhs: SunnyCandidate) -> Bool {
        switch (lhs.cloudCover, rhs.cloudCover) {
        case let (lhsCloud?, rhsCloud?) where lhsCloud != rhsCloud:
            return lhsCloud < rhsCloud
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.cityWeather.city.localizedName(locale: locale) < rhs.cityWeather.city.localizedName(locale: locale)
        }
    }

    // MARK: Candidate Selection

    func selectCandidate(_ candidate: SunnyCandidate, focusMap: Bool = true) {
        let city = candidate.cityWeather
        if focusMap {
            pushRoute(.map)
            centerOnCityTrigger = city
            Task { @MainActor in
                await Task.yield()
                showMapMarkerCard(city)
            }
        } else {
            tappedCity = city
            showingMapExpandedCard = false
            presentDetail(for: city)
        }
    }

    // MARK: Home Page

    var homeContent: some View {
        homeContent(previewActive: isListPreviewActive)
    }

    func homeContent(previewActive: Bool) -> some View {
        GeometryReader { geometry in
            let snapshotHeight = min(max(geometry.size.height * 0.32, 190), 310)
            ScrollView {
                VStack(spacing: 20) {
                    homePageHeader(previewActive: previewActive)
                    homeCard(contentPadding: 6) {
                        homeMapSnapshot(height: snapshotHeight, previewActive: previewActive)
                    }
                    if !previewActive {
                        homeCard {
                            homeSunnyDaysSection(previewActive: previewActive)
                        }
                    }
                    homeCard(contentPadding: 12) {
                        homeSunnySection(previewActive: previewActive)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .background(theme.colors.background.ignoresSafeArea())
        }
        .onAppear {
            filterSunny = false
        }
    }

    private func homeCard<Content: View>(
        contentPadding: CGFloat = 18,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: 24))
    }

    private func homePageHeader(previewActive: Bool) -> some View {
        topToolbar(titleOverride: homeTitleOverride(previewActive: previewActive)) {
            EmptyView()
        }
    }

    private func homeTitleOverride(previewActive: Bool) -> String? {
        guard previewActive, let listPreviewName else { return nil }
        return "\(listPreviewName) - \(localizedString("Preview", locale: locale))"
    }

    private func homeMapSnapshot(height: CGFloat, previewActive: Bool) -> some View {
        HomeStaticMapPreview(
            cities: previewActive ? [] : mapCities,
            previewCities: previewActive ? listPreviewCities : [],
            fitCities: previewActive ? listPreviewCities : mapFitCities,
            selectedDayOffset: selectedDayOffset,
            previewDot: theme.colors.primaryText,
            land: theme.colors.mapLand,
            water: theme.colors.mapOcean,
            mapSaturation: 0.72
        )
        .accessibilityHidden(true)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            if !previewActive {
                centerOnCityTrigger = nil
                tappedCity = nil
                showingMapExpandedCard = false
                temporaryMapSearchCity = nil
                pushRoute(.map)
            }
        }
    }

    func homeSunnySection(previewActive: Bool) -> some View {
        let sectionIcon = previewActive ? "list.bullet" : "sun.max.fill"
        let sectionTitle = previewActive
            ? localizedString("List of Cities", locale: locale)
            : localizedString("Best Sunny Places", locale: locale)

        return VStack(alignment: .leading, spacing: 12) {
            SunnyPlacesSectionHeader(icon: sectionIcon, title: sectionTitle)

            homeCandidateList(previewActive: previewActive)

            if !previewActive {
                Button {
                    pushRoute(.list)
                } label: {
                    HStack(spacing: 8) {
                        Text(localizedString("Show All Cities", locale: locale))
                            .font(.callout.weight(.medium))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(theme.colors.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func homeSunnyDaysSection(previewActive: Bool) -> some View {
        let cities = previewActive ? [] : weatherService.cityWeatherData
        let days = homeSunnyCalendarDates(for: cities)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: CityListLayout.columnSpacing) {
                Image(systemName: "sparkles")
                    .foregroundStyle(theme.colors.primaryText)
                    .frame(width: CityListLayout.rankColumnWidth, alignment: .leading)
                Text(localizedString("Best Sunny Dates", locale: locale))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                Spacer(minLength: 8)
            }

            if days.isEmpty {
                Text(localizedString("No strong sunny days", locale: locale))
                    .font(.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 7) {
                    LazyVGrid(columns: homeSunnyCalendarColumns, spacing: 0) {
                        ForEach(homeSunnyCalendarWeekdayLabels, id: \.self) { label in
                            Text(label)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(theme.colors.secondaryText.opacity(0.45))
                                .frame(maxWidth: .infinity)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    }

                    LazyVGrid(columns: homeSunnyCalendarColumns, spacing: 7) {
                        ForEach(days) { day in
                            homeSunnyHeatmapDayView(day, maxSunnyCityCount: cities.count)
                        }
                    }
                }
            }
        }
    }

    private var homeSunnyCalendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 7), count: 7)
    }

    private var homeSunnyCalendarWeekdayLabels: [String] {
        let formatter = DateFormatter()
        formatter.locale = locale
        let symbols = formatter.shortStandaloneWeekdaySymbols ?? formatter.shortWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let mondayIndex = 1
        return Array(symbols[mondayIndex...]) + Array(symbols[..<mondayIndex])
    }

    private var homeSunnyCalendarDates: [HomeSunnyCalendarDate] {
        homeSunnyCalendarDates(for: mapCities)
    }

    private func homeSunnyCalendarDates(for cities: [CityWeather]) -> [HomeSunnyCalendarDate] {
        let recommendationsByOffset = Dictionary(uniqueKeysWithValues: homeSunnyDayRecommendations(for: cities).map { ($0.id, $0) })
        let leadingCount = homeSunnyCalendarLeadingInactiveCount()
        let forecastOffsets = Array(0..<10)
        let totalBeforeTrailing = leadingCount + forecastOffsets.count
        let trailingCount = (7 - (totalBeforeTrailing % 7)) % 7
        let leadingOffsets = leadingCount == 0 ? [] : Array((-leadingCount)..<0)
        let trailingOffsets = trailingCount == 0 ? [] : Array(10..<(10 + trailingCount))

        return (leadingOffsets + forecastOffsets + trailingOffsets).map { dayOffset in
            HomeSunnyCalendarDate(
                id: dayOffset,
                dayOffset: dayOffset,
                recommendation: recommendationsByOffset[dayOffset]
            )
        }
    }

    private func homeSunnyCalendarLeadingInactiveCount() -> Int {
        let sundayBasedWeekday = Calendar.current.component(.weekday, from: Date()) - 1
        let mondayIndex = 1
        return (sundayBasedWeekday - mondayIndex + 7) % 7
    }

    @ViewBuilder
    private func homeSunnyHeatmapDayView(_ day: HomeSunnyCalendarDate, maxSunnyCityCount: Int) -> some View {
        if let recommendation = day.recommendation {
            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    selectedDayOffset = recommendation.id
                }
            } label: {
                homeSunnyHeatmapDayCell(
                    day,
                    maxSunnyCityCount: maxSunnyCityCount,
                    isSelected: recommendation.id == selectedDayOffset
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(homeSunnyHeatmapAccessibilityLabel(recommendation))
        } else {
            homeSunnyHeatmapDayCell(day, maxSunnyCityCount: maxSunnyCityCount, isSelected: false)
                .accessibilityLabel(homeSunnyCalendarInactiveAccessibilityLabel(day))
        }
    }

    private func homeSunnyHeatmapDayCell(
        _ day: HomeSunnyCalendarDate,
        maxSunnyCityCount: Int,
        isSelected: Bool
    ) -> some View {
        let fill = homeSunnyHeatmapFill(
            sunnyCityCount: day.recommendation?.sunnyCityCount ?? 0,
            maxSunnyCityCount: maxSunnyCityCount,
            isForecastDate: day.isForecastDate
        )
        let cornerRadius: CGFloat = 12

        return ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)

            Text(homeSunnyCalendarDayNumber(dayOffset: day.dayOffset))
                .font(.system(size: 16, weight: homeSunnyCalendarDayWeight(day, isSelected: isSelected), design: .default).monospacedDigit())
                .foregroundStyle(homeSunnyCalendarDayTextColor(day, isSelected: isSelected))
                .lineLimit(1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(isSelected ? theme.colors.accent : .white.opacity(0.16), lineWidth: isSelected ? 1.65 : 0.7)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(2)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func homeSunnyHeatmapFill(sunnyCityCount: Int, maxSunnyCityCount: Int, isForecastDate: Bool) -> Color {
        guard isForecastDate else {
            return theme.colors.secondaryText.opacity(colorScheme == .dark ? 0.18 : 0.10)
        }

        guard sunnyCityCount > 0, maxSunnyCityCount > 0 else {
            if colorScheme == .dark {
                return theme.colors.secondaryText.opacity(0.16)
            }
            return theme.colors.glassFill.opacity(0.56)
        }

        let fraction = max(0, min(1, Double(sunnyCityCount) / Double(maxSunnyCityCount)))
        let curvedFraction = pow(fraction, 1.55)
        return theme.colors.dotSun.opacity(0.16 + 0.79 * curvedFraction)
    }

    private func homeSunnyCalendarDayWeight(_ day: HomeSunnyCalendarDate, isSelected: Bool) -> Font.Weight {
        if !day.isForecastDate {
            return .medium
        }
        return isSelected ? .semibold : .medium
    }

    private func homeSunnyCalendarDayTextColor(_ day: HomeSunnyCalendarDate, isSelected: Bool) -> Color {
        if !day.isForecastDate {
            return theme.colors.primaryText.opacity(0.45)
        }
        return isSelected ? theme.colors.accent : theme.colors.primaryText
    }

    private func homeSunnyCalendarDayNumber(dayOffset: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        return "\(Calendar.current.component(.day, from: date))"
    }

    private func homeSunnyHeatmapAccessibilityLabel(_ day: HomeSunnyDayRecommendation) -> String {
        let totalCities = max(mapCities.count, 1)
        let percentSunny = Int((Double(day.sunnyCityCount) / Double(totalCities) * 100).rounded())
        return "\(homeSunnyDayLabel(dayOffset: day.id)), \(percentSunny)% \(localizedString("Sunny", locale: locale))"
    }

    private func homeSunnyCalendarInactiveAccessibilityLabel(_ day: HomeSunnyCalendarDate) -> String {
        "\(homeSunnyDayLabel(dayOffset: day.dayOffset)), \(localizedString("No forecast", locale: locale))"
    }

    private func homeSunnyDayLabel(dayOffset: Int) -> String {
        if dayOffset == 0 {
            return localizedString("Today", locale: locale)
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "dMMM", options: 0, locale: locale)
        return formatter.string(from: Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date())
    }

    private func homeCandidateList(limit: Int? = nil, previewActive: Bool) -> some View {
        if previewActive {
            return AnyView(homePreviewCityList())
        }

        let normalCandidates = sunnyCandidates(for: weatherService.cityWeatherData)
            .filter { $0.condition.isSunnyOrPartlySunny }
        let rankedCandidates = limit.map { Array(normalCandidates.prefix($0)) } ?? normalCandidates
        return AnyView(VStack(spacing: 0) {
            if rankedCandidates.isEmpty {
                Text(localizedString("No sunny places for this date.", locale: locale))
                    .font(.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                    .background(theme.colors.glassFill.opacity(0.42), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                listCandidateRows(
                    rankedCandidates,
                    showsDividers: true,
                    selectionAction: { candidate in
                        selectCandidate(candidate, focusMap: false)
                    }
                )
            }
        })
    }

    private func homePreviewCityList() -> some View {
        VStack(spacing: 0) {
            ForEach(Array(listPreviewCities.enumerated()), id: \.element.id) { index, city in
                CityNameListRow(
                    rank: index + 1,
                    cityName: localizedCityName(for: city)
                )

                if index < listPreviewCities.count - 1 {
                    Divider()
                        .background(theme.colors.secondaryText.opacity(0.18))
                        .padding(.leading, CityListLayout.cityNameLeadingInset)
                }
            }
        }
    }

    func sunnyCandidateRow(
        _ candidate: SunnyCandidate,
        rank: Int? = nil,
        compact: Bool = false,
        showsConditionIcon: Bool = true,
        showsWeatherMetrics: Bool = true,
        cityNameOverride: String? = nil,
        cityRenameAction: (() -> Void)? = nil
    ) -> some View {
        SunnyCandidateRow(
            candidate: candidate,
            rank: rank,
            compact: compact,
            showsConditionIcon: showsConditionIcon,
            showsWeatherMetrics: showsWeatherMetrics,
            tempUnit: tempUnit,
            cityNameOverride: cityNameOverride ?? localizedCityName(for: candidate.cityWeather.city),
            cityRenameAction: cityRenameAction
        )
    }

    var homeListMenu: some View {
        listSwitcher(titleOverride: nil)
    }
    func topToolbar<Accessory: View>(
        titleOverride: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            listSwitcher(titleOverride: titleOverride)
            Spacer(minLength: 12)
            accessory()
        }
        .frame(maxWidth: .infinity)
    }

    func topToolbarActionCapsule<Content: View>(
        spacing: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: spacing) {
            content()
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .themedGlass(in: .capsule)
    }

    func listSwitcher(titleOverride: String?) -> some View {
        Group {
            Menu {
                    ForEach(managedLists) { listID in
                        Button {
                            listEditMode = false
                            Task {
                                await switchToList(listID)
                            }
                        } label: {
                            HStack {
                                Text(listID.localizedDisplayName(locale: locale))
                                    .foregroundStyle(theme.colors.primaryText)

                                Spacer()

                                if !isShowingAllLists && listID.rawValue == weatherService.activeListID.rawValue {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(theme.colors.primaryText)
                                }
                            }
                        }
                    }

                    if managedLists.count > 1 {
                        Button {
                            listEditMode = false
                            showAllLists()
                        } label: {
                            primaryMenuLabel(localizedString("View All Lists", locale: locale), systemImage: "list.bullet")
                        }
                    }

                    Divider()

                    Button {
                        listEditMode = false
                        showingListManagementSheet = true
                    } label: {
                        primaryMenuLabel(localizedString("Manage Lists", locale: locale), systemImage: "slider.horizontal.3")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(titleOverride ?? toolbarTitle)
                            .font(.system(size: 32, weight: .semibold, design: .serif))
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)
                        if titleOverride == nil {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.colors.accent)
                        }
                    }
                }
            .menuOrder(.fixed)
        }
    }

}
