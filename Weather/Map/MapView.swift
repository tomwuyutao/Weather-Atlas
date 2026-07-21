//
//  MapView.swift
//  Weather
//
//  Purpose: Composes the weather map screen: destinations, overlays, controls,
//  marker selection, camera fitting, and map-specific presentation state.
//

import SwiftUI
import CoreLocation
import MapKit

// MARK: - Map Selection State

extension ContentView {
    /// Cities to display on the map: the active list plus any temporary searched city.
    var mapCities: [CityWeather] {
        if isListPreviewActive {
            return []
        }
        var result = weatherService.cityWeatherData
        if let preview = citySearchState.temporaryMapCity,
           !result.contains(where: { weatherService.citiesMatch($0.city, preview.city) }) {
            result.append(preview)
        }
        return result
    }

    var mapFitCities: [City] {
        if isListPreviewActive {
            return listPreviewCities
        }
        return weatherService.cityListCoordinates()
    }

    var selectedMapCity: CityWeather? {
        get {
            guard let selectedMapCityID else { return nil }
            return mapCities.first(where: { $0.id == selectedMapCityID })
        }
        nonmutating set {
            selectedMapCityID = newValue?.id
        }
    }

    var showingMapExpandedCard: Bool {
        get { selectedMapCityID != nil }
        nonmutating set {
            if !newValue {
                selectedMapCityID = nil
            }
        }
    }
}

// MARK: - Map Destination

extension ContentView {
    var fullMapDestination: some View {
        mapTabContent
            .navigationTitle(localizedString("Weather", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(false)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                centerMapOnDots(useListCoordinates: true)
            }
    }

    var mapTabContent: some View {
        ZStack(alignment: .bottom) {
            mapView
                .overlay(alignment: .topLeading) {
                    if isMapRoute, !citySearchState.isPresented {
                        VStack(alignment: .leading, spacing: 8) {
                            if weatherService.isLoading {
                                LoadingWeatherOverlay(
                                    progress: weatherService.loadingProgress,
                                    locale: locale
                                )
                                .allowsHitTesting(false)
                                .transition(.scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity))
                            }

                            if showLegend {
                                MapFloatingLegend(overlayMode: mapOverlayMode) {
                                    withAnimation(.smooth(duration: 0.2)) {
                                        showLegend = false
                                    }
                                }
                                .transition(.scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity))
                            }
                        }
                        .padding(.leading, 16)
                        .padding(.top, 72)
                    }
                }
                .animation(.smooth(duration: 0.22), value: showLegend)
                .animation(.smooth(duration: 0.22), value: weatherService.isLoading)
                .overlay(alignment: .topLeading) {
                    if !citySearchState.isPresented {
                        topToolbar {
                            mapControls
                        }
                        .padding(.horizontal, 16)
                        .safeAreaPadding(.top, 12)
                        .contentShape(Rectangle())
                        .background(Color.clear)
                        .zIndex(120)
                    }
                }
                .allowsHitTesting(!citySearchState.isPresented)

            if !citySearchState.isPresented {
                mainOverlays
            }
        }
        .tint(theme.colors.accent)
    }
}

// MARK: - Map Weather Validation

extension ContentView {
    /// Dismisses a selected marker whenever the active date, overlay, filter,
    /// or refreshed data can no longer produce the card the user is seeing.
    func dismissSelectedMapCardIfUnavailable() {
        guard showingMapExpandedCard else { return }
        guard let selectedCity = selectedMapCity,
              let forecast = selectedCity.forecastIfAvailable(on: selectedForecastDate),
              mapWeatherDataIssue(
                forecast: forecast,
                cityWeather: selectedCity,
                overlayMode: mapOverlayMode
              ) == nil else {
            dismissMapExpandedCard()
            return
        }

        if filterSunny,
           SunninessScoring.condition(for: forecast.symbolName)?.isSunny != true {
            dismissMapExpandedCard()
        }
    }
}

