//
//  MapView.swift
//  Weather
//
//  Purpose: Composes the weather map screen: map controls, marker selection,
//  camera fitting, and country-search preview controls.
//

import SwiftUI
import CoreLocation

enum MapRecenterRequest: Equatable {
    case weatherCities
    case listCoordinates
}

// MARK: - Map Controls and Interactions

extension ContentView {
    @ViewBuilder
    var mapDateSliderOverlay: some View {
        // Date slider only on map view. Discover/list use the bottom date switcher.
        if isMapRoute, showDateSlider, !showingInlineSearch, !countryListSearchMode {
            mapDateSlider(height: 420)
                .frame(width: 145, height: 420, alignment: .trailing)
                .padding(.bottom, 420)
                .padding(.trailing, 1)
                .transition(.opacity)
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
        }
    }

    // MARK: Marker Selection

    func handleMapMarkerTap(_ city: CityWeather, anchor: CGPoint? = nil) {
        if showingInlineSearch || inlineSearchFieldPresented {
            showingInlineSearch = false
            inlineSearchFieldPresented = false
            resetNativeCitySearch()
        }

        if showingMapExpandedCard, tappedCity?.id == city.id {
            return
        }
        PlatformFeedback.lightImpact()
        showMapMarkerCard(city, anchor: anchor, expanded: false, focusesMarker: true)
    }

    func handleMapBackgroundClick(_ coordinate: CLLocationCoordinate2D, anchor: CGPoint? = nil) {
        dismissMapExpandedCard()
    }

    func dismissMapExpandedCard() {
        let shouldRecenterAfterDismiss = previewCity != nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingMapExpandedCard = false
            tappedCity = nil
            previewCity = nil
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
        if previewCity?.id == city.id {
            previewCity = nil
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
                selectedCityID: mapFocusSelectedMarker ? tappedCity?.id : nil,
                recenterRequest: $mapRecenterRequest,
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
        .onChange(of: countryListSearchMode) { oldValue, newValue in
            guard oldValue, !newValue else { return }
            DispatchQueue.main.async {
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

    // MARK: Country Search Preview

    @ViewBuilder
    func countryListPreviewControls(showsInlineActions: Bool = true, usesPhoneCardFrame: Bool = false) -> some View {
        if countryListSearchMode, let country = countryListPreviewCountry {
            let cityCountRange = countryListCityCountRange(for: country)
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(country.name)
                            .font(.headline)
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)
                        Text(localizedString("Preview Largest Cities", locale: locale))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.colors.secondaryText)
                    }

                    Spacer(minLength: 12)

                    Text("\(countryListPreviewCityCount)")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(theme.colors.primaryText)
                }

                Text(String(format: localizedString("Choose how many major cities to include.", locale: locale)))
                    .font(.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

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

                        countryAddMenu(for: country, cityCount: countryListPreviewCityCount)
                    }
                }
            }
            .padding(.horizontal, usesPhoneCardFrame ? 22 : 16)
            .padding(.vertical, usesPhoneCardFrame ? 16 : 16)
            .frame(maxWidth: .infinity)
            .frame(height: usesPhoneCardFrame ? floatingMapCardHeight : nil)
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
        Task { @MainActor in
            await Task.yield()
            centerMapOnDots(useListCoordinates: true)
        }
    }

    // MARK: Map Presentation Flags

    var mapFocusSelectedMarker: Bool {
        showingMapExpandedCard
    }

    var shouldHideInlineMapCardCityName: Bool {
        false
    }

    var shouldAddInlineMapCardVerticalPadding: Bool {
        true
    }

    func cityIsInActiveList(_ cityWeather: CityWeather) -> Bool {
        weatherService.cityWeatherData.contains(where: { $0.city.name == cityWeather.city.name && $0.city.country == cityWeather.city.country })
    }

    func addCityToActiveList(_ cityWeather: CityWeather) async {
        await weatherService.addCity(cityWeather.city)
        PlatformFeedback.lightImpact()
        if let newCity = weatherService.cityWeatherData.first(where: { $0.city.name == cityWeather.city.name && $0.city.country == cityWeather.city.country }) {
            tappedCity = newCity
        }
    }
}

// MARK: - Overlay Menu
extension ContentView {
    var mapOverlayOptions: [(mode: String, icon: String, label: String)] {
        [
            ("weather",       "cloud.sun.fill",     localizedString("Weather", locale: locale)),
            ("temperature",   "thermometer.medium", localizedString("Temperature", locale: locale)),
            ("cloudCover",    "cloud.fill",         localizedString("Cloud Cover", locale: locale)),
            ("precipitation", "drop.fill",          localizedString("Precipitation", locale: locale)),
            ("windSpeed",     "wind",               localizedString("Wind Speed", locale: locale)),
            ("uvIndex",       "sun.max.fill",       localizedString("UV Index", locale: locale)),
            ("humidity",      "humidity.fill",      localizedString("Humidity", locale: locale)),
            ("visibility",    "eye.fill",           localizedString("Visibility", locale: locale))
        ]
    }

    var mapOverlayMenu: some View {
        Menu {
            ForEach(mapOverlayOptions, id: \.mode) { option in
                Button {
                    PlatformFeedback.lightImpact()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mapOverlayMode = option.mode
                    }
                } label: {
                    Label {
                        Text(option.label)
                    } icon: {
                        Image(systemName: mapOverlayMode == option.mode ? "checkmark" : option.icon)
                            .foregroundStyle(.primary)
                    }
                }
            }
        } label: {
            Image(systemName: "square.3.layers.3d")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
                .foregroundColor(.primary)
        }
        .tint(.primary)
        .menuOrder(.fixed)
    }
}
