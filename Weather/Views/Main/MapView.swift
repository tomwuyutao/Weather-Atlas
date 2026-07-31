//
//  MapView.swift
//  Weather
//
//  Purpose: Presents the place-owned library in a dedicated immersive map tab
//  while preserving Weather Atlas's compact weather-dot visual language.
//

import CoreLocation
import MapKit
import SwiftUI
import UIKit
import WeatherKit

struct MapView: View {
    let placesStore: PlacesStore
    let weatherStore: PlaceWeatherStore

    @Bindable var router: AppRouter
    @Binding var selectedDate: Date

    @State private var sortMode: WeatherMetricMode = .sunny
    @State private var filtersToSunnyPlaces = false
    @State private var fitRequestID = 0
    @State private var presentedError: MapUIError?
    @AppStorage("showLegend") private var showsLegend = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    private var selectedCollection: PlaceCollection? {
        guard let collectionID = router.selectedCollectionID else {
            return nil
        }
        return placesStore.collections.first { $0.id == collectionID }
    }

    private var collectionPlaces: [SavedPlace] {
        placesStore.places(in: router.selectedCollectionID)
    }

    private var presentations: [SavedPlacePresentation] {
        collectionPlaces.map { place in
            let weather = weatherStore.weather(for: place.id)
            return SavedPlacePresentation(
                place: place,
                recommendation: weather.flatMap {
                    RecommendationEngine.recommendation(
                        for: $0,
                        on: selectedDate,
                        source: .saved
                    )
                },
                isLoading: weatherStore.isLoading(place.id),
                failureMessage:
                    weatherStore.failuresByPlaceID[place.id]?.message
            )
        }
    }

    private var sortedPresentations: [SavedPlacePresentation] {
        let orderedRecommendations = RecommendationEngine.sorted(
            presentations.compactMap(\.recommendation),
            by: sortMode,
            locale: locale
        )
        let presentationsByID = Dictionary(
            uniqueKeysWithValues: presentations.map { ($0.id, $0) }
        )
        let ordered = orderedRecommendations.compactMap {
            presentationsByID[$0.id]
        }
        let unavailable = presentations
            .filter { $0.recommendation == nil }
            .sorted {
                displayName(for: $0.place).localizedStandardCompare(
                    displayName(for: $1.place)
                ) == .orderedAscending
            }
        return ordered + unavailable
    }

    private var forecastDates: [Date] {
        let weather = collectionPlaces.compactMap {
            weatherStore.weather(for: $0.id)
        }
        let availableDates = RecommendationEngine.availableDates(in: weather)
        let baseDates: [Date]
        if availableDates.isEmpty {
            let today = calendar.startOfDay(for: Date())
            baseDates = (0..<10).compactMap {
                calendar.date(byAdding: .day, value: $0, to: today)
            }
        } else {
            baseDates = availableDates
        }

        let normalizedSelection = calendar.startOfDay(for: selectedDate)
        return Array(Set(baseDates + [normalizedSelection])).sorted()
    }

    private var weatherLoadID: [City.ID] {
        collectionPlaces.map(\.id)
    }

    private var navigationTitle: String {
        selectedCollection?.name ?? localizedString("Map", locale: locale)
    }

