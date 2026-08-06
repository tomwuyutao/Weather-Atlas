//
//  MapView.swift
//  Weather
//
//  Purpose: Presents saved places in one immersive map while preserving
//  Weather Atlas's compact weather-dot language.
//

import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct MapView: View {
    let model: WeatherAtlasModel

    @Bindable var router: AppRouter
    @Binding var selectedDate: Date

    @State private var sortMode: WeatherMetricMode = .sunny
    @State private var filtersToSunnyPlaces = false
    /// Drives the explicit current-location focus without re-fitting saved dots.
    @State private var currentLocationFocusRequestID = 0
    @State private var presentedError: MapUIError?
    @AppStorage("showLegend") private var showsLegend = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale

    private var placesStore: PlacesStore {
        model.placesStore
    }

    private var weatherStore: PlaceWeatherStore {
        model.weatherStore
    }

    private var savedPlaces: [SavedPlace] { placesStore.allPlaces }

    private var savedPresentations: [PlacesMapPlacePresentation] {
        savedPlaces.map { place in
            let weather = weatherStore.weather(for: place.id)
            return PlacesMapPlacePresentation(
                presentation: SavedPlacePresentation(
                    place: place,
                    recommendation: weather.flatMap {
                        RecommendationEngine.recommendation(
                            for: $0,
                            on: selectedDate
                        )
                    },
                    isLoading: weatherStore.isLoading(place.id),
                    failureMessage:
                        weatherStore.failuresByPlaceID[place.id]?.message
                )
            )
        }
    }

    private var presentations: [PlacesMapPlacePresentation] {
        savedPresentations
    }

    private var sortedPresentations: [PlacesMapPlacePresentation] {
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

    private var weatherLoadID: [City.ID] {
        mapCities
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
    }

    private var mapCities: [City] {
        savedPlaces.map(\.city)
    }

    private var navigationTitle: String {
        localizedString("Map", locale: locale)
    }

    var body: some View {
        mapBody
            .toolbarVisibility(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 4) {
                    Text(navigationTitle)
                        .font(.largeTitle.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    .layoutPriority(1)

                    Spacer(minLength: 4)

                    currentLocationButton
                        .frame(minWidth: 36, minHeight: 44)
                    moreMenu
                        .frame(minWidth: 36, minHeight: 44)
                    TopForecastDateSwitcher(
                        selection: $selectedDate,
                        availableDates: ForecastDateHorizon.dates
                    )
                }
                .font(.title3)
                .buttonStyle(.plain)
                .foregroundStyle(theme.colors.primaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .task(id: weatherLoadID) {
                await weatherStore.load(
                    cities: mapCities,
                    locale: locale
                )
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
                sortMode: sortMode,
                currentLocationCoordinate: currentLocationCoordinate,
                currentLocationFocusRequestID: currentLocationFocusRequestID,
                displayName: displayName(for:),
                searchPlaces: {
                    router.selectedTab = .search
                }
            )
        }
    }

    private var moreMenu: some View {
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

            Button {
                Task {
                    await weatherStore.load(
                        cities: mapCities,
                        forceRefresh: true,
                        locale: locale
                    )
                }
            } label: {
                Label("Refresh Forecasts", systemImage: "arrow.clockwise")
            }

            Divider()

            Toggle(isOn: $filtersToSunnyPlaces) {
                Label("Sunny Places Only", systemImage: "sun.max")
            }

            Toggle(isOn: $showsLegend) {
                Label("Show Legend", systemImage: "list.bullet.rectangle")
            }
        } label: {
            Label("More", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
        }
    }

    /// Replaces the removed fit-visible-dots action with the user's actual
    /// spatial anchor. The map marker remains visibly highlighted after focus.
    private var currentLocationButton: some View {
        Button {
            currentLocationFocusRequestID &+= 1
        } label: {
            Label("Center on Current Location", systemImage: "location.fill")
                .labelStyle(.iconOnly)
        }
        .disabled(currentLocationCoordinate == nil)
        .accessibilityHint(
            "Centers the map on your current location and highlights it."
        )
    }

    private var currentLocationCoordinate: CLLocationCoordinate2D? {
        guard let coordinate = model.locationProvider.coordinate,
              CLLocationCoordinate2DIsValid(coordinate) else {
            return nil
        }
        return coordinate
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
        place.customName ?? place.city.displayName
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

/// A single stable map item using the saved-place presentation contract shared
/// by cards and weather rows.
private struct PlacesMapPlacePresentation: Identifiable {
    let presentation: SavedPlacePresentation

    var id: City.ID { presentation.id }
    var place: SavedPlace { presentation.place }
    var recommendation: PlaceRecommendation? {
        presentation.recommendation
    }
    var isLoading: Bool { presentation.isLoading }
    var failureMessage: String? { presentation.failureMessage }
}

private struct PlacesMapCanvas: View {
    let presentations: [PlacesMapPlacePresentation]
    @Binding var selectedPlaceID: City.ID?
    @Binding var showsLegend: Bool
    @Binding var filtersToSunnyPlaces: Bool
    let sortMode: WeatherMetricMode
    let currentLocationCoordinate: CLLocationCoordinate2D?
    let currentLocationFocusRequestID: Int
    let displayName: (SavedPlace) -> String
    let searchPlaces: () -> Void

    @State private var position: MapCameraPosition = .automatic
    @State private var hasInitializedCamera = false
    @State private var highlightsCurrentLocation = false
    @State private var labelPlacements:
        [City.ID: PlacesMapLabelPlacement] = [:]

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit")
    private var distanceUnitRaw = DistanceUnit.defaultRawValue

    private var layerPresentations: [PlacesMapPlacePresentation] {
        presentations.filter(hasValidActiveLayerData)
    }

    private var visiblePresentations: [PlacesMapPlacePresentation] {
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

    private var selectedPresentation: PlacesMapPlacePresentation? {
        guard let selectedPlaceID else { return nil }
        return visiblePresentations.first { $0.id == selectedPlaceID }
    }

    private var visiblePlaceIDs: [City.ID] {
        visiblePresentations
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
    }

    private var labelLayoutInputs: [PlacesMapLabelLayoutInput] {
        mapMarkers.map { marker in
            PlacesMapLabelLayoutInput(
                id: marker.id,
                name: displayName(marker.presentation.place),
                coordinate: CLLocationCoordinate2D(
                    latitude: marker.presentation.place.city.latitude,
                    longitude: marker.presentation.place.city.longitude
                )
            )
        }
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
                    sortMode: sortMode,
                    clearSelection: clearSelection
                )
                .padding(
                    .horizontal,
                    dynamicTypeSize.isAccessibilitySize ? 12 : 18
                )
                .padding(.bottom, 18)
                .frame(maxWidth: cardMaximumWidth)
                .transition(cardTransition)
                .zIndex(2)
            }
        }
        .onChange(of: visiblePlaceIDs, initial: true) { _, newIDs in
            if let selectedPlaceID, !newIDs.contains(selectedPlaceID) {
                self.selectedPlaceID = nil
            }

            if !hasInitializedCamera {
                initializeCamera()
                hasInitializedCamera = true
            }
        }
        .onChange(of: currentLocationFocusRequestID) {
            focusCurrentLocation()
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
        MapReader { mapProxy in
            GeometryReader { geometry in
                Map(position: $position, selection: $selectedPlaceID) {
                    // MapKit's muted standard style removes most visual
                    // competition; this light semantic wash further subdues
                    // the tiles while annotations remain above the overlay.
                    MapPolygon(points: subtleBaseMapOverlayPoints)
                        .foregroundStyle(
                            theme.colors.background.opacity(0.22)
                        )
                        .stroke(.clear, lineWidth: 0)

                    ForEach(mapMarkers) { marker in
                        Annotation(
                            "",
                            coordinate: CLLocationCoordinate2D(
                                latitude:
                                    marker.presentation.place.city.latitude,
                                longitude:
                                    marker.presentation.place.city.longitude
                            ),
                            anchor: .center
                        ) {
                            PlacesWeatherMapAnnotation(
                                name: displayName(
                                    marker.presentation.place
                                ),
                                color: marker.color,
                                isSelected: selectedPlaceID == marker.id,
                                labelPlacement:
                                    labelPlacements[marker.id] ?? .below,
                                differentiatingText:
                                    markerDifferentiatingText(
                                        for: marker.presentation
                                    ),
                                differentiatingSymbol:
                                    markerDifferentiatingSymbol(
                                        for: marker.presentation
                                    ),
                                accessibilityValue: markerAccessibilityValue(
                                    for: marker.presentation
                                ),
                                select: {
                                    withAnimation(
                                        reduceMotion
                                            ? nil
                                            : .smooth(duration: 0.22)
                                    ) {
                                        selectedPlaceID = marker.id
                                    }
                                }
                            )
                        }
                        .tag(marker.id)
                    }

                    if let currentLocationCoordinate {
                        // This is intentionally separate from saved-place
                        // weather dots: it stays available under all filters
                        // and makes the location-focus action unambiguous.
                        Annotation(
                            "Current Location",
                            coordinate: currentLocationCoordinate,
                            anchor: .center
                        ) {
                            CurrentLocationMapAnnotation(
                                isHighlighted: highlightsCurrentLocation
                            )
                        }
                    }
                }
                .mapStyle(
                    // "Muted" is MapKit's subtle standard-map emphasis.
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
                                reduceMotion
                                    ? nil
                                    : .smooth(duration: 0.2)
                            ) {
                                showsLegend = false
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, legendTopPadding)
                        .transition(legendTransition)
                    }
                }
                .onMapCameraChange(frequency: .onEnd) { _ in
                    updateLabelPlacements(
                        using: mapProxy,
                        viewportSize: geometry.size
                    )
                }
                .onChange(of: labelLayoutInputs, initial: true) {
                    _,
                    _ in
                    updateLabelPlacements(
                        using: mapProxy,
                        viewportSize: geometry.size
                    )
                }
                .onChange(of: geometry.size, initial: true) {
                    _,
                    newSize in
                    updateLabelPlacements(
                        using: mapProxy,
                        viewportSize: newSize
                    )
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
        }
    }

    private func updateLabelPlacements(
        using mapProxy: MapProxy,
        viewportSize: CGSize
    ) {
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return
        }

        let projectedLabels: [PlacesMapProjectedLabel] = labelLayoutInputs
            .compactMap {
                input -> PlacesMapProjectedLabel? in
                guard let point = mapProxy.convert(
                    input.coordinate,
                    to: .local
                ) else {
                    return nil
                }

                return PlacesMapProjectedLabel(
                    input: input,
                    point: point,
                    size: estimatedLabelSize(for: input.name)
                )
            }
            .sorted {
                (lhs: PlacesMapProjectedLabel,
                 rhs: PlacesMapProjectedLabel) -> Bool in
                if lhs.point.y != rhs.point.y {
                    return lhs.point.y < rhs.point.y
                }
                if lhs.point.x != rhs.point.x {
                    return lhs.point.x < rhs.point.x
                }
                return lhs.input.id.uuidString
                    < rhs.input.id.uuidString
            }

        let viewportBounds = CGRect(
            origin: .zero,
            size: viewportSize
        )
        .insetBy(dx: 4, dy: 4)
        let markerObstacles = projectedLabels.map { projectedLabel in
            (
                id: projectedLabel.input.id,
                rect: CGRect(
                    x: projectedLabel.point.x - 7,
                    y: projectedLabel.point.y - 7,
                    width: 14,
                    height: 14
                )
            )
        }

        var occupiedLabelRects: [CGRect] = []
        var newPlacements: [City.ID: PlacesMapLabelPlacement] = [:]

        for projectedLabel in projectedLabels {
            let belowRect = projectedLabel.rect(
                for: PlacesMapLabelPlacement.below
            )
            let aboveRect = projectedLabel.rect(
                for: PlacesMapLabelPlacement.above
            )
            let belowScore = labelCollisionScore(
                for: belowRect,
                labelID: projectedLabel.input.id,
                occupiedLabelRects: occupiedLabelRects,
                markerObstacles: markerObstacles,
                viewportBounds: viewportBounds
            )
            let aboveScore = labelCollisionScore(
                for: aboveRect,
                labelID: projectedLabel.input.id,
                occupiedLabelRects: occupiedLabelRects,
                markerObstacles: markerObstacles,
                viewportBounds: viewportBounds
            )
            let placement: PlacesMapLabelPlacement =
                aboveScore < belowScore ? .above : .below

            newPlacements[projectedLabel.input.id] = placement
            occupiedLabelRects.append(projectedLabel.rect(for: placement))
        }

        guard newPlacements != labelPlacements else { return }
        labelPlacements = newPlacements
    }

    private func estimatedLabelSize(for name: String) -> CGSize {
        let preferredFont = UIFont.preferredFont(forTextStyle: .caption2)
        let font = UIFont.systemFont(
            ofSize: preferredFont.pointSize,
            weight: .semibold
        )
        let measuredSize = (name as NSString).size(
            withAttributes: [.font: font]
        )

        return CGSize(
            width: min(104, max(18, ceil(measuredSize.width))) + 4,
            height: ceil(font.lineHeight) + 2
        )
    }

    private func labelCollisionScore(
        for rect: CGRect,
        labelID: City.ID,
        occupiedLabelRects: [CGRect],
        markerObstacles: [(id: City.ID, rect: CGRect)],
        viewportBounds: CGRect
    ) -> CGFloat {
        let labelOverlap = occupiedLabelRects.reduce(CGFloat.zero) {
            $0 + intersectionArea(rect, $1)
        }
        let markerOverlap = markerObstacles.reduce(CGFloat.zero) {
            partialResult,
            obstacle in
            guard obstacle.id != labelID else { return partialResult }
            return partialResult + intersectionArea(rect, obstacle.rect)
        }
        let clippedArea = intersectionArea(rect, viewportBounds)
        let offscreenArea = max(0, rect.width * rect.height - clippedArea)

        return labelOverlap * 4 + markerOverlap * 2 + offscreenArea * 6
    }

    private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
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
            guard !visiblePresentations.isEmpty else {
                position = .automatic
                return
            }
            position = .region(
                PlacesMapRegionFitting.region(
                    for: visiblePresentations.map(\.place.city)
                )
            )
        }
    }

    /// Centers on the real location marker instead of changing zoom to include
    /// every saved city. This preserves the user's manual map framing.
    private func focusCurrentLocation() {
        guard let currentLocationCoordinate else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
            position = .region(
                MKCoordinateRegion(
                    center: currentLocationCoordinate,
                    span: MKCoordinateSpan(
                        latitudeDelta: 0.16,
                        longitudeDelta: 0.16
                    )
                )
            )
            highlightsCurrentLocation = true
        }
    }

    private func hasValidActiveLayerData(
        _ presentation: PlacesMapPlacePresentation
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
        for presentation: PlacesMapPlacePresentation
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
                Label("No Places to Show", systemImage: "mappin.slash")
            } description: {
                Text(
                    "Save a city to add it to this map."
                )
            } actions: {
                Button(
                    "Search for a Place",
                    systemImage: "magnifyingglass",
                    action: searchPlaces
                )
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
        dynamicTypeSize.isAccessibilitySize ? 24 : 12
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
        for presentation: PlacesMapPlacePresentation
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
        for presentation: PlacesMapPlacePresentation
    ) -> String? {
        guard sortMode == .sunny else { return nil }
        return presentation.recommendation?.condition.displayIcon
            ?? "exclamationmark"
    }

    private func markerAccessibilityValue(
        for presentation: PlacesMapPlacePresentation
    ) -> String {
        guard let recommendation = presentation.recommendation else {
            return localizedString(
                "Forecast Unavailable",
                locale: locale
            )
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
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .systemDefault
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

    /// A native MapKit overlay spanning the complete projected world map.
    private var subtleBaseMapOverlayPoints: [MKMapPoint] {
        let world = MKMapRect.world
        return [
            MKMapPoint(x: world.minX, y: world.minY),
            MKMapPoint(x: world.maxX, y: world.minY),
            MKMapPoint(x: world.maxX, y: world.maxY),
            MKMapPoint(x: world.minX, y: world.maxY)
        ]
    }
}

private struct PlacesMapMarkerPresentation: Identifiable {
    let presentation: PlacesMapPlacePresentation
    let color: Color

    var id: City.ID { presentation.id }
}

private struct PlacesMapLabelLayoutInput: Equatable {
    let id: City.ID
    let name: String
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees

    init(
        id: City.ID,
        name: String,
        coordinate: CLLocationCoordinate2D
    ) {
        self.id = id
        self.name = name
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }
}

private struct PlacesMapProjectedLabel {
    let input: PlacesMapLabelLayoutInput
    let point: CGPoint
    let size: CGSize

    func rect(for placement: PlacesMapLabelPlacement) -> CGRect {
        CGRect(
            x: point.x - size.width / 2,
            y: point.y + placement.verticalOffset - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

private enum PlacesMapLabelPlacement: Equatable {
    case above
    case below

    var verticalOffset: CGFloat {
        switch self {
        case .above:
            -15
        case .below:
            15
        }
    }
}

/// A distinct, accessible marker for the device coordinate. It is independent
/// of the saved-place weather layer, so filters never hide the user's anchor.
private struct CurrentLocationMapAnnotation: View {
    let isHighlighted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if isHighlighted {
                Circle()
                    .stroke(.white.opacity(0.94), lineWidth: 2)
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.22), radius: 3)
            }

            Circle()
                .fill(.blue)
                .frame(width: 14, height: 14)
                .overlay {
                    Circle().stroke(.white, lineWidth: 3)
                }
                .shadow(color: .black.opacity(0.24), radius: 2)
        }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .accessibilityLabel("Current Location")
        .accessibilityValue(
            isHighlighted ? "Map centered here" : "Location marker"
        )
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.22),
            value: isHighlighted
        )
    }
}

