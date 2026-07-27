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
    /// Loaded cities belonging to the active list.
    var mapCities: [CityWeather] {
        if isListPreviewActive {
            return []
        }
        return weatherService.cityWeatherData
    }

    /// Model adapter backed by stable selected-marker identity.
    var selectedMapCity: CityWeather? {
        get {
            guard let selectedMapCityID else { return nil }
            return mapCities.first(where: { $0.id == selectedMapCityID })
        }
        nonmutating set {
            selectedMapCityID = newValue?.id
        }
    }

    /// Boolean presentation adapter that clears selection when set to false.
    var isMapCardPresented: Bool {
        get { selectedMapCityID != nil }
        nonmutating set {
            if !newValue {
                selectedMapCityID = nil
            }
        }
    }

    /// Removes horizon omissions, missing metric fields, and filtered conditions
    /// before MapKit or the floating card can consume a marker.
    private var currentMapMarkers: [MapMarkerModel] {
        let cities = mapCities
        return cities.compactMap { cityWeather in
            guard !isExpectedForecastBoundaryOmission(
                for: cityWeather,
                among: cities,
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
            if filterSunny,
               SunninessScoring.condition(for: forecast.symbolName)?.isSunny != true {
                return nil
            }
            return MapMarkerModel(cityWeather: cityWeather, forecast: forecast)
        }
    }
}

// MARK: - Map Destination

extension ContentView {
    /// Wraps Map View as a route and owns per-visit camera initialization/reset.
    var fullMapDestination: some View {
        mapTabContent
            .navigationTitle(localizedString("Weather", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(false)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                centerMapOnDots()
            }
            .onDisappear {
                // A fresh map visit starts from the fitted overview, while date
                // changes during the current visit retain the user's camera.
                mapCameraPosition = .automatic
            }
    }

    /// Composes map, toolbar, legend, loading state, and selected-city overlays.
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
                floatingMapCardOverlay
            }
        }
        .tint(theme.colors.accent)
    }
}

// MARK: - Map Weather Validation

