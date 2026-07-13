//
//  MapView.swift
//  Weather
//
//  Purpose: Composes the weather map screen: map controls, marker selection,
//  camera fitting, and marker selection.
//

import SwiftUI
import CoreLocation
import MapKit

enum MapRecenterRequest: Equatable {
    case weatherCities
    case listCoordinates
}

// MARK: - Overlay Menu

extension ContentView {
    var mapOverlayOptions: [(mode: String, icon: String, label: String)] {
        [
        ("weather", "sun.max.fill", localizedString("Sunniness", locale: locale)),
            ("temperature", "thermometer.medium", localizedString("Temperature", locale: locale)),
            ("cloudCover", "cloud", localizedString("Cloud Cover", locale: locale)),
            ("precipitation", "cloud.rain", localizedString("Rain", locale: locale)),
            ("windSpeed", "wind", localizedString("Wind", locale: locale)),
            ("uvIndex", "sun.max.trianglebadge.exclamationmark", localizedString("UV Index", locale: locale))
        ]
    }

    var mapOverlayMenu: some View {
        Menu {
            ForEach(mapOverlayOptions, id: \.mode) { option in
                Button {
                    Haptics.lightImpact()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mapOverlayMode = option.mode
                        forceReloadMapDots()
                    }
                } label: {
                    primaryMenuLabel(option.label, systemImage: mapOverlayMode == option.mode ? "checkmark" : option.icon)
                }
            }
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: bottomToolbarIconSize, weight: .regular))
                .imageScale(.medium)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 32, height: 36)
                .contentShape(Rectangle())
        }
        .tint(theme.colors.accent)
        .menuOrder(.fixed)
    }

    @ViewBuilder
    private var mapMoreMenuItems: some View {
        Toggle(isOn: Binding(
            get: { showLegend },
            set: { newValue in withAnimation(.smooth(duration: 0.3)) { showLegend = newValue } }
        )) {
            primaryMenuLabel(localizedString("Legend", locale: locale), systemImage: "eye")
        }

        Toggle(isOn: Binding(
            get: { filterSunny },
            set: { newValue in withAnimation { filterSunny = newValue } }
        )) {
            primaryMenuLabel(localizedString("Filter Sunny", locale: locale), systemImage: "sun.max")
        }

        Button {
            refreshWeather()
        } label: {
            primaryMenuLabel(
                localizedString("Refresh", locale: locale) + (timeSinceRefreshText().isEmpty ? "" : " (\(timeSinceRefreshText()))"),
                systemImage: "arrow.clockwise"
            )
        }
        .disabled(weatherService.isLoading)
    }

    var mapMoreMenu: some View {
        Menu {
            mapMoreMenuItems
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: bottomToolbarIconSize, weight: .regular))
                .imageScale(.medium)
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 32, height: 36)
                .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .tint(theme.colors.accent)
    }

    var mapControls: some View {
        topToolbarActionCapsule(spacing: 18) {
            Button {
                mapRecenterRequest = nil
                DispatchQueue.main.async {
                    mapRecenterRequest = .listCoordinates
                }
            } label: {
                Image(systemName: "dot.squareshape.split.2x2")
                    .font(.system(size: bottomToolbarIconSize, weight: .regular))
                    .imageScale(.medium)
                    .foregroundStyle(theme.colors.primaryText)
                    .frame(width: 32, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tint(theme.colors.primaryText)

            mapOverlayMenu
                .font(.system(size: bottomToolbarIconSize, weight: .regular))
                .imageScale(.medium)

            mapMoreMenu
                .font(.system(size: bottomToolbarIconSize, weight: .regular))
                .imageScale(.medium)
        }
    }
}

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
    let onMarkerTap: (CityWeather) -> Void
    let onMapClick: (() -> Void)?
    let onMapGestureStart: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var cameraPosition: MapCameraPosition = .region(Self.defaultRegion)
    @State private var lastCenteredCityID: UUID?

    private let mapSaturation: Double = 0.72

    private var markerSaturationCompensation: Double {
        mapSaturation == 0 ? 1 : 1 / mapSaturation
    }

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
                            onMarkerTap(cityWeather)
                        } label: {
                            WeatherMapMarker(
                                color: markerColor(for: cityWeather),
                                isSelected: isSelected
                            )
                            .id(markerIdentity(for: cityWeather, isSelected: isSelected))
                            .saturation(markerSaturationCompensation)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .saturation(mapSaturation)
            .safeAreaPadding(.leading, 16)
            .safeAreaPadding(.bottom, 10)
            .onMapCameraChange(frequency: .onEnd) { _ in
                onMapGestureStart?()
            }
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard proxy.convert(value.location, from: .local) != nil else { return }
                        onMapClick?()
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
                let forecast = cityWeather.forecast(for: selectedDayOffset)
                return SunninessScoring.condition(for: forecast.symbolName).isSunny
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
        let forecast = cityWeather.forecast(for: selectedDayOffset)
        let colors = AppTheme.shared.colors

        switch overlayMode {
        case "temperature":
            let celsius = selectedDayOffset == 0 ? cityWeather.temperature : forecast.dailyHigh
            return temperatureColor(celsius: celsius, colors: colors)
        case "cloudCover":
            guard let cloudCover = forecast.cloudCover else { return unavailableOverlayColor(colors: colors) }
            return cloudCoverColor(cloudCover, colors: colors)
        case "precipitation":
            guard let precipitationChance = forecast.precipitationChance else { return unavailableOverlayColor(colors: colors) }
            return precipitationColor(precipitationChance, colors: colors)
        case "windSpeed":
            guard let windSpeed = forecast.windSpeed else { return unavailableOverlayColor(colors: colors) }
            return windColor(kmh: windSpeed, colors: colors)
        case "uvIndex":
            guard let uvIndex = forecast.uvIndex else { return unavailableOverlayColor(colors: colors) }
            return uvColor(index: uvIndex, colors: colors)
        default:
            return SunninessScoring.condition(for: forecast.symbolName).dotColor
        }
    }

    private func temperatureColor(celsius: Double, colors: ThemeColors) -> Color {
        let partlySunny = colors.dotPartlyCloudy.compatMix(with: colors.filterSunny, by: 0.18)
        if celsius <= 0 {
            return colors.dotRain.compatMix(with: colors.dotDrizzle, by: clamped((celsius + 20) / 20))
        } else if celsius <= 10 {
            return colors.dotDrizzle.compatMix(with: colors.dotCloudy, by: clamped(celsius / 10))
        } else if celsius <= 20 {
            return colors.dotCloudy.compatMix(with: partlySunny, by: clamped((celsius - 10) / 10))
        } else {
            return partlySunny.compatMix(with: colors.destructive, by: clamped((celsius - 20) / 20))
        }
    }

    private func cloudCoverColor(_ cloudCover: Double, colors: ThemeColors) -> Color {
        colors.dotRain.compatMix(with: colors.dotCloudy, by: clamped(cloudCover))
    }

    private func precipitationColor(_ precipitationChance: Double, colors: ThemeColors) -> Color {
        colors.dotCloudy.compatMix(with: colors.dotDrizzle, by: clamped(precipitationChance))
    }

    private func windColor(kmh: Double, colors: ThemeColors) -> Color {
        let partlySunny = colors.dotPartlyCloudy.compatMix(with: colors.filterSunny, by: 0.18)
        return colors.dotCloudy.compatMix(with: partlySunny, by: clamped(kmh / 100))
    }

    private func uvColor(index: Int, colors: ThemeColors) -> Color {
        colors.dotCloudy.compatMix(with: colors.destructive, by: clamped(Double(index) / 11))
    }

    private func unavailableOverlayColor(colors: ThemeColors) -> Color {
        colors.secondaryText.opacity(0.45)
    }

    private func clamped(_ value: Double) -> Double {
        max(0, min(1, value))
    }

    private func markerIdentity(for cityWeather: CityWeather, isSelected: Bool) -> String {
        let scheme = colorScheme == .dark ? "dark" : "light"
        return [
            cityWeather.id.uuidString,
            overlayMode,
            "\(selectedDayOffset)",
            "\(markerReloadID)",
            isSelected ? "selected" : "idle",
            scheme
        ].joined(separator: "-")
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

// MARK: - Weather Marker

private struct SelectedPulseRing: View {
    enum Shape { case circle, roundedRect, capsule }
    let shape: Shape
    var color: Color = .white
    @State private var isPulsing = false

    var body: some View {
        Group {
            switch shape {
            case .circle:
                Circle()
                    .stroke(color.opacity(isPulsing ? 0.3 : 0.8), lineWidth: isPulsing ? 1.5 : 2.5)
                    .frame(width: 22, height: 22)
                    .scaleEffect(isPulsing ? 1.22 : 1.0)
            case .roundedRect:
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(isPulsing ? 0.4 : 0.9), lineWidth: isPulsing ? 2.5 : 3)
            case .capsule:
                Capsule()
                    .stroke(color.opacity(isPulsing ? 0.34 : 0.88), lineWidth: isPulsing ? 2.5 : 3)
                    .scaleEffect(isPulsing ? 1.08 : 1.0)
            }
        }
        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isPulsing)
        .onAppear { isPulsing = true }
    }
}