private struct PlacesWeatherMapAnnotation: View {
    let name: String
    let color: Color
    let isSelected: Bool
    let labelPlacement: PlacesMapLabelPlacement
    let differentiatingText: String?
    let differentiatingSymbol: String?
    let accessibilityValue: String
    let select: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: select) {
            PlacesWeatherMapDot(
                color: color,
                isSelected: isSelected,
                differentiatingText: differentiatingText,
                differentiatingSymbol: differentiatingSymbol
            )
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(name)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .overlay {
            Text(name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 104)
                .fixedSize(horizontal: true, vertical: false)
                .offset(y: labelPlacement.verticalOffset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
    let presentation: PlacesMapPlacePresentation
    let displayName: String
    let sortMode: WeatherMetricMode
    let clearSelection: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit")
    private var distanceUnitRaw = DistanceUnit.defaultRawValue

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: AppRoute.place(id: presentation.id)) {
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
        .weatherAtlasInteractiveGlass(
            colorScheme: colorScheme,
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

                    Text(
                        statusDescription
                    )
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
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .systemDefault
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
    @Environment(\.colorScheme) private var colorScheme
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
        .detailTranslucentCard(
            colorScheme: colorScheme,
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
        metricLegendContent
    }

    @ViewBuilder
    private var metricLegendContent: some View {
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
                    wrappedCloudyConditionsTitle,
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
                labels: temperatureUnit == .fahrenheit
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
        let isWrapped = title.contains("\n")

        return HStack(
            alignment: isWrapped ? .top : .center,
            spacing: 12
        ) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.5), radius: 2)
                .padding(.top, isWrapped ? 5 : 0)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(
                    horizontal: !dynamicTypeSize.isAccessibilitySize,
                    vertical: true
                )
        }
    }

    private var wrappedCloudyConditionsTitle: String {
        let title = localizedString(
            "Cloudy, Windy, Snowy, Foggy",
            locale: locale
        )
        let separator = title.contains("、") ? "、" : ","
        let conditions = title
            .components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard conditions.count == 4 else { return title }

        let joiner = separator == "、" ? separator : "\(separator) "
        let firstLine = conditions.prefix(2).joined(separator: joiner)
        let secondLine = conditions.suffix(2).joined(separator: joiner)
        return "\(firstLine)\(separator)\n\(secondLine)"
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
                ForEach(Array(labels.enumerated()), id: \.element) {
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
        return sortMode == .sunny ? nil : 172
    }

    private var gradientHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 200 : 132
    }

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .systemDefault
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