extension ContentView {
    /// Dismisses a selected marker whenever the active date, overlay, filter,
    /// or refreshed data can no longer produce the card the user is seeing.
    func dismissInvalidMapCard() { //? so according to my understanding this part is ust saying if data is unavailable, hide the dot. why does it have to be so complicated? the name is complicated as well
        guard isMapCardPresented else { return }
        guard let selectedCity = selectedMapCity,
              let forecast = selectedCity.forecastIfAvailable(on: selectedForecastDate),
              mapWeatherDataIssue(
                forecast: forecast,
                cityWeather: selectedCity,
                overlayMode: mapOverlayMode
              ) == nil else {
            dismissMapCard()
            return
        }

        if filterSunny,
           SunninessScoring.condition(for: forecast.symbolName)?.isSunny != true {
            dismissMapCard()
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

/// Prevalidated city/forecast pair safe for the active map layer.
private struct MapMarkerModel: Identifiable {
    /// Source city weather aggregate.
    let cityWeather: CityWeather
    /// Forecast matching the selected literal date.
    let forecast: DailyForecast

    /// Reuses stable city identity for map annotation diffing.
    var id: UUID { cityWeather.id }
}

// MARK: - Loading Overlay

/// Compact progress capsule shown while Map weather is loading.
private struct LoadingWeatherOverlay: View {
    /// Completed fraction of configured city fetches.
    let progress: Double
    /// App-selected locale used by the progress label.
    let locale: Locale

    /// Active semantic palette.
    @Environment(\.appTheme) private var theme
    /// Contrast preference used to replace material with an opaque capsule.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    /// Builds the progress indicator and localized status label.
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
    /// Menu that changes the metric encoded by marker color and cards.
    var mapOverlayMenu: some View {
        Menu {
            // Keep localized map layers in their fixed menu order.
            ForEach([
                (mode: "weather", icon: "sun.max.fill", label: localizedString("Sunniness", locale: locale)),
                (mode: "temperature", icon: "thermometer.medium", label: localizedString("Max Temperature", locale: locale)),
                (mode: "cloudCover", icon: "cloud", label: localizedString("Cloud Cover", locale: locale)),
                (mode: "precipitation", icon: "cloud.rain", label: localizedString("Rain Chance", locale: locale)),
                (mode: "uvIndex", icon: "sun.max.trianglebadge.exclamationmark", label: localizedString("UV Index", locale: locale))
            ], id: \.mode) { option in
                Button {
                    Haptics.lightImpact()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mapOverlayMode = option.mode
                    }
                } label: {
                    primaryMenuLabel(
                        option.label,
                        systemImage: mapOverlayMode == option.mode ? "checkmark" : option.icon
                    )
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
    /// Legend, sunny filter, and refresh actions shown in the overflow menu.
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

    /// Overflow menu button for secondary map controls.
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

    /// Floating top control capsule for fit, overlay, and more actions.
    var mapControls: some View {
        topToolbarActionCapsule(spacing: 18) {
            Button {
                centerMapOnDots()
            } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
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
/// MapKit renderer for prevalidated weather annotations and bound camera state.
private struct AppleMapView: View {
    /// Marker payloads already filtered for the active layer.
    let markers: [MapMarkerModel]
    /// Raw metric mode controlling text, symbol, and color encoding.
    let overlayMode: String
    /// Full camera binding retained across in-map state changes.
    @Binding var cameraPosition: MapCameraPosition
    /// Stable identity of the selected annotation.
    @Binding var selectedCityID: UUID?

    /// Active semantic palette.
    @Environment(\.appTheme) private var theme
    /// App-selected locale used by marker values.
    @Environment(\.locale) private var locale
    /// Contrast preference used by marker treatments.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// Persisted raw temperature preference for temperature markers.
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.defaultRawValue

    // MARK: Body and Camera

    /// Defers MapKit until layout has a usable viewport, avoiding invalid
    /// camera calculations during transient zero-sized proposals. //? what that
    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > 1, proxy.size.height > 1 {
                mapContent
            } else {
                theme.colors.background
            }
        }
    }

    /// Builds annotations while leaving camera mutations to user gestures/actions.
    private var mapContent: some View {
        Map(position: $cameraPosition) {
            ForEach(markers) { marker in
                if let color = markerColor(for: marker.forecast) {
                    Annotation(
                        "",
                        coordinate: CLLocationCoordinate2D(
                            latitude: marker.cityWeather.city.latitude,
                            longitude: marker.cityWeather.city.longitude
                        ),
                        anchor: .center
                    ) {
                        Button {
                            selectedCityID = marker.cityWeather.id
                        } label: {
                            WeatherMapMarker(
                                color: color,
                                isSelected: selectedCityID == marker.cityWeather.id,
                                differentiatingText: markerDifferentiatingText(for: marker.forecast),
                                // The categorical layer supplements dot color with a symbol.
                                differentiatingSymbol: overlayMode == "weather"
                                    ? marker.forecast.weatherIcon
                                    : nil
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .safeAreaPadding(.leading, 16)
        .safeAreaPadding(.bottom, 10)
    }

    /// Supplies a text cue when accessibility cannot rely on marker color alone. //?whats that
    private func markerDifferentiatingText(for forecast: DailyForecast) -> String? {
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

    // MARK: Marker Coloring

    /// Resolves the active layer color or returns `nil` for absent source data.
    private func markerColor(for forecast: DailyForecast) -> Color? {
        let colors = theme.colors

        switch overlayMode {
        case "temperature":
            let celsius = forecast.dailyHigh
            // Map Celsius across the shared cold-to-hot semantic gradient.
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
        case "cloudCover":
            guard let cloudCover = forecast.cloudCover else { return nil }
            // Map a cloud fraction into the cloud-cover gradient.
            return colors.dotRain.interpolated(with: colors.dotCloudy, by: clamped(cloudCover))
        case "precipitation":
            guard let precipitationChance = forecast.precipitationChance else { return nil }
            // Map precipitation probability into the rain gradient.
            return colors.dotCloudy.interpolated(
                with: colors.dotDrizzle,
                by: clamped(precipitationChance)
            )
        case "uvIndex":
            guard let uvIndex = forecast.uvIndex else { return nil }
            // Map UV index into the neutral-to-destructive gradient.
            return colors.dotCloudy.interpolated(
                with: colors.destructive,
                by: clamped(Double(uvIndex) / 11)
            )
        default:
            guard let condition = SunninessScoring.condition(for: forecast.symbolName) else { return nil }
            return condition.dotColor(for: colors)
        }
    }

    /// Restricts interpolation fractions to the zero-through-one domain.
    private func clamped(_ value: Double) -> Double {
        max(0, min(1, value))
    }

}

/// Geographic fitting helpers, including international-date-line handling.
private enum MapRegionFitting {
    /// Global overview used only when no city coordinates exist.
    static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 180)
    )

    /// Builds a square region centered on one city.
    static func region(centeredOn city: City, span: CLLocationDegrees) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude),
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
    }

    /// Fits all cities using the shortest longitude arc and padded latitude span.
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

    /// Adds viewport padding and caps MapKit's supported coordinate deltas.
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

/// Animated selection ring suppressed when Reduce Motion is enabled.
private struct SelectedPulseRing: View {
    /// Semantic metric color surrounding the selected dot.
    let color: Color
    /// Internal phase driving the repeating scale/opacity animation.
    @State private var isPulsing = false
    // Stop the repeating selection pulse when Reduce Motion is on.
    /// System motion preference controlling repetition.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Builds and starts the adaptive pulse ring.
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

/// Interactive weather annotation with selection and non-color alternatives.
private struct WeatherMapMarker: View {
    /// Semantic color encoding the active metric.
    let color: Color
    /// Whether this annotation owns the visible map card.
    let isSelected: Bool
    /// Optional numeric value used when color differentiation is unavailable.
    let differentiatingText: String?
    /// Optional condition symbol used when color differentiation is unavailable.
    let differentiatingSymbol: String?
    /// Internal phase driving the selected-dot glow.
    @State private var glowPulse = false
    /// Motion preference controlling selected-marker glow animation.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Preference requiring text/symbol information in addition to hue.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    /// Preference requiring an opaque, strongly outlined marker.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// Active semantic palette.
    @Environment(\.appTheme) private var theme

    /// Builds marker glow, selection, and accessibility variants.
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

    /// Fits the camera to every marker valid for the current map state.
    func centerMapOnDots() {
        let cities = currentMapMarkers.map { $0.cityWeather.city }
        guard !cities.isEmpty else { return }
        withAnimation(.smooth(duration: 0.35)) {
            mapCameraPosition = .region(MapRegionFitting.region(for: cities))
        }
    }

    /// Centers the camera tightly on one requested city.
    func centerMap(on city: CityWeather) {
        withAnimation(.smooth(duration: 0.35)) {
            mapCameraPosition = .region(MapRegionFitting.region(centeredOn: city.city, span: 0.35))
        }
    }

    /// Clears selected and temporary city state, refitting after search previews. //? i think this is depreciated since search is now rounting to detailview
    func dismissMapCard() {
        let shouldRecenterAfterDismiss = citySearchState.temporaryMapCity != nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isMapCardPresented = false
            selectedMapCity = nil
            citySearchState.temporaryMapCity = nil
            if shouldRecenterAfterDismiss {
                centerMapOnDots()
            }
        }
    }

    /// Selects a marker with the shared spring transition.
    func showMapMarkerCard(_ city: CityWeather) {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
            selectedMapCity = city
        }
    }

    // MARK: Map Composition

    /// Renders the map plus the expected forecast-boundary omission notice.
    var mapView: some View {
        // Map omissions are measured against the active list, not a search preview.
        let droppedCityCount = expectedForecastBoundaryOmissionCount(in: weatherService.cityWeatherData)
        let markers = currentMapMarkers

        return ZStack {
            AppleMapView(
                markers: markers,
                overlayMode: mapOverlayMode,
                cameraPosition: $mapCameraPosition,
                selectedCityID: $selectedMapCityID
            )
            .ignoresSafeArea()

            if !citySearchState.isPresented,
               !isMapCardPresented,
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
        .background(theme.colors.background.ignoresSafeArea())
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.2), value: droppedCityCount)
        .onChange(of: selectedMapCityID) { previousID, selectedID in
            if selectedID != nil, selectedID != previousID {
                Haptics.lightImpact()
            }
        }
        .onChange(of: weatherService.isLoading) { wasLoading, isLoading in
            if wasLoading, !isLoading, !mapCities.isEmpty {
                centerMapOnDots()
            }
        }


    }
}
