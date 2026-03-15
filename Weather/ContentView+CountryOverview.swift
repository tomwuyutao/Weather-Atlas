//
//  ContentView+CountryOverview.swift
//  Weather
//
//  Country Overview mode: pin-to-select a country, generate a weather grid,
//  fetch + cache results, and display the overlay UI.
//

import SwiftUI
import MapKit

#if !os(macOS)
extension ContentView {

    // MARK: - Country-under-pin tracking

    func updateCountryUnderPin() {
        guard countrySelectionMode, let coord = mapCenterCoordinate else { return }
        updateCountryUnderPinDirect(coord)
    }

    func updateCountryUnderPinDirect(_ coord: CLLocationCoordinate2D) {
        let svgPoint = GeoProjection.geoToSVG(latitude: coord.latitude, longitude: coord.longitude)
        let found = countries.first(where: { $0.path.boundingBox.contains(svgPoint) && $0.path.contains(svgPoint) })
        let name = found?.title ?? ""
        if name != countryUnderPin {
            withAnimation(.easeOut(duration: 0.15)) {
                countryUnderPin = name
            }
            gridPreviewTask?.cancel()
            gridPreviewPoints = []
            if let country = found {
                let title = country.title
                gridPreviewTask = Task {
                    // Small delay so rapid panning doesn't trigger expensive computation
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    // Recheck that the country is still the same
                    guard countryUnderPin == title else { return }
                    let grid = generateCountryGrid(for: country)
                    guard !Task.isCancelled, countryUnderPin == title else { return }
                    gridPreviewPoints = grid.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    }
                }
            }
        }
    }

    // MARK: - Grid Generation

    func generateCountryGrid(for country: CountryPath, maxPoints: Int = 100) -> [City] {
        let bbox = country.path.boundingBox
        let topLeft = GeoProjection.svgToGeo(svgPoint: CGPoint(x: bbox.minX, y: bbox.minY))
        let bottomRight = GeoProjection.svgToGeo(svgPoint: CGPoint(x: bbox.maxX, y: bbox.maxY))

        let minLat = min(topLeft.latitude, bottomRight.latitude)
        let maxLat = max(topLeft.latitude, bottomRight.latitude)
        let minLon = min(topLeft.longitude, bottomRight.longitude)
        let maxLon = max(topLeft.longitude, bottomRight.longitude)

        let midLat = (minLat + maxLat) / 2

        // Try increasing spacing until we're under maxPoints
        for spacing in [0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0, 7.0] {
            // Adjust longitude spacing so the grid appears square on Mercator projection
            let lonSpacing = spacing / max(cos(midLat * .pi / 180), 0.3)
            var gridCities: [City] = []
            var lat = minLat + spacing / 2
            while lat <= maxLat {
                var lon = minLon + lonSpacing / 2
                while lon <= maxLon {
                    let svgPoint = GeoProjection.geoToSVG(latitude: lat, longitude: lon)
                    if country.path.contains(svgPoint) {
                        // Normalize longitude to -180...180 for WeatherKit
                        var normalizedLon = lon
                        if normalizedLon > 180 { normalizedLon -= 360 }
                        if normalizedLon < -180 { normalizedLon += 360 }
                        let city = City(
                            name: "\(country.title) \(gridCities.count + 1)",
                            country: country.title,
                            latitude: lat,
                            longitude: normalizedLon
                        )
                        gridCities.append(city)
                    }
                    lon += lonSpacing
                }
                lat += spacing
            }
            if gridCities.count <= maxPoints {
                return gridCities
            }
        }
        return []
    }

    // MARK: - Confirm / Load

    func confirmCountryOverview() {
        let name = countryUnderPin
        guard let country = countries.first(where: { $0.title == name }) else { return }

        countryOverviewCountryName = name
        gridPreviewPoints = []

        // Check cache (2 hour validity)
        if let cached = countryOverviewCache[name],
           Date().timeIntervalSince(cached.date) < 7200 {
            countryOverviewData = cached.data
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                countrySelectionMode = false
                countryUnderPin = ""
                countryOverviewActive = true
            }
            return
        }

        let gridCities = generateCountryGrid(for: country)
        guard !gridCities.isEmpty else { return }

        countryOverviewData = []
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            countrySelectionMode = false
            countryUnderPin = ""
            isLoadingCountryOverview = true
            countryOverviewActive = true
        }

        countryOverviewLoadingTask = Task {
            let results = await weatherService.fetchWeatherForGrid(gridCities, onProgress: { progress in
                Task { @MainActor in
                    countryOverviewProgress = progress
                }
            }, onResult: { cityWeather in
                Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.2)) {
                        countryOverviewData.append(cityWeather)
                    }
                }
            })
            guard !Task.isCancelled else { return }
            await MainActor.run {
                countryOverviewCache[name] = (data: results, date: Date())
                CountryOverviewCacheManager.save(countryOverviewCache)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isLoadingCountryOverview = false
                    countryOverviewProgress = 0
                }
            }
        }
    }

    // MARK: - Overlay Views

    var countrySelectionTopOverlay: some View {
        ZStack {
            // Center pin — offset upward so the tip points at the map center
            Image(systemName: "mappin")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(theme.colors.destructive)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                .offset(y: -18)

            // Top capsule with country name
            VStack {
                if !countryUnderPin.isEmpty {
                    Text(countryUnderPin)
                        .font(.avenir(.headline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .themedGlass(in: .capsule)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text(localizedString("Move map to select a country", locale: locale))
                        .font(.avenir(.subheadline, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .themedGlass(in: .capsule)
                }

                Spacer()
            }
            .padding(.top, 60)
        }
    }

    @ViewBuilder
    var countrySearchBottomBar: some View {
        VStack {
            Spacer()

            GlassEffectContainer(spacing: 20) {
                HStack(spacing: countrySelectionMode ? 20 : 12) {
                    if countrySelectionMode {
                        // Confirm button
                        Button {
                            confirmCountryOverview()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(countryUnderPin.isEmpty ? .gray : AppTheme.shared.colors.accent, in: .circle)
                        }
                        .buttonStyle(.plain)
                        .glassEffectID("cConfirm", in: countryBarNS)
                        .disabled(countryUnderPin.isEmpty)
                    } else {
                        // Loading capsule
                        HStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.small)

                            Text(String(format: localizedString("Loading %@…", locale: locale), countryOverviewCountryName))
                                .font(.avenir(.subheadline, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text("\(Int(countryOverviewProgress * 100))%")
                                .font(.avenir(.subheadline, weight: .medium))
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .themedGlass(in: .capsule)
                        .glassEffectID("cConfirm", in: countryBarNS)
                    }

                    if !countrySelectionMode {
                        Spacer()
                    }

                    // Cancel button
                    Button {
                        if isLoadingCountryOverview {
                            countryOverviewLoadingTask?.cancel()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isLoadingCountryOverview = false
                                countryOverviewActive = false
                                countryOverviewData = []
                                countryOverviewCountryName = ""
                                countryOverviewProgress = 0
                                recenterOnAllCities = true
                            }
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                countrySelectionMode = false
                                countryUnderPin = ""
                                gridPreviewPoints = []
                                recenterOnAllCities = true
                            }
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .frame(width: 44, height: 44)
                            .themedGlass(in: .circle)
                    }
                    .buttonStyle(.plain)
                    .glassEffectID("cCancel", in: countryBarNS)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: countrySelectionMode)
            }
        }
    }

    var countryOverviewExitOverlay: some View {
        VStack {
            Spacer()

            HStack(alignment: .bottom, spacing: 12) {
                // Exit capsule — left aligned
                HStack(spacing: 12) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(countryOverviewCountryName)
                        .font(.avenir(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .themedGlass(in: .capsule)
                .contentShape(Capsule())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showingMapExpandedCard = false
                        tappedCity = nil
                        countryOverviewActive = false
                        countryOverviewData = []
                        countryOverviewCountryName = ""
                        resolvedGridCityNames = [:]
                        resolvedGridCityName = nil
                        recenterOnAllCities = true
                    }
                }

                Spacer()

                // Recenter + map settings — right aligned
                HStack(spacing: 8) {
                    Button {
                        focusSubsetCities = countryOverviewData
                        focusSubsetTrigger = true
                    } label: {
                        Image(systemName: "dot.squareshape.split.2x2")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingMapStyleSheet = true
                    } label: {
                        Image(systemName: "square.3.layers.3d")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(6)
                .themedGlass(in: .capsule)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
    }
}

// MARK: - Cache

struct CachedCountryOverviewEntry: Codable {
    let countryName: String
    let data: [CachedCityWeather]
    let date: Date
}

enum CountryOverviewCacheManager {
    private static let cacheKey = "countryOverviewCache"

    static func load() -> [String: (data: [CityWeather], date: Date)] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let entries = try? JSONDecoder().decode([CachedCountryOverviewEntry].self, from: data) else {
            return [:]
        }
        var result: [String: (data: [CityWeather], date: Date)] = [:]
        for entry in entries {
            // Skip entries older than 2 hours
            if Date().timeIntervalSince(entry.date) < 7200 {
                result[entry.countryName] = (data: entry.data.map { $0.toCityWeather() }, date: entry.date)
            }
        }
        return result
    }

    static func save(_ cache: [String: (data: [CityWeather], date: Date)]) {
        let entries = cache.compactMap { name, value -> CachedCountryOverviewEntry? in
            // Only persist entries less than 2 hours old
            guard Date().timeIntervalSince(value.date) < 7200 else { return nil }
            return CachedCountryOverviewEntry(
                countryName: name,
                data: value.data.map { CachedCityWeather(from: $0) },
                date: value.date
            )
        }
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
        }
    }
}
#endif