/// Resolves the exact source-data requirement for the active map layer. The
/// marker and floating card share this check so neither can display a fallback.
func mapWeatherDataIssue(
    forecast: DailyForecast,
    cityWeather: CityWeather,
    overlayMode: String
) -> WeatherDataIssue? {
    switch overlayMode {
    case "cloudCover":
        return forecast.cloudCover == nil ? .missingCloudCoverData : nil
    case "precipitation":
        return forecast.precipitationChance == nil ? .missingPrecipitationData : nil
    case "uvIndex":
        return forecast.uvIndex == nil ? .missingUVIndexData : nil
    case "temperature":
        return nil
    default:
        guard SunninessScoring.condition(for: forecast.symbolName) != nil else {
            return .unknownWeatherSymbol(forecast.symbolName)
        }
        guard case .failure(let issue) = SunninessScoring.sunnyHoursData(
            for: forecast,
            timeZone: cityWeather.timeZone
        ) else {
            return nil
        }
        return issue
    }
}

// MARK: - Loading Overlay

private struct LoadingWeatherOverlay: View {
    let progress: Double
    let locale: Locale

    @Environment(\.appTheme) private var theme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        HStack(spacing: 10) {
            ProgressView(value: progress)
                .progressViewStyle(.circular)

            Text(localizedString("Loading Weather", locale: locale))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            if colorSchemeContrast == .increased {
                Capsule().fill(theme.colors.glassFill)
            } else {
                Capsule().fill(.regularMaterial)
            }
        }
        .overlay {
            if colorSchemeContrast == .increased {
                Capsule().stroke(theme.colors.primaryText, lineWidth: 1)
            }
        }
    }
}

// MARK: - Overlay Menu

extension ContentView {
    var mapOverlayOptions: [(mode: String, icon: String, label: String)] {
        [
            ("weather", "sun.max.fill", localizedString("Sunniness", locale: locale)),
            ("temperature", "thermometer.medium", localizedString("Max Temperature", locale: locale)),
            ("cloudCover", "cloud", localizedString("Cloud Cover", locale: locale)),
            ("precipitation", "cloud.rain", localizedString("Rain Chance", locale: locale)),
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
                    primaryMenuLabel(option.label, systemImage: mapOverlayMode == option.mode ? "checkmark" : option.icon)
                }
            }
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: AppToolbarMetrics.iconSize, weight: .regular))
                .imageScale(.medium)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .padding(.horizontal, -6)
        .padding(.vertical, -4)
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
                .font(.system(size: AppToolbarMetrics.iconSize, weight: .regular))
                .imageScale(.medium)
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .padding(.horizontal, -6)
        .padding(.vertical, -4)
        .menuOrder(.fixed)
        .tint(theme.colors.accent)
    }

    var mapControls: some View {
        topToolbarActionCapsule(spacing: 18) {
            Button {
                centerMapOnDots(useListCoordinates: true)
            } label: {
                Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                    .font(.system(size: AppToolbarMetrics.iconSize, weight: .regular))
                    .imageScale(.medium)
                    .foregroundStyle(theme.colors.primaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, -6)
            .padding(.vertical, -4)
            .tint(theme.colors.primaryText)

            mapOverlayMenu
                .font(.system(size: AppToolbarMetrics.iconSize, weight: .regular))
                .imageScale(.medium)

            mapMoreMenu
                .font(.system(size: AppToolbarMetrics.iconSize, weight: .regular))
                .imageScale(.medium)
        }
    }
}

// MARK: - Apple Maps Implementation
struct AppleWeatherMapView: View {
    let cities: [CityWeather]
    let selectedForecastDate: Date
    let overlayMode: String
    let filterSunny: Bool
    @Binding var cameraPosition: MapCameraPosition
    @Binding var selectedCityID: UUID?

    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.defaultRawValue

