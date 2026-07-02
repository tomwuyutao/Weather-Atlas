//
//  AppleWeatherMapView.swift
//  Weather
//
//  Purpose: Renders the Apple Maps version of the weather map.
//

import SwiftUI
import MapKit

// MARK: - Apple Maps Implementation
struct AppleWeatherMapView: View {
    let cities: [CityWeather]
    let fitCities: [City]
    let selectedDayOffset: Int
    let overlayMode: String
    let filterSunny: Bool
    let markerReloadID: Int
    let selectedCityID: UUID?
    @Binding var recenterRequest: MapRecenterRequest?
    let centerOnCity: CityWeather?
    let onMarkerTap: (CityWeather, CGPoint?) -> Void
    let onMapClick: ((CLLocationCoordinate2D, CGPoint?) -> Void)?
    let onMapGestureStart: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var cameraPosition: MapCameraPosition = .region(Self.defaultRegion)
    @State private var lastCenteredCityID: UUID?

    // MARK: Body and Camera

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, interactionModes: .all) {
                ForEach(visibleCities) { cityWeather in
                    let isSelected = selectedCityID == cityWeather.id
                    Annotation(
                        "",
                        coordinate: CLLocationCoordinate2D(
                            latitude: cityWeather.city.latitude,
                            longitude: cityWeather.city.longitude
                        ),
                        anchor: .center
                    ) {
                        Button {
                            onMarkerTap(cityWeather, nil)
                        } label: {
                            Circle()
                                .fill(markerColor(for: cityWeather))
                                .frame(width: 9, height: 9)
                                .scaleEffect(isSelected ? 1.5 : 1)
                                .shadow(color: markerColor(for: cityWeather).opacity(isSelected ? 0.85 : 0.65), radius: isSelected ? 12 : 7)
                                .overlay {
                                    if isSelected {
                                        SelectedPulseRing(shape: .circle, color: markerColor(for: cityWeather))
                                            .frame(width: 10, height: 10)
                                    }
                                }
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .safeAreaPadding(.leading, 16)
            .safeAreaPadding(.bottom, 10)
            .simultaneousGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { _ in onMapGestureStart?() }
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard let coordinate = proxy.convert(value.location, from: .local) else { return }
                        onMapClick?(coordinate, value.location)
                    }
            )
        }
        .onAppear {
            fitVisibleContent()
        }
        .onChange(of: markerReloadID) { _, _ in
            fitVisibleContent()
        }
        .onChange(of: recenterRequest) { _, request in
            guard let request else { return }
            fitVisibleContent(using: request)
            recenterRequest = nil
        }
        .onChange(of: centerOnCity?.id) { _, _ in
            guard let centerOnCity, centerOnCity.id != lastCenteredCityID else { return }
            lastCenteredCityID = centerOnCity.id
            withAnimation(.smooth(duration: 0.35)) {
                cameraPosition = .region(Self.region(centeredOn: centerOnCity.city, span: 0.35))
            }
        }
    }

    private var visibleCities: [CityWeather] {
        cities.filter { cityWeather in
            guard !filterSunny else {
                if selectedDayOffset == -1 {
                    return cityWeather.condition == .clear && !cityWeather.weatherIcon.contains("moon")
                }
                let forecast = cityWeather.forecast(for: selectedDayOffset)
                return forecast.condition == .clear && !forecast.weatherIcon.contains("moon")
            }
            return true
        }
    }

    private func fitVisibleContent(using request: MapRecenterRequest = .weatherCities) {
        let citiesToFit = request == .listCoordinates ? fitCities : visibleCities.map(\.city)
        let region = Self.region(for: citiesToFit)
        withAnimation(.smooth(duration: 0.35)) {
            cameraPosition = .region(region)
        }
    }

    // MARK: Marker Coloring

    private func markerColor(for cityWeather: CityWeather) -> Color {
        if overlayMode == "temperature" {
            return .orange
        }
        let forecast = cityWeather.forecast(for: max(0, selectedDayOffset))
        let isNow = selectedDayOffset == -1
        let condition = isNow ? cityWeather.condition : forecast.condition
        let icon = isNow ? cityWeather.weatherIcon : forecast.weatherIcon
        if icon.contains("moon") { return Color(red: 0.64, green: 0.52, blue: 0.72) }
        switch condition {
        case .clear: return Color(red: 1.0, green: 0.54, blue: 0.40)
        case .partlySunny, .partlyCloudy: return Color(red: 0.93, green: 0.70, blue: 0.41)
        case .rain: return Color(red: 0.30, green: 0.44, blue: 0.83)
        case .drizzle: return Color(red: 0.40, green: 0.67, blue: 0.89)
        case .cloudy, .snow, .fog, .wind: return colorScheme == .dark
            ? Color(red: 0.83, green: 0.89, blue: 0.93)
            : Color(red: 0.72, green: 0.78, blue: 0.82)
        }
    }

    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 180)
    )

    private static func region(centeredOn city: City, span: CLLocationDegrees) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude),
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
    }

    private static func region(for cities: [City]) -> MKCoordinateRegion {
        guard !cities.isEmpty else { return defaultRegion }
        var minLat = cities[0].latitude
        var maxLat = cities[0].latitude
        var minLon = cities[0].longitude
        var maxLon = cities[0].longitude
        for city in cities.dropFirst() {
            minLat = min(minLat, city.latitude)
            maxLat = max(maxLat, city.latitude)
            minLon = min(minLon, city.longitude)
            maxLon = max(maxLon, city.longitude)
        }
        return paddedRegion(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
    }

    private static func paddedRegion(
        minLat: CLLocationDegrees,
        maxLat: CLLocationDegrees,
        minLon: CLLocationDegrees,
        maxLon: CLLocationDegrees
    ) -> MKCoordinateRegion {
        let latDelta = max(1.2, (maxLat - minLat) * 1.25)
        let lonDelta = max(1.2, (maxLon - minLon) * 1.25)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: min(160, latDelta), longitudeDelta: min(340, lonDelta))
        )
    }

}
