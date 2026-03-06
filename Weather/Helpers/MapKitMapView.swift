//
//  MapKitMapView.swift
//  Weather
//
//  MapKit-based map view with custom SVG country overlay and weather marker annotations.
//

import SwiftUI
import MapKit

struct MapKitMapView: View {
    let countries: [CountryPath]
    let cities: [CityWeather]
    let selectedDayOffset: Int
    let showCloudCover: Bool
    let filterSunny: Bool
    let isPlaying: Bool
    let namespace: Namespace.ID

    @Binding var showingCityDetail: Bool
    @Binding var tappedCity: CityWeather?

    var centerOnCity: CityWeather?
    @Binding var recenterOnAllCities: Bool
    var focusOnSubsetCities: [CityWeather] = []
    @Binding var focusOnSubsetTrigger: Bool
    var mapMode: String = "minimal"
    var onDoubleTapMarker: (() -> Void)?

    @State private var position: MapCameraPosition = .automatic
    @State private var hasCenteredOnCities: Bool = false
    @State private var highlightedMarkerID: UUID?
    @State private var tappedMarkerID: UUID?

    // Incremented on every camera change to force overlay redraw
    @State private var cameraChangeCounter: Int = 0

    var body: some View {
        MapReader { proxy in
            Map(position: $position, interactionModes: [.pan, .zoom]) {
                // Empty map content — annotations rendered manually above overlay
            }
            .mapStyle(.standard(elevation: .flat, emphasis: mapMode == "detailed" ? .muted : .automatic, pointsOfInterest: .excludingAll))
            .mapControls { }
            .environment(\.locale, Locale(identifier: "en"))
            .onMapCameraChange(frequency: .continuous) { _ in
                cameraChangeCounter += 1
            }
            // SVG country overlay
            .overlay {
                if mapMode == "minimal" || mapMode == "borders" || mapMode == "calibration" {
                    SVGProxyOverlay(
                        countries: countries,
                        proxy: proxy,
                        cameraChangeCounter: cameraChangeCounter,
                        style: mapMode == "borders" ? .borders : (mapMode == "calibration" ? .calibration : .filled),
                        cities: mapMode == "borders" ? cities : []
                    )
                    .allowsHitTesting(false)
                }
            }
            // Weather marker annotations on top of SVG overlay (non-interactive so map gestures pass through)
            .overlay {
                AnnotationsOverlay(
                    cities: cities,
                    proxy: proxy,
                    cameraChangeCounter: cameraChangeCounter,
                    selectedDayOffset: selectedDayOffset,
                    showCloudCover: showCloudCover,
                    filterSunny: filterSunny,
                    isPlaying: isPlaying,
                    namespace: namespace,
                    highlightedMarkerID: highlightedMarkerID,
                    tappedMarkerID: tappedMarkerID,
                    showingCityDetail: $showingCityDetail,
                    tappedCity: $tappedCity
                )
                .allowsHitTesting(false)
            }
            // Transparent tap detection layer — finds nearest marker on tap
            .onTapGesture { location in
                let _ = cameraChangeCounter
                let tapRadius: CGFloat = 30.0
                var closest: (city: CityWeather, dist: CGFloat)?
                for cityWeather in cities {
                    guard passesFilter(cityWeather) else { continue }
                    guard let pt = proxy.convert(
                        CLLocationCoordinate2D(
                            latitude: cityWeather.city.latitude,
                            longitude: cityWeather.city.longitude
                        ),
                        to: .local
                    ) else { continue }
                    let dx = pt.x - location.x
                    let dy = pt.y - location.y
                    let dist = sqrt(dx * dx + dy * dy)
                    if dist < tapRadius {
                        if closest == nil || dist < closest!.dist {
                            closest = (city: cityWeather, dist: dist)
                        }
                    }
                }
                if let hit = closest {
                    // If tapping the already-selected marker, go to detail view
                    if showingCityDetail && tappedCity?.id == hit.city.id {
                        onDoubleTapMarker?()
                        return
                    }
                    tappedCity = hit.city
                    tappedMarkerID = hit.city.id
                    Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            showingCityDetail = true
                        }
                        try? await Task.sleep(for: .milliseconds(100))
                        tappedMarkerID = nil
                    }
                } else {
                    // Tapped empty space — dismiss expanded card
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showingCityDetail = false
                    }
                }
            }
            .onAppear {
                if !cities.isEmpty && !hasCenteredOnCities {
                    fitAllCities(animated: false)
                    hasCenteredOnCities = true
                }
            }
            .onChange(of: cities.count) { _, newCount in
                if newCount > 0 && !hasCenteredOnCities {
                    fitAllCities(animated: false)
                    hasCenteredOnCities = true
                }
            }
            .onChange(of: recenterOnAllCities) { _, newValue in
                if newValue {
                    fitAllCities(animated: true)
                    recenterOnAllCities = false
                }
            }
            .onChange(of: focusOnSubsetTrigger) { _, newValue in
                if newValue && !focusOnSubsetCities.isEmpty {
                    fitCities(focusOnSubsetCities, animated: true)
                    focusOnSubsetTrigger = false
                }
            }
            .onChange(of: centerOnCity?.id) { _, _ in
                if let city = centerOnCity {
                    animateToCity(city)
                    highlightedMarkerID = city.id
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(.easeOut(duration: 0.5)) {
                            highlightedMarkerID = nil
                        }
                    }
                }
            }
        }
    }

    private func passesFilter(_ cityWeather: CityWeather) -> Bool {
        guard filterSunny else { return true }
        let forecast = cityWeather.forecast(for: selectedDayOffset)
        return forecast.condition == .clear
    }

    private func fitAllCities(animated: Bool) {
        fitCities(cities, animated: animated)
    }

    private func fitCities(_ citiesToFit: [CityWeather], animated: Bool) {
        guard !citiesToFit.isEmpty else { return }

        var minLat = Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        var minLon = Double.greatestFiniteMagnitude
        var maxLon = -Double.greatestFiniteMagnitude

        for city in citiesToFit {
            minLat = min(minLat, city.city.latitude)
            maxLat = max(maxLat, city.city.latitude)
            minLon = min(minLon, city.city.longitude)
            maxLon = max(maxLon, city.city.longitude)
        }

        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let spanLat = max((maxLat - minLat) * 1.4, 2.0)
        let spanLon = max((maxLon - minLon) * 1.4, 2.0)

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
        )

        if animated {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                position = .region(region)
            }
        } else {
            position = .region(region)
        }
    }

    private func animateToCity(_ cityWeather: CityWeather) {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: cityWeather.city.latitude,
                longitude: cityWeather.city.longitude
            ),
            span: MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 5.0)
        )
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            position = .region(region)
        }
    }
}

