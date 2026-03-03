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
    
    // Incremented on every camera change to force overlay redraw
    @State private var cameraChangeCounter: Int = 0

    var body: some View {
        MapReader { proxy in
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
            .onMapCameraChange(frequency: .continuous) { _ in
                cameraChangeCounter += 1
            }
            .overlay {
                SVGProxyOverlay(
                    countries: countries,
                    proxy: proxy,
                    cameraChangeCounter: cameraChangeCounter
                )
                .allowsHitTesting(false)
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

// MARK: - SVG Overlay using MapProxy

/// Uses MapProxy.convert to get exact screen positions of reference coordinates,
/// then draws transformed SVG country paths in a Canvas.
/// The cameraChangeCounter dependency forces re-evaluation on every pan/zoom.
private struct SVGProxyOverlay: View {
    let countries: [CountryPath]
    let proxy: MapProxy
    let cameraChangeCounter: Int

    private static let refCoordA = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
    private static let refCoordB = CLLocationCoordinate2D(latitude: 45.0, longitude: 90.0)
    private static let refSvgA = GeoProjection.geoToSVG(latitude: 0.0, longitude: 0.0)
    private static let refSvgB = GeoProjection.geoToSVG(latitude: 45.0, longitude: 90.0)

    var body: some View {
        // Query proxy for screen positions of reference points.
        // These calls happen during view body evaluation, which is triggered
        // whenever cameraChangeCounter changes (on every pan/zoom).
        let ptA = proxy.convert(Self.refCoordA, to: .local)
        let ptB = proxy.convert(Self.refCoordB, to: .local)

        Canvas { context, size in
            // Use cameraChangeCounter to ensure Canvas re-renders
            let _ = cameraChangeCounter
            
            guard let screenA = ptA, let screenB = ptB else { return }
            guard size.width > 0, size.height > 0 else { return }

            let svgA = Self.refSvgA
            let svgB = Self.refSvgB
            let svgDx = Double(svgB.x - svgA.x)
            let svgDy = Double(svgB.y - svgA.y)
            guard abs(svgDx) > 0.001, abs(svgDy) > 0.001 else { return }

            let scaleX = (screenB.x - screenA.x) / svgDx
            let scaleY = (screenB.y - screenA.y) / svgDy
            guard scaleX.isFinite, scaleY.isFinite, scaleX != 0, scaleY != 0 else { return }

            let tx = screenA.x - Double(svgA.x) * scaleX
            // Zoom-proportional upward correction: the overlay drifts down more when zoomed in
            let yCorrection = -0.5 * abs(scaleX)
            let ty = screenA.y - Double(svgA.y) * scaleY + yCorrection

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
