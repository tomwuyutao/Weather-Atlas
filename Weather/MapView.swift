//
//  MapView.swift
//  Weather
//
//  Shared map composition and map interaction handling.
//

import SwiftUI
import WebKit
import CoreLocation
import MapKit
#if os(iOS)
import UIKit
#endif

enum WeatherMapProvider: String {
    case openStreetMap
    case appleMaps
}

extension ContentView {
    @ViewBuilder
    var iOSDateSliderOverlay: some View {
        // Date slider only on map tab — list tab uses the date switcher capsule
        if selectedTab == 1, showDateSlider, !showingInlineSearch, !isMapSpecialMode, !countryListSearchMode {
            #if os(macOS)
            GeometryReader { geometry in
                let topClearance: CGFloat = 34
                let bottomClearance: CGFloat = 174
                let availableHeight = max(190, geometry.size.height - topClearance - bottomClearance)
                let sliderHeight = min(300, max(220, availableHeight * 0.52))

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Color.clear
                        .frame(width: 60, height: sliderHeight)
                        .contentShape(Rectangle())
                        .overlay(alignment: .trailing) {
                            mapDateSlider(height: sliderHeight)
                        }
                        .padding(.trailing, 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.top, topClearance)
                .padding(.bottom, bottomClearance)
            }
            .transition(.opacity)
            #else
            mapDateSlider(height: 420)
                .frame(width: 145, height: 420, alignment: .trailing)
                .padding(.bottom, 420)
                .padding(.trailing, 1)
                .transition(.opacity)
            #endif
        }
    }

