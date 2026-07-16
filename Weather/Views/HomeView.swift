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
    let water: Color
    let mapSaturation: Double
    @Environment(\.appTheme) private var theme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
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
                    staticMapMarker(color: markerColor(for: cityWeather))
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
                    staticMapMarker(color: previewDot)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .saturation(mapSaturation)
        .allowsHitTesting(false)
        .background(water)
        .onAppear {
            fitAllCities()
        }
        .onChange(of: fitCities.map(\.id)) { _, _ in
            fitAllCities()
        }
    }

    private func markerColor(for cityWeather: CityWeather) -> Color {
        let forecast = cityWeather.forecast(for: selectedDayOffset)
        return SunninessScoring.condition(for: forecast.symbolName).dotColor(for: theme.colors)
    }

    @ViewBuilder
    private func staticMapMarker(color: Color) -> some View {
        if colorSchemeContrast == .increased {
            // Accessibility: An opaque backing and high-contrast outline keep the
            // weather color perceivable over every possible MapKit tile.
            ZStack {
                Circle()
                    .fill(theme.colors.glassFill)
                    .frame(width: 18, height: 18)
                    .overlay {
                        Circle().stroke(theme.colors.primaryText, lineWidth: 2)
                    }

                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            .saturation(markerSaturationCompensation)
        } else {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.42), radius: 5, y: 1)
                .saturation(markerSaturationCompensation)
        }
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
        // Widely scattered cities need increasingly more room than a local list.
        // There is deliberately no upper cap here; MapKit itself limits the view
        // to the world map when the fitted rectangle reaches that extent.
        let paddingMultiplier: Double = widestRelativeSpan > 0.22
            ? max(0.85, widestRelativeSpan * 2.4)
            : 0.34
        let minimumPadding = widestRelativeSpan > 0.22 ? 2_000_000.0 : 650_000.0
        let fittedRect = cityRect.insetBy(
            dx: -max(cityRect.width * paddingMultiplier, minimumPadding),
            dy: -max(cityRect.height * paddingMultiplier, minimumPadding)
        )
        cameraPosition = .rect(fittedRect)
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

    @ViewBuilder
    var body: some View {
        if cityRenameAction == nil {
            rowContent
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rowAccessibilityLabel)
                .accessibilityValue(rowAccessibilityValue)
                // Accessibility: Use the visibly rendered city name as the first
                // Voice Control command even when VoiceOver also announces rank.
                .accessibilityInputLabels([
                    Text(cityName),
                    Text(rowAccessibilityLabel)
                ])
        } else {
            // Keep the city summary and rename as separate VoiceOver controls
            // while preserving the standard editing interactions.
            rowContent
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        // Accessibility: Use a wrapping layout at accessibility Dynamic Type sizes
        // while keeping the standard compact row unchanged at normal sizes.
        if dynamicTypeSize.isAccessibilitySize {
            HStack(alignment: .top, spacing: CityListLayout.columnSpacing) {
                if let rank {
                    CityRankLabel(rank: rank)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    cityNameLabel(lineLimit: 2)

                    if showsWeatherMetrics {
                        weatherMetrics(usesFixedColumns: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                renameButton
            }
            .padding(.horizontal, 0)
            .padding(.vertical, verticalPadding)
            .contentShape(Rectangle())
        } else {
            HStack(spacing: CityListLayout.columnSpacing) {
                if let rank {
                    CityRankLabel(rank: rank)
                        .accessibilityHidden(true)
                }

                cityNameLabel(lineLimit: 1)

                Spacer(minLength: 8)

                if showsWeatherMetrics {
                    weatherMetrics(usesFixedColumns: true)
                }

                renameButton
            }
            .padding(.horizontal, 0)
            .padding(.vertical, verticalPadding)
            .contentShape(Rectangle())
        }
    }

    private func cityNameLabel(lineLimit: Int) -> some View {
        Text(cityName)
            .font(.body.weight(.medium))
            .foregroundStyle(theme.colors.primaryText)
            .lineLimit(lineLimit)
            .accessibilityLabel(rowAccessibilityLabel)
    }

    private func weatherMetrics(usesFixedColumns: Bool) -> some View {
        let icon = candidate.condition.displayIcon
        let cloudText = candidate.cloudCover.map { "\(Int(($0 * 100).rounded()))%" } ?? "-"

        return HStack(spacing: usesFixedColumns ? 0 : 10) {
            HStack(spacing: 3) {
                Image(systemName: "thermometer.medium")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.colors.primaryText)
                    .accessibilityHidden(true)
                Text(tempUnit.display(candidate.temperature))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.colors.primaryText)
                    .monospacedDigit()
            }
            .frame(width: usesFixedColumns ? temperatureMetricWidth : nil, alignment: .leading)

            HStack(spacing: 3) {
                Image(systemName: "cloud")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.colors.secondaryText.opacity(0.50))
                    .accessibilityHidden(true)
                Text(cloudText)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
            }
            .frame(width: usesFixedColumns ? cloudMetricWidth : nil, alignment: .leading)
            .padding(.trailing, usesFixedColumns ? 5 : 0)

            if showsConditionIcon {
                Image(systemName: icon)
                    .font(.caption.weight(.medium))
                    .weatherIconStyle(for: icon)
                    .frame(width: usesFixedColumns ? conditionMetricWidth : nil, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(theme.colors.secondaryText)
        .lineLimit(1)
        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var renameButton: some View {
        if let cityRenameAction {
            Button(action: cityRenameAction) {
                Image(systemName: "pencil")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(theme.colors.primaryText)
                    // Accessibility: Enlarge only the control's hit target; the
                    // compensating padding below preserves the visual row spacing.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, -6)
            .padding(.vertical, -4)
            .accessibilityLabel("\(localizedString("Rename", locale: locale)), \(cityName)")
        }
    }

    private var cityName: String {
        cityNameOverride ?? candidate.cityWeather.city.localizedName(locale: locale)
    }

    // MARK: - Accessibility - Candidate Row Descriptions

    private var rowAccessibilityLabel: String {
        guard let rank else { return cityName }
        return "\(rank), \(cityName)"
    }

    private var rowAccessibilityValue: String {
        var values = [candidate.condition.localizedDisplayName(locale: locale)]

        if showsWeatherMetrics {
            values.append("\(localizedString("Temperature", locale: locale)), \(tempUnit.display(candidate.temperature))")
            let cloudValue = candidate.cloudCover
                .map { "\(Int(($0 * 100).rounded()))%" }
                ?? localizedString("No forecast", locale: locale)
            values.append("\(localizedString("Cloud Cover", locale: locale)), \(cloudValue)")
        }

        return values.joined(separator: ", ")
    }

    // MARK: - Layout

    private var verticalPadding: CGFloat {
        compact ? 8 : 9
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

struct SunnyPlacesSectionHeader: View {
    let icon: String
    let title: String

    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: CityListLayout.columnSpacing) {
            // Accessibility: Omit the decorative icon when large text needs the
            // full row width; the heading retains its semantic label below.
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: icon)
                    .foregroundStyle(theme.colors.primaryText)
                    .frame(width: CityListLayout.rankColumnWidth, alignment: .leading)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }
}

struct CityNameListRow: View {
    let rank: Int
    let cityName: String

    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: CityListLayout.columnSpacing) {
            CityRankLabel(rank: rank)

            Text(cityName)
                .font(.body.weight(.medium))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

            Spacer(minLength: 8)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rank), \(cityName)")
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
    let sunnyCityCount: Double
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
    func updateBestSunnyPlacesWidget() {
        guard !isListPreviewActive else { return }
        let lists = managedLists.map { listID -> WidgetDataList in
            let weatherData = weatherService.weatherData(for: listID)
            let cities = weatherData.map { cityWeather in
                let todayForecast = cityWeather.forecast(for: 0)
                let daytimeHours = SunninessScoring.daytimeHours(for: todayForecast, timeZone: cityWeather.timeZone)

                return WidgetDataCity(
                    id: WidgetDataStore.cityIdentifier(
                        country: cityWeather.city.country,
                        latitude: cityWeather.city.latitude,
                        longitude: cityWeather.city.longitude,
                        listID: listID.rawValue
                    ),
                    cityName: CityListID.customCityName(for: cityWeather.city)
                        ?? cityWeather.city.localizedName(locale: locale),
                    timeZoneIdentifier: cityWeather.timeZone.identifier,
                    latitude: cityWeather.city.latitude,
                    longitude: cityWeather.city.longitude,
                    daytimeHours: daytimeHours.map { $0.hour(in: cityWeather.timeZone) },
                    sunnyHours: daytimeHours
                        .filter { SunninessScoring.condition(for: $0.symbolName) == .clear }
                        .map { $0.hour(in: cityWeather.timeZone) },
                    partlySunnyHours: daytimeHours
                        .filter { SunninessScoring.condition(for: $0.symbolName) == .partlySunny }
                        .map { $0.hour(in: cityWeather.timeZone) }
                )
            }

            return WidgetDataList(
                id: listID.rawValue,
                displayName: listID.localizedDisplayName(locale: locale),
                cities: cities
            )
        }

        WidgetDataStore.save(
            WidgetDataCatalog(
                lists: lists
            )
        )
    }

    var selectedListSortMode: WeatherListSortMode {
        WeatherListSortMode(rawValue: listSortMode) ?? .sunny
    }

    func sunnyCandidate(for cityWeather: CityWeather) -> SunnyCandidate {
        let forecast = cityWeather.forecast(for: selectedDayOffset)
        let condition = SunninessScoring.condition(for: forecast.symbolName)

        return SunnyCandidate(
            cityWeather: cityWeather,
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
                title: localizedString("Cloudy, Windy, Snowy, Foggy", locale: locale),
                icon: "cloud",
                candidates: remaining
            ),
            SunninessCandidateGroup(
                title: localizedString("Drizzle, Rain", locale: locale),
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
            let sunnyCityCount = cities.reduce(0.0) { count, cityWeather in
                switch SunninessScoring.condition(for: cityWeather.forecast(for: dayOffset).symbolName) {
                case .clear:
                    return count + 1
                case .partlySunny:
                    return count + 0.5
                default:
                    return count
                }
            }

            return HomeSunnyDayRecommendation(
                id: dayOffset,
                sunnyCityCount: sunnyCityCount
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
            centerMap(on: city)
            showMapMarkerCard(city)
        } else {
            presentDetail(for: city)
        }
    }

    // MARK: Home Page

    var homeContent: some View {
        homeContent(previewActive: isListPreviewActive)
    }

    func homeContent(previewActive: Bool) -> some View {
        GeometryReader { geometry in
            let availableContentWidth = min(max(geometry.size.width - 32, 0), 1_160)
            // The app's text-size setting currently caps at xxLarge, so treat that
            // maximum as the readable single-column breakpoint as well as the
            // system accessibility categories.
            let usesReadableSingleColumn = dynamicTypeSize >= .xxLarge
            let usesWideLayout = availableContentWidth >= 900 && !usesReadableSingleColumn
            let columnSpacing: CGFloat = 20
            let primaryColumnWidth = (availableContentWidth - columnSpacing) * 0.58
            // Preserve the existing height calculation in narrow windows. On a
            // wide window, derive the map height from its column so it retains a
            // useful landscape proportion instead of stretching with the screen.
            let snapshotHeight = usesWideLayout
                ? min(max(primaryColumnWidth * 0.48, 240), 310)
                : min(max(geometry.size.height * 0.32, 190), 310)

            ScrollView {
                VStack(spacing: 20) {
                    homePageHeader(previewActive: previewActive)

                    if usesWideLayout {
                        HStack(alignment: .top, spacing: columnSpacing) {
                            VStack(spacing: 20) {
                                homeCard(contentPadding: 6) {
                                    homeMapSnapshot(height: snapshotHeight, previewActive: previewActive)
                                }

                                if !previewActive {
                                    homeCard {
                                        homeSunnyDaysSection(previewActive: previewActive)
                                    }
                                }
                            }
                            .frame(width: primaryColumnWidth, alignment: .top)

                            homeCard(contentPadding: 12) {
                                homeSunnySection(previewActive: previewActive)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    } else {
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
                }
                // Keep the page comfortably readable in full-screen and large
                // Stage Manager windows while leaving compact layouts unchanged.
                .frame(maxWidth: usesReadableSingleColumn ? 760 : 1_160)
                .frame(maxWidth: .infinity)
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
        guard previewActive, let previewName = listPreviewState.name else { return nil }
        return "\(previewName) - \(localizedString("Preview", locale: locale))"
    }

    @ViewBuilder
    private func homeMapSnapshot(height: CGFloat, previewActive: Bool) -> some View {
        if previewActive {
            homeMapSnapshotVisual(height: height, previewActive: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(localizedString("Maps", locale: locale))
                .accessibilityValue(cityCountText(listPreviewCities.count))
        } else {
            // Accessibility: A semantic Button makes the entire map card operable
            // by VoiceOver, Voice Control, Switch Control, and direct touch.
            Button {
                selectedMapCity = nil
                showingMapExpandedCard = false
                citySearchState.temporaryMapCity = nil
                pushRoute(.map)
            } label: {
                homeMapSnapshotVisual(height: height, previewActive: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localizedString("Maps", locale: locale))
            .accessibilityValue(cityCountText(mapCities.count))
            .accessibilityHint(localizedString("Opens map", locale: locale))
        }
    }

    private func homeMapSnapshotVisual(height: CGFloat, previewActive: Bool) -> some View {
        HomeStaticMapPreview(
            cities: previewActive ? [] : mapCities,
            previewCities: previewActive ? listPreviewCities : [],
            fitCities: previewActive ? listPreviewCities : mapFitCities,
            selectedDayOffset: selectedDayOffset,
            previewDot: theme.colors.primaryText,
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
                            .accessibilityHidden(true)
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
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "sparkles")
                        .foregroundStyle(theme.colors.primaryText)
                        .frame(width: CityListLayout.rankColumnWidth, alignment: .leading)
                        .accessibilityHidden(true)
                }
                Text(localizedString("Best Sunny Dates", locale: locale))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                Spacer(minLength: 8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(localizedString("Best Sunny Dates", locale: locale))
            .accessibilityAddTraits(.isHeader)

            if days.isEmpty {
                Text(localizedString("No strong sunny days", locale: locale))
                    .font(.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else if dynamicTypeSize.isAccessibilitySize {
                // Accessibility: Replace the seven-column heatmap with readable,
                // full-width controls at accessibility Dynamic Type sizes.
                if days.contains(where: { $0.recommendation != nil }) {
                    VStack(spacing: 8) {
                        ForEach(days.filter(\.isForecastDate)) { day in
                            homeSunnyAccessibilityDayRow(day, maxSunnyCityCount: cities.count)
                        }
                    }
                } else {
                    Text(localizedString("No strong sunny days", locale: locale))
                        .font(.callout)
                        .foregroundStyle(theme.colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(spacing: 7) {
                    LazyVGrid(columns: homeSunnyCalendarColumns, spacing: 0) {
                        ForEach(homeSunnyCalendarWeekdayLabels, id: \.self) { label in
                            Text(label)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(theme.colors.secondaryText)
                                .frame(maxWidth: .infinity)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .accessibilityHidden(true)
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let symbols = calendar.shortStandaloneWeekdaySymbols
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
            let isSelected = recommendation.id == selectedDayOffset
            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    selectedDayOffset = recommendation.id
                }
            } label: {
                homeSunnyHeatmapDayCell(
                    day,
                    maxSunnyCityCount: maxSunnyCityCount,
                    isSelected: isSelected
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(homeSunnyDayLabel(dayOffset: recommendation.id))
            .accessibilityValue(homeSunnyHeatmapAccessibilityValue(recommendation))
            // Accessibility: The compact heatmap visibly shows the calendar day
            // number, so Voice Control accepts that text as well as the full date.
            .accessibilityInputLabels([
                Text(homeSunnyCalendarDayNumber(dayOffset: recommendation.id)),
                Text(homeSunnyDayLabel(dayOffset: recommendation.id))
            ])
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            homeSunnyHeatmapDayCell(day, maxSunnyCityCount: maxSunnyCityCount, isSelected: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(homeSunnyCalendarInactiveAccessibilityLabel(day))
        }
    }

    // MARK: - Accessibility - Large Text Calendar

    @ViewBuilder
    private func homeSunnyAccessibilityDayRow(_ day: HomeSunnyCalendarDate, maxSunnyCityCount: Int) -> some View {
        if let recommendation = day.recommendation {
            let isSelected = recommendation.id == selectedDayOffset
            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    selectedDayOffset = recommendation.id
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(homeSunnyDayLabel(dayOffset: recommendation.id))
                        .font(.body.weight(isSelected ? .bold : .semibold))

                    Spacer(minLength: 8)

                    Text(homeSunnyHeatmapAccessibilityValue(recommendation))
                        .font(.body)
                        .multilineTextAlignment(.trailing)
                }
                .foregroundStyle(
                    homeSunnyHeatmapTextColor(
                        sunnyCityCount: recommendation.sunnyCityCount,
                        isForecastDate: true,
                        isSelected: isSelected
                    )
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(
                    homeSunnyHeatmapFill(
                        sunnyCityCount: recommendation.sunnyCityCount,
                        maxSunnyCityCount: maxSunnyCityCount,
                        isForecastDate: true
                    ),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? theme.colors.accent : .white.opacity(0.16), lineWidth: isSelected ? 1.65 : 0.7)
                }
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(homeSunnyDayLabel(dayOffset: recommendation.id))
            .accessibilityValue(homeSunnyHeatmapAccessibilityValue(recommendation))
            .accessibilityInputLabels([Text(homeSunnyDayLabel(dayOffset: recommendation.id))])
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    // MARK: - Sunny Calendar Rendering

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

            VStack(spacing: 0) {
                Text(homeSunnyCalendarDayNumber(dayOffset: day.dayOffset))
                    .font(.system(size: 16, weight: homeSunnyCalendarDayWeight(day, isSelected: isSelected), design: .default).monospacedDigit())

                if (differentiateWithoutColor || colorSchemeContrast == .increased),
                   let recommendation = day.recommendation,
                   maxSunnyCityCount > 0 {
                    // Accessibility: Expose heatmap intensity numerically when color
                    // alone must not carry meaning or Increase Contrast is enabled.
                    Text("\(Int((recommendation.sunnyCityCount / Double(maxSunnyCityCount) * 100).rounded()))%")
                        .font(.system(size: 8, weight: .semibold, design: .rounded).monospacedDigit())
                }
            }
            .foregroundStyle(
                homeSunnyHeatmapTextColor(
                    sunnyCityCount: day.recommendation?.sunnyCityCount ?? 0,
                    isForecastDate: day.isForecastDate,
                    isSelected: isSelected
                )
            )
            .lineLimit(1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                // Accessibility: In Increase Contrast, every heatmap cell receives
                // a measured outline in addition to its numeric intensity label.
                .stroke(
                    isSelected
                        ? theme.colors.accent
                        : (colorSchemeContrast == .increased ? theme.colors.primaryText : .white.opacity(0.16)),
                    lineWidth: isSelected ? 1.65 : (colorSchemeContrast == .increased ? 1.25 : 0.7)
                )
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(2)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func homeSunnyHeatmapFill(sunnyCityCount: Double, maxSunnyCityCount: Int, isForecastDate: Bool) -> Color {
        guard isForecastDate else {
            return theme.colors.secondaryText.opacity(colorScheme == .dark ? 0.18 : 0.10)
        }

        guard sunnyCityCount > 0, maxSunnyCityCount > 0 else {
            if colorScheme == .dark {
                return theme.colors.secondaryText.opacity(0.16)
            }
            return theme.colors.glassFill.opacity(0.56)
        }

        if colorSchemeContrast == .increased {
            // Accessibility: The numeric percentage carries intensity in Increase
            // Contrast, so sunny cells use one solid, measured-contrast fill.
            return theme.colors.dotSun
        }

        let fraction = max(0, min(1, sunnyCityCount / Double(maxSunnyCityCount)))
        let curvedFraction = pow(fraction, 1.55)
        return theme.colors.dotSun.opacity(0.16 + 0.79 * curvedFraction)
    }

    private func homeSunnyCalendarDayWeight(_ day: HomeSunnyCalendarDate, isSelected: Bool) -> Font.Weight {
        if !day.isForecastDate {
            return .medium
        }
        return isSelected ? .semibold : .medium
    }

    private func homeSunnyHeatmapTextColor(
        sunnyCityCount: Double,
        isForecastDate: Bool,
        isSelected: Bool
    ) -> Color {
        if !isForecastDate {
            return theme.colors.secondaryText
        }

        if colorSchemeContrast == .increased,
           colorScheme == .dark,
           sunnyCityCount > 0 {
            // Accessibility: Bright increased-contrast yellow needs a dark foreground.
            return theme.colors.background
        }

        return isSelected ? theme.colors.accent : theme.colors.primaryText
    }

    private func homeSunnyCalendarDayNumber(dayOffset: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        return "\(Calendar.current.component(.day, from: date))"
    }

    // MARK: - Accessibility - Calendar Descriptions

    private func homeSunnyHeatmapAccessibilityValue(_ day: HomeSunnyDayRecommendation) -> String {
        let totalCities = max(mapCities.count, 1)
        let percentSunny = Int((day.sunnyCityCount / Double(totalCities) * 100).rounded())
        return "\(percentSunny)% \(localizedString("Sunny", locale: locale))"
    }

    private func homeSunnyCalendarInactiveAccessibilityLabel(_ day: HomeSunnyCalendarDate) -> String {
        "\(homeSunnyDayLabel(dayOffset: day.dayOffset)), \(localizedString("No forecast", locale: locale))"
    }

    private func homeSunnyDayLabel(dayOffset: Int) -> String {
        if dayOffset == 0 {
            return localizedString("Today", locale: locale)
        }

        let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        return date.formatted(
            Date.FormatStyle.dateTime
                .day()
                .month(.abbreviated)
                .locale(locale)
        )
    }

    // MARK: - Candidate List

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
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .accessibilityAddTraits(
                            !isShowingAllLists && listID.rawValue == weatherService.activeListID.rawValue
                                ? .isSelected
                                : []
                        )
                    }

                    if managedLists.count > 1 {
                        Button {
                            listEditMode = false
                            showAllLists()
                        } label: {
                            primaryMenuLabel(localizedString("View All Lists", locale: locale), systemImage: "list.bullet")
                        }
                        // Accessibility: Expose the aggregate-list state without
                        // relying on which menu row was most recently chosen.
                        .accessibilityAddTraits(isShowingAllLists ? .isSelected : [])
                    }

                    Divider()

                    Button {
                        listEditMode = false
                        listManagementState.isPresented = true
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
                                .accessibilityHidden(true)
                        }
                    }
                }
            .menuOrder(.fixed)
            // Accessibility: Match the Voice Control name to the list title that
            // is visibly rendered (for example, "Europe").
            .accessibilityLabel(titleOverride ?? toolbarTitle)
            .accessibilityValue(localizedString("List of Cities", locale: locale))
            .accessibilityInputLabels([Text(titleOverride ?? toolbarTitle)])
            .accessibilitySortPriority(2)
        }
    }

}
