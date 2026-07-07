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

private struct MapDateSliderTutorialPreview: View {
    init() {
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        UserDefaults.standard.set(false, forKey: "hasSeenMapDateSliderTutorial")
    }

    var body: some View {
        ContentView(initialRoute: .map, showsMapDateSliderTutorialPreview: true)
    }
}

#Preview("Map Slider Tutorial") {
    MapDateSliderTutorialPreview()
}

// MARK: - Overlay Menu

extension ContentView {
    var mapOverlayOptions: [(mode: String, icon: String, label: String)] {
        [
            ("weather", "cloud.sun", localizedString("Weather", locale: locale)),
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
                    }
                } label: {
                    Label {
                        Text(option.label)
                            .foregroundStyle(theme.colors.primaryText)
                    } icon: {
                        Image(systemName: mapOverlayMode == option.mode ? "checkmark" : option.icon)
                            .foregroundStyle(theme.colors.primaryText)
                    }
                }
            }
        } label: {
            Image(systemName: "square.3.layers.3d")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(theme.colors.primaryText)
        }
        .tint(theme.colors.primaryText)
        .menuOrder(.fixed)
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
                            WeatherMapMarker(
                                color: markerColor(for: cityWeather),
                                isSelected: isSelected
                            )
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
            return AppTheme.shared.colors.dotSun
        }
        let forecast = cityWeather.forecast(for: max(0, selectedDayOffset))
        let isNow = selectedDayOffset == -1
        let condition = isNow ? cityWeather.condition : forecast.condition
        let icon = isNow ? cityWeather.weatherIcon : forecast.weatherIcon
        let colors = AppTheme.shared.colors
        return icon.contains("moon") ? colors.moonIconColor : condition.dotColor(for: colors)
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
    @ViewBuilder
    var mapDateSliderOverlay: some View {
        // Date slider only on map view. Home/list use the bottom date switcher.
        if isMapRoute, !showingSearchSheet {
            mapDateSlider(height: 420) {
                if showingMapDateSliderTutorial {
                    dismissMapDateSliderTutorial()
                }
            }
                .frame(width: 145, height: 420, alignment: .trailing)
                .padding(.bottom, 470)
                .padding(.trailing, 1)
                .transition(.opacity)
        }
    }

    var mapDateSliderTutorialOverlay: some View {
        let tutorialSliderHeight: CGFloat = 420
        let capsuleY = CGFloat(max(0, min(10, selectedDayOffset + 1))) * tutorialSliderHeight / 10
        let labelFont: Font = .avenir(.subheadline, weight: .semibold)
        let idleMinWidth: CGFloat = 52
        let idleHorizontalPadding: CGFloat = 12
        let idleVerticalPadding: CGFloat = 7
        let idleTailSize = CGSize(width: 24, height: 16)
        let hintSpacing: CGFloat = 4
        let hintGapBelowCapsule: CGFloat = 210

        return ZStack(alignment: .topTrailing) {
            HStack(alignment: .center, spacing: hintSpacing) {
                Text(localizedString("Drag to change dates", locale: locale))
                    .font(.avenir(.title3, weight: .regular))
                    .multilineTextAlignment(.trailing)
                    .fixedSize()

                Text(sliderDateText(for: selectedDayOffset))
                    .font(labelFont)
                    .frame(minWidth: idleMinWidth)
                    .fixedSize()
                    .padding(.horizontal, idleHorizontalPadding)
                    .padding(.vertical, idleVerticalPadding)
                    .hidden()
                    .overlay {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 28, weight: .semibold))
                    }

                Color.clear
                    .frame(width: idleTailSize.width, height: idleTailSize.height)
                    .offset(x: 9)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
            .offset(y: capsuleY + hintGapBelowCapsule)
        }
        .frame(width: 360, height: tutorialSliderHeight, alignment: .topTrailing)
        .padding(.bottom, 470)
        .padding(.trailing, 1)
        .allowsHitTesting(false)
    }

    func showMapDateSliderTutorialIfNeeded() {
        guard !hasSeenMapDateSliderTutorial else { return }
        selectedDayOffset = 4
        isFadingMapDateSliderTutorial = false
        showingMapDateSliderTutorial = true
    }

    func dismissMapDateSliderTutorial() {
        guard showingMapDateSliderTutorial, !isFadingMapDateSliderTutorial else { return }
        hasSeenMapDateSliderTutorial = true
        withAnimation(.easeOut(duration: 0.5)) {
            isFadingMapDateSliderTutorial = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
            showingMapDateSliderTutorial = false
            isFadingMapDateSliderTutorial = false
        }
    }

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
            await weatherService.refreshWeather()
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

    func handleMapMarkerTap(_ city: CityWeather, anchor: CGPoint? = nil) {
        if showingSearchSheet || searchFieldPresented {
            showingSearchSheet = false
            searchFieldPresented = false
            resetNativeCitySearch()
        }

        if showingMapExpandedCard, tappedCity?.id == city.id {
            return
        }
        Haptics.lightImpact()
        showMapMarkerCard(city, anchor: anchor, expanded: false, focusesMarker: true)
    }

    func handleMapBackgroundClick(_ coordinate: CLLocationCoordinate2D, anchor: CGPoint? = nil) {
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

    func showMapMarkerCard(_ city: CityWeather, anchor: CGPoint? = nil, expanded: Bool, focusesMarker: Bool) {
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
                onMarkerTap: { city, point in
                    handleMapMarkerTap(city, anchor: point)
                },
                onMapClick: { coordinate, point in
                    handleMapBackgroundClick(coordinate, anchor: point)
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
