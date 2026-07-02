//
//  DiscoveryView.swift
//  Weather
//
//  Purpose: Defines the Discover-first experience, including the static map
//  preview, sunniness ranking, list switching, and ranked city list surface.
//

import SwiftUI
import MapKit

// MARK: - Static Discover Map

struct DiscoveryStaticMapPreview: View {
    let cities: [CityWeather]
    let rankedCandidates: [SunnyCandidate]
    let selectedDayOffset: Int
    let accent: Color
    let contextDot: Color
    let land: Color
    let water: Color
    let line: Color
    @AppStorage("mapProvider") private var mapProviderRaw: String = WeatherMapProvider.openStreetMap.rawValue
    @State private var previewTappedCity: CityWeather?
    @State private var mapRecenterRequest: MapRecenterRequest?
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
                    selectedDayOffset: selectedDayOffset,
                    overlayMode: "weather",
                    filterSunny: false,
                    markerReloadID: markerReloadID,
                    markerSizeScale: 0.88,
                    showsMarkerHoverLabels: false,
                    tappedCity: $previewTappedCity,
                    recenterRequest: $mapRecenterRequest,
                    centerOnCity: nil,
                    leadingFitPadding: 0,
                    focusSelectedMarker: false,
                    allowsMarkerHover: false,
                    cameraProfile: .preview,
                    onMarkerTap: { _, _ in },
                    onMapClick: nil,
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
                .onChange(of: selectedDayOffset) { _, _ in
                    refitMapLibrePreview()
                }
            }
        }
        .background(water)
    }

    private var markerReloadID: Int {
        selectedDayOffset * 10_000 + Int(rankedCandidates.map(\.score).reduce(0, +).rounded())
    }

    private func refitMapLibrePreview() {
        mapRecenterRequest = .listCoordinates
        mapRecenterRequest = nil
        DispatchQueue.main.async {
            mapRecenterRequest = .listCoordinates
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
        case .cloud: return localizedString("Cloud", locale: locale)
        case .sunny: return localizedString("Sunny", locale: locale)
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
    var listSortMode: WeatherListSortMode {
        WeatherListSortMode(rawValue: weatherListSortModeRaw) ?? .sunny
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
            score: SunninessScoring.score(
                condition: isNow ? cityWeather.condition : forecast.condition,
                icon: isNow ? cityWeather.weatherIcon : forecast.weatherIcon,
                cloudCover: cloudCover
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
        case .temperature:
            return candidates.sorted { $0.temperature > $1.temperature }
        case .cloud:
            return candidates.sorted { ($0.cloudCover ?? 1) < ($1.cloudCover ?? 1) }
        case .sunny:
            return candidates.sorted { $0.score > $1.score }
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
                showMapMarkerCard(city, expanded: false, focusesMarker: true)
            }
        } else {
            tappedCity = city
            showingMapExpandedCard = false
            presentDetail(for: city)
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
        topToolbar {
            EmptyView()
        }
    }

    private func discoveryMapSnapshot(height: CGFloat) -> some View {
        DiscoveryStaticMapPreview(
            cities: mapCities,
            rankedCandidates: Array(recommendedSunnyCandidates.prefix(5)),
            selectedDayOffset: selectedDayOffset,
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
            pushRoute(.map)
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
            }

            discoveryCandidateList()

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

    private func discoveryCandidateList(limit: Int? = nil) -> some View {
        let rankedCandidates = limit.map { Array(recommendedSunnyCandidates.prefix($0)) } ?? recommendedSunnyCandidates
        return VStack(spacing: 6) {
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
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 9) {
                HStack(spacing: 3) {
                    Image(systemName: "thermometer.medium")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.secondaryText.opacity(0.72))
                        .frame(width: 13, alignment: .center)
                    Text(tempUnit.display(candidate.temperature))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 34, alignment: .leading)
                }
                .frame(width: 50, alignment: .leading)

                HStack(spacing: 3) {
                    Image(systemName: "cloud")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.secondaryText.opacity(0.50))
                        .frame(width: 13, alignment: .center)
                    Text(cloudText)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 30, alignment: .leading)
                }
                .frame(width: 48, alignment: .leading)

                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .weatherIconStyle(for: icon)
                    .frame(width: 20, alignment: .center)
            }
            .foregroundStyle(theme.colors.secondaryText)
            .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(theme.colors.glassFill.opacity(0.58), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    var discoveryListMenu: some View {
        atlasListMenu(titleOverride: nil)
    }
    func topToolbar<Accessory: View>(
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
    func atlasListMenu(titleOverride: String?) -> some View {
        Group {
            if listEditMode && titleOverride == nil {
                Button {
                    listToRenameID = weatherService.activeListID
                    renameAlertText = weatherService.activeListID.localizedDisplayName(locale: locale)
                    showingRenameAlert = true
                } label: {
                    HStack(spacing: 6) {
                        Text(toolbarTitle)
                            .font(.title2.weight(.semibold))
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    ForEach(managedLists) { listID in
                        Button(listID.localizedDisplayName(locale: locale)) {
                            listEditMode = false
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
    }
}