    private let mapSaturation: Double = 0.72

    private var markerSaturationCompensation: Double {
        mapSaturation == 0 ? 1 : 1 / mapSaturation
    }

    // MARK: Body and Camera

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > 1, proxy.size.height > 1 {
                mapContent
            } else {
                theme.colors.mapOcean
            }
        }
    }

    private var mapContent: some View {
        Map(position: $cameraPosition) {
            ForEach(visibleCities) { cityWeather in
                if let color = markerColor(for: cityWeather) {
                    Annotation(
                        "",
                        coordinate: CLLocationCoordinate2D(
                            latitude: cityWeather.city.latitude,
                            longitude: cityWeather.city.longitude
                        ),
                        anchor: .center
                    ) {
                        Button {
                            selectedCityID = cityWeather.id
                        } label: {
                            WeatherMapMarker(
                                color: color,
                                isSelected: selectedCityID == cityWeather.id,
                                differentiatingText: markerDifferentiatingText(for: cityWeather),
                                differentiatingSymbol: markerDifferentiatingSymbol(for: cityWeather)
                            )
                            .saturation(markerSaturationCompensation)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .saturation(mapSaturation)
        .safeAreaPadding(.leading, 16)
        .safeAreaPadding(.bottom, 10)
        .onMapCameraChange(frequency: .onEnd) { context in
            // Persist the complete user-positioned camera. A region stores only
            // center and span, so reusing it after a gesture would reset the
            // map's heading and pitch when the user's fingers leave the screen.
            cameraPosition = .camera(context.camera)
        }
        .onAppear {
            fitVisibleContent()
        }
        .onChange(of: selectedForecastDate) { _, _ in
            fitVisibleContent()
        }
        .onChange(of: filterSunny) { _, _ in
            fitVisibleContent()
        }
    }

    private var visibleCities: [CityWeather] {
        cities.filter { cityWeather in
            guard !isExpectedForecastBoundaryOmission(
                for: cityWeather,
                among: cities,
                on: selectedForecastDate
            ) else {
                return false
            }
            guard let forecast = cityWeather.forecastIfAvailable(on: selectedForecastDate) else {
                return false
            }
            guard mapWeatherDataIssue(
                forecast: forecast,
                cityWeather: cityWeather,
                overlayMode: overlayMode
            ) == nil else {
                return false
            }
            guard filterSunny else { return true }
            guard let condition = SunninessScoring.condition(for: forecast.symbolName) else { return false }
            return condition.isSunny
        }
    }

    private func fitVisibleContent() {
        let citiesToFit = visibleCities.map(\.city)
        guard !citiesToFit.isEmpty else { return }
        let region = MapRegionFitting.region(for: citiesToFit)
        withAnimation(.smooth(duration: 0.35)) {
            cameraPosition = .region(region)
        }
    }

    private func markerDifferentiatingText(for cityWeather: CityWeather) -> String? {
        guard let forecast = cityWeather.forecastIfAvailable(on: selectedForecastDate) else {
            return nil
        }
        guard mapWeatherDataIssue(
            forecast: forecast,
            cityWeather: cityWeather,
            overlayMode: overlayMode
        ) == nil else {
            return nil
        }
        switch overlayMode {
        case "temperature":
            let celsius = forecast.dailyHigh
            return (TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic).display(celsius)
        case "cloudCover":
            return forecast.cloudCover.map { "\(Int(($0 * 100).rounded()))%" }
        case "precipitation":
            return forecast.precipitationChance.map { "\(Int(($0 * 100).rounded()))%" }
        case "uvIndex":
            return forecast.uvIndex.map(String.init)
        default:
            return nil
        }
    }

    private func markerDifferentiatingSymbol(for cityWeather: CityWeather) -> String? {
        guard overlayMode == "weather",
              let forecast = cityWeather.forecastIfAvailable(on: selectedForecastDate) else {
            return nil
        }
        return forecast.weatherIcon
    }

    // MARK: Marker Coloring

    private func markerColor(for cityWeather: CityWeather) -> Color? {
        let colors = theme.colors
        guard let forecast = cityWeather.forecastIfAvailable(on: selectedForecastDate) else { return nil }
        guard mapWeatherDataIssue(
            forecast: forecast,
            cityWeather: cityWeather,
            overlayMode: overlayMode
        ) == nil else { return nil }

        switch overlayMode {
        case "temperature":
            let celsius = forecast.dailyHigh
            return temperatureColor(celsius: celsius, colors: colors)
        case "cloudCover":
            guard let cloudCover = forecast.cloudCover else { return nil }
            return cloudCoverColor(cloudCover, colors: colors)
        case "precipitation":
            guard let precipitationChance = forecast.precipitationChance else { return nil }
            return precipitationColor(precipitationChance, colors: colors)
        case "uvIndex":
            guard let uvIndex = forecast.uvIndex else { return nil }
            return uvColor(index: uvIndex, colors: colors)
        default:
            guard let condition = SunninessScoring.condition(for: forecast.symbolName) else { return nil }
            return condition.dotColor(for: colors)
        }
    }

    private func temperatureColor(celsius: Double, colors: ThemeColors) -> Color {
        let partlySunny = colors.dotPartlyCloudy.interpolated(with: colors.filterSunny, by: 0.18)
        if celsius <= 0 {
            return colors.dotRain.interpolated(with: colors.dotDrizzle, by: clamped((celsius + 20) / 20))
        } else if celsius <= 10 {
            return colors.dotDrizzle.interpolated(with: colors.dotCloudy, by: clamped(celsius / 10))
        } else if celsius <= 20 {
            return colors.dotCloudy.interpolated(with: partlySunny, by: clamped((celsius - 10) / 10))
        } else {
            return partlySunny.interpolated(with: colors.destructive, by: clamped((celsius - 20) / 20))
        }
    }

    private func cloudCoverColor(_ cloudCover: Double, colors: ThemeColors) -> Color {
        colors.dotRain.interpolated(with: colors.dotCloudy, by: clamped(cloudCover))
    }

    private func precipitationColor(_ precipitationChance: Double, colors: ThemeColors) -> Color {
        colors.dotCloudy.interpolated(with: colors.dotDrizzle, by: clamped(precipitationChance))
    }

    private func uvColor(index: Int, colors: ThemeColors) -> Color {
        colors.dotCloudy.interpolated(with: colors.destructive, by: clamped(Double(index) / 11))
    }

    private func clamped(_ value: Double) -> Double {
        max(0, min(1, value))
    }

}

private enum MapRegionFitting {
    static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 180)
    )

    static func region(centeredOn city: City, span: CLLocationDegrees) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude),
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
    }

    static func region(for cities: [City]) -> MKCoordinateRegion {
        guard !cities.isEmpty else { return defaultRegion }
        var minLat = cities[0].latitude
        var maxLat = cities[0].latitude
        for city in cities.dropFirst() {
            minLat = min(minLat, city.latitude)
            maxLat = max(maxLat, city.latitude)
        }
        let longitudeArc = minimumLongitudeArc(for: cities.map(\.longitude))
        return paddedRegion(
            minLat: minLat,
            maxLat: maxLat,
            centerLongitude: longitudeArc.center,
            longitudeSpan: longitudeArc.span
        )
    }

    /// Finds the shortest longitude arc containing every city, so locations on
    /// opposite sides of the international date line remain visually adjacent.
    private static func minimumLongitudeArc(
        for longitudes: [CLLocationDegrees]
    ) -> (center: CLLocationDegrees, span: CLLocationDegrees) {
        guard longitudes.count > 1 else {
            return (longitudes.first ?? 0, 0)
        }

        let normalized = longitudes
            .map { longitude in longitude >= 0 ? longitude : longitude + 360 }
            .sorted()
        var largestGap = -CLLocationDegrees.infinity
        var arcStart = normalized[0]

        for index in normalized.indices {
            let current = normalized[index]
            let next = index == normalized.index(before: normalized.endIndex)
                ? normalized[0] + 360
                : normalized[index + 1]
            let gap = next - current
            if gap > largestGap {
                largestGap = gap
                arcStart = next.truncatingRemainder(dividingBy: 360)
            }
        }

        let span = 360 - largestGap
        let normalizedCenter = (arcStart + span / 2).truncatingRemainder(dividingBy: 360)
        let center = normalizedCenter > 180 ? normalizedCenter - 360 : normalizedCenter
        return (center, span)
    }

    private static func paddedRegion(
        minLat: CLLocationDegrees,
        maxLat: CLLocationDegrees,
        centerLongitude: CLLocationDegrees,
        longitudeSpan: CLLocationDegrees
    ) -> MKCoordinateRegion {
        let latDelta = max(1.2, (maxLat - minLat) * 1.25)
        let lonDelta = max(1.2, longitudeSpan * 1.25)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: centerLongitude
            ),
            span: MKCoordinateSpan(latitudeDelta: min(160, latDelta), longitudeDelta: min(340, lonDelta))
        )
    }
}