private struct WeatherMapMarker: View {
    let color: Color
    let isSelected: Bool
    @State private var glowPulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(isSelected ? 0.34 : 0.22))
                .frame(width: isSelected ? 28 : 18, height: isSelected ? 28 : 18)
                .blur(radius: isSelected ? 8 : 5)
                .scaleEffect(isSelected && glowPulse ? 1.18 : 1)
                .animation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true), value: glowPulse)

            if isSelected {
                SelectedPulseRing(shape: .circle, color: color)
                    .frame(width: 10, height: 10)
                    .transition(.scale.combined(with: .opacity))
            }

            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .shadow(color: color.opacity(0.42), radius: 3)
        }
        .frame(width: 36, height: 36)
        .contentShape(Circle())
        .animation(.smooth(duration: 0.22), value: isSelected)
        .onAppear {
            glowPulse = isSelected
        }
        .onChange(of: isSelected) { _, selected in
            glowPulse = selected
        }
    }
}

// MARK: - Map Controls and Interactions

extension ContentView {
    // MARK: Camera Controls

    func centerMapOnDots(useListCoordinates: Bool = false) {
        mapMarkerReloadID += 1
        mapRecenterRequest = nil
        DispatchQueue.main.async {
            mapRecenterRequest = useListCoordinates ? .listCoordinates : .weatherCities
        }
    }