// MARK: - Annotations Overlay

/// Renders weather markers above the SVG overlay using MapProxy to position them.
private struct AnnotationsOverlay: View {
    let cities: [CityWeather]
    let proxy: MapProxy
    let cameraChangeCounter: Int
    let selectedDayOffset: Int
    let showCloudCover: Bool
    let filterSunny: Bool
    let isPlaying: Bool
    let namespace: Namespace.ID
    let highlightedMarkerID: UUID?
    let tappedMarkerID: UUID?
    @Binding var showingCityDetail: Bool
    @Binding var tappedCity: CityWeather?

    var body: some View {
        // Use cameraChangeCounter to force re-evaluation on pan/zoom
        let _ = cameraChangeCounter
        
        GeometryReader { geometry in
            // Collect on-screen marker positions for collision detection
            let screenPositions: [(id: UUID, pt: CGPoint)] = cities.compactMap { cityWeather in
                guard passesFilter(cityWeather) else { return nil }
                guard let pt = proxy.convert(
                    CLLocationCoordinate2D(
                        latitude: cityWeather.city.latitude,
                        longitude: cityWeather.city.longitude
                    ),
                    to: .local
                ) else { return nil }
                let margin: CGFloat = 40
                guard pt.x > -margin && pt.x < geometry.size.width + margin &&
                      pt.y > -margin && pt.y < geometry.size.height + margin else { return nil }
                return (id: cityWeather.id, pt: pt)
            }
            let markerMode = computeDisplayMode(screenPositions)

            ForEach(cities) { cityWeather in
                if passesFilter(cityWeather),
                   let screenPt = proxy.convert(
                    CLLocationCoordinate2D(
                        latitude: cityWeather.city.latitude,
                        longitude: cityWeather.city.longitude
                    ),
                    to: .local
                   ) {
                    WeatherMarker(
                        cityWeather: cityWeather,
                        dayOffset: selectedDayOffset,
                        isCompact: true,
                        namespace: namespace,
                        showCloudCover: showCloudCover,
                        filterSunny: filterSunny,
                        passesFilter: true,
                        isPlaying: isPlaying,
                        displayMode: markerMode,
                        isSelected: showingCityDetail && tappedCity?.id == cityWeather.id
                    )
                    .overlay {
                        if highlightedMarkerID == cityWeather.id {
                            MapRevealPulseRing()
                        }
                    }

                    .position(screenPt)
                }
            }
        }
    }

    private func passesFilter(_ cityWeather: CityWeather) -> Bool {
        guard filterSunny else { return true }
        let forecast = cityWeather.forecast(for: selectedDayOffset)
        return forecast.condition == .clear
    }