// MARK: - Weather Marker

private struct SelectedPulseRing: View {
    let color: Color
    @State private var isPulsing = false
    // Stop the repeating selection pulse when Reduce Motion is on.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .stroke(color.opacity(isPulsing ? 0.3 : 0.8), lineWidth: isPulsing ? 1.5 : 2.5)
            .frame(width: 22, height: 22)
            .scaleEffect(isPulsing ? 1.22 : 1.0)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
            value: isPulsing
        )
        .onAppear { isPulsing = !reduceMotion }
        .onChange(of: reduceMotion) { _, shouldReduceMotion in
            isPulsing = !shouldReduceMotion
        }
    }
}

private struct WeatherMapMarker: View {
    let color: Color
    let isSelected: Bool
    let differentiatingText: String?
    let differentiatingSymbol: String?
    @State private var glowPulse = false
    // These environment values alter only motion and redundant
    // marker encoding; selection and map behavior remain unchanged.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(isSelected ? 0.34 : 0.22))
                .frame(width: isSelected ? 28 : 18, height: isSelected ? 28 : 18)
                .blur(radius: isSelected ? 8 : 5)
                .scaleEffect(isSelected && glowPulse ? 1.18 : 1)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.15).repeatForever(autoreverses: true),
                    value: glowPulse
                )

            if isSelected && !differentiateWithoutColor {
                SelectedPulseRing(color: color)
                    .frame(width: 10, height: 10)
                    .transition(.scale.combined(with: .opacity))
            }

            if differentiateWithoutColor {
                // Show a symbol or metric value so marker meaning
                // is not conveyed by color alone.
                Group {
                    if let differentiatingText {
                        Text(differentiatingText)
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 5)
                    } else if let differentiatingSymbol {
                        Image(systemName: differentiatingSymbol)
                            .font(.caption2.weight(.bold))
                            .padding(5)
                    }
                }
                .foregroundStyle(theme.colors.primaryText)
                .frame(minWidth: 26, maxWidth: 40, minHeight: 24)
                .background {
                    if colorSchemeContrast == .increased {
                        Capsule().fill(theme.colors.glassFill)
                    } else {
                        Capsule().fill(.regularMaterial)
                    }
                }
                .overlay {
                    Capsule()
                        .stroke(
                            colorSchemeContrast == .increased ? theme.colors.primaryText : color,
                            lineWidth: isSelected ? 3 : 2
                        )
                }
            } else if colorSchemeContrast == .increased {
                // Place the metric color on an opaque, outlined disk so
                // it retains sufficient contrast over every possible MapKit background.
                Circle()
                    .fill(theme.colors.glassFill)
                    .frame(width: isSelected ? 24 : 20, height: isSelected ? 24 : 20)
                    .overlay {
                        Circle()
                            .stroke(theme.colors.primaryText, lineWidth: isSelected ? 2.5 : 2)
                    }

                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                    .shadow(color: color.opacity(0.42), radius: 3)
            }
        }
        // Enlarge the map marker's hit region without enlarging
        // the normal visual dot.
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .animation(.smooth(duration: 0.22), value: isSelected)
        .onAppear {
            glowPulse = isSelected && !reduceMotion
        }
        .onChange(of: isSelected) { _, selected in
            glowPulse = selected && !reduceMotion
        }
        .onChange(of: reduceMotion) { _, shouldReduceMotion in
            glowPulse = isSelected && !shouldReduceMotion
        }
    }
}