    var iOSDatePickerPopover: some View {
        DatePicker(
            "",
            selection: Binding(
                get: {
                    Calendar.current.date(byAdding: .day, value: max(0, selectedDayOffset), to: Date()) ?? Date()
                },
                set: { newDate in
                    let calendar = Calendar.current
                    let components = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: newDate))
                    if let days = components.day {
                        withAnimation(.smooth(duration: 0.2)) {
                            selectedDayOffset = max(0, min(9, days))
                        }
                    }
                }
            ),
            in: Date()...(Calendar.current.date(byAdding: .day, value: 9, to: Date()) ?? Date()),
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
        .frame(width: 280, height: 300)
        .padding(8)
        .presentationCompactAdaptation(.popover)
    }

    func centerMapOnDots(useListCoordinates: Bool = false) {
        recenterOnAllCities = false
        recenterUsesListCoordinates = useListCoordinates
        DispatchQueue.main.async {
            recenterOnAllCities = true
        }
    }

    func forceReloadMapDots() {
        mapMarkerReloadID += 1
    }

    func refreshActiveWeather() {
        dismissMapSelectionForRefresh()
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
            previewCity = nil
            #if os(macOS) || os(iOS)
            macHoverPresentedCardCityID = nil
            macMapExpandedCardFocusesMarker = false
            macMapExpandedCardAnchor = nil
            macMapExpandedCardBaseOffset = .zero
            macExpandedCardShowsDetails = false
            macMapLookupPreviewCityID = nil
            #endif
        }
    }

    var iOSMapControlsCapsule: some View {
        HStack(spacing: 8) {
            Button {
                PlatformFeedback.lightImpact()
                centerMapOnDots()
            } label: {
                Image(systemName: "dot.squareshape.split.2x2")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            mapOverlayMenu
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .padding(6)
        .themedGlass(in: .capsule)
        .transition(.scale.combined(with: .opacity))
    }

    func handleMapMarkerTap(_ city: CityWeather, anchor: CGPoint? = nil) {
        if showingInlineSearch || inlineSearchFieldPresented {
            showingInlineSearch = false
            inlineSearchFieldPresented = false
            resetNativeCitySearch()
        }

        #if os(macOS)
        if showingCityDetail || iPadInspectorPinned {
            PlatformFeedback.lightImpact()
            macHoverPresentedCardCityID = nil
            macMapExpandedCardFocusesMarker = true
            macMapExpandedCardAnchor = anchor ?? macCenteredMapMarkerAnchor()
            macMapExpandedCardBaseOffset = .zero
            macExpandedCardShowsDetails = true
            withAnimation(iPadInspectorMorphAnimation) {
                tappedCity = city
                showingMapExpandedCard = false
                showingCityDetail = true
            }
            return
        }
        #endif

        #if os(iOS)
        if shouldUseIPadLayout, showingCityDetail || iPadInspectorPinned {
            PlatformFeedback.lightImpact()
            macHoverPresentedCardCityID = nil
            macMapExpandedCardFocusesMarker = true
            macMapExpandedCardAnchor = anchor ?? macCenteredMapMarkerAnchor()
            macMapExpandedCardBaseOffset = .zero
            macExpandedCardShowsDetails = true
            withAnimation(iPadInspectorMorphAnimation) {
                tappedCity = city
                iPadInspectorPresentedCityID = city.id
                showingMapExpandedCard = false
                showingCityDetail = true
            }
            return
        }

        if !shouldUseIPadLayout, showingMapExpandedCard, tappedCity?.id == city.id {
            return
        }
        #endif
        PlatformFeedback.lightImpact()
        showMapMarkerCard(city, anchor: anchor, expanded: false, focusesMarker: true)
    }

    func handleMapBackgroundClick(_ coordinate: CLLocationCoordinate2D, anchor: CGPoint? = nil) {
        #if os(macOS) || os(iOS)
        #if os(macOS)
        withAnimation(iPadInspectorMorphAnimation) {
            if showingCityDetail {
                showingCityDetail = false
                iPadInspectorPinned = false
                macMapExpandedCardFocusesMarker = false
                macExpandedCardShowsDetails = false
                selectedDayOffset = -1
            } else if showingMapExpandedCard {
                dismissMapExpandedCard()
            }
        }
        return
        #endif

        #if os(iOS)
        if shouldUseIPadLayout {
            withAnimation(iPadInspectorMorphAnimation) {
                if showingCityDetail {
                    showingCityDetail = false
                    iPadInspectorPresentedCityID = nil
                    iPadInspectorPinned = false
                    macMapExpandedCardFocusesMarker = false
                    macExpandedCardShowsDetails = false
                    selectedDayOffset = -1
                } else if showingMapExpandedCard {
                    dismissMapExpandedCard()
                }
            }
            return
        }
        #endif

        #if os(iOS)
        guard usesFloatingMapCardLayout else {
            dismissMapExpandedCard()
            return
        }

        if showingMapExpandedCard {
            dismissMapExpandedCard()
            return
        }

        macMapLookupTaskID += 1
        let taskID = macMapLookupTaskID
        macMapLookupPreviewCityID = nil
        macMapExpandedCardAnchor = anchor
        macMapExpandedCardBaseOffset = .zero
        Task {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
            let name = placemark?.locality
                ?? placemark?.subAdministrativeArea
                ?? placemark?.administrativeArea
                ?? placemark?.name
                ?? String(format: "%.2f, %.2f", coordinate.latitude, coordinate.longitude)
            let country = placemark?.country ?? ""
            let city = City(name: name, country: country, latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let cityWeather = await weatherService.fetchWeatherForCity(city) else {
                return
            }
            guard taskID == macMapLookupTaskID else { return }

            await MainActor.run {
                macMapLookupPreviewCityID = cityWeather.id
                previewCity = cityWeather
                tappedCity = cityWeather
                macMapExpandedCardFocusesMarker = true
                macMapExpandedCardAnchor = anchor
                macMapExpandedCardBaseOffset = .zero
                macExpandedCardShowsDetails = false
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    showingMapExpandedCard = true
                }
            }
        }
        #endif
        #else
        dismissMapExpandedCard()
        #endif
    }

    func dismissMapExpandedCard() {
        #if os(macOS)
        let shouldRecenterAfterDismiss = previewCity != nil && previewCity?.id != macMapLookupPreviewCityID
        #else
        let shouldRecenterAfterDismiss = previewCity != nil
        #endif
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingMapExpandedCard = false
            tappedCity = nil
            previewCity = nil
            if shouldRecenterAfterDismiss {
                recenterOnAllCities = true
            }
            #if os(macOS) || os(iOS)
            macHoverPresentedCardCityID = nil
            macMapExpandedCardFocusesMarker = false
            macMapExpandedCardAnchor = nil
            macMapExpandedCardBaseOffset = .zero
            macExpandedCardShowsDetails = false
            macMapLookupPreviewCityID = nil
            #endif
        }
    }

    func showMapMarkerCard(_ city: CityWeather, anchor: CGPoint? = nil, expanded: Bool, focusesMarker: Bool) {
        #if os(macOS) || os(iOS)
        if usesFloatingMapCardLayout {
            macHoverPresentedCardCityID = nil
            macMapExpandedCardFocusesMarker = focusesMarker
            macExpandedCardShowsDetails = expanded
            macMapExpandedCardAnchor = anchor ?? (focusesMarker ? macCenteredMapMarkerAnchor() : nil)
            macMapExpandedCardBaseOffset = .zero
        }
        #endif

        if showingMapExpandedCard && tappedCity?.id == city.id {
            if usesFloatingMapCardLayout {
                #if os(macOS) || os(iOS)
                macHoverPresentedCardCityID = nil
                macMapExpandedCardFocusesMarker = focusesMarker
                #endif
                return
            } else {
                showingCityDetail = true
                #if os(iOS)
                pushIPhoneRoute(.cityDetail)
                #endif
                return
            }
        }

        tappedCity = city
        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
            showingMapExpandedCard = true
        }
    }

    func macCenteredMapMarkerAnchor() -> CGPoint? {
        #if os(macOS) || os(iOS)
        guard macMapViewportSize.width > 0, macMapViewportSize.height > 0 else { return nil }
        return CGPoint(
            x: macMapViewportSize.width / 2 + CGFloat(macMapLeadingFitPadding) * 0.88,
            y: macMapViewportSize.height / 2
        )
        #else
        return nil
        #endif
    }

    #if os(macOS) || os(iOS)
    func deleteMapCity(_ city: CityWeather) {
        weatherService.removeCity(city)
        if previewCity?.id == city.id {
            previewCity = nil
        }
        showingMapExpandedCard = false
        tappedCity = nil
        selectedDayOffset = -1
        recenterOnAllCities = true
    }

    func handleMapMarkerCommandHover(_ city: CityWeather?, anchor: CGPoint?) {
        guard let city else {
            if macHoverPresentedCardCityID == tappedCity?.id {
                showingMapExpandedCard = false
                tappedCity = nil
                macHoverPresentedCardCityID = nil
                macMapExpandedCardFocusesMarker = false
                macExpandedCardShowsDetails = false
            }
            return
        }

        guard !showingMapExpandedCard || macHoverPresentedCardCityID != nil else { return }
        macHoverPresentedCardCityID = city.id
        macMapExpandedCardFocusesMarker = false
        macMapExpandedCardAnchor = anchor
        macMapExpandedCardBaseOffset = .zero
        macExpandedCardShowsDetails = false
        tappedCity = city
        showingMapExpandedCard = true
    }
    #endif

    var iOSMapView: some View {
        mapView
    }

    var mapView: some View {
        ZStack {
            if WeatherMapProvider(rawValue: mapProviderRaw) == .appleMaps {
                AppleWeatherMapView(
                    cities: mapCities,
                    fitCities: mapFitCities,
                    selectedDayOffset: selectedDayOffset,
                    overlayMode: mapOverlayMode,
                    filterSunny: filterSunny,
                    markerReloadID: mapMarkerReloadID,
                    focusedCountryBoundary: nil,
                    selectedCityID: mapFocusSelectedMarker ? tappedCity?.id : nil,
                    recenterOnAllCities: $recenterOnAllCities,
                    recenterUsesListCoordinates: $recenterUsesListCoordinates,
                    centerOnCity: centerOnCityTrigger,
                    onMarkerTap: { city, point in
                        guard !countryListSearchMode else { return }
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
            } else {
                MapLibreWebMapView(
                    cities: mapCities,
                    fitCities: mapFitCities,
                    selectedDayOffset: selectedDayOffset,
                    overlayMode: mapOverlayMode,
                    filterSunny: filterSunny,
                    markerReloadID: mapMarkerReloadID,
                    markerSizeScale: mapMarkerSizeScale,
                    showsMarkerHoverLabels: mapShowsMarkerHoverLabels,
                    focusedCountryBoundary: CountryBoundaryCatalog.shared.feature(for: countryListPreviewCountry),
                    tappedCity: $tappedCity,
                    recenterOnAllCities: $recenterOnAllCities,
                    recenterUsesListCoordinates: $recenterUsesListCoordinates,
                    centerOnCity: centerOnCityTrigger,
                    leadingFitPadding: macMapLeadingFitPadding,
                    focusSelectedMarker: mapFocusSelectedMarker,
                    allowsMarkerHover: mapAllowsMarkerHover,
                    cameraProfile: mapCameraProfile,
                    onMarkerTap: { city, point in
                        guard !countryListSearchMode else { return }
                        handleMapMarkerTap(city, anchor: point)
                    },
                    onMapClick: { coordinate, point in
                        handleMapBackgroundClick(coordinate, anchor: point)
                    },
                    onMarkerCommandHover: { city, point in
                        #if os(macOS) || os(iOS)
                        if usesFloatingMapCardLayout {
                            handleMapMarkerCommandHover(city, anchor: point)
                        }
                        #endif
                    },
                    onMapGestureStart: {
                        if showingMapExpandedCard {
                            dismissMapExpandedCard()
                        }
                    }
                )
                .ignoresSafeArea()
            }

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
        .onChange(of: countryListPreviewCountry?.id) { _, newValue in
            guard countryListSearchMode, newValue != nil else { return }
            centerMapOnDots(useListCoordinates: true)
        }
        .onChange(of: countryListPreviewCityCount) { _, _ in
            guard countryListSearchMode, countryListPreviewCountry != nil else { return }
            centerMapOnDots(useListCoordinates: true)
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

    @ViewBuilder
    func countryListPreviewControls(showsInlineActions: Bool = true, usesIPhoneCardFrame: Bool = false) -> some View {
        if countryListSearchMode, let country = countryListPreviewCountry {
            let cityCountRange = countryListCityCountRange(for: country)
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(country.name)
                            .font(.headline)
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)
                        Text("Country list")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.colors.secondaryText)
                    }

                    Spacer(minLength: 12)

                    Text("\(countryListPreviewCityCount)")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(theme.colors.primaryText)
                }

                Slider(
                    value: Binding(
                        get: { Double(countryListPreviewCityCount) },
                        set: { newValue in
                            countryListPreviewCityCount = countryListClampedCityCount(Int(newValue.rounded()), for: country)
                            forceReloadMapDots()
                        }
                    ),
                    in: cityCountRange,
                    step: 1
                )
                .tint(theme.colors.accent)

                if showsInlineActions {
                    HStack(spacing: 10) {
                        Button("Cancel") {
                            cancelCountryListPreview()
                        }
                        .buttonStyle(.borderless)

                        Spacer(minLength: 8)

                        Button("Create") {
                            commitCountryList(country, cityCount: countryListPreviewCityCount)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.colors.accent)
                    }
                }
            }
            .padding(.horizontal, usesIPhoneCardFrame ? 22 : 16)
            .padding(.vertical, usesIPhoneCardFrame ? 16 : 16)
            .frame(maxWidth: .infinity)
            .frame(height: usesIPhoneCardFrame ? iOSFloatingMapCardHeight : nil)
            .themedGlass(in: .rect(cornerRadius: 24))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .gesture(DragGesture(minimumDistance: 0))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    func countryListCityCountRange(for country: CountryCityGroup) -> ClosedRange<Double> {
        let upper = max(1, min(30, country.cities.count))
        let lower = min(5, upper)
        return Double(lower)...Double(upper)
    }

    func countryListClampedCityCount(_ count: Int, for country: CountryCityGroup) -> Int {
        let range = countryListCityCountRange(for: country)
        return max(Int(range.lowerBound), min(Int(range.upperBound), count))
    }

    func cancelCountryListPreview() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            countryListSearchMode = false
            countryListPreviewCountry = nil
            countryListInitialCountry = nil
            showingInlineSearch = false
            inlineSearchFieldPresented = false
            inlineSearchText = ""
        }
        centerMapOnDots(useListCoordinates: true)
    }

    var macMapLeadingFitPadding: Double {
        #if os(macOS)
        macSidebarVisibility == .detailOnly ? 0 : Double(macMeasuredSidebarWidth)
        #elseif os(iOS)
        shouldUseIPadLayout && iPadSidebarVisibility != .detailOnly ? 280 : 0
        #else
        0
        #endif
    }

    var mapFocusSelectedMarker: Bool {
        #if os(iOS)
        shouldUseIPadLayout ? macMapExpandedCardFocusesMarker : showingMapExpandedCard
        #elseif os(macOS)
        usesFloatingMapCardLayout ? macMapExpandedCardFocusesMarker : false
        #else
        false
        #endif
    }

    var mapAllowsMarkerHover: Bool {
        #if os(iOS)
        shouldUseIPadLayout
        #else
        true
        #endif
    }

    var mapMarkerSizeScale: Double {
        #if os(iOS)
        shouldUseIPadLayout ? 1.28 : 1.0
        #else
        1.0
        #endif
    }

    var mapShowsMarkerHoverLabels: Bool {
        #if os(iOS)
        shouldUseIPadLayout
        #else
        true
        #endif
    }

    var shouldHideInlineMapCardCityName: Bool {
        false
    }

    var shouldAddInlineMapCardVerticalPadding: Bool {
        #if os(iOS)
        !shouldUseIPadLayout
        #else
        false
        #endif
    }

    var mapCameraProfile: MapCameraProfile {
        #if os(macOS)
        .desktop
        #elseif os(iOS)
        shouldUseIPadLayout ? .tablet : .mobile
        #else
        .mobile
        #endif
    }

    func cityIsInSidebar(_ cityWeather: CityWeather) -> Bool {
        weatherService.cityWeatherData.contains(where: { $0.city.name == cityWeather.city.name && $0.city.country == cityWeather.city.country })
    }

    func addCityToSidebar(_ cityWeather: CityWeather) async {
        await weatherService.addCity(cityWeather.city)
        PlatformFeedback.lightImpact()
        if let newCity = weatherService.cityWeatherData.first(where: { $0.city.name == cityWeather.city.name && $0.city.country == cityWeather.city.country }) {
            tappedCity = newCity
        }
    }
}