    var body: some View {
        mapBody
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleMenu {
                collectionTitleMenu
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    layerMenu
                    sunnyFilterButton
                    legendButton
                    fitButton
                }
            }
            .task(id: weatherLoadID) {
                await weatherStore.load(
                    cities: collectionPlaces.map(\.city),
                    locale: locale
                )
            }
            .onChange(
                of: router.selectedCollectionID,
                initial: true
            ) {
                _,
                collectionID in
                guard placesStore.selectedCollectionID != collectionID else {
                    return
                }
                persistCollectionSelection(collectionID)
            }
            .onChange(of: placesStore.collections.map(\.id)) {
                validateCollectionSelection()
            }
            .sensoryFeedback(
                .selection,
                trigger: filtersToSunnyPlaces
            )
            .sensoryFeedback(.selection, trigger: showsLegend)
            .alert(
                "Unable to Update Places",
                isPresented: errorIsPresented,
                presenting: presentedError
            ) { _ in
                Button("OK") {
                    presentedError = nil
                }
            } message: { error in
                Text(error.message)
            }
    }

    @ViewBuilder
    private var mapBody: some View {
        if let loadErrorDescription = placesStore.loadErrorDescription {
            ContentUnavailableView {
                Label("Places Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadErrorDescription)
            } actions: {
            Button("Try Again", action: placesStore.retryLoading)
                .buttonStyle(.borderedProminent)
            }
            .weatherAtlasScreenBackground()
        } else {
            PlacesMapCanvas(
                presentations: sortedPresentations,
                selectedPlaceID: $router.selectedMapPlaceID,
                showsLegend: $showsLegend,
                filtersToSunnyPlaces: $filtersToSunnyPlaces,
                selectedDate: selectedDate,
                sortMode: sortMode,
                fitRequestID: fitRequestID,
                displayName: displayName(for:),
                weatherAttribution: weatherStore.weatherAttribution,
                addPlace: {
                    router.presentedSheet = .addPlace(
                        collectionID: router.selectedCollectionID
                    )
                }
            )
            .overlay(alignment: .top) {
                floatingDateStrip
            }
        }
    }

    private var floatingDateStrip: some View {
        ForecastDateStrip(
            selection: $selectedDate,
            availableDates: forecastDates
        )
        .padding(.vertical, 6)
        .mapFloatingSurface(
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var collectionTitleMenu: some View {
        Button {
            selectCollection(nil)
        } label: {
            if router.selectedCollectionID == nil {
                Label("All Places", systemImage: "checkmark")
            } else {
                Text("All Places")
            }
        }

        if !placesStore.collections.isEmpty {
            Section("Collections") {
                ForEach(placesStore.collections) { collection in
                    Button {
                        selectCollection(collection.id)
                    } label: {
                        if router.selectedCollectionID == collection.id {
                            Label(
                                collection.name,
                                systemImage: "checkmark"
                            )
                        } else {
                            Text(collection.name)
                        }
                    }
                }
            }
        }

        Divider()

        Button {
            router.presentedSheet = .createCollection(placeID: nil)
        } label: {
            Label("New Collection", systemImage: "folder.badge.plus")
        }

        Button {
            router.mapPath.append(.collections)
        } label: {
            Label("Manage Collections", systemImage: "folder")
        }
    }

    private var layerMenu: some View {
        Menu {
            Picker("Map Data", selection: $sortMode) {
                ForEach(WeatherMetricMode.allCases) { mode in
                    Label(
                        mode.title(locale: locale),
                        systemImage: mode.icon
                    )
                    .tag(mode)
                }
            }

            Divider()

            Button {
                Task {
                    await weatherStore.load(
                        cities: collectionPlaces.map(\.city),
                        forceRefresh: true,
                        locale: locale
                    )
                }
            } label: {
                Label("Refresh Forecasts", systemImage: "arrow.clockwise")
            }
        } label: {
            Label("Map Data", systemImage: "square.3.layers.3d")
        }
        .accessibilityHint(
            localizedString(
                "Changes the map metric or refreshes forecasts.",
                locale: locale
            )
        )
    }

    private var sunnyFilterButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
                filtersToSunnyPlaces.toggle()
            }
        } label: {
            Label(
                "Filter Sunny",
                systemImage: filtersToSunnyPlaces
                    ? "sun.max.fill"
                    : "sun.max"
            )
            .labelStyle(.iconOnly)
            .foregroundStyle(
                filtersToSunnyPlaces
                    ? theme.colors.filterSunny
                    : theme.colors.primaryText
            )
        }
        .tint(
            filtersToSunnyPlaces
                ? theme.colors.filterSunny
                : theme.colors.accent
        )
        .accessibilityAddTraits(
            filtersToSunnyPlaces ? .isSelected : []
        )
    }

    private var legendButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
                showsLegend.toggle()
            }
        } label: {
            Label(
                "Legend",
                systemImage: showsLegend ? "eye.fill" : "eye.slash"
            )
            .labelStyle(.iconOnly)
        }
        .accessibilityAddTraits(showsLegend ? .isSelected : [])
    }

    private var fitButton: some View {
        Button {
            fitRequestID &+= 1
        } label: {
            Label(
                "Fit Visible Places",
                systemImage:
                    "arrow.up.left.and.down.right.magnifyingglass"
            )
            .labelStyle(.iconOnly)
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { presentedError != nil },
            set: { isPresented in
                if !isPresented {
                    presentedError = nil
                }
            }
        )
    }

    private func displayName(for place: SavedPlace) -> String {
        place.customName ?? place.city.localizedName(locale: locale)
    }

    private func selectCollection(
        _ collectionID: PlaceCollection.ID?
    ) {
        do {
            try placesStore.selectCollection(id: collectionID)
            router.selectedCollectionID = collectionID
            router.selectedMapPlaceID = nil
        } catch {
            present(error)
        }
    }

    private func persistCollectionSelection(
        _ collectionID: PlaceCollection.ID?
    ) {
        do {
            try placesStore.selectCollection(id: collectionID)
            router.selectedMapPlaceID = nil
        } catch {
            router.selectedCollectionID = placesStore.selectedCollectionID
            present(error)
        }
    }

    private func validateCollectionSelection() {
        guard let collectionID = router.selectedCollectionID,
              !placesStore.collections.contains(where: {
                  $0.id == collectionID
              }) else {
            return
        }
        selectCollection(nil)
    }

    private func present(_ error: Error) {
        presentedError = MapUIError(
            message: localizedPlacesErrorDescription(
                error,
                locale: locale
            )
        )
    }
}

