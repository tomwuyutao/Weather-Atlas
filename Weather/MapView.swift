//
//  MapView.swift
//  Weather
//
//  Shared map composition and map interaction handling.
//

import SwiftUI
import CoreLocation
import MapKit

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
            Color.clear
                .frame(width: 80, height: 500)
                .contentShape(Rectangle())
                .overlay(alignment: .trailing) {
                    mapDateSlider(height: 420)
                }
                .padding(.bottom, 380)
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

    var iOSMapControlsCapsule: some View {
        HStack(spacing: 8) {
            Button {
                PlatformFeedback.lightImpact()
                recenterOnAllCities = false
                DispatchQueue.main.async {
                    recenterOnAllCities = true
                }
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
            let mapItems: [MKMapItem]
            if let request = MKReverseGeocodingRequest(location: location) {
                mapItems = (try? await request.mapItems) ?? []
            } else {
                mapItems = []
            }
            let mapItem = mapItems.first
            let address = mapItem?.addressRepresentations
            let name = address?.cityName
                ?? mapItem?.name
                ?? address?.regionName
                ?? String(format: "%.2f, %.2f", coordinate.latitude, coordinate.longitude)
            let country = address?.regionName ?? ""
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
                selectedDayOffset: selectedDayOffset,
                overlayMode: mapOverlayMode,
                filterSunny: filterSunny,
                tappedCity: $tappedCity,
                recenterOnAllCities: $recenterOnAllCities,
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

            if weatherService.isLoading {
                GeometryReader { geo in
                    VStack(spacing: 12) {
                        Image(systemName: "cloud.sun.fill")
                            #if os(macOS)
                            .font(.system(size: 28, weight: .medium))
                            #else
                            .font(.system(size: 40, weight: .medium))
                            #endif
                            .weatherIconStyle(for: "cloud.sun.fill")
                        Text(localizedString("Loading Weather", locale: locale))
                            #if os(macOS)
                            .font(.headline.weight(.semibold))
                            #else
                            .font(.avenir(.title3, weight: .semibold))
                            #endif
                        Capsule()
                            .fill(theme.colors.primaryText.opacity(0.15))
                            .frame(width: 118, height: 3)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(theme.colors.accent)
                                    .frame(width: 118 * weatherService.loadingProgress, height: 3)
                            }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .background(
                        (colorScheme == .dark
                         ? Color(red: 0.08, green: 0.08, blue: 0.12).opacity(0.48)
                         : Color.white.opacity(0.62)),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.16), radius: 22, x: 0, y: 10)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .allowsHitTesting(false)
            }

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
