//
//  DiscoveryView.swift
//  Weather
//
//  Purpose: Defines the Discover-first experience, including the static map
//  preview, sunniness ranking, list switching, and comparison list surface.
//

import SwiftUI
import MapKit

// MARK: - App Modes

enum WeatherAtlasMode: String, CaseIterable, Hashable, Identifiable {
    case discover
    case list
    case map

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .discover: return "sun.max.fill"
        case .map: return "map"
        case .list: return "list.bullet"
        }
    }

    func title(locale: Locale) -> String {
        switch self {
        case .discover: return localizedString("Discover", locale: locale)
        case .map: return localizedString("Map", locale: locale)
        case .list: return localizedString("List", locale: locale)
        }
    }
}

// MARK: - Static Discover Map

struct DiscoveryStaticMapPreview: View {
    let cities: [CityWeather]
    let rankedCandidates: [SunnyCandidate]
    let accent: Color
    let contextDot: Color
    let land: Color
    let water: Color
    let line: Color
    @AppStorage("mapProvider") private var mapProviderRaw: String = WeatherMapProvider.openStreetMap.rawValue
    @State private var previewTappedCity: CityWeather?
    @State private var recenterOnAllCities = false
    @State private var recenterUsesListCoordinates = false
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 48, longitude: 12),
        span: MKCoordinateSpan(latitudeDelta: 28, longitudeDelta: 38)
    ))

    private var rankByCityID: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: rankedCandidates.prefix(5).enumerated().map { ($0.element.cityWeather.id, $0.offset + 1) })
    }

    var body: some View {
        Group {
            if WeatherMapProvider(rawValue: mapProviderRaw) == .appleMaps {
                appleMapPreview
            } else {
                MapLibreWebMapView(
                    cities: cities,
                    fitCities: cities.map(\.city),
                    selectedDayOffset: -1,
                    overlayMode: "weather",
                    filterSunny: false,
                    markerReloadID: rankedCandidates.count,
                    markerSizeScale: 0.88,
                    showsMarkerHoverLabels: false,
                    focusedCountryBoundary: nil,
                    tappedCity: $previewTappedCity,
                    recenterOnAllCities: $recenterOnAllCities,
                    recenterUsesListCoordinates: $recenterUsesListCoordinates,
                    //?whats the diffrence between recenterOnAllCities and recenterUsesListCoordinates?
                    //?i think one recenter declaration is enough
                    centerOnCity: nil,
                    leadingFitPadding: 0,
                    focusSelectedMarker: false,
                    allowsMarkerHover: false,
                    cameraProfile: .preview,
                    onMarkerTap: { _, _ in },
                    onMapClick: nil,
                    onMarkerCommandHover: nil,
                    onCameraMove: nil,
                    onMapGestureStart: nil
                )
                .allowsHitTesting(false)
                .onAppear {
                    refitMapLibrePreview()
                }
                .onChange(of: cities.map(\.id)) { _, _ in
                    refitMapLibrePreview()
                }
            }
        }
        .background(water)
    }

    private func refitMapLibrePreview() {
        recenterUsesListCoordinates = true
        recenterOnAllCities = false
        DispatchQueue.main.async {
            recenterOnAllCities = true
        }
        for delay in [0.18, 0.45, 0.9] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                recenterUsesListCoordinates = true
                recenterOnAllCities = false
                DispatchQueue.main.async {
                    recenterOnAllCities = true
                }
            }
        }
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
                            .fill(contextDot.opacity(0.45))
                            .frame(width: 8, height: 8)
                            .shadow(color: contextDot.opacity(0.20), radius: 4, y: 1)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .allowsHitTesting(false)
        .background(water)
        .onAppear {
            refitApplePreview()
        }
        .onChange(of: cities.map(\.id)) { _, _ in
            refitApplePreview()
        }
    }

    private func numberedDot(rank: Int, candidate: SunnyCandidate?) -> some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.20))
                .frame(width: 34, height: 34)
                .blur(radius: 7)

            Circle()
                .fill((candidate?.score ?? 0) >= 55 ? accent : contextDot.opacity(0.75))
                .frame(width: 23, height: 23)
                .shadow(color: accent.opacity(0.28), radius: 7, y: 2)

            Text("\(rank)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(width: 36, height: 36)
    }

    private func fitAllCities() {
        guard !cities.isEmpty else { return }
        let latitudes = cities.map(\.city.latitude)
        let longitudes = cities.map(\.city.longitude)
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

// MARK: - List Sorting

enum WeatherListSortMode: String, CaseIterable, Identifiable {
    case sunny
    case temperature
    case rain
    case cloud
    case city

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .sunny: return "sun.max.fill"
        case .temperature: return "thermometer.medium"
        case .rain: return "drop.fill"
        case .cloud: return "cloud.fill"
        case .city: return "textformat"
        }
    }

    func title(locale: Locale) -> String {
        switch self {
        case .sunny: return localizedString("Sunny", locale: locale)
        case .temperature: return localizedString("Temperature", locale: locale)
        case .rain: return localizedString("Rain", locale: locale)
        case .cloud: return localizedString("Cloud", locale: locale)
        case .city: return localizedString("City", locale: locale)
        }
    }
}

