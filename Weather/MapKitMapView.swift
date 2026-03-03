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

    @State private var position: MapCameraPosition = .automatic
    @State private var hasCenteredOnCities: Bool = false
    @State private var highlightedMarkerID: UUID?

    // Track the visible map rect for SVG overlay transform
    @State private var visibleMapRect: MKMapRect = .world

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            ForEach(cities) { cityWeather in
                let passes = passesFilter(cityWeather)
                if passes {
                    Annotation(
                        cityWeather.city.name,
                        coordinate: CLLocationCoordinate2D(
                            latitude: cityWeather.city.latitude,
                            longitude: cityWeather.city.longitude
                        ),
                        anchor: .center
                    ) {
                        WeatherMarker(
                            cityWeather: cityWeather,
                            dayOffset: selectedDayOffset,
                            isCompact: false,
                            namespace: namespace,
                            showCloudCover: showCloudCover,
                            filterSunny: filterSunny,
                            passesFilter: true,
                            isPlaying: isPlaying
                        )
                        .overlay {
                            if highlightedMarkerID == cityWeather.id {
                                MapRevealPulseRing()
                            }
                        }
                        .onTapGesture {
                            tappedCity = cityWeather
                            Task {
                                try? await Task.sleep(for: .milliseconds(150))
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                    showingCityDetail = true
                                }
                            }
                        }
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { }
        .onMapCameraChange(frequency: .continuous) { context in
            visibleMapRect = context.rect
        }
        .overlay {
            GeometryReader { geometry in
                SVGCanvasOverlay(
                    countries: countries,
                    viewSize: geometry.size,
                    visibleMapRect: visibleMapRect
                )
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
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

    private func passesFilter(_ cityWeather: CityWeather) -> Bool {
        guard filterSunny else { return true }
        let forecast = cityWeather.forecast(for: selectedDayOffset)
        return forecast.condition == .clear && forecast.cloudCover < 0.30
    }

    private func fitAllCities(animated: Bool) {
        guard !cities.isEmpty else { return }

        var minLat = Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        var minLon = Double.greatestFiniteMagnitude
        var maxLon = -Double.greatestFiniteMagnitude

        for city in cities {
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

// MARK: - SVG Country Overlay

/// Draws SVG country shapes transformed from SVG space to screen space
/// using two reference geo-points and the visible MKMapRect.
/// Accounts for safe area difference between the map's rendering area and the overlay.
private struct SVGCanvasOverlay: View {
    let countries: [CountryPath]
    let viewSize: CGSize
    let visibleMapRect: MKMapRect

    private static let refSvgA = GeoProjection.geoToSVG(latitude: 0.0, longitude: 0.0)
    private static let refSvgB = GeoProjection.geoToSVG(latitude: 45.0, longitude: 90.0)

    private static let refMapPtA = MKMapPoint(CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0))
    private static let refMapPtB = MKMapPoint(CLLocationCoordinate2D(latitude: 45.0, longitude: 90.0))

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            guard visibleMapRect.size.width > 0, visibleMapRect.size.height > 0 else { return }

            // Use a single uniform scale derived from the X axis (horizontal alignment is correct).
            // MKMapPoint uses Mercator which has equal scale in X and Y at every point.
            // Map the center of the MKMapRect to the center of the canvas, so any tiny
            // height discrepancy between the map rect and the overlay is distributed evenly.
            let pxPerMap = size.width / visibleMapRect.size.width

            // Map center in MKMapPoint space
            let mapCenterX = visibleMapRect.origin.x + visibleMapRect.size.width / 2.0
            let mapCenterY = visibleMapRect.origin.y + visibleMapRect.size.height / 2.0

            // Screen center
            let screenCenterX = size.width / 2.0
            let screenCenterY = size.height / 2.0

            // Convert reference MKMapPoints to screen via center-anchored transform
            let screenA = CGPoint(
                x: screenCenterX + (Self.refMapPtA.x - mapCenterX) * pxPerMap,
                y: screenCenterY + (Self.refMapPtA.y - mapCenterY) * pxPerMap
            )
            let screenB = CGPoint(
                x: screenCenterX + (Self.refMapPtB.x - mapCenterX) * pxPerMap,
                y: screenCenterY + (Self.refMapPtB.y - mapCenterY) * pxPerMap
            )

            let svgA = Self.refSvgA
            let svgB = Self.refSvgB
            let svgDx = Double(svgB.x - svgA.x)
            let svgDy = Double(svgB.y - svgA.y)
            guard abs(svgDx) > 0.001, abs(svgDy) > 0.001 else { return }

            let scaleX = (screenB.x - screenA.x) / svgDx
            let scaleY = (screenB.y - screenA.y) / svgDy
            guard scaleX.isFinite, scaleY.isFinite, scaleX != 0, scaleY != 0 else { return }

            let tx = screenA.x - Double(svgA.x) * scaleX
            let ty = screenA.y - Double(svgA.y) * scaleY

            var transform = CGAffineTransform(
                a: scaleX, b: 0,
                c: 0, d: scaleY,
                tx: tx, ty: ty
            )

            for country in countries {
                if let transformed = country.path.copy(using: &transform) {
                    context.fill(
                        Path(transformed),
                        with: .color(.red.opacity(0.4))
                    )
                    context.stroke(
                        Path(transformed),
                        with: .color(.red),
                        lineWidth: 1.5
                    )
                }
            }
        }
        .frame(width: viewSize.width, height: viewSize.height)
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
