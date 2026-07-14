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

    private var selectedMapOverlayLabel: String {
        mapOverlayOptions.first(where: { $0.mode == mapOverlayMode })?.label
            ?? localizedString("Sunniness", locale: locale)
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
                .accessibilityAddTraits(mapOverlayMode == option.mode ? .isSelected : [])
            }
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: bottomToolbarIconSize, weight: .regular))
                .imageScale(.medium)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(theme.colors.primaryText)
                // Accessibility: Expand the semantic menu target while negative
                // outer padding preserves the visible glass-control spacing.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .padding(.horizontal, -6)
        .padding(.vertical, -4)
        .tint(theme.colors.accent)
        .menuOrder(.fixed)
        .accessibilityLabel(localizedString("Weather", locale: locale))
        .accessibilityValue(selectedMapOverlayLabel)
        // Accessibility: Give Voice Control a stable spoken target for this
        // icon-only menu without changing its visible presentation.
        .accessibilityInputLabels([Text(localizedString("Weather", locale: locale))])
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
                // Accessibility: Use the full recommended target without
                // changing the rendered SF Symbol or glass capsule.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .padding(.horizontal, -6)
        .padding(.vertical, -4)
        .menuOrder(.fixed)
        .tint(theme.colors.accent)
        .accessibilityLabel(localizedString("Menu", locale: locale))
        .accessibilityInputLabels([Text(localizedString("Menu", locale: locale))])
    }

    var mapControls: some View {
        topToolbarActionCapsule(spacing: 18) {
            Button {
                centerMapOnDots(useListCoordinates: true)
            } label: {
                Image(systemName: "dot.squareshape.split.2x2")
                    .font(.system(size: bottomToolbarIconSize, weight: .regular))
                    .imageScale(.medium)
                    .foregroundStyle(theme.colors.primaryText)
                    // Accessibility: The complete 44-point label is tappable.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, -6)
            .padding(.vertical, -4)
            .tint(theme.colors.primaryText)
            .accessibilityLabel(localizedString("Cities", locale: locale))
            .accessibilityInputLabels([Text(localizedString("Cities", locale: locale))])

            mapOverlayMenu
                .font(.system(size: bottomToolbarIconSize, weight: .regular))
                .imageScale(.medium)

            mapMoreMenu
                .font(.system(size: bottomToolbarIconSize, weight: .regular))
                .imageScale(.medium)
        }
        // Accessibility: Keep persistent map controls ahead of the interactive
        // annotation field in VoiceOver's traversal order.
        .accessibilitySortPriority(1)
    }
}

// MARK: - Apple Maps Implementation
struct AppleWeatherMapView: View {
    let cities: [CityWeather]
    let fitCities: [City]
    let selectedDayOffset: Int
    let overlayMode: String
    let filterSunny: Bool
    @Binding var cameraPosition: MapCameraPosition
    @Binding var selectedCityID: UUID?

    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.defaultRawValue

    private let mapSaturation: Double = 0.72

    private var markerSaturationCompensation: Double {
        mapSaturation == 0 ? 1 : 1 / mapSaturation
    }

    // MARK: Body and Camera