// MARK: - Map Controls and Interactions

extension ContentView {
    // MARK: Camera Controls

    func centerMapOnDots(useListCoordinates _: Bool = false) {
        let cities = mapCities.compactMap { cityWeather -> City? in
            guard !isExpectedForecastBoundaryOmission(
                for: cityWeather,
                among: mapCities,
                on: selectedForecastDate
            ) else {
                return nil
            }
            guard let forecast = cityWeather.forecastIfAvailable(on: selectedForecastDate) else {
                return nil
            }
            guard mapWeatherDataIssue(
                forecast: forecast,
                cityWeather: cityWeather,
                overlayMode: mapOverlayMode
            ) == nil else {
                return nil
            }
            guard filterSunny else { return cityWeather.city }
            guard let condition = SunninessScoring.condition(for: forecast.symbolName) else { return nil }
            return condition.isSunny ? cityWeather.city : nil
        }
        guard !cities.isEmpty else { return }
        withAnimation(.smooth(duration: 0.35)) {
            mapCameraPosition = .region(MapRegionFitting.region(for: cities))
        }
    }

    func centerMap(on city: CityWeather) {
        withAnimation(.smooth(duration: 0.35)) {
            mapCameraPosition = .region(MapRegionFitting.region(centeredOn: city.city, span: 0.35))
        }
    }