private struct MapUIError: Identifiable {
    let id = UUID()
    let message: String
}

private struct PlacesMapCanvas: View {
    let presentations: [SavedPlacePresentation]
    @Binding var selectedPlaceID: SavedPlace.ID?
    @Binding var showsLegend: Bool
    @Binding var filtersToSunnyPlaces: Bool
    let selectedDate: Date
    let sortMode: WeatherMetricMode
    let fitRequestID: Int
    let displayName: (SavedPlace) -> String
    let weatherAttribution: WeatherAttribution?
    let addPlace: () -> Void

    @State private var position: MapCameraPosition = .automatic
    @State private var hasInitializedCamera = false

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit")
    private var distanceUnitRaw = DistanceUnit.defaultRawValue

    private var layerPresentations: [SavedPlacePresentation] {
        presentations.filter(hasValidActiveLayerData)
    }

    private var visiblePresentations: [SavedPlacePresentation] {
        mapMarkers.map(\.presentation)
    }

    private var mapMarkers: [PlacesMapMarkerPresentation] {
        let candidates = filtersToSunnyPlaces
            ? layerPresentations.filter {
                $0.recommendation?.condition.isSunny == true
            }
            : layerPresentations

        return candidates.compactMap { presentation in
            guard let color = markerColor(for: presentation) else {
                return nil
            }
            return PlacesMapMarkerPresentation(
                presentation: presentation,
                color: color
            )
        }
    }

    private var selectedPresentation: SavedPlacePresentation? {
        guard let selectedPlaceID else { return nil }
        return visiblePresentations.first { $0.id == selectedPlaceID }
    }

    private var visiblePlaceIDs: [SavedPlace.ID] {
        visiblePresentations
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mapContent

            if visiblePresentations.isEmpty {
                emptyMapState
                    .zIndex(1)
            }

            if let selectedPresentation {
                MapPlaceSelectionCard(
                    presentation: selectedPresentation,
                    displayName: displayName(selectedPresentation.place),
                    selectedDate: selectedDate,
                    sortMode: sortMode,
                    clearSelection: clearSelection
                )
                .padding(
                    .horizontal,
                    dynamicTypeSize.isAccessibilitySize ? 12 : 18
                )
                .padding(.bottom, weatherAttribution == nil ? 18 : 52)
                .frame(maxWidth: cardMaximumWidth)
                .transition(cardTransition)
                .zIndex(2)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let weatherAttribution, !visiblePresentations.isEmpty {
                WeatherAttributionView(attribution: weatherAttribution)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
            }
        }
        .onChange(of: visiblePlaceIDs, initial: true) { _, newIDs in
            if let selectedPlaceID, !newIDs.contains(selectedPlaceID) {
                self.selectedPlaceID = nil
            }

            if hasInitializedCamera {
                fitAllVisiblePlaces()
            } else {
                initializeCamera()
                hasInitializedCamera = true
            }
        }
        .onChange(of: fitRequestID) {
            fitAllVisiblePlaces()
        }
        .animation(
            reduceMotion
                ? nil
                : .spring(response: 0.35, dampingFraction: 0.85),
            value: selectedPlaceID
        )
        .sensoryFeedback(.selection, trigger: selectedPlaceID)
    }

