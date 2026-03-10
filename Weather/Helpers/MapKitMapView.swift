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
    var countrySelectionMode: Bool = false
    var forceDotsOnly: Bool = false
    var gridPreviewPoints: [CLLocationCoordinate2D] = []
    @Binding var mapCenterCoordinate: CLLocationCoordinate2D?
    var radialSearchMode: Bool = false
    var radialSearchRadius: Double = 250_000
    var onRadiusChange: ((Double) -> Void)? = nil
    var onDoubleTapMarker: (() -> Void)?
    var onCameraMove: ((CLLocationCoordinate2D) -> Void)?

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
            .onMapCameraChange(frequency: .continuous) { context in
                cameraChangeCounter += 1
                let coord = context.camera.centerCoordinate
                mapCenterCoordinate = coord
                if countrySelectionMode || radialSearchMode {
                    onCameraMove?(coord)
                }
            }
            // Black underlay to prevent MapKit tiles flashing during transitions
            .overlay {
                if mapMode != "detailed" {
                    Color.black
                        .allowsHitTesting(false)
                }
            }
            // SVG country overlay
            .overlay {
                if mapMode == "minimal" || mapMode == "borders" || mapMode == "calibration" {
                    SVGProxyOverlay(
                        countries: countries,
                        proxy: proxy,
                        cameraChangeCounter: cameraChangeCounter,
                        style: (countrySelectionMode || radialSearchMode) ? .borders : (mapMode == "borders" ? .borders : (mapMode == "calibration" ? .calibration : .filled)),
                        cities: (countrySelectionMode || radialSearchMode || mapMode == "borders") ? cities : [],
                        borderAllCountries: countrySelectionMode || radialSearchMode
                    )
                    .allowsHitTesting(false)
                }
            }
            // Weather marker annotations on top of SVG overlay (non-interactive so map gestures pass through)
            .overlay {
                if !countrySelectionMode && !radialSearchMode {
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
                        forceDotsOnly: forceDotsOnly,
                        showingCityDetail: $showingCityDetail,
                        tappedCity: $tappedCity
                    )
                    .allowsHitTesting(false)
                }
            }
            // Grid preview dots during country selection
            .overlay {
                if (countrySelectionMode || radialSearchMode), !gridPreviewPoints.isEmpty {
                    GridPreviewOverlay(
                        points: gridPreviewPoints,
                        proxy: proxy,
                        cameraChangeCounter: cameraChangeCounter
                    )
                    .allowsHitTesting(false)
                }
            }
            // Radial search circle overlay
            .overlay {
                if radialSearchMode, let center = mapCenterCoordinate {
                    RadialSearchCircleOverlay(
                        center: center,
                        radiusMeters: radialSearchRadius,
                        proxy: proxy,
                        cameraChangeCounter: cameraChangeCounter,
                        onRadiusChange: onRadiusChange
                    )
                }
            }
            // Transparent tap detection layer — finds nearest marker on tap
            .onTapGesture { location in
                guard !countrySelectionMode && !radialSearchMode else { return }
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
                    withAnimation(.smooth(duration: 0.3)) {
                        tappedCity = hit.city
                    }
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
                // Trigger overlay redraw after map has laid out
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    cameraChangeCounter += 1
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
            .onChange(of: mapMode) { _, _ in
                // Force overlay redraw when map mode changes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    cameraChangeCounter += 1
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
    var forceDotsOnly: Bool = false
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
            let markerMode: MarkerDisplayMode = forceDotsOnly ? .dot : computeDisplayMode(screenPositions)

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
                    .scaleEffect(
                        (tappedMarkerID == cityWeather.id || highlightedMarkerID == cityWeather.id || (showingCityDetail && tappedCity?.id == cityWeather.id)) ? 1.5 : 1.0
                    )
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: tappedMarkerID)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: highlightedMarkerID)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: showingCityDetail)

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
    var borderAllCountries: Bool = false

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
            let borderedIDs: Set<String> = style == .borders ? (borderAllCountries ? Set(countries.map(\.id)) : countriesWithCities) : []

            // Corner rounding radius in screen points
            let cornerRadius: CGFloat = min(max(abs(scaleX) * 1.5, 1.5), 8.0)

            // First pass: fill all countries
            for country in countries {
                if let transformed = country.path.copy(using: &transform) {
                    let smoothed = Path(Self.roundCorners(transformed, radius: cornerRadius))
                    switch style {
                    case .filled, .borders:
                        context.fill(smoothed, with: .color(landColor))
                    case .calibration:
                        context.stroke(smoothed, with: .color(.red), lineWidth: 1)
                    }
                }
            }

            // Second pass: stroke borders on top of all fills
            if style == .borders {
                let borderWidth = min(max(abs(scaleX) * 0.4, 1.5), 3)
                for country in countries {
                    if borderedIDs.contains(country.id),
                       let transformed = country.path.copy(using: &transform) {
                        let smoothed = Path(Self.roundCorners(transformed, radius: cornerRadius))
                        context.stroke(smoothed, with: .color(borderColor), lineWidth: borderWidth)
                    }
                }
            }
        }
    }

    // MARK: - Corner rounding

    /// Rounds sharp corners in a CGPath by replacing each vertex with a
    /// quadratic curve that cuts the corner. The `radius` controls how
    /// far from each corner the curve begins/ends (in screen points).
    private static func roundCorners(_ cgPath: CGPath, radius: CGFloat) -> CGPath {
        // Extract subpaths
        var subpaths: [[CGPoint]] = []
        var current: [CGPoint] = []
        var closedFlags: [Bool] = []

        cgPath.applyWithBlock { elementPtr in
            let element = elementPtr.pointee
            switch element.type {
            case .moveToPoint:
                if !current.isEmpty {
                    subpaths.append(current)
                    closedFlags.append(false)
                }
                current = [element.points[0]]
            case .addLineToPoint:
                current.append(element.points[0])
            case .addCurveToPoint:
                // Keep curve endpoints — these are already smooth
                current.append(element.points[2])
            case .addQuadCurveToPoint:
                current.append(element.points[1])
            case .closeSubpath:
                if !current.isEmpty {
                    subpaths.append(current)
                    closedFlags.append(true)
                    current = []
                }
            @unknown default:
                break
            }
        }
        if !current.isEmpty {
            subpaths.append(current)
            closedFlags.append(false)
        }

        let result = CGMutablePath()

        for (i, points) in subpaths.enumerated() {
            guard points.count >= 3 else {
                // Too few points to round — draw as-is
                if let first = points.first {
                    result.move(to: first)
                    for j in 1..<points.count { result.addLine(to: points[j]) }
                    if closedFlags[i] { result.closeSubpath() }
                }
                continue
            }

            let closed = closedFlags[i]
            let n = points.count

            if closed {
                // For closed subpaths, round every corner including first/last
                let prev = points[n - 1]
                let curr = points[0]
                let next = points[1]
                let (start, _) = Self.cornerOffsets(prev: prev, curr: curr, next: next, radius: radius)
                result.move(to: start)

                for j in 0..<n {
                    let p0 = points[(j + n - 1) % n]
                    let p1 = points[j]
                    let p2 = points[(j + 1) % n]
                    let (startPt, endPt) = Self.cornerOffsets(prev: p0, curr: p1, next: p2, radius: radius)
                    result.addLine(to: startPt)
                    result.addQuadCurve(to: endPt, control: p1)
                }
                result.closeSubpath()
            } else {
                // Open subpath — keep first and last points, round interior corners
                result.move(to: points[0])
                for j in 1..<(n - 1) {
                    let (startPt, endPt) = Self.cornerOffsets(prev: points[j - 1], curr: points[j], next: points[j + 1], radius: radius)
                    result.addLine(to: startPt)
                    result.addQuadCurve(to: endPt, control: points[j])
                }
                result.addLine(to: points[n - 1])
            }
        }

        return result
    }

    /// Computes the two offset points where rounding begins and ends around a corner vertex.
    private static func cornerOffsets(prev: CGPoint, curr: CGPoint, next: CGPoint, radius: CGFloat) -> (CGPoint, CGPoint) {
        let dx1 = curr.x - prev.x
        let dy1 = curr.y - prev.y
        let len1 = sqrt(dx1 * dx1 + dy1 * dy1)

        let dx2 = next.x - curr.x
        let dy2 = next.y - curr.y
        let len2 = sqrt(dx2 * dx2 + dy2 * dy2)

        // Clamp radius so it doesn't exceed half of either segment
        let r = min(radius, len1 * 0.5, len2 * 0.5)

        let start: CGPoint
        if len1 > 0.001 {
            start = CGPoint(x: curr.x - dx1 / len1 * r, y: curr.y - dy1 / len1 * r)
        } else {
            start = curr
        }

        let end: CGPoint
        if len2 > 0.001 {
            end = CGPoint(x: curr.x + dx2 / len2 * r, y: curr.y + dy2 / len2 * r)
        } else {
            end = curr
        }

        return (start, end)
    }
}