    func dismissMapExpandedCard() {
        let shouldRecenterAfterDismiss = citySearchState.temporaryMapCity != nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingMapExpandedCard = false
            selectedMapCity = nil
            citySearchState.temporaryMapCity = nil
            if shouldRecenterAfterDismiss {
                centerMapOnDots()
            }
        }
    }

    func showMapMarkerCard(_ city: CityWeather) {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
            selectedMapCity = city
        }
    }

    // MARK: Map Composition

    var mapView: some View {
        let droppedCityCount = expectedForecastBoundaryOmissionCount(
            in: forecastDateSourceCities
        )

        return ZStack {
            AppleWeatherMapView(
                cities: mapCities,
                selectedForecastDate: selectedForecastDate,
                overlayMode: mapOverlayMode,
                filterSunny: filterSunny,
                cameraPosition: $mapCameraPosition,
                selectedCityID: $selectedMapCityID
            )
            .ignoresSafeArea()

            if !citySearchState.isPresented,
               !showingMapExpandedCard,
               droppedCityCount > 0 {
                forecastAvailabilityNote(droppedCityCount: droppedCityCount)
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 106)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(70)
            }

        }
        .background(theme.colors.mapOcean.ignoresSafeArea())
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.2), value: droppedCityCount)
        .onChange(of: selectedMapCityID) { previousID, selectedID in
            if selectedID != nil, selectedID != previousID {
                Haptics.lightImpact()
            }
        }
        .onChange(of: weatherService.isLoading) { wasLoading, isLoading in
            if wasLoading, !isLoading, !mapCities.isEmpty {
                centerMapOnDots(useListCoordinates: true)
            }
        }


    }
}
