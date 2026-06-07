//
//  MapView.swift
//  Weather
//
//  Shared map composition and map interaction handling.
//

import SwiftUI
import CoreLocation

extension ContentView {
    @ViewBuilder
    var iOSDateSliderOverlay: some View {
        // Date slider only on map tab — list tab uses the date switcher capsule
        if selectedTab == 1, !showingInlineSearch, !isMapSpecialMode {
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
        centerMapOnDots(useListCoordinates: true)
        Task {
            await weatherService.refreshWeather()
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
        #if os(iOS)
        if !shouldUseIPadLayout, showingMapExpandedCard, tappedCity?.id == city.id {
            return
        }
        #endif
        showMapMarkerCard(city, anchor: anchor, expanded: false, focusesMarker: true)
    }

    func handleMapBackgroundClick(_ coordinate: CLLocationCoordinate2D, anchor: CGPoint? = nil) {
        #if os(macOS) || os(iOS)
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

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            tappedCity = city
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
            MapLibreWebMapView(
                cities: mapCities,
                fitCities: weatherService.cityListCoordinates(),
                selectedDayOffset: selectedDayOffset,
                overlayMode: mapOverlayMode,
                filterSunny: filterSunny,
                markerReloadID: mapMarkerReloadID,
                markerSizeScale: mapMarkerSizeScale,
                showsMarkerHoverLabels: mapShowsMarkerHoverLabels,
                tappedCity: $tappedCity,
                recenterOnAllCities: $recenterOnAllCities,
                recenterUsesListCoordinates: $recenterUsesListCoordinates,
                centerOnCity: centerOnCityTrigger,
                leadingFitPadding: macMapLeadingFitPadding,
                focusSelectedMarker: mapFocusSelectedMarker,
                allowsMarkerHover: mapAllowsMarkerHover,
                cameraProfile: mapCameraProfile,
                onMarkerTap: { city, point in
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
                }
            )
            .ignoresSafeArea()

        }
        .background(theme.colors.mapOcean.ignoresSafeArea())
        .ignoresSafeArea()

    }

    var macMapLeadingFitPadding: Double {
        #if os(macOS)
        macSidebarVisibility == .detailOnly ? 0 : 220
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
        false
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
        false
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
