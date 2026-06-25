//
//  DiscoveryView.swift
//  Weather
//
//  Discovery, mode switching, sunny ranking, and comparison-list surfaces.
//

import SwiftUI

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

struct SunnyCandidate: Identifiable {
    let cityWeather: CityWeather
    let score: Double
    let cloudCover: Double?
    let precipitationChance: Double?
    let temperature: Double

    var id: UUID { cityWeather.id }
}

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

    func atlasModeButton(_ mode: WeatherAtlasMode, size: CGFloat = 44) -> some View {
        Button {
            setAtlasMode(mode)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: mode.icon)
                    .font(.system(size: 17, weight: atlasMode == mode ? .semibold : .regular))
                Text(mode.title(locale: locale))
                    .font(.caption2.weight(atlasMode == mode ? .semibold : .regular))
            }
            .foregroundStyle(atlasMode == mode ? theme.colors.accent : theme.colors.primaryText)
            .frame(width: size + 12, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tint(atlasMode == mode ? theme.colors.accent : theme.colors.primaryText)
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

    func selectCandidate(_ candidate: SunnyCandidate, focusMap: Bool = true) {
        let city = candidate.cityWeather
        if focusMap {
            setAtlasMode(.map)
        }
        centerOnCityTrigger = city
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            showMapMarkerCard(city, expanded: false, focusesMarker: true)
        }
    }

    var discoveryContent: some View {
        ZStack {
            iOSMapView
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if !showingInlineSearch {
                discoveryCandidateOverlay
            }

            if showingMapExpandedCard, let city = tappedCity {
                iOSFloatingMapCardOverlay(for: city)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            filterSunny = false
            centerMapOnDots(useListCoordinates: true)
        }
        .onChange(of: weatherService.activeListID) { _, _ in
            centerMapOnDots(useListCoordinates: true)
        }
        .onChange(of: mapCities.count) { _, _ in
            centerMapOnDots(useListCoordinates: true)
        }
    }

    private func iOSFloatingMapCardOverlay(for city: CityWeather) -> some View {
        VStack {
            Spacer()
            mapExpandedCard(for: city, forceIPhoneStyle: !usesFloatingMapCardLayout)
                .padding(.horizontal, 16)
                .padding(.bottom, 92)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    var discoveryCandidateOverlay: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < 620
            VStack(alignment: .leading, spacing: 10) {
                discoveryHeader
                discoveryCandidateList(limit: isCompact ? 4 : 6)
            }
            .padding(12)
            .frame(width: isCompact ? min(geometry.size.width - 28, 390) : 390)
            .themedGlass(in: .rect(cornerRadius: 22))
            .padding(.horizontal, isCompact ? 14 : 18)
            .padding(.bottom, isCompact ? 104 : 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isCompact ? .bottom : .bottomLeading)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var discoveryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(theme.colors.dotSun)
                Text(localizedString("Best Sunny Places", locale: locale))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                Spacer(minLength: 8)
                iOSDateSwitcherCapsule
            }

            HStack(spacing: 8) {
                discoveryListMenu
                Spacer(minLength: 8)
            }
        }
    }

    private func discoveryCandidateList(limit: Int) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(sunnyCandidates.prefix(limit).enumerated()), id: \.element.id) { index, candidate in
                Button {
                    selectCandidate(candidate)
                } label: {
                    sunnyCandidateRow(candidate, rank: index + 1, compact: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    func sunnyCandidateRow(_ candidate: SunnyCandidate, rank: Int? = nil, compact: Bool = false) -> some View {
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
                if !compact {
                    let cloudText = candidate.cloudCover.map { "\(Int($0 * 100))%" } ?? "-"
                    let rainText = candidate.precipitationChance.map { "\(Int($0 * 100))%" } ?? "-"
                    Text("\(tempUnit.display(candidate.temperature))  \(cloudText) cloud  \(rainText) rain")
                        .font(.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(tempUnit.display(candidate.temperature))
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)

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

    private var comparisonListHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                discoveryListMenu
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
                }
                .buttonStyle(.plain)
                .themedGlass(in: .capsule)
            }

            HStack(spacing: 10) {
                iOSDateSwitcherCapsule
                Spacer(minLength: 8)
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
            HStack(spacing: 8) {
                Text(toolbarTitle)
                    .font(.headline)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .menuOrder(.fixed)
        .tint(.primary)
    }
}