    var body: some View {
        Map(position: $cameraPosition) {
            ForEach(visibleCities) { cityWeather in
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
                            color: markerColor(for: cityWeather),
                            isSelected: selectedCityID == cityWeather.id,
                            differentiatingText: markerDifferentiatingText(for: cityWeather),
                            differentiatingSymbol: markerDifferentiatingSymbol(for: cityWeather)
                        )
                        .saturation(markerSaturationCompensation)
                    }
                    .buttonStyle(.plain)
                    // Accessibility: Combine the marker's visual layers into one
                    // city control with the active metric exposed as its value.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(cityWeather.city.localizedName(locale: locale))
                    .accessibilityValue(markerAccessibilityValue(for: cityWeather))
                    .accessibilityInputLabels(markerAccessibilityInputLabels(for: cityWeather))
                    .accessibilityAddTraits(selectedCityID == cityWeather.id ? [.isSelected] : [])
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .saturation(mapSaturation)
        .safeAreaPadding(.leading, 16)
        .safeAreaPadding(.bottom, 10)
        .onAppear {
            fitVisibleContent()
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

    private func fitVisibleContent() {
        let citiesToFit = fitCities.isEmpty ? visibleCities.map(\.city) : fitCities
        let region = MapRegionFitting.region(for: citiesToFit)
        withAnimation(.smooth(duration: 0.35)) {
            cameraPosition = .region(region)
        }
    }

    // MARK: - Accessibility - Marker Descriptions

    private func markerAccessibilityValue(for cityWeather: CityWeather) -> String {
        let forecast = cityWeather.forecast(for: selectedDayOffset)
        let metricName: String
        let metricValue: String

        switch overlayMode {
        case "temperature":
            let celsius = selectedDayOffset == 0 ? cityWeather.temperature : forecast.dailyHigh
            metricName = localizedString("Temperature", locale: locale)
            metricValue = (TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic).display(celsius)
        case "cloudCover":
            metricName = localizedString("Cloud Cover", locale: locale)
            metricValue = forecast.cloudCover.map { "\(Int(($0 * 100).rounded()))%" }
                ?? localizedString("No forecast", locale: locale)
        case "precipitation":
            metricName = localizedString("Rain", locale: locale)
            metricValue = forecast.precipitationChance.map { "\(Int(($0 * 100).rounded()))%" }
                ?? localizedString("No forecast", locale: locale)
        case "windSpeed":
            metricName = localizedString("Wind", locale: locale)
            metricValue = forecast.windSpeed.map {
                (DistanceUnit(rawValue: distanceUnitRaw) ?? .automatic).displayWindSpeed($0)
            } ?? localizedString("No forecast", locale: locale)
        case "uvIndex":
            metricName = localizedString("UV Index", locale: locale)
            metricValue = forecast.uvIndex.map(String.init)
                ?? localizedString("No forecast", locale: locale)
        default:
            metricName = localizedString("Sunniness", locale: locale)
            metricValue = SunninessScoring.condition(for: forecast.symbolName).localizedDisplayName(locale: locale)
        }

        return "\(metricName), \(metricValue)"
    }

    private func markerAccessibilityInputLabels(for cityWeather: CityWeather) -> [Text] {
        var labels = [Text(cityWeather.city.localizedName(locale: locale))]
        if let visibleMetric = markerDifferentiatingText(for: cityWeather) {
            // Accessibility: When Differentiate Without Color displays text inside
            // a marker, let Voice Control target that same visible metric too.
            labels.append(Text(visibleMetric))
        }
        return labels
    }

    private func markerDifferentiatingText(for cityWeather: CityWeather) -> String? {
        let forecast = cityWeather.forecast(for: selectedDayOffset)
        switch overlayMode {
        case "temperature":
            let celsius = selectedDayOffset == 0 ? cityWeather.temperature : forecast.dailyHigh
            return (TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic).display(celsius)
        case "cloudCover":
            return forecast.cloudCover.map { "\(Int(($0 * 100).rounded()))%" } ?? "-"
        case "precipitation":
            return forecast.precipitationChance.map { "\(Int(($0 * 100).rounded()))%" } ?? "-"
        case "windSpeed":
            return forecast.windSpeed.map {
                (DistanceUnit(rawValue: distanceUnitRaw) ?? .automatic).displayWindSpeed($0)
            } ?? "-"
        case "uvIndex":
            return forecast.uvIndex.map(String.init) ?? "-"
        default:
            return nil
        }
    }

    private func markerDifferentiatingSymbol(for cityWeather: CityWeather) -> String? {
        guard overlayMode == "weather" else { return nil }
        return cityWeather.forecast(for: selectedDayOffset).weatherIcon
    }

    // MARK: Marker Coloring

    private func markerColor(for cityWeather: CityWeather) -> Color {
        let forecast = cityWeather.forecast(for: selectedDayOffset)
        let colors = theme.colors

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
            return SunninessScoring.condition(for: forecast.symbolName).dotColor(for: colors)
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

    private func windColor(kmh: Double, colors: ThemeColors) -> Color {
        let partlySunny = colors.dotPartlyCloudy.interpolated(with: colors.filterSunny, by: 0.18)
        return colors.dotCloudy.interpolated(with: partlySunny, by: clamped(kmh / 100))
    }

    private func uvColor(index: Int, colors: ThemeColors) -> Color {
        colors.dotCloudy.interpolated(with: colors.destructive, by: clamped(Double(index) / 11))
    }

    private func unavailableOverlayColor(colors: ThemeColors) -> Color {
        // Accessibility: Preserve the no-data marker at full contrast when requested;
        // its reduced standard opacity remains unchanged.
        colorSchemeContrast == .increased ? colors.secondaryText : colors.secondaryText.opacity(0.45)
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
    var color: Color = .white
    @State private var isPulsing = false
    // Accessibility: Stop the repeating selection pulse when Reduce Motion is on.
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
    // Accessibility: These environment values alter only motion and redundant
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
                // Accessibility: Show a symbol or metric value so marker meaning
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
                .foregroundStyle(.primary)
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
                // Accessibility: Place the metric color on an opaque, outlined disk so
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
        // Accessibility: Enlarge the map marker's hit region without enlarging
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

    func centerMapOnDots(useListCoordinates: Bool = false) {
        let cities = useListCoordinates ? mapFitCities : mapCities.map(\.city)
        withAnimation(.smooth(duration: 0.35)) {
            mapCameraPosition = .region(MapRegionFitting.region(for: cities))
        }
    }

    func centerMap(on city: CityWeather) {
        withAnimation(.smooth(duration: 0.35)) {
            mapCameraPosition = .region(MapRegionFitting.region(centeredOn: city.city, span: 0.35))
        }
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
        guard showingMapExpandedCard || selectedMapCity != nil else { return }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingMapExpandedCard = false
            selectedMapCity = nil
            citySearchState.temporaryMapCity = nil
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
        ZStack {
            AppleWeatherMapView(
                cities: mapCities,
                fitCities: mapFitCities,
                selectedDayOffset: selectedDayOffset,
                overlayMode: mapOverlayMode,
                filterSunny: filterSunny,
                cameraPosition: $mapCameraPosition,
                selectedCityID: $selectedMapCityID
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

    private func weatherServiceErrorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.colors.destructive)
                .accessibilityHidden(true)

            Text(message)
                .font(.callout.weight(.medium))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

            Spacer(minLength: 8)

            Button {
                weatherService.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    // Accessibility: Keep the compact icon but make its full
                    // 44-point circular region dismiss the banner.
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(-9)
            .accessibilityLabel(localizedString("Cancel", locale: locale))
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