    private var mapContent: some View {
        Map(position: $position, selection: $selectedPlaceID) {
            ForEach(mapMarkers) { marker in
                Annotation(
                    "",
                    coordinate: CLLocationCoordinate2D(
                        latitude: marker.presentation.place.city.latitude,
                        longitude: marker.presentation.place.city.longitude
                    ),
                    anchor: .center
                ) {
                    Button {
                        withAnimation(
                            reduceMotion
                                ? nil
                                : .smooth(duration: 0.22)
                        ) {
                            selectedPlaceID = marker.id
                        }
                    } label: {
                        PlacesWeatherMapAnnotation(
                            name: displayName(marker.presentation.place),
                            color: marker.color,
                            isSelected: selectedPlaceID == marker.id,
                            differentiatingText:
                                markerDifferentiatingText(
                                    for: marker.presentation
                                ),
                            differentiatingSymbol:
                                markerDifferentiatingSymbol(
                                    for: marker.presentation
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        displayName(marker.presentation.place)
                    )
                    .accessibilityValue(
                        markerAccessibilityValue(
                            for: marker.presentation
                        )
                    )
                    .accessibilityAddTraits(
                        selectedPlaceID == marker.id
                            ? .isSelected
                            : []
                    )
                }
                .tag(marker.id)
            }
        }
        .mapStyle(
            .standard(
                elevation: .flat,
                emphasis: .muted,
                pointsOfInterest: .excludingAll,
                showsTraffic: false
            )
        )
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .overlay(alignment: .topLeading) {
            if showsLegend,
               selectedPresentation == nil,
               !visiblePresentations.isEmpty {
                PlacesMapLegend(sortMode: sortMode) {
                    withAnimation(
                        reduceMotion ? nil : .smooth(duration: 0.2)
                    ) {
                        showsLegend = false
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, legendTopPadding)
                .transition(legendTransition)
            }
        }
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.22),
            value: showsLegend
        )
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.22),
            value: selectedPlaceID
        )
    }

    private func clearSelection() {
        withAnimation(
            reduceMotion
                ? nil
                : .spring(response: 0.35, dampingFraction: 0.85)
        ) {
            selectedPlaceID = nil
        }
    }

    private func initializeCamera() {
        if let selectedPlaceID,
           let selected = visiblePresentations.first(where: {
               $0.id == selectedPlaceID
           }) {
            position = .region(
                PlacesMapRegionFitting.region(
                    centeredOn: selected.place.city,
                    span: 0.35
                )
            )
        } else {
            fitAllVisiblePlaces()
        }
    }

    private func fitAllVisiblePlaces() {
        guard !visiblePresentations.isEmpty else {
            position = .automatic
            return
        }

        let cities = visiblePresentations.map(\.place.city)
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
            position = .region(PlacesMapRegionFitting.region(for: cities))
        }
    }

    private func hasValidActiveLayerData(
        _ presentation: SavedPlacePresentation
    ) -> Bool {
        guard let recommendation = presentation.recommendation else {
            return false
        }

        switch sortMode {
        case .sunny, .temperature, .cloud:
            return true
        case .feelsLike:
            return recommendation.maximumFeelsLike != nil
        case .rainChance:
            return recommendation.precipitationChance != nil
        case .visibility:
            return recommendation.maximumVisibilityKilometers != nil
        case .uvIndex:
            return recommendation.forecast.uvIndex != nil
        }
    }

    private func markerColor(
        for presentation: SavedPlacePresentation
    ) -> Color? {
        guard let recommendation = presentation.recommendation else {
            return nil
        }

        switch sortMode {
        case .sunny:
            return recommendation.condition.dotColor(for: theme.colors)
        case .temperature:
            return temperatureColor(for: recommendation.forecast.dailyHigh)
        case .feelsLike:
            guard let value = recommendation.maximumFeelsLike else {
                return nil
            }
            return temperatureColor(for: value)
        case .cloud:
            return theme.colors.dotRain.interpolated(
                with: theme.colors.dotCloudy,
                by: clamped(recommendation.cloudCover)
            )
        case .rainChance:
            guard let value = recommendation.precipitationChance else {
                return nil
            }
            return theme.colors.dotCloudy.interpolated(
                with: theme.colors.dotDrizzle,
                by: clamped(value)
            )
        case .visibility:
            guard let value = recommendation.maximumVisibilityKilometers else {
                return nil
            }
            return theme.colors.dotRain.interpolated(
                with: theme.colors.dotSun,
                by: clamped(value / 30)
            )
        case .uvIndex:
            guard let value = recommendation.forecast.uvIndex else {
                return nil
            }
            return theme.colors.dotCloudy.interpolated(
                with: theme.colors.destructive,
                by: clamped(Double(value) / 11)
            )
        }
    }

    @ViewBuilder
    private var emptyMapState: some View {
        if presentations.isEmpty {
            ContentUnavailableView {
                Label("No Saved Places", systemImage: "mappin.slash")
            } description: {
                Text(
                    "Save cities you care about. You can organize them into optional collections later."
                )
            } actions: {
                Button("Add Place", systemImage: "plus", action: addPlace)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
        } else if presentations.contains(where: \.isLoading),
           layerPresentations.isEmpty {
            ProgressView("Loading Forecasts")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial)
        } else if filtersToSunnyPlaces {
            ContentUnavailableView {
                Label("No Sun", systemImage: "sun.max")
            } description: {
                Text("No sunny places for this date.")
            } actions: {
                Button("Show All Cities") {
                    withAnimation(
                        reduceMotion ? nil : .smooth(duration: 0.2)
                    ) {
                        filtersToSunnyPlaces = false
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
        } else {
            ContentUnavailableView {
                Label(
                    "Forecast Unavailable",
                    systemImage: "cloud.slash"
                )
            } description: {
                Text("No forecast for the selected date.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
        }
    }

    private var cardMaximumWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 390 : 580
    }

    private var legendTopPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 128 : 72
    }

    private var cardTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .scale(scale: 0.4, anchor: .bottom)
            .combined(with: .opacity)
            .combined(with: .offset(y: 20))
    }

    private var legendTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .scale(scale: 0.92, anchor: .topLeading)
            .combined(with: .opacity)
    }

    private func markerDifferentiatingText(
        for presentation: SavedPlacePresentation
    ) -> String? {
        guard let recommendation = presentation.recommendation else {
            return nil
        }

        switch sortMode {
        case .sunny:
            return nil
        case .temperature:
            return temperatureUnit.display(
                recommendation.forecast.dailyHigh
            )
        case .feelsLike:
            return recommendation.maximumFeelsLike.map(
                temperatureUnit.display
            )
        case .cloud:
            return percentage(recommendation.cloudCover)
        case .rainChance:
            return recommendation.precipitationChance.map(percentage)
        case .visibility:
            return recommendation.maximumVisibilityKilometers.map(
                distanceUnit.display
            )
        case .uvIndex:
            return recommendation.forecast.uvIndex.map(String.init)
        }
    }

    private func markerDifferentiatingSymbol(
        for presentation: SavedPlacePresentation
    ) -> String? {
        guard sortMode == .sunny else { return nil }
        return presentation.recommendation?.condition.displayIcon
            ?? "exclamationmark"
    }

    private func markerAccessibilityValue(
        for presentation: SavedPlacePresentation
    ) -> String {
        guard let recommendation = presentation.recommendation else {
            return localizedString("Forecast Unavailable", locale: locale)
        }

        if sortMode == .sunny {
            return recommendation.condition.localizedDisplayName(
                locale: locale
            )
        }

        let value = markerDifferentiatingText(for: presentation) ?? "—"
        return "\(sortMode.title(locale: locale)), \(value)"
    }

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic
    }

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    private func percentage(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func temperatureColor(for celsius: Double) -> Color {
        let colors = theme.colors
        let partlySunny = colors.dotPartlyCloudy.interpolated(
            with: colors.filterSunny,
            by: 0.18
        )

        if celsius <= 0 {
            return colors.dotRain.interpolated(
                with: colors.dotDrizzle,
                by: clamped((celsius + 20) / 20)
            )
        }
        if celsius <= 10 {
            return colors.dotDrizzle.interpolated(
                with: colors.dotCloudy,
                by: clamped(celsius / 10)
            )
        }
        if celsius <= 20 {
            return colors.dotCloudy.interpolated(
                with: partlySunny,
                by: clamped((celsius - 10) / 10)
            )
        }
        return partlySunny.interpolated(
            with: colors.destructive,
            by: clamped((celsius - 20) / 20)
        )
    }

    private func clamped(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}

private struct PlacesMapMarkerPresentation: Identifiable {
    let presentation: SavedPlacePresentation
    let color: Color

    var id: SavedPlace.ID { presentation.id }
}

private struct PlacesWeatherMapAnnotation: View {
    let name: String
    let color: Color
    let isSelected: Bool
    let differentiatingText: String?
    let differentiatingSymbol: String?

    @Environment(\.appTheme) private var theme

    var body: some View {
        PlacesWeatherMapDot(
            color: color,
            isSelected: isSelected,
            differentiatingText: differentiatingText,
            differentiatingSymbol: differentiatingSymbol
        )
        .overlay(alignment: .bottom) {
            Text(name)
                .font(.caption2.weight(.medium))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(maxWidth: 104)
                .background(
                    theme.colors.glassFill.opacity(0.9),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            theme.colors.primaryText.opacity(0.16),
                            lineWidth: 0.6
                        )
                }
                .fixedSize(horizontal: true, vertical: false)
                .offset(y: 15)
                .allowsHitTesting(false)
        }
        .frame(width: 104, height: 44)
        .contentShape(Rectangle())
    }
}