    func forceReloadMapDots() {
        mapMarkerReloadID += 1
    }

    func refreshWeather() {
        dismissMapSelectionForRefresh()
        daytimeScoreRefetchKeys.removeAll()
        Task {
            if isShowingAllLists {
                await loadAllListsWeatherData()
            } else {
                await weatherService.refreshWeather()
            }
            if !mapCities.isEmpty {
                centerMapOnDots(useListCoordinates: true)
            }
        }
    }

    private func dismissMapSelectionForRefresh() {
        guard showingMapExpandedCard || tappedCity != nil else { return }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingMapExpandedCard = false
            tappedCity = nil
            temporaryMapSearchCity = nil
        }
    }

    // MARK: Marker Selection

    func handleMapMarkerTap(_ city: CityWeather) {
        if showingSearchSheet || searchFieldPresented {
            showingSearchSheet = false
            searchFieldPresented = false
            resetNativeCitySearch()
        }

        if showingMapExpandedCard, tappedCity?.id == city.id {
            return
        }
        Haptics.lightImpact()
        showMapMarkerCard(city)
    }

    func handleMapBackgroundClick() {
        dismissMapExpandedCard()
    }

    func dismissMapExpandedCard() {
        let shouldRecenterAfterDismiss = temporaryMapSearchCity != nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingMapExpandedCard = false
            tappedCity = nil
            temporaryMapSearchCity = nil
            if shouldRecenterAfterDismiss {
                mapRecenterRequest = .weatherCities
            }
        }
    }

    func showMapMarkerCard(_ city: CityWeather) {
        if showingMapExpandedCard && tappedCity?.id == city.id {
            presentDetail(for: city)
            return
        }

        tappedCity = city
        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
            showingMapExpandedCard = true
        }
    }

    func deleteMapCity(_ city: CityWeather) {
        weatherService.removeCity(city)
        if temporaryMapSearchCity?.id == city.id {
            temporaryMapSearchCity = nil
        }
        showingMapExpandedCard = false
        tappedCity = nil
        selectedDayOffset = 0
        mapRecenterRequest = .listCoordinates
    }

    // MARK: Map Composition

    var weatherMapView: some View {
        mapView
    }

    var mapView: some View {
        ZStack {
            AppleWeatherMapView(
                cities: mapCities,
                fitCities: mapFitCities,
                selectedDayOffset: selectedDayOffset,
                overlayMode: mapOverlayMode,
                filterSunny: filterSunny,
                markerReloadID: mapMarkerReloadID,
                selectedCityID: tappedCity?.id,
                recenterRequest: $mapRecenterRequest,
                centerOnCity: centerOnCityTrigger,
                onMarkerTap: { city in
                    handleMapMarkerTap(city)
                },
                onMapClick: {
                    handleMapBackgroundClick()
                },
                onMapGestureStart: {
                    if showingMapExpandedCard {
                        dismissMapExpandedCard()
                    }
                }
            )
            .ignoresSafeArea()

            if let errorMessage = weatherService.errorMessage {
                weatherServiceErrorBanner(errorMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 72)
                    .padding(.horizontal, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(80)
            }

        }
        .background(theme.colors.mapOcean.ignoresSafeArea())
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.2), value: weatherService.errorMessage)
        .onChange(of: weatherService.isLoading) { wasLoading, isLoading in
            if wasLoading, !isLoading, !mapCities.isEmpty {
                centerMapOnDots(useListCoordinates: true)
            }
        }


    }

    private func weatherServiceErrorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.colors.destructive)

            Text(message)
                .font(.callout.weight(.medium))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button {
                weatherService.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: 520)
        .background(theme.colors.glassFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
    }

}
