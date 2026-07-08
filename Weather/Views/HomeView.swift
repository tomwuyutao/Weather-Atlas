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
    let rankedCandidates: [SunnyCandidate]
    let selectedDayOffset: Int
    let accent: Color
    let contextDot: Color
    let land: Color
    let water: Color
    @Environment(\.colorScheme) private var colorScheme
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 48, longitude: 12),
        span: MKCoordinateSpan(latitudeDelta: 28, longitudeDelta: 38)
    ))

    private var rankByCityID: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: rankedCandidates.prefix(3).enumerated().map { ($0.element.cityWeather.id, $0.offset + 1) })
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
                    if let rank = rankByCityID[cityWeather.id] {
                        numberedDot(rank: rank, candidate: rankedCandidates.first { $0.id == cityWeather.id })
                    } else {
                        Circle()
                            .fill(markerColor(for: cityWeather))
                            .frame(width: 8, height: 8)
                            .shadow(color: markerColor(for: cityWeather).opacity(0.42), radius: 5, y: 1)
                    }
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
                        .fill(accent)
                        .frame(width: 8, height: 8)
                        .shadow(color: accent.opacity(0.36), radius: 5, y: 1)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
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

    private func numberedDot(rank: Int, candidate: SunnyCandidate?) -> some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.20))
                .frame(width: 28, height: 28)
                .blur(radius: 6)

            Circle()
                .fill(candidate?.condition.isSunny == true ? accent : contextDot.opacity(0.75))
                .frame(width: 20, height: 20)
                .shadow(color: accent.opacity(0.24), radius: 6, y: 2)

            Text("\(rank)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(width: 30, height: 30)
    }

    private func markerColor(for cityWeather: CityWeather) -> Color {
        let forecast = cityWeather.forecast(for: selectedDayOffset)
        return SunninessScoring.condition(for: forecast.symbolName).dotColor
    }

    private func fitAllCities() {
        let citiesForFitting = fitCities.isEmpty ? cities.map(\.city) : fitCities
        guard !citiesForFitting.isEmpty else { return }
        let latitudes = citiesForFitting.map(\.latitude)
        let longitudes = citiesForFitting.map(\.longitude)
        guard let minLatitude = latitudes.min(),
              let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(),
              let maxLongitude = longitudes.max() else { return }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let latitudeDelta = max(8, min(160, (maxLatitude - minLatitude) * 1.45))
        let longitudeDelta = max(10, min(320, (maxLongitude - minLongitude) * 1.45))
        cameraPosition = .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        ))
    }

    private func refitApplePreview() {
        DispatchQueue.main.async {
            fitAllCities()
        }
    }
}

#Preview("Home View") {
    ContentView()
}

// MARK: - List Sorting