private struct PlacesWeatherMapDot: View {
    let color: Color
    let isSelected: Bool
    let differentiatingText: String?
    let differentiatingSymbol: String?

    @State private var glowPulse = false
    @Environment(\.accessibilityDifferentiateWithoutColor)
    private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var markerScale: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 1.25 : 1
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(isSelected ? 0.34 : 0.22))
                .frame(
                    width: isSelected ? 28 : 18,
                    height: isSelected ? 28 : 18
                )
                .blur(radius: isSelected ? 8 : 5)
                .scaleEffect(isSelected && glowPulse ? 1.18 : 1)
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: 1.15)
                            .repeatForever(autoreverses: true),
                    value: glowPulse
                )

            if isSelected && !differentiateWithoutColor {
                PlacesMapSelectedPulseRing(color: color)
            }

            if differentiateWithoutColor {
                differentiatingContent
                    .foregroundStyle(theme.colors.primaryText)
                    .frame(minWidth: 26, maxWidth: 44, minHeight: 24)
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
                                colorSchemeContrast == .increased
                                    ? theme.colors.primaryText
                                    : color,
                                lineWidth: isSelected ? 3 : 2
                            )
                    }
            } else if colorSchemeContrast == .increased {
                Circle()
                    .fill(theme.colors.glassFill)
                    .frame(
                        width: isSelected ? 24 : 20,
                        height: isSelected ? 24 : 20
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                theme.colors.primaryText,
                                lineWidth: isSelected ? 2.5 : 2
                            )
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
        .scaleEffect(markerScale)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.22),
            value: isSelected
        )
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

    @ViewBuilder
    private var differentiatingContent: some View {
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
}

