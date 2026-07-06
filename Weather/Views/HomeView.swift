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
                .fill(candidate?.score.map { $0 >= 55 ? accent : contextDot.opacity(0.75) } ?? contextDot.opacity(0.75))
                .frame(width: 20, height: 20)
                .shadow(color: accent.opacity(0.24), radius: 6, y: 2)

            Text("\(rank)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(width: 30, height: 30)
    }

    private func markerColor(for cityWeather: CityWeather) -> Color {
        let forecast = cityWeather.forecast(for: max(0, selectedDayOffset))
        let isNow = selectedDayOffset == -1
        let condition = isNow ? cityWeather.condition : forecast.condition
        let icon = isNow ? cityWeather.weatherIcon : forecast.weatherIcon
        let colors = AppTheme.shared.colors
        return icon.contains("moon") ? colors.moonIconColor : condition.dotColor(for: colors)
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
    let score: Double?
    let cloudCover: Double?
    let precipitationChance: Double?
    let temperature: Double

    var id: UUID { cityWeather.id }
}

// MARK: - Home and List Logic

extension ContentView {
    var selectedListSortMode: WeatherListSortMode {
        WeatherListSortMode(rawValue: listSortMode) ?? .sunny
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
                switch (lhs.score, rhs.score) {
                case let (lhsScore?, rhsScore?):
                    if lhsScore != rhsScore { return lhsScore > rhsScore }
                    return lhs.cityWeather.city.localizedName(locale: locale) < rhs.cityWeather.city.localizedName(locale: locale)
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.cityWeather.city.localizedName(locale: locale) < rhs.cityWeather.city.localizedName(locale: locale)
                }
            }
    }

    var homeSunnyScoreThreshold: Double {
        70
    }

    var recommendedSunnyCandidates: [SunnyCandidate] {
        sunnyCandidates.filter { candidate in
            guard let score = candidate.score else { return false }
            return score >= homeSunnyScoreThreshold
        }
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
            return candidates.sorted { lhs, rhs in
                switch (lhs.score, rhs.score) {
                case let (lhsScore?, rhsScore?):
                    if lhsScore != rhsScore { return lhsScore > rhsScore }
                    return lhs.cityWeather.city.localizedName(locale: locale) < rhs.cityWeather.city.localizedName(locale: locale)
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.cityWeather.city.localizedName(locale: locale) < rhs.cityWeather.city.localizedName(locale: locale)
                }
            }
        }
    }

    // MARK: Candidate Selection

    func selectCandidate(_ candidate: SunnyCandidate, focusMap: Bool = true) {
        let city = candidate.cityWeather
        if focusMap {
            pushRoute(.map, showsBackButton: true)
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

    // MARK: Home Page

    var homeContent: some View {
        GeometryReader { geometry in
            let snapshotHeight = min(max(geometry.size.height * 0.32, 190), 310)
            ScrollView {
                VStack(spacing: 16) {
                    homePageHeader
                    homeMapSnapshot(height: snapshotHeight)
                    homeSunnySection
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

    private var homePageHeader: some View {
        topToolbar {
            EmptyView()
        }
    }

    private func homeMapSnapshot(height: CGFloat) -> some View {
        HomeStaticMapPreview(
            cities: mapCities,
            fitCities: mapFitCities,
            rankedCandidates: Array(recommendedSunnyCandidates.prefix(3)),
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
            pushRoute(.map, showsBackButton: true)
        }
    }

    private var homeSunnySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(theme.colors.dotSun)
                Text(localizedString("Best Sunny Places", locale: locale))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                Spacer(minLength: 8)
            }

            homeCandidateList()

            Button {
                pushRoute(.list, showsBackButton: true)
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

    private func homeCandidateList(limit: Int? = nil) -> some View {
        let rankedCandidates = limit.map { Array(recommendedSunnyCandidates.prefix($0)) } ?? recommendedSunnyCandidates
        return VStack(spacing: 0) {
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

                    if index < rankedCandidates.count - 1 {
                        Divider()
                            .background(theme.colors.secondaryText.opacity(0.18))
                            .padding(.leading, 34)
                    }
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

                HStack(spacing: 3) {
                    Image(systemName: "cloud")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.secondaryText.opacity(0.50))
                        .frame(width: 13, alignment: .center)
                    Text(cloudText)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 38, alignment: .leading)
                }
                .frame(width: 54, alignment: .leading)

                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .weatherIconStyle(for: icon)
                    .frame(width: 18, alignment: .leading)
            }
            .foregroundStyle(theme.colors.secondaryText)
            .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
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
                            .font(.system(.title, design: .serif).weight(.semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.colors.primaryText)
                    }
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
                            Text(listID.localizedDisplayName(locale: locale))
                                .foregroundStyle(theme.colors.primaryText)
                        }
                    }

                    Divider()

                    Button {
                        beginCreatingListFromSwitcher()
                    } label: {
                        primaryMenuLabel(localizedString("New List", locale: locale), systemImage: "plus")
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
                                .foregroundStyle(theme.colors.destructive)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(titleOverride ?? toolbarTitle)
                            .font(.system(.title, design: .serif).weight(.semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)
                        if titleOverride == nil {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.colors.primaryText)
                        }
                    }
                }
                .menuOrder(.fixed)
                .tint(theme.colors.primaryText)
            }
        }
    }
}