// MARK: - Grid Preview Overlay (country selection)

private struct GridPreviewOverlay: View {
    let points: [CLLocationCoordinate2D]
    let proxy: MapProxy
    let cameraChangeCounter: Int

    var body: some View {
        let _ = cameraChangeCounter
        Canvas { context, size in
            for coord in points {
                if let pt = proxy.convert(coord, to: .local) {
                    let margin: CGFloat = 20
                    guard pt.x > -margin && pt.x < size.width + margin &&
                          pt.y > -margin && pt.y < size.height + margin else { continue }
                    let rect = CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.3)))
                }
            }
        }
    }
}

// MARK: - Radial Search Circle Overlay

private struct RadialSearchCircleOverlay: View {
    let center: CLLocationCoordinate2D
    let radiusMeters: Double
    let proxy: MapProxy
    let cameraChangeCounter: Int
    var onRadiusChange: ((Double) -> Void)?

    var body: some View {
        let _ = cameraChangeCounter
        GeometryReader { geometry in
            let screenCenter = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let edgeCoord = center.coordinate(at: radiusMeters, bearing: 90)
            if let centerPt = proxy.convert(center, to: .local),
               let edgePt = proxy.convert(edgeCoord, to: .local) {
                let screenRadius = abs(edgePt.x - centerPt.x)

                // Circle stroke — always at screen center
                Circle()
                    .stroke(Color.white.opacity(0.6), lineWidth: 4)
                    .frame(width: screenRadius * 2, height: screenRadius * 2)
                    .position(screenCenter)
                    .allowsHitTesting(false)

                // Drag handle at right edge
                Circle()
                    .fill(Color.blue)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    .position(x: screenCenter.x + screenRadius, y: screenCenter.y)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if let dragCoord = proxy.convert(value.location, from: .local) {
                                    let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
                                    let dragLoc = CLLocation(latitude: dragCoord.latitude, longitude: dragCoord.longitude)
                                    let newRadius = centerLoc.distance(from: dragLoc)
                                    let clamped = min(max(newRadius, 50_000), 500_000)
                                    onRadiusChange?(clamped)
                                }
                            }
                    )
            }
        }
    }
}

// MARK: - CLLocationCoordinate2D Bearing Extension

extension CLLocationCoordinate2D {
    /// Returns a coordinate at a given distance (meters) and bearing (degrees) from this coordinate.
    func coordinate(at distanceMeters: Double, bearing bearingDegrees: Double) -> CLLocationCoordinate2D {
        let R = 6_371_000.0
        let d = distanceMeters / R
        let brng = bearingDegrees * .pi / 180
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180

        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(brng))
        let lon2 = lon1 + atan2(sin(brng) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))

        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
}