private struct PlacesMapSelectedPulseRing: View {
    let color: Color

    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .stroke(
                color.opacity(isPulsing ? 0.3 : 0.8),
                lineWidth: isPulsing ? 1.5 : 2.5
            )
            .frame(width: 22, height: 22)
            .scaleEffect(isPulsing ? 1.22 : 1)
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 1.2)
                        .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = !reduceMotion
            }
            .onChange(of: reduceMotion) { _, shouldReduceMotion in
                isPulsing = !shouldReduceMotion
            }
    }
}

private struct MapPlaceSelectionCard: View {
    let presentation: SavedPlacePresentation
    let displayName: String
    let selectedDate: Date
    let sortMode: WeatherMetricMode
    let clearSelection: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit")
    private var distanceUnitRaw = DistanceUnit.defaultRawValue

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(
                value: AppRoute.place(
                    id: presentation.id,
                    date: selectedDate
                )
            ) {
                cardContent
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: cardHeight)
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: 24,
                            style: .continuous
                        )
                    )
            }
            .buttonStyle(.plain)

            Button("Close", systemImage: "xmark", action: clearSelection)
                .labelStyle(.iconOnly)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
        }
        .mapFloatingSurface(
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var cardContent: some View {
        if let recommendation = presentation.recommendation {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    Text(metricValue(for: recommendation))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()

                    Text(displayName)
                        .font(.headline)

                    Label(
                        sortMode.title(locale: locale),
                        systemImage: recommendation.condition.displayIcon
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(metricValue(for: recommendation))
                            .font(.system(size: 32, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.74)

                        Text(
                            "\(displayName) · \(sortMode.title(locale: locale))"
                        )
                        .font(.headline.weight(.regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: recommendation.condition.displayIcon)
                        .font(.system(size: 40, weight: .medium))
                        .weatherIconStyle(
                            for: recommendation.condition.displayIcon
                        )
                        .frame(width: 56, height: 48)
                        .accessibilityHidden(true)
                }
            }
        } else {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(displayName)
                        .font(.headline)

                    Text(statusDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cardHeight: CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return 150
        }
        switch dynamicTypeSize {
        case .xSmall, .small, .medium, .large:
            return 128
        case .xLarge:
            return 138
        default:
            return 150
        }
    }

    private var statusDescription: String {
        if presentation.isLoading {
            return localizedString("Loading forecast…", locale: locale)
        }
        return presentation.failureMessage
            ?? localizedString(
                "No forecast for the selected date.",
                locale: locale
            )
    }

    private func metricValue(
        for recommendation: PlaceRecommendation
    ) -> String {
        switch sortMode {
        case .sunny:
            if let range = recommendation.bestSunnyWindow {
                let start = SunninessScoring.compactHourLabel(
                    range.lowerBound,
                    locale: locale
                )
                let end = SunninessScoring.compactHourLabel(
                    range.upperBound + 1,
                    locale: locale
                )
                return "\(start)–\(end)"
            }
            return recommendation.sunnyHourCount == 0
                ? localizedString("No Sun", locale: locale)
                : String(recommendation.sunnyHourCount)
        case .temperature:
            return temperatureUnit.display(
                recommendation.forecast.dailyHigh
            )
        case .feelsLike:
            return recommendation.maximumFeelsLike.map(
                temperatureUnit.display
            ) ?? "—"
        case .cloud:
            return percentage(recommendation.cloudCover)
        case .rainChance:
            return recommendation.precipitationChance.map(percentage) ?? "—"
        case .visibility:
            return recommendation.maximumVisibilityKilometers.map(
                distanceUnit.display
            ) ?? "—"
        case .uvIndex:
            return recommendation.forecast.uvIndex.map(String.init) ?? "—"
        }
    }

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic
    }

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    private func percentage(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private struct PlacesMapLegend: View {
    let sortMode: WeatherMetricMode
    let close: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit")
    private var distanceUnitRaw = DistanceUnit.defaultRawValue

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.vertical) {
                    legendContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.visible)
                .frame(maxHeight: 220)
            } else {
                legendContent
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .padding(.trailing, 20)
        .frame(
            width: legendWidth,
            alignment: .leading
        )
        .mapFloatingSurface(
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(alignment: .topTrailing) {
            Button("Close", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
        }
        .fixedSize(
            horizontal: !dynamicTypeSize.isAccessibilitySize,
            vertical: false
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var legendContent: some View {
        switch sortMode {
        case .sunny:
            VStack(alignment: .leading, spacing: 11) {
                legendEntry(
                    localizedString("Clear", locale: locale),
                    color: theme.colors.dotSun
                )
                legendEntry(
                    localizedString("Partly Sunny", locale: locale),
                    color: theme.colors.dotPartlyCloudy
                )
                legendEntry(
                    localizedString("Rain", locale: locale),
                    color: theme.colors.dotRain
                )
                legendEntry(
                    localizedString("Drizzle", locale: locale),
                    color: theme.colors.dotDrizzle
                )
                legendEntry(
                    localizedString(
                        "Cloudy, Windy, Snowy, Foggy",
                        locale: locale
                    ),
                    color: theme.colors.dotCloudy
                )
            }
        case .temperature, .feelsLike:
            verticalGradientLegend(
                colors: [
                    temperatureColor(for: 40),
                    temperatureColor(for: 20),
                    temperatureColor(for: 10),
                    temperatureColor(for: 0),
                    temperatureColor(for: -20)
                ],
                labels: temperatureUnit.resolved == .fahrenheit
                    ? ["104°F", "68°F", "50°F", "32°F", "-4°F"]
                    : ["40°C", "20°C", "10°C", "0°C", "-20°C"]
            )
        case .cloud:
            verticalGradientLegend(
                colors: [
                    cloudColor(1),
                    cloudColor(0.66),
                    cloudColor(0.33),
                    cloudColor(0)
                ],
                labels: ["100%", "75%", "50%", "25%", "0%"]
            )
        case .rainChance:
            verticalGradientLegend(
                colors: [
                    rainColor(1),
                    rainColor(0.66),
                    rainColor(0.33),
                    rainColor(0)
                ],
                labels: ["100%", "75%", "50%", "25%", "0%"]
            )
        case .visibility:
            verticalGradientLegend(
                colors: [
                    theme.colors.dotSun,
                    theme.colors.dotPartlyCloudy,
                    theme.colors.dotCloudy,
                    theme.colors.dotRain
                ],
                labels: [
                    distanceUnit.display(30),
                    distanceUnit.display(20),
                    distanceUnit.display(10),
                    distanceUnit.display(0)
                ]
            )
        case .uvIndex:
            verticalGradientLegend(
                colors: [
                    uvColor(1),
                    uvColor(0.82),
                    uvColor(0.55),
                    uvColor(0.27),
                    uvColor(0)
                ],
                labels: ["11+", "9", "6", "3", "0"]
            )
        }
    }

    private func legendEntry(
        _ title: String,
        color: Color
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.5), radius: 2)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(
                    horizontal: false,
                    vertical: dynamicTypeSize.isAccessibilitySize
                )
        }
    }

    private func verticalGradientLegend(
        colors: [Color],
        labels: [String]
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            LinearGradient(
                colors: colors,
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 10, height: gradientHeight)
            .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) {
                    index,
                    label in
                    Text(label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(theme.colors.secondaryText)
                    if index < labels.count - 1 {
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(height: gradientHeight)
        }
    }

    private var legendWidth: CGFloat? {
        if dynamicTypeSize.isAccessibilitySize {
            return 260
        }
        return sortMode == .sunny ? nil : 118
    }

    private var gradientHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 200 : 132
    }

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic
    }

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    private func temperatureColor(for celsius: Double) -> Color {
        let colors = theme.colors
        let partlySunny = colors.dotPartlyCloudy.interpolated(
            with: colors.filterSunny,
            by: 0.18
        )
        if celsius <= 0 {
            return colors.dotRain.interpolated(
                with: colors.dotDrizzle,
                by: clamped((celsius + 20) / 20)
            )
        }
        if celsius <= 10 {
            return colors.dotDrizzle.interpolated(
                with: colors.dotCloudy,
                by: clamped(celsius / 10)
            )
        }
        if celsius <= 20 {
            return colors.dotCloudy.interpolated(
                with: partlySunny,
                by: clamped((celsius - 10) / 10)
            )
        }
        return partlySunny.interpolated(
            with: colors.destructive,
            by: clamped((celsius - 20) / 20)
        )
    }

    private func cloudColor(_ value: Double) -> Color {
        theme.colors.dotRain.interpolated(
            with: theme.colors.dotCloudy,
            by: clamped(value)
        )
    }

    private func rainColor(_ value: Double) -> Color {
        theme.colors.dotCloudy.interpolated(
            with: theme.colors.dotDrizzle,
            by: clamped(value)
        )
    }

    private func uvColor(_ value: Double) -> Color {
        theme.colors.dotCloudy.interpolated(
            with: theme.colors.destructive,
            by: clamped(value)
        )
    }

    private func clamped(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}

private struct MapFloatingSurfaceModifier<Surface: InsettableShape>:
    ViewModifier
{
    let surface: Surface

    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.appTheme) private var theme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency || colorSchemeContrast == .increased {
            content
                .background(theme.colors.glassFill, in: surface)
                .overlay {
                    surface.stroke(
                        theme.colors.primaryText.opacity(
                            colorSchemeContrast == .increased ? 0.9 : 0.18
                        ),
                        lineWidth: colorSchemeContrast == .increased ? 1 : 0.8
                    )
                }
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: surface)
                .overlay {
                    surface.stroke(
                        theme.colors.primaryText.opacity(0.14),
                        lineWidth: 0.6
                    )
                }
        } else {
            content
                .background(.ultraThinMaterial, in: surface)
                .overlay {
                    surface.stroke(
                        theme.colors.primaryText.opacity(0.14),
                        lineWidth: 0.6
                    )
                }
        }
    }
}