enum WeatherListSortMode: String, CaseIterable, Identifiable {
    case temperature
    case cloud
    case sunny

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
        sunnyCandidates.filter { $0.condition.isSunny }
    }

    var homeVisibleCandidates: [SunnyCandidate] {
        isListPreviewActive ? sunnyCandidates : recommendedSunnyCandidates
    }

    var sortedListCandidates: [SunnyCandidate] {
        let candidates = mapCities.map(sunnyCandidate(for:))
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
            return candidates.sorted(by: isBetterSunnyCandidate)
        }
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
                    homeMapSnapshot(height: snapshotHeight, previewActive: previewActive)
                    if !previewActive {
                        homeSunnyDaysSection(previewActive: previewActive)
                    }
                    homeSunnySection(previewActive: previewActive)
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
            rankedCandidates: previewActive ? [] : Array(sunnyCandidates(for: weatherService.cityWeatherData).filter { $0.condition.isSunny }.prefix(3)),
            selectedDayOffset: selectedDayOffset,
            accent: theme.colors.dotSun,
            contextDot: theme.colors.secondaryText,
            land: theme.colors.mapLand,
            water: theme.colors.mapOcean
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

    private func homeSunnySection(previewActive: Bool) -> some View {
        let sectionIcon = previewActive ? "list.bullet" : "sun.max.fill"
        let sectionTitle = previewActive
            ? localizedString("List of Cities", locale: locale)
            : localizedString("Best Sunny Places", locale: locale)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: sectionIcon)
                    .foregroundStyle(theme.colors.dotSun)
                Text(sectionTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                Spacer(minLength: 8)
            }

            homeCandidateList(previewActive: previewActive)

            if !previewActive {
                Button {
                    pushRoute(.list)
                } label: {
                    HStack(spacing: 8) {
                        Text(localizedString("Show All Cities", locale: locale))
                            .font(.callout.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(theme.colors.accent)
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
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(theme.colors.dotSun)
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
                .padding(.horizontal, 10)
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
                .font(.system(size: 18, weight: homeSunnyCalendarDayWeight(day, isSelected: isSelected), design: .default).monospacedDigit())
                .foregroundStyle(homeSunnyCalendarDayTextColor(day, isSelected: isSelected))
                .lineLimit(1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(isSelected ? theme.colors.accent : .white.opacity(0.16), lineWidth: isSelected ? 2 : 0.7)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(2)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func homeSunnyHeatmapFill(sunnyCityCount: Int, maxSunnyCityCount: Int, isForecastDate: Bool) -> Color {
        guard isForecastDate else {
            return theme.colors.secondaryText.opacity(colorScheme == .dark ? 0.18 : 0.16)
        }

        guard sunnyCityCount > 0, maxSunnyCityCount > 0 else {
            return theme.colors.glassFill.opacity(colorScheme == .dark ? 0.34 : 0.56)
        }

        let fraction = max(0, min(1, Double(sunnyCityCount) / Double(maxSunnyCityCount)))
        return theme.colors.dotSun.opacity(0.24 + 0.62 * fraction)
    }

    private func homeSunnyCalendarDayWeight(_ day: HomeSunnyCalendarDate, isSelected: Bool) -> Font.Weight {
        if !day.isForecastDate {
            return .medium
        }
        return isSelected ? .bold : .semibold
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
            .filter { $0.condition.isSunny }
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
                ForEach(Array(rankedCandidates.enumerated()), id: \.element.id) { index, candidate in
                    Button {
                        selectCandidate(candidate, focusMap: false)
                    } label: {
                        sunnyCandidateRow(candidate, rank: index + 1, compact: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        })
    }

    private func homePreviewCityList() -> some View {
        VStack(spacing: 0) {
            ForEach(Array(listPreviewCities.enumerated()), id: \.element.id) { index, city in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(theme.colors.secondaryText)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(city.localizedName(locale: locale))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .contentShape(Rectangle())

                if index < listPreviewCities.count - 1 {
                    Divider()
                        .background(theme.colors.secondaryText.opacity(0.18))
                        .padding(.leading, 34)
                }
            }
        }
    }

    func sunnyCandidateRow(
        _ candidate: SunnyCandidate,
        rank: Int? = nil,
        compact: Bool = false,
        deleteAction: (() -> Void)? = nil
    ) -> some View {
        let icon = sunnyCandidateIcon(for: candidate)
        let cloudText = candidate.cloudCover.map { "\(Int($0 * 100))%" } ?? "-"
        let cloudMetricSpacing: CGFloat = dynamicTypeSize > .large ? 7 : 3
        let cloudValueWidth: CGFloat = dynamicTypeSize > .large ? 48 : 38
        let cloudColumnWidth: CGFloat = dynamicTypeSize > .large ? 72 : 54
        let verticalPadding: CGFloat = compact ? 8 : 9
        return HStack(spacing: 10) {
            if let deleteAction {
                Button {
                    deleteAction()
                } label: {
                    ZStack {
                        Circle()
                            .fill(theme.colors.destructive)
                            .frame(width: 28, height: 28)

                        Image(systemName: "minus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 32)
                .transition(.scale(scale: 0.82).combined(with: .opacity))
            } else if let rank {
                Text("\(rank)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(width: 24)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.cityWeather.city.localizedName(locale: locale))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
            }
            .padding(.leading, deleteAction == nil ? 0 : 6)

            Spacer(minLength: 8)

            HStack(spacing: 7) {
                HStack(spacing: 3) {
                    Image(systemName: "thermometer.medium")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.dotSun)
                        .frame(width: 13, alignment: .center)
                    Text(tempUnit.display(candidate.temperature))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.dotSun)
                        .monospacedDigit()
                        .frame(width: 34, alignment: .leading)
                }
                .frame(width: 50, alignment: .leading)

                HStack(spacing: cloudMetricSpacing) {
                    Image(systemName: "cloud")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.secondaryText.opacity(0.50))
                        .frame(width: 13, alignment: .center)
                    Text(cloudText)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: cloudValueWidth, alignment: .leading)
                }
                .frame(width: cloudColumnWidth, alignment: .leading)

                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .weatherIconStyle(for: icon)
                    .frame(width: 18, alignment: .leading)
            }
            .foregroundStyle(theme.colors.secondaryText)
            .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, verticalPadding)
        .contentShape(Rectangle())
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

    func listSwitcher(titleOverride: String?) -> some View {
        Group {
            if listEditMode && titleOverride == nil {
                Button {
                    listToRenameID = weatherService.activeListID
                    renameAlertText = weatherService.activeListID.localizedDisplayName(locale: locale)
                    showingRenameAlert = true
                } label: {
                    HStack(spacing: 6) {
                        Text(toolbarTitle)
                            .font(.system(size: 34, weight: .semibold, design: .serif))
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.colors.accent)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
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

                                if listID.rawValue == weatherService.activeListID.rawValue {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(theme.colors.primaryText)
                                }
                            }
                        }
                    }

                    Divider()

                    Button {
                        listEditMode = false
                        activateAddListOptions()
                    } label: {
                        primaryMenuLabel(localizedString("Add List", locale: locale), systemImage: "plus")
                    }

                    Button {
                        listEditMode = false
                        listToRenameID = weatherService.activeListID
                        renameAlertText = weatherService.activeListID.localizedDisplayName(locale: locale)
                        showingRenameAlert = true
                    } label: {
                        primaryMenuLabel(localizedString("Rename List", locale: locale), systemImage: "pencil")
                    }

                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showingDeleteListConfirmation = true
                        }
                    } label: {
                        Label {
                            Text(localizedString("Delete List", locale: locale))
                                .foregroundStyle(theme.colors.primaryText)
                        } icon: {
                            Image(systemName: "trash")
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(theme.colors.destructive)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(titleOverride ?? toolbarTitle)
                            .font(.system(size: 34, weight: .semibold, design: .serif))
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
}
