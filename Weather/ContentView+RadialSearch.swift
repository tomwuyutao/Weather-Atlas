//
//  ContentView+RadialSearch.swift
//  Weather
//
//  Extracted from ContentView.swift
//

import SwiftUI
import MapKit

extension ContentView {

    // MARK: - Radial Grid Generation

    func generateRadialGrid(center: CLLocationCoordinate2D, radiusMeters: Double, maxPoints: Int = 60) -> [City] {
        let latDegreesPerMeter = 1.0 / 111_320.0
        let radiusDegLat = radiusMeters * latDegreesPerMeter
        let radiusDegLon = radiusDegLat / max(cos(center.latitude * .pi / 180), 0.1)

        let minLat = center.latitude - radiusDegLat
        let maxLat = center.latitude + radiusDegLat
        let minLon = center.longitude - radiusDegLon
        let maxLon = center.longitude + radiusDegLon

        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)

        // Finer spacing tiers for smaller circles
        let spacings: [Double] = radiusMeters < 100_000 ? [0.4, 0.5, 0.75, 1.0, 1.5, 2.0] :
                                  radiusMeters < 200_000 ? [0.75, 1.0, 1.5, 2.0, 3.0] :
                                  [1.0, 1.5, 2.0, 3.0, 4.0, 5.0]
        for spacing in spacings {
            let lonSpacing = spacing / max(cos(center.latitude * .pi / 180), 0.3)
            var gridCities: [City] = []
            var lat = minLat + spacing / 2
            while lat <= maxLat {
                var lon = minLon + lonSpacing / 2
                while lon <= maxLon {
                    let pointLocation = CLLocation(latitude: lat, longitude: lon)
                    if centerLocation.distance(from: pointLocation) <= radiusMeters {
                        var normalizedLon = lon
                        if normalizedLon > 180 { normalizedLon -= 360 }
                        if normalizedLon < -180 { normalizedLon += 360 }

                        // Clip to land: check if point falls on any country SVG path
                        let svgPoint = GeoProjection.geoToSVG(latitude: lat, longitude: normalizedLon)
                        let isOnLand = countries.contains { country in
                            country.path.boundingBox.contains(svgPoint) && country.path.contains(svgPoint)
                        }
                        if isOnLand {
                            let city = City(
                                name: "Radial \(gridCities.count + 1)",
                                country: "Radial Search",
                                latitude: lat,
                                longitude: normalizedLon
                            )
                            gridCities.append(city)
                        }
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

    func updateRadialGridPreview() {
        guard radialSearchMode, let coord = mapCenterCoordinate else { return }
        radialGridPreviewTask?.cancel()
        gridPreviewPoints = []
        radialGridPreviewTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, radialSearchMode else { return }
            let grid = generateRadialGrid(center: coord, radiusMeters: radialSearchRadius)
            guard !Task.isCancelled, radialSearchMode else { return }
            gridPreviewPoints = grid.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
        }
    }

    // MARK: - Radial Search Overlays

    var radialSelectionTopOverlay: some View {
        VStack {
            Text(formatRadius(radialSearchRadius))
                .font(.avenir(.headline, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .themedGlass(in: .capsule)
                .contentTransition(.numericText())

            Spacer()
        }
        .padding(.top, 60)
    }

    func formatRadius(_ meters: Double) -> String {
        let distUnit = DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
        if distUnit == .miles {
            let miles = meters / 1609.344
            if miles >= 1 {
                return String(format: "%.0f mi", miles)
            }
            let feet = meters * 3.28084
            return String(format: "%.0f ft", feet)
        }
        if meters >= 1000 {
            return String(format: "%.0f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }

    func confirmRadialSearch() {
        guard let center = mapCenterCoordinate else { return }
        gridPreviewPoints = []

        let gridCities = generateRadialGrid(center: center, radiusMeters: radialSearchRadius)
        guard !gridCities.isEmpty else { return }

        radialSearchData = []
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            radialSearchActive = true
            isLoadingRadialSearch = true
            radialSearchMode = false
        }

        radialSearchLoadingTask = Task {
            let results = await weatherService.fetchWeatherForGrid(gridCities, onProgress: { progress in
                Task { @MainActor in
                    radialSearchProgress = progress
                }
            }, onResult: { cityWeather in
                Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.2)) {
                        radialSearchData.append(cityWeather)
                    }
                }
            })
            guard !Task.isCancelled else { return }
            await MainActor.run {
                _ = results
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isLoadingRadialSearch = false
                    radialSearchProgress = 0
                }
            }
        }
    }

    @ViewBuilder
    var radialSearchBottomBar: some View {
        VStack {
            Spacer()

            GlassEffectContainer(spacing: 20) {
                HStack(spacing: radialSearchMode ? 20 : 12) {
                    if radialSearchMode {
                        // Confirm button
                        Button {
                            confirmRadialSearch()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .glassEffectID("rConfirm", in: radialBarNS)
                    } else {
                        // Loading capsule
                        HStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.small)

                            Text(localizedString("Radial Search…", locale: locale))
                                .font(.avenir(.subheadline, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text("\(Int(radialSearchProgress * 100))%")
                                .font(.avenir(.subheadline, weight: .medium))
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .themedGlass(in: .capsule)
                        .glassEffectID("rConfirm", in: radialBarNS)
                    }

                    if !radialSearchMode {
                        Spacer()
                    }

                    // Cancel button
                    Button {
                        if isLoadingRadialSearch {
                            radialSearchLoadingTask?.cancel()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isLoadingRadialSearch = false
                                radialSearchActive = false
                                radialSearchData = []
                                radialSearchProgress = 0
                                recenterOnAllCities = true
                            }
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                radialSearchMode = false
                                gridPreviewPoints = []
                                radialSearchRadius = 160_000
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
                    .glassEffectID("rCancel", in: radialBarNS)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: radialSearchMode)
            }
        }
    }

    var radialSearchExitOverlay: some View {
        VStack {
            Spacer()

            HStack(alignment: .bottom, spacing: 12) {
                // Exit capsule — left aligned
                HStack(spacing: 12) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(localizedString("Radial Search", locale: locale))
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
                        radialSearchActive = false
                        radialSearchData = []
                        resolvedGridCityNames = [:]
                        resolvedGridCityName = nil
                        recenterOnAllCities = true
                    }
                }

                Spacer()

                // Recenter + map settings — right aligned
                HStack(spacing: 8) {
                    Button {
                        focusSubsetCities = radialSearchData
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