private extension View {
    func mapFloatingSurface<Surface: InsettableShape>(
        in surface: Surface
    ) -> some View {
        modifier(MapFloatingSurfaceModifier(surface: surface))
    }
}

private enum PlacesMapRegionFitting {
    static func region(
        centeredOn city: City,
        span: CLLocationDegrees
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: city.latitude,
                longitude: city.longitude
            ),
            span: MKCoordinateSpan(
                latitudeDelta: span,
                longitudeDelta: span
            )
        )
    }

    static func region(for cities: [City]) -> MKCoordinateRegion {
        var minimumLatitude = cities[0].latitude
        var maximumLatitude = cities[0].latitude
        for city in cities.dropFirst() {
            minimumLatitude = min(minimumLatitude, city.latitude)
            maximumLatitude = max(maximumLatitude, city.latitude)
        }

        let longitudeArc = minimumLongitudeArc(
            for: cities.map(\.longitude)
        )
        return paddedRegion(
            minimumLatitude: minimumLatitude,
            maximumLatitude: maximumLatitude,
            centerLongitude: longitudeArc.center,
            longitudeSpan: longitudeArc.span
        )
    }

    private static func minimumLongitudeArc(
        for longitudes: [CLLocationDegrees]
    ) -> (center: CLLocationDegrees, span: CLLocationDegrees) {
        guard longitudes.count > 1 else {
            return (longitudes.first ?? 0, 0)
        }

        let normalized = longitudes
            .map { $0 >= 0 ? $0 : $0 + 360 }
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
        let normalizedCenter = (arcStart + span / 2)
            .truncatingRemainder(dividingBy: 360)
        let center = normalizedCenter > 180
            ? normalizedCenter - 360
            : normalizedCenter
        return (center, span)
    }

    private static func paddedRegion(
        minimumLatitude: CLLocationDegrees,
        maximumLatitude: CLLocationDegrees,
        centerLongitude: CLLocationDegrees,
        longitudeSpan: CLLocationDegrees
    ) -> MKCoordinateRegion {
        let latitudeDelta = max(
            1.2,
            (maximumLatitude - minimumLatitude) * 1.25
        )
        let longitudeDelta = max(1.2, longitudeSpan * 1.25)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minimumLatitude + maximumLatitude) / 2,
                longitude: centerLongitude
            ),
            span: MKCoordinateSpan(
                latitudeDelta: min(160, latitudeDelta),
                longitudeDelta: min(340, longitudeDelta)
            )
        )
    }
}