// MARK: - Sunniness Ranking Model

struct SunnyCandidate: Identifiable {
    let cityWeather: CityWeather
    let score: Double
    let cloudCover: Double?
    let precipitationChance: Double?
    let temperature: Double

    var id: UUID { cityWeather.id }
}

// MARK: - Discover and List Logic

extension ContentView {
    var atlasMode: WeatherAtlasMode {
        WeatherAtlasMode(rawValue: weatherAtlasModeRaw) ?? .map
    }

    var listSortMode: WeatherListSortMode {
        WeatherListSortMode(rawValue: weatherListSortModeRaw) ?? .sunny
    }

    func setAtlasMode(_ mode: WeatherAtlasMode) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            weatherAtlasModeRaw = mode.rawValue
            selectedTab = mode == .list ? 2 : 1
            showingMapSidebar = false
            if mode != .list {
                comparisonListEditMode = false
            }
            if mode != .map && showingMapExpandedCard {
                showingMapExpandedCard = false
            }
        }
        if mode != .list {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                centerMapOnDots(useListCoordinates: true)
            }
        }
    }

    func sunnyCandidate(for cityWeather: CityWeather) -> SunnyCandidate {
        let isNow = selectedDayOffset == -1
        let forecast = cityWeather.forecast(for: max(0, selectedDayOffset))
        let cloudCover = isNow ? cityWeather.currentCloudCover : forecast.cloudCover
        let precipitationChance: Double? = isNow
            ? ([.rain, .drizzle, .snow].contains(cityWeather.condition) ? 1 : 0)
            : forecast.precipitationChance
        let temperature = isNow ? cityWeather.temperature : forecast.dailyHigh

        return SunnyCandidate(
            cityWeather: cityWeather,
            score: sunnyScore(
                condition: isNow ? cityWeather.condition : forecast.condition,
                icon: isNow ? cityWeather.weatherIcon : forecast.weatherIcon,
                cloudCover: cloudCover,
                precipitationChance: precipitationChance,
                temperature: temperature,
                windSpeed: isNow ? cityWeather.currentWindSpeed : forecast.windSpeed,
                uvIndex: isNow ? cityWeather.currentUVIndex : forecast.uvIndex,
                visibility: isNow ? cityWeather.currentVisibility : forecast.maxVisibility
            ),
            cloudCover: cloudCover,
            precipitationChance: precipitationChance,
            temperature: temperature
        )
    }

    func sunnyCandidateIcon(for candidate: SunnyCandidate) -> String {
        selectedDayOffset == -1
            ? candidate.cityWeather.weatherIcon
            : candidate.cityWeather.forecast(for: max(0, selectedDayOffset)).weatherIcon
    }

    // MARK: Sunniness Scoring

    private func sunnyScore(
        condition: AppWeatherCondition,
        icon: String,
        cloudCover: Double?,
        precipitationChance: Double?,
        temperature: Double,
        windSpeed: Double?,
        uvIndex: Int?,
        visibility: Double?
    ) -> Double {
        if icon.contains("moon") {
            return 0
        }
        //? I want to simplify the sunniness scoring system. i only care about the weather condition (the icons), as well as the cloud cover. a day's sunniness score should depend on the above two variables across the entire dya. say london is cloudy condition, with high cloud condotion in part of the day, then the sunniness score is lowered. i want four tiers of scoring by weather condotion: sunny/clear gets highest score, partly sunny 2nd highest, partly cloudy 3rd highest, every remaining stuff gets lowest score
        //? idk why the sunniness scoring code is within the discovery view file. it is actually used across teh app, in detailview as well ( i plan to display it in detailview). so its better moved to another place
        let conditionScore: Double
        switch condition {
        case .clear: conditionScore = 34
        case .partlySunny: conditionScore = 25
        case .partlyCloudy: conditionScore = 14
        case .cloudy, .fog, .wind: conditionScore = 6
        case .rain, .drizzle, .snow: conditionScore = 0
        }

        let cloudScore = (1 - min(max(cloudCover ?? 0.5, 0), 1)) * 24
        let rainScore = (1 - min(max(precipitationChance ?? 0.5, 0), 1)) * 20
        let tempComfort = max(0, 1 - abs(temperature - 25) / 18) * 12
        let windScore = (1 - min(max((windSpeed ?? 18) / 70, 0), 1)) * 5
        let uvScore = min(max(Double(uvIndex ?? 0) / 8, 0), 1) * 3
        let visibilityScore = min(max((visibility ?? 15) / 30, 0), 1) * 2

        return max(0, min(100, conditionScore + cloudScore + rainScore + tempComfort + windScore + uvScore + visibilityScore))
    }

    var sunnyCandidates: [SunnyCandidate] {
        mapCities
            .map(sunnyCandidate(for:))
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.cityWeather.city.localizedName(locale: locale) < rhs.cityWeather.city.localizedName(locale: locale)
            }
    }

    private var discoverySunnyScoreThreshold: Double {
        70
    }

    var recommendedSunnyCandidates: [SunnyCandidate] {
        sunnyCandidates.filter { $0.score >= discoverySunnyScoreThreshold }
    }

    var sortedListCandidates: [SunnyCandidate] {
        let candidates = mapCities.map(sunnyCandidate(for:))
        switch listSortMode {
        case .sunny:
            return candidates.sorted { $0.score > $1.score }
        case .temperature:
            return candidates.sorted { $0.temperature > $1.temperature }
        case .rain:
            return candidates.sorted { ($0.precipitationChance ?? 1) < ($1.precipitationChance ?? 1) }
        case .cloud:
            return candidates.sorted { ($0.cloudCover ?? 1) < ($1.cloudCover ?? 1) }
        case .city:
            return candidates.sorted {
                $0.cityWeather.city.localizedName(locale: locale) < $1.cityWeather.city.localizedName(locale: locale)
            }
        }
    }

    // MARK: Candidate Selection

    func selectCandidate(_ candidate: SunnyCandidate, focusMap: Bool = true) {
        let city = candidate.cityWeather
        if focusMap {
            setAtlasMode(.map)
            centerOnCityTrigger = city
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                showMapMarkerCard(city, expanded: false, focusesMarker: true)
            }
        } else {
            tappedCity = city
            showingMapExpandedCard = false
            showingCityDetail = true
            #if os(iOS)
            if !shouldUseIPadLayout {
                pushIPhoneRoute(.cityDetail)
            } else {
                iPadInspectorPresentedCityID = city.id
            }
            #endif
        }
    }

    // MARK: Discover Page

    var discoveryContent: some View {
        GeometryReader { geometry in
            let snapshotHeight = min(max(geometry.size.height * 0.32, 190), 310)
            ScrollView {
                VStack(spacing: 16) {
                    discoveryPageHeader
                    discoveryMapSnapshot(height: snapshotHeight)
                    discoverySunnySection
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 112)
            }
            .scrollIndicators(.hidden)
            .background(theme.colors.background.ignoresSafeArea())
        }
        .onAppear {
            filterSunny = false
        }
    }

    private var discoveryPageHeader: some View {
        atlasTopHeader {
            EmptyView()
        }
    }

    private func discoveryMapSnapshot(height: CGFloat) -> some View {
        DiscoveryStaticMapPreview(
            cities: mapCities,
            rankedCandidates: Array(recommendedSunnyCandidates.prefix(5)),
            accent: theme.colors.dotSun,
            contextDot: theme.colors.secondaryText,
            land: theme.colors.mapLand,
            water: theme.colors.mapOcean,
            line: theme.colors.accent.opacity(0.28)
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
            #if os(iOS)
            if !shouldUseIPadLayout {
                pushIPhoneRoute(.map)
            } else {
                setAtlasMode(.map) //?what is setatlasmode? explain to me
            }
            #else
            setAtlasMode(.map)
            #endif
        }
    }

    private var discoverySunnySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(theme.colors.dotSun)
                Text(localizedString("Best Sunny Places", locale: locale))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                Spacer(minLength: 8)
                Text(localizedString("Score", locale: locale))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
            }

            discoveryCandidateList()

            Button {
                #if os(iOS)
                if !shouldUseIPadLayout {
                    pushIPhoneRoute(.list)
                } else {
                    setAtlasMode(.list)
                }
                #else
                setAtlasMode(.list)
                #endif
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

    private func discoveryCandidateList(limit: Int? = nil) -> some View {
        let rankedCandidates = limit.map { Array(recommendedSunnyCandidates.prefix($0)) } ?? recommendedSunnyCandidates
        return VStack(spacing: 6) {
            if rankedCandidates.isEmpty {
                Text(localizedString("No strong sunny places for this date.", locale: locale))//?remove the "strong" from that sentence
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
        }
    }

    func sunnyCandidateRow(_ candidate: SunnyCandidate, rank: Int? = nil, compact: Bool = false) -> some View {
        let icon = sunnyCandidateIcon(for: candidate)
        let cloudText = candidate.cloudCover.map { "\(Int($0 * 100))%" } ?? "-"
        return HStack(spacing: 10) {
            if let rank {
                Text("\(rank)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(width: 20)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.cityWeather.city.localizedName(locale: locale))
                    .font(compact ? .callout.weight(.semibold) : .headline.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
                if compact {
                    HStack(spacing: 5) {
                        Image(systemName: icon)
                            .font(.caption.weight(.semibold))
                            .weatherIconStyle(for: icon)
                        Text(String(format: localizedString("%@ cloud", locale: locale), cloudText))
                            .font(.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                } else {
                    let rainText = candidate.precipitationChance.map { "\(Int($0 * 100))%" } ?? "-"
                    Text("\(tempUnit.display(candidate.temperature))  \(cloudText) cloud  \(rainText) rain")
                        .font(.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if !compact {
                Text(tempUnit.display(candidate.temperature))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
            }

            Text("\(Int(candidate.score.rounded()))")
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundStyle(scoreColor(candidate.score))
                .frame(minWidth: 34, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, compact ? 7 : 10)
        .background(theme.colors.glassFill.opacity(0.58), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 75 { return theme.colors.dotSun }
        if score >= 55 { return theme.colors.dotPartlyCloudy }
        return theme.colors.secondaryText
    }

    var weatherComparisonListView: some View {
        VStack(spacing: 0) {
            comparisonListHeader

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(sortedListCandidates.enumerated()), id: \.element.id) { index, candidate in
                        if comparisonListEditMode {
                            comparisonCandidateRow(candidate, rank: index + 1)
                        } else {
                            Button {
                                selectCandidate(candidate)
                            } label: {
                                comparisonCandidateRow(candidate, rank: index + 1)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                cityActions(for: candidate.cityWeather, in: weatherService.activeListID)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 96)
            }
            .scrollContentBackground(.hidden)
        }
        .background(theme.colors.background.ignoresSafeArea())
    }
    //? what is a "comparison list"?
    private var comparisonListHeader: some View {
        VStack(spacing: 12) {
            atlasTopHeader {
                EmptyView()
            }

            HStack(spacing: 10) {
                Menu {
                    ForEach(WeatherListSortMode.allCases) { mode in
                        Button {
                            weatherListSortModeRaw = mode.rawValue
                        } label: {
                            Label(mode.title(locale: locale), systemImage: listSortMode == mode ? "checkmark" : mode.icon)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                        .themedGlass(in: .capsule)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                Button {
                    withAnimation(.smooth(duration: 0.2)) {
                        comparisonListEditMode.toggle()
                    }
                } label: {
                    Image(systemName: comparisonListEditMode ? "checkmark" : "pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                        .themedGlass(in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    func comparisonCandidateRow(_ candidate: SunnyCandidate, rank: Int) -> some View {
        HStack(spacing: 8) {
            if comparisonListEditMode {
                Button {
                    removeComparisonCity(candidate.cityWeather)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(theme.colors.destructive)
                        .frame(width: 34, height: 44)
                }
                .buttonStyle(.plain)
            }

            sunnyCandidateRow(candidate, rank: rank, compact: false)

            if comparisonListEditMode {
                Button {
                    beginEditingComparisonCity(candidate.cityWeather)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .frame(width: 38, height: 44)
                        .themedGlass(in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.smooth(duration: 0.2), value: comparisonListEditMode)
    }

    func beginEditingComparisonCity(_ city: CityWeather) {
        listToRenameID = nil
        showingRenameAlert = false
        cityToRename = city
        cityToRenameListID = weatherService.activeListID
        cityRenameText = city.city.localizedName(locale: locale)
        showingCityRenameAlert = true
    }

    func removeComparisonCity(_ city: CityWeather) {
        weatherService.removeCity(city, from: weatherService.activeListID)
        refreshSidebarCityOrder()
        PlatformFeedback.lightImpact()
    }

    var discoveryListMenu: some View {
        atlasListMenu(titleOverride: nil)
    }
    //?what is an "atlastopheader"
    func atlasTopHeader<Accessory: View>(
        titleOverride: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            atlasListMenu(titleOverride: titleOverride)
            Spacer(minLength: 12)
            accessory()
        }
        .frame(maxWidth: .infinity)
    }
    //?whats that?
    func atlasListMenu(titleOverride: String?) -> some View {
        Menu {
            ForEach(sidebarLists) { listID in
                Button(listID.localizedDisplayName(locale: locale)) {
                    comparisonListEditMode = false
                    Task {
                        await switchToList(listID)
                    }
                }
            }

            Divider()

            Button {
                beginCreatingListFromSwitcher()
            } label: {
                Label(localizedString("New List", locale: locale), systemImage: "plus")
            }
        } label: {
            HStack(spacing: 6) {
                Text(titleOverride ?? toolbarTitle)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                if titleOverride == nil {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
        }
        .menuOrder(.fixed)
        .tint(.primary)
    }
}

//?my app has 3 main views: discover, list, map. is there a dedicated file for the list view, or is that embedded into discoveryview