private struct AppleWeatherMapView: View {
    let cities: [CityWeather]
    let fitCities: [City]
    let selectedDayOffset: Int
    let overlayMode: String
    let filterSunny: Bool
    let markerReloadID: Int
    let focusedCountryBoundary: CountryBoundaryFeature?
    let selectedCityID: UUID?
    @Binding var recenterOnAllCities: Bool
    @Binding var recenterUsesListCoordinates: Bool
    let centerOnCity: CityWeather?
    let onMarkerTap: (CityWeather, CGPoint?) -> Void
    let onMapClick: ((CLLocationCoordinate2D, CGPoint?) -> Void)?
    let onMapGestureStart: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var cameraPosition: MapCameraPosition = .region(Self.defaultRegion)
    @State private var lastCenteredCityID: UUID?

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, interactionModes: .all) {
                if let mask = countryMaskPolygon {
                    MapPolygon(mask)
                        .foregroundStyle(Color.black.opacity(colorScheme == .dark ? 0.34 : 0.22))
                }

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
        .onChange(of: focusedCountryBoundary) { _, _ in
            fitVisibleContent()
        }
        .onChange(of: recenterOnAllCities) { _, shouldRecenter in
            guard shouldRecenter else { return }
            fitVisibleContent()
            recenterOnAllCities = false
            recenterUsesListCoordinates = false
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

    private var countryMaskPolygon: MKPolygon? {
        guard let focusedCountryBoundary else { return nil }
        let exterior = [
            CLLocationCoordinate2D(latitude: -85, longitude: -180),
            CLLocationCoordinate2D(latitude: -85, longitude: 180),
            CLLocationCoordinate2D(latitude: 85, longitude: 180),
            CLLocationCoordinate2D(latitude: 85, longitude: -180)
        ]
        let holes = Self.outerRings(from: focusedCountryBoundary).compactMap(Self.polygon(from:))
        return MKPolygon(coordinates: exterior, count: exterior.count, interiorPolygons: holes)
    }

    private func fitVisibleContent() {
        let region: MKCoordinateRegion
        if let focusedCountryBoundary, let boundaryRegion = Self.region(for: focusedCountryBoundary) {
            region = boundaryRegion
        } else {
            let citiesToFit = recenterUsesListCoordinates ? fitCities : visibleCities.map(\.city)
            region = Self.region(for: citiesToFit)
        }
        withAnimation(.smooth(duration: 0.35)) {
            cameraPosition = .region(region)
        }
    }

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

    private static func region(for feature: CountryBoundaryFeature) -> MKCoordinateRegion? {
        let rings = outerRings(from: feature)
        let coordinates = rings.flatMap { $0 }
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude
        for coordinate in coordinates.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
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

    private static func outerRings(from feature: CountryBoundaryFeature) -> [[CLLocationCoordinate2D]] {
        switch feature.geometry.coordinates {
        case .polygon(let polygon):
            return polygon.first.map { [coordinates(from: $0)] } ?? []
        case .multiPolygon(let multiPolygon):
            return multiPolygon.compactMap { polygon in
                polygon.first.map(coordinates(from:))
            }
        }
    }

    private static func coordinates(from ring: [[Double]]) -> [CLLocationCoordinate2D] {
        ring.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
    }

    private static func polygon(from coordinates: [CLLocationCoordinate2D]) -> MKPolygon? {
        guard coordinates.count >= 3 else { return nil }
        return MKPolygon(coordinates: coordinates, count: coordinates.count)
    }
}

#if os(iOS)
import UIKit
#endif

#if os(macOS)
typealias PlatformWebViewRepresentable = NSViewRepresentable
#else
typealias PlatformWebViewRepresentable = UIViewRepresentable
#endif

struct MapLibreWebMapView: PlatformWebViewRepresentable {
    let cities: [CityWeather]
    let fitCities: [City]
    let selectedDayOffset: Int
    var overlayMode: String = "weather"
    let filterSunny: Bool
    var markerReloadID: Int = 0
    var markerSizeScale: Double = 1
    var showsMarkerHoverLabels: Bool = true
    var focusedCountryBoundary: CountryBoundaryFeature?
    @Binding var tappedCity: CityWeather?
    @Binding var recenterOnAllCities: Bool
    @Binding var recenterUsesListCoordinates: Bool
    var centerOnCity: CityWeather?
    var leadingFitPadding: Double = 0
    var focusSelectedMarker: Bool = true
    var allowsMarkerHover: Bool = true
    var cameraProfile: MapCameraProfile = .desktop
    var onMarkerTap: (CityWeather, CGPoint?) -> Void
    var onMapClick: ((CLLocationCoordinate2D, CGPoint?) -> Void)? = nil
    var onMarkerCommandHover: ((CityWeather?, CGPoint?) -> Void)? = nil
    var onCameraMove: ((CLLocationCoordinate2D) -> Void)? = nil
    var onMapGestureStart: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.defaultRawValue

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        updateWebView(webView, context: context)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        dismantleWebView(nsView, coordinator: coordinator)
    }
    #else
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        updateWebView(webView, context: context)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        dismantleWebView(uiView, coordinator: coordinator)
    }
    #endif

    private func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "mapEvent")
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        configuration.dataDetectorTypes = []
        #endif

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        #if os(iOS)
        webView.allowsLinkPreview = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = platformMapBackgroundColor
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset = .zero
        webView.scrollView.scrollIndicatorInsets = .zero
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = webView.backgroundColor
        }
        #elseif os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        webView.loadHTMLString(Self.html, baseURL: Bundle.main.resourceURL)
        context.coordinator.webView = webView
        return webView
    }

    private func updateWebView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.webView = webView
        #if os(iOS)
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = platformMapBackgroundColor
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = platformMapBackgroundColor
        }
        #endif
        context.coordinator.pushStateIfReady()
    }

    #if os(iOS)
    private var platformMapBackgroundColor: UIColor {
        colorScheme == .dark
            ? UIColor(red: 0x1A / 255.0, green: 0x1B / 255.0, blue: 0x2E / 255.0, alpha: 1)
            : UIColor(red: 0xF4 / 255.0, green: 0xF1 / 255.0, blue: 0xEB / 255.0, alpha: 1)
    }
    #endif

    private static func dismantleWebView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mapEvent")
        webView.stopLoading()
        webView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MapLibreWebMapView
        weak var webView: WKWebView?
        private var isReady = false
        private var lastPayload = ""
        private var lastStyleKey = ""
        private var lastMarkerReloadID = 0
        private var lastCenteredCityID: UUID?
        private var observers: [NSObjectProtocol] = []

        init(parent: MapLibreWebMapView) {
            self.parent = parent
            super.init()
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: .weatherZoomInCommand, object: nil, queue: .main) { [weak self] _ in
                self?.evaluate("window.weatherMapZoomIn?.();")
            })
            observers.append(center.addObserver(forName: .weatherZoomOutCommand, object: nil, queue: .main) { [weak self] _ in
                self?.evaluate("window.weatherMapZoomOut?.();")
            })
            observers.append(center.addObserver(forName: .weatherPanCommand, object: nil, queue: .main) { [weak self] notification in
                guard let key = notification.object as? String else { return }
                self?.evaluate("window.weatherMapStep?.(\(Self.jsString(key)));")
            })
            observers.append(center.addObserver(forName: .weatherKeyboardZoomCommand, object: nil, queue: .main) { [weak self] notification in
                guard let key = notification.object as? String else { return }
                self?.evaluate("window.weatherMapKeyboardZoom?.(\(Self.jsString(key)));")
            })
            #if os(iOS)
            observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                let styleKey = self.parent.colorScheme == .dark ? "dark" : "bright"
                self.evaluate("window.weatherMapReloadBaseMapAfterActivation?.(\(Self.jsString(styleKey)));")
                self.pushStateIfReady(force: true)
            })
            #endif
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            pushStateIfReady(force: true)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "mapEvent",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            switch type {
            case "ready":
                isReady = true
                pushStateIfReady(force: true)
            case "markerTap":
                guard let id = body["id"] as? String,
                      let city = parent.cities.first(where: { $0.id.uuidString == id }) else { return }
                let point: CGPoint?
                if parent.cameraProfile == .mobile,
                   let tapX = body["tapX"] as? Double,
                   let tapY = body["tapY"] as? Double {
                    point = CGPoint(x: tapX, y: tapY)
                } else if let x = body["x"] as? Double, let y = body["y"] as? Double {
                    point = CGPoint(x: x, y: y)
                } else {
                    point = nil
                }
                parent.onMarkerTap(city, point)
            case "mapBackgroundClick":
                guard let lat = body["lat"] as? Double,
                      let lng = body["lng"] as? Double else { return }
                let point: CGPoint?
                if let x = body["x"] as? Double, let y = body["y"] as? Double {
                    point = CGPoint(x: x, y: y)
                } else {
                    point = nil
                }
                parent.onMapClick?(CLLocationCoordinate2D(latitude: lat, longitude: lng), point)
            case "markerCommandHover":
                guard let id = body["id"] as? String,
                      let city = parent.cities.first(where: { $0.id.uuidString == id }) else { return }
                let point: CGPoint?
                if let x = body["x"] as? Double, let y = body["y"] as? Double {
                    point = CGPoint(x: x, y: y)
                } else {
                    point = nil
                }
                parent.onMarkerCommandHover?(city, point)
            case "markerCommandHoverEnd":
                parent.onMarkerCommandHover?(nil, nil)
            case "cameraMove":
                guard let lat = body["lat"] as? Double,
                      let lng = body["lng"] as? Double else { return }
                parent.onCameraMove?(CLLocationCoordinate2D(latitude: lat, longitude: lng))
            case "mapGestureStart":
                parent.onMapGestureStart?()
            default:
                break
            }
        }

        func pushStateIfReady(force: Bool = false) {
            guard isReady, webView != nil else { return }

            let styleKey = parent.colorScheme == .dark ? "dark" : "bright"
            if force || styleKey != lastStyleKey {
                lastStyleKey = styleKey
                evaluate("window.setMapStyleMode(\(Self.jsString(styleKey)));")
            }

            evaluate("window.setWeatherMapCameraProfile?.(\(Self.jsString(parent.cameraProfile.rawValue)));")

            let features = parent.makeFeatures()
            let fitCoordinates = parent.makeFitCoordinates()
            guard let data = try? JSONEncoder().encode(features),
                  let json = String(data: data, encoding: .utf8),
                  let fitData = try? JSONEncoder().encode(fitCoordinates),
                  let fitJSON = String(data: fitData, encoding: .utf8),
                  let boundaryData = try? JSONEncoder().encode(parent.focusedCountryBoundary),
                  let boundaryJSON = String(data: boundaryData, encoding: .utf8) else { return }
            let selectedID = parent.focusSelectedMarker ? (parent.tappedCity?.id.uuidString ?? "") : ""
            let payload = "{features:\(json),fitCoordinates:\(fitJSON),focusedCountryBoundary:\(boundaryJSON),selectedID:\(Self.jsString(selectedID)),allowsMarkerHover:\(parent.allowsMarkerHover ? "true" : "false"),showsMarkerHoverLabels:\(parent.showsMarkerHoverLabels ? "true" : "false"),markerSizeScale:\(parent.markerSizeScale)}"

            let shouldReloadMarkers = parent.markerReloadID != lastMarkerReloadID
            if shouldReloadMarkers {
                lastMarkerReloadID = parent.markerReloadID
            }
            if force || shouldReloadMarkers || payload != lastPayload {
                lastPayload = payload
                evaluate("window.updateWeatherData(\(payload));")
            }

            if parent.recenterOnAllCities {
                evaluate("window.fitWeatherData(\(parent.leadingFitPadding), \(parent.recenterUsesListCoordinates ? "true" : "false"));")
                DispatchQueue.main.async {
                    self.parent.recenterOnAllCities = false
                    self.parent.recenterUsesListCoordinates = false
                }
            }

            if let centerOnCity = parent.centerOnCity, centerOnCity.id != lastCenteredCityID {
                lastCenteredCityID = centerOnCity.id
                evaluate("window.flyToCity(\(Self.jsString(centerOnCity.id.uuidString)), \(parent.leadingFitPadding)); ")
            }
        }

        private func evaluate(_ script: String) {
            webView?.evaluateJavaScript(script)
        }

        private static func jsString(_ value: String) -> String {
            guard let data = try? JSONEncoder().encode(value),
                  let string = String(data: data, encoding: .utf8) else { return "\"\"" }
            return string
        }
    }

    private func makeFitCoordinates() -> [MapLibreFitCoordinate] {
        fitCities.map { city in
            MapLibreFitCoordinate(latitude: city.latitude, longitude: city.longitude)
        }
    }

    private func makeFeatures() -> [MapLibreWeatherFeature] {
        return cities.compactMap { cityWeather in
            let isHiddenByFilter = filterSunny && !passesFilter(cityWeather)
            let forecast = cityWeather.forecast(for: max(0, selectedDayOffset))
            let hasData = selectedDayOffset == -1
                ? cityWeather.hasCurrentData(forOverlay: overlayMode)
                : forecast.hasData(forOverlay: overlayMode)
            guard hasData else { return nil }

            let color = markerColor(for: cityWeather, forecast: forecast)
            return MapLibreWeatherFeature(
                id: cityWeather.id.uuidString,
                name: cityWeather.city.localizedName(locale: locale),
                country: cityWeather.city.country,
                latitude: cityWeather.city.latitude,
                longitude: cityWeather.city.longitude,
                label: "",
                color: color,
                hidden: isHiddenByFilter
            )
        }
    }

    private func passesFilter(_ cityWeather: CityWeather) -> Bool {
        guard filterSunny else { return true }
        if selectedDayOffset == -1 {
            return cityWeather.condition == .clear && !cityWeather.weatherIcon.contains("moon")
        }
        let forecast = cityWeather.forecast(for: selectedDayOffset)
        return forecast.condition == .clear && !forecast.weatherIcon.contains("moon")
    }

    private func markerColor(for cityWeather: CityWeather, forecast: DailyForecast) -> String {
        let isNow = selectedDayOffset == -1
        if overlayMode == "temperature" {
            return temperatureColor(isNow ? cityWeather.temperature : forecast.dailyHigh)
        }
        if overlayMode == "cloudCover" {
            let value = isNow ? cityWeather.currentCloudCover : forecast.cloudCover
            return blendHex(from: dotRainHex, to: dotCloudyHex, amount: value ?? 0.5)
        }
        if overlayMode == "precipitation" {
            let chance: Double
            if isNow {
                chance = [.rain, .drizzle, .snow].contains(cityWeather.condition) ? 1 : 0
            } else {
                chance = forecast.precipitationChance ?? 0.5
            }
            return blendHex(from: 0xFFFFFF, to: dotDrizzleHex, amount: chance)
        }
        if overlayMode == "windSpeed" {
            let windSpeed = (isNow ? cityWeather.currentWindSpeed : forecast.windSpeed) ?? 0
            let wind = min(1, windSpeed / 100)
            return blendHex(from: 0xFFFFFF, to: saturatedPartlySunnyHex, amount: wind)
        }
        if overlayMode == "uvIndex" {
            let uv = min(1, Double((isNow ? cityWeather.currentUVIndex : forecast.uvIndex) ?? 0) / 11)
            return blendHex(from: 0xFFFFFF, to: destructiveHex, amount: uv)
        }
        if overlayMode == "humidity" {
            return blendHex(from: 0xFFFFFF, to: dotDrizzleHex, amount: (isNow ? cityWeather.currentHumidity : forecast.maxHumidity) ?? 0.5)
        }
        if overlayMode == "visibility" {
            let visibility = min(1, ((isNow ? cityWeather.currentVisibility : forecast.maxVisibility) ?? 15) / 30)
            return blendHex(from: 0xFFFFFF, to: dotRainHex, amount: visibility)
        }
        let condition = isNow ? cityWeather.condition : forecast.condition
        return color(for: condition, icon: isNow ? cityWeather.weatherIcon : forecast.weatherIcon)
    }

    private func color(for condition: AppWeatherCondition, icon: String) -> String {
        if icon.contains("moon") { return "#A285B7" }
        switch condition {
        case .clear: return "#FF8A65"
        case .partlySunny: return "#EEB368"
        case .partlyCloudy: return colorScheme == .dark ? "#D3E3EC" : "#B8C7D0"
        case .cloudy: return colorScheme == .dark ? "#D3E3EC" : "#B8C7D0"
        case .rain: return "#4D70D4"
        case .drizzle: return "#65ABE3"
        case .snow: return colorScheme == .dark ? "#D3E3EC" : "#B8C7D0"
        case .fog: return "#D3E3EC"
        case .wind: return colorScheme == .dark ? "#D3E3EC" : "#B8C7D0"
        }
    }

    private func temperatureColor(_ tempC: Double) -> String {
        if tempC <= 0 {
            return blendHex(from: dotRainHex, to: dotDrizzleHex, amount: max(0, min(1, (tempC + 20) / 20)))
        }
        if tempC <= 10 {
            return blendHex(from: dotDrizzleHex, to: dotCloudyHex, amount: max(0, min(1, tempC / 10)))
        }
        if tempC <= 20 {
            return blendHex(from: dotCloudyHex, to: saturatedPartlySunnyHex, amount: max(0, min(1, (tempC - 10) / 10)))
        }
        return blendHex(from: saturatedPartlySunnyHex, to: destructiveHex, amount: max(0, min(1, (tempC - 20) / 20)))
    }

    private var dotCloudyHex: Int {
        colorScheme == .dark ? 0xD3E3EC : 0xB8C7D0
    }

    private var dotRainHex: Int {
        0x4D70D4
    }

    private var dotDrizzleHex: Int {
        0x65ABE3
    }

    private var dotPartlyCloudyHex: Int {
        colorScheme == .dark ? 0xF4DC85 : 0xEEB368
    }

    private var destructiveHex: Int {
        0xC94949
    }

    private var saturatedPartlySunnyHex: Int {
        blendInt(from: dotPartlyCloudyHex, to: 0xFF8A65, amount: 0.18)
    }

    private func blendHex(from: Int, to: Int, amount: Double) -> String {
        let color = blendInt(from: from, to: to, amount: amount)
        return String(format: "#%02X%02X%02X", (color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF)
    }

    private func blendInt(from: Int, to: Int, amount: Double) -> Int {
        let t = max(0, min(1, amount))
        let r1 = Double((from >> 16) & 0xFF)
        let g1 = Double((from >> 8) & 0xFF)
        let b1 = Double(from & 0xFF)
        let r2 = Double((to >> 16) & 0xFF)
        let g2 = Double((to >> 8) & 0xFF)
        let b2 = Double(to & 0xFF)
        let r = Int(r1 + (r2 - r1) * t)
        let g = Int(g1 + (g2 - g1) * t)
        let b = Int(b1 + (b2 - b1) * t)
        return (r << 16) | (g << 8) | b
    }

    private static let html = """
    <!doctype html>
    <html>
    <head>
      <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
      <link rel="stylesheet" href="https://unpkg.com/maplibre-gl/dist/maplibre-gl.css">
      <script src="https://unpkg.com/maplibre-gl/dist/maplibre-gl.js"></script>
      <style>
        html, body { margin: 0; padding: 0; width: 100%; height: 100%; min-height: 100%; overflow: hidden; background: #FFFFFF; }
        body { -webkit-user-select: none; user-select: none; -webkit-touch-callout: none; position: fixed; inset: 0; }
        #map { position: fixed; inset: 0; width: 100vw; height: 100vh; height: 100dvh; background: #FFFFFF; }
        @media (prefers-color-scheme: dark) {
          html, body, #map { background: #2E2961; }
        }
        #window-drag-blur {
          position: fixed;
          top: 0;
          left: 0;
          right: 0;
          height: 42px;
          z-index: 4;
          pointer-events: none;
          background: rgba(237, 231, 222, 0.10);
          -webkit-backdrop-filter: blur(10px) saturate(1.12);
          backdrop-filter: blur(10px) saturate(1.12);
          border-bottom: 1px solid rgba(255, 255, 255, 0.08);
          display: none;
        }
        body.desktop-camera #window-drag-blur {
          display: block;
        }
        body.dark-map #window-drag-blur {
          background: rgba(26, 27, 46, 0.10);
          border-bottom-color: rgba(255, 255, 255, 0.04);
        }
        .maplibregl-map, .maplibregl-canvas-container, .maplibregl-canvas { width: 100% !important; height: 100% !important; cursor: default !important; }
        .maplibregl-canvas { transition: filter 220ms ease; }
        body.focus-selected .maplibregl-canvas { filter: saturate(0.82) brightness(0.94); }
        .maplibregl-ctrl-logo, .maplibregl-ctrl-attrib { display: none !important; }
        #hover-label {
          position: fixed;
          z-index: 5;
          padding: 4px 8px;
          border-radius: 999px;
          font: 600 12px -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
          color: #444444;
          background: rgba(248, 244, 241, 0.9);
          opacity: 0;
          transform: translate(-50%, -100%) translateY(-20px);
          pointer-events: none;
          transition: opacity 100ms ease, transform 100ms ease;
          box-shadow: 0 6px 18px rgba(0, 0, 0, 0.14);
          -webkit-backdrop-filter: blur(18px) saturate(1.2);
          backdrop-filter: blur(18px) saturate(1.2);
          white-space: nowrap;
        }
        body.dark-map #hover-label {
          color: #E7E7E8;
          background: rgba(46, 41, 97, 0.9);
        }
        #hover-label.visible {
          opacity: 1;
          transform: translate(-50%, -100%) translateY(-16px);
        }
      </style>
    </head>
    <body>
      <div id="map"></div>
      <div id="window-drag-blur"></div>
      <div id="hover-label"></div>
      <script>
        var map;
        var loaded = false;
        var pendingPayload = null;
        var currentStyleMode = window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'bright';
        var lastMovePost = 0;
        var hoveredMarkerID = '';
        var hoveredMarkerPoint = null;
        var commandPressed = false;
        var commandHoverCardID = '';
        var selectedMarkerID = '';
        var markerScales = {};
        var markerVisibilityScales = {};
        var markerScaleAnimationFrame = null;
        var selectedPulseAnimationFrame = null;
        var selectedPulse = 0;
        var pinchVelocity = 0;
        var pinchAnimationFrame = null;
        var mapResizeObserver = null;
        var pendingFitRequest = null;
        var initStarted = false;
        var baseStylePreferencesApplied = false;
        var leftMouseDown = null;
        var touchDown = null;
        var suppressNextClickUntil = 0;
        const markerHitRadius = 16;
        var cameraProfile = (/iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)) ? 'mobile' : 'desktop';
        const cameraProfiles = {
          desktop: {
            initialCenter: [0, 20],
            initialZoom: 1.45,
            fitPadding: { top: 180, right: 180, bottom: 180, left: 180 },
            fitMaxZoom: 4.2,
            cityZoom: 5,
            useLeadingOffset: true
          },
          tablet: {
            initialCenter: [0, 12],
            initialZoom: 1.15,
            fitPadding: { top: 116, right: 70, bottom: 180, left: 70 },
            fitMaxZoom: 3.65,
            cityZoom: 4.35,
            useLeadingOffset: true
          },
          mobile: {
            initialCenter: [0, 12],
            initialZoom: 1.15,
            fitPadding: { top: 104, right: 52, bottom: 168, left: 52 },
            fitMaxZoom: 4.2,
            cityZoom: 4.35,
            useLeadingOffset: true
          }
        };

        function styleURL(mode) {
          return mode === 'dark'
            ? 'https://tiles.openfreemap.org/styles/dark'
            : 'https://tiles.openfreemap.org/styles/bright';
        }

        function post(message) {
          window.webkit?.messageHandlers?.mapEvent?.postMessage(message);
        }

        ['contextmenu', 'selectstart', 'copy', 'cut', 'paste', 'dragstart'].forEach(eventName => {
          document.addEventListener(eventName, event => event.preventDefault(), { passive: false });
        });

        function postMapGestureStart() {
          post({ type: 'mapGestureStart' });
        }

        function mapElementHasUsableSize() {
          const element = document.getElementById('map');
          const rect = element?.getBoundingClientRect();
          return !!rect && rect.width >= 64 && rect.height >= 64;
        }

        function activeCameraProfile() {
          return cameraProfiles[cameraProfile] || cameraProfiles.desktop;
        }

        function applyCameraProfileClass() {
          document.body.classList.toggle('desktop-camera', cameraProfile === 'desktop');
        }

        function layerTextField(layer) {
          const value = layer?.layout?.['text-field'];
          return JSON.stringify(value || '').toLowerCase();
        }

        function layerSignature(layer) {
          const id = (layer.id || '').toLowerCase();
          const sourceLayer = (layer['source-layer'] || '').toLowerCase();
          const textField = layerTextField(layer);
          return `${id} ${sourceLayer} ${textField}`;
        }

        function themePalette(mode) {
          return mode === 'dark'
            ? { ocean: '#2E2961', land: '#423D74', subtleLand: '#423D74', road: '#56508B' }
            : { ocean: '#FFFFFF', land: '#F8F4F1', subtleLand: '#F8F4F1', road: '#E6DDD7' };
        }

        function isRoadLikeLayer(combined) {
          return combined.includes('road')
            || combined.includes('street')
            || combined.includes('transport')
            || combined.includes('highway')
            || combined.includes('motorway')
            || combined.includes('trunk')
            || combined.includes('primary')
            || combined.includes('secondary')
            || combined.includes('tertiary')
            || combined.includes('minor')
            || combined.includes('service')
            || combined.includes('path')
            || combined.includes('track')
            || combined.includes('rail');
        }

        function isBoundaryLikeLayer(combined) {
          return combined.includes('boundary')
            || combined.includes('admin')
            || combined.includes('border')
            || combined.includes('disputed');
        }

        function applyWarmMapPaint(layer, palette) {
          const combined = layerSignature(layer);
          layer.paint = layer.paint || {};

          if (layer.type === 'background') {
            layer.paint['background-color'] = palette.land;
            return;
          }

          if (layer.type === 'fill') {
            if (combined.includes('water') || combined.includes('ocean') || combined.includes('sea')) {
              layer.paint['fill-color'] = palette.ocean;
            } else if (combined.includes('park') || combined.includes('landcover') || combined.includes('landuse') || combined.includes('wood') || combined.includes('grass')) {
              layer.paint['fill-color'] = palette.subtleLand;
            } else {
              layer.paint['fill-color'] = palette.land;
            }
            layer.paint['fill-opacity'] = 1;
            return;
          }

          if (layer.type === 'line' && isBoundaryLikeLayer(combined)) {
            layer.layout = layer.layout || {};
            layer.layout.visibility = 'none';
            layer.paint['line-color'] = currentStyleMode === 'dark' ? '#171322' : '#5C526E';
            layer.paint['line-opacity'] = currentStyleMode === 'dark' ? 0.48 : 0.28;
            layer.paint['line-width'] = [
              'interpolate',
              ['linear'],
              ['zoom'],
              0, 0.35,
              3, 0.65,
              6, 1.05
            ];
            return;
          }

          if (layer.type === 'line' && isRoadLikeLayer(combined)) {
            layer.layout = layer.layout || {};
            layer.layout.visibility = 'none';
          }

          if (layer.type === 'symbol') {
            layer.layout = layer.layout || {};
            layer.layout.visibility = 'none';
          }
        }

        function shouldHideBaseLayer(layer) {
          const combined = layerSignature(layer);

          if (layer.type === 'line') {
            return isRoadLikeLayer(combined)
              || combined.includes('ferry')
              || combined.includes('marine')
              || combined.includes('navigation')
              || combined.includes('shipping');
          }

          if (layer.type === 'symbol') {
            return true;
          }

          return false;
        }

        async function cleanedStyle(mode) {
          const response = await fetch(styleURL(mode), { cache: 'reload' });
          const style = await response.json();
          const palette = themePalette(mode);
          style.layers = (style.layers || [])
            .filter(layer => !shouldHideBaseLayer(layer))
            .map(layer => {
              applyWarmMapPaint(layer, palette);
              return layer;
            });
          return style;
        }

        function applyWeatherMapStylePreferences() {
          if (!map || !map.isStyleLoaded() || baseStylePreferencesApplied) return;
          const style = map.getStyle();
          if (!style || !style.layers) return;

          const palette = themePalette(currentStyleMode);
          style.layers.forEach(layer => {
            if (shouldHideBaseLayer(layer)) {
              try { map.setLayoutProperty(layer.id, 'visibility', 'none'); } catch (_) {}
            } else {
              applyWarmMapPaint(layer, palette);
              try {
                Object.entries(layer.paint || {}).forEach(([key, value]) => map.setPaintProperty(layer.id, key, value));
              } catch (_) {}
            }
          });
          baseStylePreferencesApplied = true;
        }

        function updateBoundaryLayerVisibility(showBoundaries) {
          if (!map || !map.isStyleLoaded()) return;
          const style = map.getStyle();
          if (!style || !style.layers) return;
          style.layers.forEach(layer => {
            if (layer.type !== 'line' || !isBoundaryLikeLayer(layerSignature(layer))) return;
            try {
              map.setLayoutProperty(layer.id, 'visibility', showBoundaries ? 'visible' : 'none');
            } catch (_) {}
          });
        }

        function ensureLayers() {
          if (!map || !map.isStyleLoaded()) return;
          applyWeatherMapStylePreferences();
          if (!map.getSource('weather')) {
            map.addSource('weather', { type: 'geojson', data: emptyCollection() });
          }
          if (!map.getSource('country-mask')) {
            map.addSource('country-mask', { type: 'geojson', data: emptyCollection() });
          }
          if (!map.getLayer('country-mask-fill')) {
            map.addLayer({
              id: 'country-mask-fill', type: 'fill', source: 'country-mask',
              paint: {
                'fill-color': currentStyleMode === 'dark' ? '#070612' : '#FFFFFF',
                'fill-opacity': currentStyleMode === 'dark' ? 0.34 : 0.42
              }
            });
          }
          if (!map.getLayer('weather-hit')) {
            map.addLayer({
              id: 'weather-hit', type: 'circle', source: 'weather',
              paint: {
                'circle-radius': ['*', ['number', ['get', 'markerSizeScale'], 1], ['*', ['number', ['get', 'visibleScale'], 1], markerHitRadius]],
                'circle-color': 'rgba(0,0,0,0.01)',
                'circle-opacity': 0.01
              }
            });
          }
          if (!map.getLayer('weather-glow')) {
            map.addLayer({
              id: 'weather-glow', type: 'circle', source: 'weather',
              paint: {
                'circle-radius': ['*', ['number', ['get', 'markerSizeScale'], 1], ['*', ['number', ['get', 'visibleScale'], 1], ['+', 13, ['*', ['number', ['get', 'selectedPulse'], 0], 13]]]],
                'circle-color': ['get', 'color'],
                'circle-opacity': ['*',
                  ['number', ['get', 'visibleScale'], 1],
                  ['case',
                    ['boolean', ['get', 'selected'], false], ['-', 0.62, ['*', ['number', ['get', 'selectedPulse'], 0], 0.42]],
                    ['boolean', ['get', 'hovered'], false], 0.38,
                    ['boolean', ['get', 'dimmed'], false], 0.08,
                    0.24
                  ]
                ],
                'circle-radius-transition': { duration: 300, delay: 0 },
                'circle-color-transition': { duration: 360, delay: 0 },
                'circle-opacity-transition': { duration: 220, delay: 0 },
                'circle-blur': 0.85
              }
            });
          }
          if (!map.getLayer('weather-halo')) {
            map.addLayer({
              id: 'weather-halo', type: 'circle', source: 'weather',
              paint: {
                'circle-radius': ['*', ['number', ['get', 'markerSizeScale'], 1], ['*', ['number', ['get', 'visibleScale'], 1], ['+', 7, ['*', ['number', ['get', 'selectedPulse'], 0], 5]]]],
                'circle-color': ['get', 'color'],
                'circle-opacity': ['*',
                  ['number', ['get', 'visibleScale'], 1],
                  ['case',
                    ['boolean', ['get', 'selected'], false], 0.42,
                    ['boolean', ['get', 'hovered'], false], 0.24,
                    ['boolean', ['get', 'dimmed'], false], 0.04,
                    0.14
                  ]
                ],
                'circle-radius-transition': { duration: 300, delay: 0 },
                'circle-color-transition': { duration: 360, delay: 0 },
                'circle-opacity-transition': { duration: 220, delay: 0 },
                'circle-blur': 0.45
              }
            });
          }
          if (!map.getLayer('weather-points')) {
            map.addLayer({
              id: 'weather-points', type: 'circle', source: 'weather',
              paint: {
                'circle-radius': ['*', ['number', ['get', 'markerSizeScale'], 1], ['*', ['number', ['get', 'visibleScale'], 1], ['+', 4.5, ['*', ['number', ['get', 'scale'], 0], 2.5]]]],
                'circle-color': ['get', 'color'],
                'circle-opacity': ['*',
                  ['number', ['get', 'visibleScale'], 1],
                  ['case',
                    ['boolean', ['get', 'selected'], false], 1,
                    ['boolean', ['get', 'dimmed'], false], 0.28,
                    1
                  ]
                ],
                'circle-radius-transition': { duration: 300, delay: 0 },
                'circle-color-transition': { duration: 360, delay: 0 },
                'circle-opacity-transition': { duration: 220, delay: 0 }
              }
            });
          }
        }

        function emptyCollection() {
          return { type: 'FeatureCollection', features: [] };
        }

        function countryMaskFeature(boundaryFeature) {
          if (!boundaryFeature?.geometry) return null;
          const worldRing = [[-180, -90], [180, -90], [180, 90], [-180, 90], [-180, -90]];
          let holes = [];
          if (boundaryFeature.geometry.type === 'Polygon') {
            holes = boundaryFeature.geometry.coordinates.map(ring => ring.slice().reverse());
          } else if (boundaryFeature.geometry.type === 'MultiPolygon') {
            holes = boundaryFeature.geometry.coordinates.flatMap(polygon => polygon.map(ring => ring.slice().reverse()));
          }
          if (!holes.length) return null;
          return {
            type: 'Feature',
            geometry: { type: 'Polygon', coordinates: [worldRing, ...holes] },
            properties: {}
          };
        }

        function updateCountryMask(boundaryFeature) {
          const source = map.getSource('country-mask');
          if (!source) return;
          source.setData(emptyCollection());
        }

        function extendBoundsWithCoordinates(bounds, coordinates) {
          if (!Array.isArray(coordinates)) return;
          if (typeof coordinates[0] === 'number' && typeof coordinates[1] === 'number') {
            bounds.extend(coordinates);
            return;
          }
          coordinates.forEach(item => extendBoundsWithCoordinates(bounds, item));
        }

        function boundaryBounds(boundaryFeature) {
          if (!boundaryFeature?.geometry?.coordinates) return null;
          const bounds = new maplibregl.LngLatBounds();
          extendBoundsWithCoordinates(bounds, boundaryFeature.geometry.coordinates);
          return bounds.isEmpty() ? null : bounds;
        }

        function collectionFromPayload(payload) {
          const selectedID = payload.selectedID || '';
          const hasSelection = selectedID !== '';
          const hoverEnabled = payload.allowsMarkerHover !== false;
          return {
            type: 'FeatureCollection',
            features: (payload.features || []).map(item => ({
              type: 'Feature',
              id: item.id,
              properties: {
                id: item.id,
                name: item.name,
                country: item.country,
                label: item.label,
                color: item.color,
                hidden: !!item.hidden,
                scale: markerScales[item.id] ?? 0,
                visibleScale: markerVisibilityScales[item.id] ?? (item.hidden ? 0 : 1),
                selectedPulse: item.id === selectedID ? selectedPulse : 0,
                selected: item.id === selectedID,
                hovered: hoverEnabled && item.id === hoveredMarkerID,
                dimmed: hasSelection && item.id !== selectedID,
                markerSizeScale: payload.markerSizeScale || 1
              },
              geometry: { type: 'Point', coordinates: [item.longitude, item.latitude] }
            }))
          };
        }

        function markerTargetScale(id) {
          const hoverEnabled = pendingPayload?.allowsMarkerHover !== false;
          return (id && id === selectedMarkerID) ? 1.35 : (hoverEnabled && id && id === hoveredMarkerID ? 1 : 0);
        }

        function markerVisibilityTarget(item) {
          return item.hidden ? 0 : 1;
        }

        function renderWeatherSource() {
          const source = map?.getSource('weather');
          if (source && pendingPayload) source.setData(collectionFromPayload(pendingPayload));
        }

        function animateMarkerScales() {
          if (markerScaleAnimationFrame) return;
          function step() {
            let needsNextFrame = false;
            (pendingPayload?.features || []).forEach(item => {
              const current = markerScales[item.id] ?? 0;
              const target = markerTargetScale(item.id);
              const next = current + (target - current) * 0.26;
              markerScales[item.id] = Math.abs(next - target) < 0.01 ? target : next;
              if (markerScales[item.id] !== target) needsNextFrame = true;

              const currentVisibility = markerVisibilityScales[item.id] ?? (item.hidden ? 0 : 1);
              const visibilityTarget = markerVisibilityTarget(item);
              const nextVisibility = currentVisibility + (visibilityTarget - currentVisibility) * 0.22;
              markerVisibilityScales[item.id] = Math.abs(nextVisibility - visibilityTarget) < 0.01 ? visibilityTarget : nextVisibility;
              if (markerVisibilityScales[item.id] !== visibilityTarget) needsNextFrame = true;
            });
            renderWeatherSource();
            markerScaleAnimationFrame = needsNextFrame ? requestAnimationFrame(step) : null;
          }
          markerScaleAnimationFrame = requestAnimationFrame(step);
        }

        function updateMarkerScaleTargets() {
          (pendingPayload?.features || []).forEach(item => {
            if (markerScales[item.id] === undefined) markerScales[item.id] = 0;
            if (markerVisibilityScales[item.id] === undefined) markerVisibilityScales[item.id] = item.hidden ? 0 : 1;
          });
          animateMarkerScales();
        }

        function updateSelectedPulse() {
          if (!selectedMarkerID) {
            if (selectedPulseAnimationFrame) cancelAnimationFrame(selectedPulseAnimationFrame);
            selectedPulseAnimationFrame = null;
            selectedPulse = 0;
            renderWeatherSource();
            return;
          }
          if (selectedPulseAnimationFrame) return;
          const start = performance.now();
          function step(now) {
            selectedPulse = (Math.sin((now - start) / 520) + 1) / 2;
            renderWeatherSource();
            selectedPulseAnimationFrame = selectedMarkerID ? requestAnimationFrame(step) : null;
          }
          selectedPulseAnimationFrame = requestAnimationFrame(step);
        }

        function updateSource(payload) {
          pendingPayload = payload;
          if (payload?.allowsMarkerHover === false || payload?.showsMarkerHoverLabels === false) {
            hoveredMarkerID = '';
            hoveredMarkerPoint = null;
            document.getElementById('hover-label')?.classList.remove('visible');
          }
          selectedMarkerID = payload?.selectedID || '';
          document.body.classList.toggle('focus-selected', !!selectedMarkerID);
          ensureLayers();
          updateBoundaryLayerVisibility(!!payload?.focusedCountryBoundary);
          updateCountryMask(payload?.focusedCountryBoundary || null);
          updateMarkerScaleTargets();
          updateSelectedPulse();
          renderWeatherSource();
          if (pendingFitRequest && mapElementHasUsableSize()) {
            const request = pendingFitRequest;
            window.fitWeatherData(request.leadingPadding, request.useFitCoordinates);
          }
        }

        window.updateWeatherData = function(payload) {
          if (!loaded) { pendingPayload = payload; return; }
          updateSource(payload);
        };

        window.setWeatherMapCameraProfile = function(profile) {
          cameraProfile = cameraProfiles[profile] ? profile : 'desktop';
          applyCameraProfileClass();
        };

        window.fitWeatherData = function(leadingPadding = 0, useFitCoordinates = false) {
          pendingFitRequest = { leadingPadding, useFitCoordinates };
          if (!mapElementHasUsableSize()) return;
          if (!pendingPayload) return;
          const countryBounds = boundaryBounds(pendingPayload.focusedCountryBoundary);
          const savedListCoordinates = pendingPayload.fitCoordinates || [];
          const fitItems = useFitCoordinates ? savedListCoordinates : (pendingPayload.features?.length ? pendingPayload.features : savedListCoordinates);
          if (!countryBounds && !fitItems.length) return;
          const bounds = countryBounds || new maplibregl.LngLatBounds();
          if (!countryBounds) {
            fitItems.forEach(item => bounds.extend([item.longitude, item.latitude]));
          }
          if (!bounds.isEmpty()) {
            const camera = activeCameraProfile();
            const padding = {
              top: camera.fitPadding.top,
              right: camera.fitPadding.right,
              bottom: camera.fitPadding.bottom,
              left: camera.fitPadding.left + (camera.useLeadingOffset ? leadingPadding : 0)
            };
            map.fitBounds(bounds, {
              padding,
              duration: 550,
              maxZoom: camera.fitMaxZoom
            });
            pendingFitRequest = null;
          }
        };

        window.flyToCity = function(id, leadingPadding = 0) {
          const item = pendingPayload?.features?.find(feature => feature.id === id);
          const camera = activeCameraProfile();
          if (item) map.flyTo({
            center: [item.longitude, item.latitude],
            zoom: Math.max(map.getZoom(), camera.cityZoom),
            duration: 550,
            offset: [camera.useLeadingOffset ? leadingPadding / 2 : 0, 0]
          });
        };

        window.setMapStyleMode = async function(mode) {
          currentStyleMode = mode;
          document.body.classList.toggle('dark-map', mode === 'dark');
          baseStylePreferencesApplied = false;
          if (!map) return;
          const restoreWeatherLayers = () => {
            baseStylePreferencesApplied = false;
            ensureLayers();
            if (pendingPayload) updateSource(pendingPayload);
            renderWeatherSource();
          };
          map.once('style.load', restoreWeatherLayers);
          map.setStyle(await cleanedStyle(mode));
        };

        window.weatherMapZoomIn = function() {
          if (map) map.zoomIn({ duration: 220 });
        };

        window.weatherMapZoomOut = function() {
          if (map) map.zoomOut({ duration: 220 });
        };

        window.weatherMapStep = function(key) {
          if (!map) return;
          const step = 80;
          if (key === 'w') map.panBy([0, -step], { duration: 180 });
          if (key === 'a') map.panBy([-step, 0], { duration: 180 });
          if (key === 's') map.panBy([0, step], { duration: 180 });
          if (key === 'd') map.panBy([step, 0], { duration: 180 });
        };

        window.weatherMapKeyboardZoom = function(key) {
          if (!map) return;
          if (key === 'c') map.zoomTo(map.getZoom() + 0.6, { duration: 180 });
          if (key === 'v') map.zoomTo(map.getZoom() - 0.6, { duration: 180 });
        };

        function markerScreenPoint(feature, fallbackPoint) {
          const coordinates = feature?.geometry?.coordinates;
          return coordinates ? map.project(coordinates) : fallbackPoint;
        }

        function nearestMarkerFeature(features, point) {
          if (!features || !features.length) return null;
          let best = null;
          let bestDistance = Infinity;
          const seen = new Set();
          features.forEach(feature => {
            const id = feature?.properties?.id;
            if (!id || seen.has(id)) return;
            seen.add(id);
            const markerPoint = markerScreenPoint(feature, point);
            const dx = markerPoint.x - point.x;
            const dy = markerPoint.y - point.y;
            const distance = dx * dx + dy * dy;
            if (distance < bestDistance) {
              bestDistance = distance;
              best = feature;
            }
          });
          return best;
        }

        function markerFeatureAtPoint(point, radius = markerHitRadius) {
          const hitBox = [
            [point.x - radius, point.y - radius],
            [point.x + radius, point.y + radius]
          ];
          const features = map.queryRenderedFeatures(hitBox, {
            layers: ['weather-hit', 'weather-points', 'weather-halo', 'weather-glow']
          });
          return nearestMarkerFeature(features, point);
        }

        function openHoveredMarkerFromPoint(point) {
          const feature = markerFeatureAtPoint(point, markerHitRadius);
          if (!feature?.properties?.id) return false;
          const markerPoint = markerScreenPoint(feature, point);
          post({ type: 'markerTap', id: feature.properties.id, x: markerPoint.x, y: markerPoint.y, tapX: point.x, tapY: point.y });
          return true;
        }

        function updateHoveredMarkerLabel(id, point) {
          if (pendingPayload?.allowsMarkerHover === false || pendingPayload?.showsMarkerHoverLabels === false) {
            document.getElementById('hover-label')?.classList.remove('visible');
            return;
          }
          const feature = pendingPayload?.features?.find(item => item.id === id);
          const label = document.getElementById('hover-label');
          if (!label || !feature || !point) return;
          if (id && id === selectedMarkerID) {
            label.classList.remove('visible');
            return;
          }
          const clipped = point.x < 18
            || point.y < 18
            || point.x > window.innerWidth - 18
            || point.y > window.innerHeight - 18;
          if (clipped || !feature.name) {
            label.classList.remove('visible');
          } else {
            label.textContent = feature.name || '';
            label.style.left = `${point.x}px`;
            label.style.top = `${point.y}px`;
            label.classList.add('visible');
          }
        }

        function refreshHoveredMarker(id, point) {
          if (pendingPayload?.allowsMarkerHover === false) return;
          if (pendingPayload?.showsMarkerHoverLabels === false) {
            document.getElementById('hover-label')?.classList.remove('visible');
          } else {
            updateHoveredMarkerLabel(id, point);
          }
          if (hoveredMarkerID === id) {
            hoveredMarkerPoint = point;
          } else {
            hoveredMarkerID = id;
            hoveredMarkerPoint = point;
            if (pendingPayload) updateSource(pendingPayload);
          }
        }

        function updateHoveredMarkerPosition() {
          if (!hoveredMarkerID || !pendingPayload) return;
          const feature = pendingPayload.features?.find(item => item.id === hoveredMarkerID);
          if (!feature) {
            clearHoveredMarker();
            return;
          }
          const point = map.project([feature.longitude, feature.latitude]);
          hoveredMarkerPoint = point;
          updateHoveredMarkerLabel(hoveredMarkerID, point);
        }

        function endCommandHoverCard() {
          if (!commandHoverCardID) return;
          commandHoverCardID = '';
          post({ type: 'markerCommandHoverEnd' });
        }

        function updateCommandHoverCard() {
          if (!commandPressed || !hoveredMarkerID || !hoveredMarkerPoint) {
            endCommandHoverCard();
            return;
          }
          if (commandHoverCardID === hoveredMarkerID) return;
          commandHoverCardID = hoveredMarkerID;
          post({
            type: 'markerCommandHover',
            id: hoveredMarkerID,
            x: hoveredMarkerPoint.x,
            y: hoveredMarkerPoint.y
          });
        }

        function clearHoveredMarker() {
          if (!hoveredMarkerID) return;
          hoveredMarkerID = '';
          hoveredMarkerPoint = null;
          document.getElementById('hover-label')?.classList.remove('visible');
          if (pendingPayload) updateSource(pendingPayload);
          endCommandHoverCard();
        }

        function stopPinchInertia() {
          if (pinchAnimationFrame) cancelAnimationFrame(pinchAnimationFrame);
          pinchAnimationFrame = null;
          pinchVelocity = 0;
        }

        function resizeMapSoon() {
          if (!map) return;
          requestAnimationFrame(() => {
            map.resize();
            if (pendingFitRequest && mapElementHasUsableSize()) {
              const request = pendingFitRequest;
              window.fitWeatherData(request.leadingPadding, request.useFitCoordinates);
            }
            setTimeout(() => {
              map.resize();
              if (pendingFitRequest && mapElementHasUsableSize()) {
                const request = pendingFitRequest;
                window.fitWeatherData(request.leadingPadding, request.useFitCoordinates);
              }
            }, 120);
          });
        }

        window.weatherMapRefreshAfterActivation = function() {
          if (!map) {
            startMapWhenReady();
            return;
          }
          resizeMapSoon();
          ensureLayers();
          if (pendingPayload) updateSource(pendingPayload);
        };

        window.weatherMapReloadBaseMapAfterActivation = async function(mode = currentStyleMode) {
          if (!map) {
            startMapWhenReady();
            return;
          }

          currentStyleMode = mode;
          document.body.classList.toggle('dark-map', mode === 'dark');
          const cameraState = {
            center: map.getCenter(),
            zoom: map.getZoom(),
            bearing: map.getBearing(),
            pitch: map.getPitch()
          };

          resizeMapSoon();
          baseStylePreferencesApplied = false;
          try {
            map.once('style.load', () => {
              loaded = true;
              resizeMapSoon();
              ensureLayers();
              if (pendingPayload) updateSource(pendingPayload);
              try {
                map.jumpTo(cameraState);
              } catch (_) {}
            });
            map.setStyle(await cleanedStyle(mode));
          } catch (error) {
            console.error('Base map reload failed', error);
            resizeMapSoon();
            ensureLayers();
            if (pendingPayload) updateSource(pendingPayload);
          }
        };

        function startPinchInertia(point) {
          if (pinchAnimationFrame) cancelAnimationFrame(pinchAnimationFrame);
          function step() {
            pinchVelocity *= 0.88;
            if (Math.abs(pinchVelocity) < 0.001) {
              pinchAnimationFrame = null;
              pinchVelocity = 0;
              return;
            }
            map.zoomTo(map.getZoom() + pinchVelocity, {
              duration: 0,
              around: map.unproject(point)
            });
            pinchAnimationFrame = requestAnimationFrame(step);
          }
          pinchAnimationFrame = requestAnimationFrame(step);
        }

        async function init() {
          if (initStarted || map) return;
          if (!mapElementHasUsableSize()) {
            setTimeout(startMapWhenReady, 80);
            return;
          }
          initStarted = true;
          applyCameraProfileClass();
          const camera = activeCameraProfile();
          map = new maplibregl.Map({
            container: 'map',
            style: await cleanedStyle(currentStyleMode),
            preserveDrawingBuffer: false,
            center: camera.initialCenter,
            zoom: camera.initialZoom,
            minZoom: 1,
            maxZoom: 12,
            attributionControl: false
          });
          map.dragRotate.disable();
          map.touchZoomRotate.disableRotation();
          map.scrollZoom.disable();
          map.getCanvas().addEventListener('wheel', event => {
            postMapGestureStart();
            event.preventDefault();
            event.stopImmediatePropagation();
            const point = new maplibregl.Point(event.offsetX, event.offsetY);
            if (event.ctrlKey) {
              const delta = -event.deltaY / 72;
              pinchVelocity = Math.max(-0.62, Math.min(0.62, delta));
              map.zoomTo(map.getZoom() + pinchVelocity, {
                duration: 0,
                around: map.unproject(point)
              });
              startPinchInertia(point);
            } else {
              stopPinchInertia();
              map.panBy([event.deltaX, event.deltaY], { duration: 0 });
            }
          }, { capture: true, passive: false });
          map.getCanvas().addEventListener('mousedown', event => {
            if (event.button !== 0) return;
            postMapGestureStart();
            leftMouseDown = {
              x: event.offsetX,
              y: event.offsetY,
              time: Date.now(),
              hoveredID: hoveredMarkerID || '',
              hoveredPoint: hoveredMarkerPoint ? { x: hoveredMarkerPoint.x, y: hoveredMarkerPoint.y } : null
            };
          }, { capture: true, passive: true });
          map.getCanvas().addEventListener('touchstart', event => {
            postMapGestureStart();
            if (event.touches.length !== 1) {
              touchDown = null;
              return;
            }
            const rect = map.getCanvas().getBoundingClientRect();
            const touch = event.touches[0];
            touchDown = {
              x: touch.clientX - rect.left,
              y: touch.clientY - rect.top,
              time: Date.now()
            };
          }, { capture: true, passive: true });
          map.getCanvas().addEventListener('touchend', event => {
            const down = touchDown;
            touchDown = null;
            if (!down || event.changedTouches.length !== 1) return;
            const rect = map.getCanvas().getBoundingClientRect();
            const touch = event.changedTouches[0];
            const point = new maplibregl.Point(touch.clientX - rect.left, touch.clientY - rect.top);
            const dx = point.x - down.x;
            const dy = point.y - down.y;
            const movement = Math.sqrt(dx * dx + dy * dy);
            const elapsed = Date.now() - down.time;
            if (movement > 16 || elapsed >= 800) return;
            const feature = markerFeatureAtPoint(point, markerHitRadius);
            if (!feature?.properties?.id) return;
            const markerPoint = markerScreenPoint(feature, point);
            suppressNextClickUntil = Date.now() + 350;
            post({ type: 'markerTap', id: feature.properties.id, x: markerPoint.x, y: markerPoint.y, tapX: point.x, tapY: point.y });
            event.preventDefault();
            event.stopImmediatePropagation();
          }, { capture: true, passive: false });
          map.getCanvas().addEventListener('mouseup', event => {
            if (event.button !== 0) return;
            const point = new maplibregl.Point(event.offsetX, event.offsetY);
            const down = leftMouseDown;
            leftMouseDown = null;
            if (!down) return;
            const dx = event.offsetX - down.x;
            const dy = event.offsetY - down.y;
            const movement = Math.sqrt(dx * dx + dy * dy);
            const elapsed = Date.now() - down.time;
            if (movement <= 12 && elapsed < 1000) {
              const feature = markerFeatureAtPoint(point, markerHitRadius);
              if (feature?.properties?.id) {
                const markerPoint = markerScreenPoint(feature, point);
                post({ type: 'markerTap', id: feature.properties.id, x: markerPoint.x, y: markerPoint.y, tapX: point.x, tapY: point.y });
                event.preventDefault();
                event.stopImmediatePropagation();
              }
            }
          }, { capture: true, passive: false });
          map.on('load', () => {
            loaded = true;
            resizeMapSoon();
            ensureLayers();
            if (pendingPayload) updateSource(pendingPayload);
            post({ type: 'ready' });
          });
          map.on('styledata', () => {
            if (!loaded) return;
            resizeMapSoon();
            ensureLayers();
            if (pendingPayload) updateSource(pendingPayload);
          });
          map.on('click', event => {
            if (Date.now() < suppressNextClickUntil) return;
            if (event.originalEvent?._weatherMarkerHandled) return;
            const feature = markerFeatureAtPoint(event.point);
            if (feature?.properties?.id) {
              event.originalEvent._weatherMarkerHandled = true;
              const markerPoint = markerScreenPoint(feature, event.point);
              post({ type: 'markerTap', id: feature.properties.id, x: markerPoint.x, y: markerPoint.y, tapX: event.point.x, tapY: event.point.y });
            } else {
              const lngLat = event.lngLat;
              post({ type: 'mapBackgroundClick', lat: lngLat.lat, lng: lngLat.lng, x: event.point.x, y: event.point.y });
            }
          });
          map.on('click', 'weather-hit', event => {
            if (Date.now() < suppressNextClickUntil) return;
            const feature = nearestMarkerFeature(event.features, event.point);
            if (!feature?.properties?.id) return;
            event.originalEvent._weatherMarkerHandled = true;
            const markerPoint = markerScreenPoint(feature, event.point);
            post({ type: 'markerTap', id: feature.properties.id, x: markerPoint.x, y: markerPoint.y, tapX: event.point.x, tapY: event.point.y });
          });
          map.on('contextmenu', event => {
            event.preventDefault();
          });
          map.on('mousemove', 'weather-hit', event => {
            if (pendingPayload?.allowsMarkerHover === false) return;
            const feature = nearestMarkerFeature(event.features, event.point);
            if (!feature?.properties?.id) return;
            commandPressed = !!event.originalEvent?.metaKey;
            const markerPoint = markerScreenPoint(feature, event.point);
            refreshHoveredMarker(feature.properties.id, markerPoint);
            updateCommandHoverCard();
          });
          map.on('mouseenter', 'weather-hit', () => { map.getCanvas().style.cursor = 'default'; });
          map.on('mouseleave', 'weather-hit', () => {
            map.getCanvas().style.cursor = 'default';
            clearHoveredMarker();
          });
          window.addEventListener('resize', resizeMapSoon);
          if (window.ResizeObserver) {
            mapResizeObserver = new ResizeObserver(resizeMapSoon);
            mapResizeObserver.observe(document.getElementById('map'));
          }

          map.on('move', () => {
            updateHoveredMarkerPosition();
            const now = Date.now();
            if (now - lastMovePost < 120) return;
            lastMovePost = now;
            const center = map.getCenter();
            post({ type: 'cameraMove', lat: center.lat, lng: center.lng });
          });
          const pressedPanKeys = new Set();
          const pressedZoomKeys = new Set();
          let panAnimationFrame = null;

          function panLoop() {
            if (!pressedPanKeys.size && !pressedZoomKeys.size) {
              panAnimationFrame = null;
              return;
            }
            let x = 0;
            let y = 0;
            const step = 12;
            if (pressedPanKeys.has('w')) y -= step;
            if (pressedPanKeys.has('a')) x -= step;
            if (pressedPanKeys.has('s')) y += step;
            if (pressedPanKeys.has('d')) x += step;
            if (x !== 0 || y !== 0) map.panBy([x, y], { duration: 0 });
            if (pressedZoomKeys.has('c')) map.zoomTo(map.getZoom() + 0.035, { duration: 0 });
            if (pressedZoomKeys.has('v')) map.zoomTo(map.getZoom() - 0.035, { duration: 0 });
            panAnimationFrame = requestAnimationFrame(panLoop);
          }

          function startPanLoop() {
            if (!panAnimationFrame) panAnimationFrame = requestAnimationFrame(panLoop);
          }

          window.addEventListener('keydown', event => {
            const key = event.key.toLowerCase();
            if (event.metaKey || key === 'meta') {
              commandPressed = true;
              updateCommandHoverCard();
            }
            if (event.metaKey && (key === '+' || key === '=')) {
              event.preventDefault();
              window.weatherMapZoomIn();
              return;
            }
            if (event.metaKey && key === '-') {
              event.preventDefault();
              window.weatherMapZoomOut();
              return;
            }
            if (event.metaKey || event.ctrlKey || event.altKey) return;

            if (['w', 'a', 's', 'd'].includes(key)) {
              event.preventDefault();
              pressedPanKeys.add(key);
              startPanLoop();
            }
            if (['c', 'v'].includes(key)) {
              event.preventDefault();
              pressedZoomKeys.add(key);
              startPanLoop();
            }
          });
          window.addEventListener('keyup', event => {
            const key = event.key.toLowerCase();
            if (!event.metaKey || key === 'meta') {
              commandPressed = false;
              endCommandHoverCard();
            }
            pressedPanKeys.delete(key);
            pressedZoomKeys.delete(key);
          });
          window.addEventListener('blur', () => {
            pressedPanKeys.clear();
            pressedZoomKeys.clear();
            commandPressed = false;
            endCommandHoverCard();
          });
        }

        function startMapWhenReady(attempt = 0) {
          if (window.maplibregl) {
            init().catch(error => {
              initStarted = false;
              console.error('Map init failed', error);
              if (attempt < 12) setTimeout(() => startMapWhenReady(attempt + 1), 250);
            });
            return;
          }
          if (attempt < 24) setTimeout(() => startMapWhenReady(attempt + 1), 250);
        }

        startMapWhenReady();
      </script>
    </body>
    </html>
    """
}

enum MapCameraProfile: String {
    case desktop
    case tablet
    case mobile
}

private struct MapLibreWeatherFeature: Codable {
    let id: String
    let name: String
    let country: String
    let latitude: Double
    let longitude: Double
    let label: String
    let color: String
    let hidden: Bool
}

private struct MapLibreFitCoordinate: Codable {
    let latitude: Double
    let longitude: Double
}