    private func computeDisplayMode(_ positions: [(id: UUID, pt: CGPoint)]) -> MarkerDisplayMode {
        // Pin size: label (~50 wide) + dot below, with padding
        let cardWidth: CGFloat = 54
        let cardHeight: CGFloat = 46
        if !anyRectOverlapping(positions, width: cardWidth, height: cardHeight) {
            return .card
        }
        return .dot
    }

    private func anyRectOverlapping(_ positions: [(id: UUID, pt: CGPoint)], width: CGFloat, height: CGFloat) -> Bool {
        let halfW = width / 2
        let halfH = height / 2
        for i in 0..<positions.count {
            for j in (i + 1)..<positions.count {
                let dx = abs(positions[i].pt.x - positions[j].pt.x)
                let dy = abs(positions[i].pt.y - positions[j].pt.y)
                if dx < halfW + halfW && dy < halfH + halfH {
                    return true
                }
            }
        }
        return false
    }
}

// MARK: - SVG Country Overlay

/// Uses MapProxy.convert to get exact screen positions of reference coordinates,
/// then draws transformed SVG country paths in a Canvas.
private struct SVGProxyOverlay: View {
    enum Style { case filled, borders, calibration }

    let countries: [CountryPath]
    let proxy: MapProxy
    let cameraChangeCounter: Int
    var style: Style = .filled
    var cities: [CityWeather] = []

    private static let refCoordA = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
    private static let refCoordB = CLLocationCoordinate2D(latitude: 45.0, longitude: 90.0)
    private static let refSvgA = GeoProjection.geoToSVG(latitude: 0.0, longitude: 0.0)
    private static let refSvgB = GeoProjection.geoToSVG(latitude: 45.0, longitude: 90.0)

    /// Returns the set of country IDs that contain at least one city
    private var countriesWithCities: Set<String> {
        guard !cities.isEmpty else { return [] }
        let svgPoints = cities.map { city in
            GeoProjection.geoToSVG(latitude: city.city.latitude, longitude: city.city.longitude)
        }
        var ids = Set<String>()
        for country in countries {
            for pt in svgPoints {
                if country.path.contains(pt) {
                    ids.insert(country.id)
                    break
                }
            }
        }
        return ids
    }

    var body: some View {
        let ptA = proxy.convert(Self.refCoordA, to: .local)
        let ptB = proxy.convert(Self.refCoordB, to: .local)

        Canvas { context, size in
            let _ = cameraChangeCounter

            guard let screenA = ptA, let screenB = ptB else { return }
            guard size.width > 0, size.height > 0 else { return }

            // Fill entire canvas with black ocean (not in calibration mode)
            if style != .calibration {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            }

            let svgA = Self.refSvgA
            let svgB = Self.refSvgB
            let svgDx = Double(svgB.x - svgA.x)
            let svgDy = Double(svgB.y - svgA.y)
            guard abs(svgDx) > 0.001, abs(svgDy) > 0.001 else { return }

            let scaleX = (screenB.x - screenA.x) / svgDx
            let baseScaleY = (screenB.y - screenA.y) / svgDy
            guard scaleX.isFinite, baseScaleY.isFinite, scaleX != 0, baseScaleY != 0 else { return }

            // Stretch vertically by a small factor, anchored at the equator (refA)
            let yStretch = 1.0032
            let scaleY = baseScaleY * yStretch
            let tx = screenA.x - Double(svgA.x) * scaleX
            let ty = screenA.y - Double(svgA.y) * scaleY

            var transform = CGAffineTransform(
                a: scaleX, b: 0,
                c: 0, d: scaleY,
                tx: tx, ty: ty
            )

            let landColor = Color(red: 28/255.0, green: 28/255.0, blue: 30/255.0)
            let borderColor = Color(red: 45/255.0, green: 45/255.0, blue: 47/255.0)
            let borderedIDs = style == .borders ? countriesWithCities : []

            for country in countries {
                if let transformed = country.path.copy(using: &transform) {
                    let path = Path(transformed)
                    switch style {
                    case .filled:
                        context.fill(path, with: .color(landColor))
                    case .borders:
                        context.fill(path, with: .color(landColor))
                        if borderedIDs.contains(country.id) {
                            context.stroke(path, with: .color(borderColor), lineWidth: 2)
                        }
                    case .calibration:
                        context.stroke(path, with: .color(.red), lineWidth: 1)
                    }
                }
            }
        }
    }
}

// MARK: - Pulsing ring for "Reveal on Map"

private struct MapRevealPulseRing: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .stroke(Color.accentColor, lineWidth: 2)
            .frame(width: 44, height: 44)
            .scaleEffect(isPulsing ? 1.3 : 0.9)
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
