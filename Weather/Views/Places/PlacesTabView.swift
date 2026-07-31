//
//  PlacesTabView.swift
//  Weather
//
//  Purpose: Presents the place-owned library as one native list-or-map
//  workspace. Collections are optional filters, never owners of places.
//

import MapKit
import SwiftUI
import WeatherKit

/// Content for the Places tab.
///
/// The app shell owns the tab's `NavigationStack`; this view contributes
/// value-based links and native navigation-bar content to that stack.
struct PlacesTabView: View {
    let placesStore: PlacesStore
    let weatherStore: PlaceWeatherStore

    @Bindable var router: AppRouter
    @Binding var selectedDate: Date

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.appTheme) private var theme

    @State private var searchText = ""
    @State private var sortMode: WeatherListSortMode = .sunny
    @State private var membershipPlace: SavedPlace?
    @State private var pendingDeletion: SavedPlace?
    @State private var presentedError: PlacesUIError?
    @State private var restoredPersistedCollection = false

    private var selectedCollection: PlaceCollection? {
        guard let collectionID = router.selectedCollectionID else { return nil }
        return placesStore.collections.first { $0.id == collectionID }
    }

    private var collectionPlaces: [SavedPlace] {
        placesStore.places(in: router.selectedCollectionID)
    }

    private var filteredPlaces: [SavedPlace] {
        guard !searchText.isEmpty else { return collectionPlaces }
        return collectionPlaces.filter { place in
            displayName(for: place).localizedStandardContains(searchText)
                || place.city.country.localizedStandardContains(searchText)
        }
    }

    private var presentations: [SavedPlacePresentation] {
        filteredPlaces.map { place in
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
                failureMessage: weatherStore.failuresByPlaceID[place.id]?.message
            )
        }
    }

    private var sortedPresentations: [SavedPlacePresentation] {
        let recommendations = presentations.compactMap(\.recommendation)
        let orderedRecommendations = RecommendationEngine.sorted(
            recommendations,
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

    private var sunnySections: [PlacesWeatherSection] {
        RecommendationConditionGroup.allCases.compactMap { condition in
            let matches = sortedPresentations.filter {
                $0.recommendation?.conditionGroup == condition
            }
            guard !matches.isEmpty else { return nil }
            return PlacesWeatherSection(
                condition: condition,
                presentations: matches
            )
        }
    }

    private var loadingPresentations: [SavedPlacePresentation] {
        sortedPresentations.filter {
            $0.recommendation == nil && $0.isLoading
        }
    }

    private var unavailablePresentations: [SavedPlacePresentation] {
        sortedPresentations.filter {
            $0.recommendation == nil && !$0.isLoading
        }
    }

    private var forecastDates: [Date] {
        let weather = collectionPlaces.compactMap {
            weatherStore.weather(for: $0.id)
        }
        let availableDates = RecommendationEngine.availableDates(in: weather)
        guard availableDates.isEmpty else { return availableDates }

        let today = calendar.startOfDay(for: Date())
        return (0..<10).compactMap {
            calendar.date(byAdding: .day, value: $0, to: today)
        }
    }

    private var weatherLoadID: [City.ID] {
        collectionPlaces.map(\.id)
    }

    private var navigationTitle: String {
        selectedCollection?.name ?? localizedString("Places", locale: locale)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForecastDateStrip(
                selection: $selectedDate,
                availableDates: forecastDates
            )

            Picker("View", selection: $router.placesViewMode) {
                Label("List", systemImage: "list.bullet")
                    .tag(PlacesViewMode.list)
                Label("Map", systemImage: "map")
                    .tag(PlacesViewMode.map)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            placesContent
        }
        .weatherAtlasScreenBackground()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbarTitleMenu {
            collectionTitleMenu
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                sortMenu

                Button {
                    router.presentedSheet = .addPlace(
                        collectionID: router.selectedCollectionID
                    )
                } label: {
                    Label("Add Place", systemImage: "plus")
                }
                .accessibilityHint("Searches for a city to save.")
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search Places"
        )
        .sheet(item: $membershipPlace) { place in
            PlaceCollectionMembershipSheet(
                place: place,
                placesStore: placesStore
            )
        }
        .confirmationDialog(
            "Delete Place?",
            isPresented: deletionIsPresented,
            presenting: pendingDeletion
        ) { place in
            Button("Delete \(displayName(for: place))", role: .destructive) {
                deletePlace(place)
            }
            Button("Cancel", role: .cancel) {}
        } message: { place in
            Text(
                "\(displayName(for: place)) will be removed from All Places and every collection."
            )
        }
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
        .task(id: weatherLoadID) {
            await weatherStore.load(
                cities: collectionPlaces.map(\.city),
                locale: locale
            )
        }
        .onAppear {
            restoreCollectionSelectionIfNeeded()
        }
        .onChange(of: router.selectedCollectionID) { _, collectionID in
            guard restoredPersistedCollection,
                  placesStore.selectedCollectionID != collectionID else {
                return
            }
            persistCollectionSelection(collectionID)
        }
        .onChange(of: placesStore.collections.map(\.id)) {
            validateCollectionSelection()
        }
        .sensoryFeedback(.selection, trigger: router.placesViewMode)
    }

    @ViewBuilder
    private var placesContent: some View {
        if let loadErrorDescription = placesStore.loadErrorDescription {
            PlacesLibraryUnavailableView(
                message: loadErrorDescription,
                retry: placesStore.retryLoading
            )
        } else if collectionPlaces.isEmpty {
            PlacesEmptyView(
                collectionName: selectedCollection?.name,
                addPlace: {
                    router.presentedSheet = .addPlace(
                        collectionID: router.selectedCollectionID
                    )
                },
                manageCollections: {
                    router.placesPath.append(.collections)
                }
            )
        } else if filteredPlaces.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            switch router.placesViewMode {
            case .list:
                placesList
            case .map:
                PlacesLibraryMap(
                    presentations: sortedPresentations,
                    selectedPlaceID: $router.selectedMapPlaceID,
                    selectedDate: selectedDate,
                    displayName: displayName(for:),
                    weatherAttribution: weatherStore.weatherAttribution
                )
            }
        }
    }

    private var placesList: some View {
        List {
            if sortMode == .sunny {
                ForEach(sunnySections) { section in
                    Section {
                        ForEach(section.presentations) { presentation in
                            placeRow(presentation)
                        }
                    } header: {
                        Label {
                            Text(section.condition.title(locale: locale))
                        } icon: {
                            Image(systemName: section.condition.systemImage)
                                .foregroundStyle(
                                    conditionTint(section.condition)
                                )
                        }
                    }
                }

                if !loadingPresentations.isEmpty {
                    Section("Loading Forecasts") {
                        ForEach(loadingPresentations) { presentation in
                            placeRow(presentation)
                        }
                    }
                }

                if !unavailablePresentations.isEmpty {
                    Section("Forecast Unavailable") {
                        ForEach(unavailablePresentations) { presentation in
                            placeRow(presentation)
                        }
                    }
                }
            } else {
                ForEach(sortedPresentations) { presentation in
                    placeRow(presentation)
                }
            }

            if let attribution = weatherStore.weatherAttribution,
               !sortedPresentations.isEmpty {
                Section {
                    WeatherAttributionView(attribution: attribution)
                }
            }
        }
        .listStyle(.insetGrouped)
        .weatherAtlasScrollableBackground()
        .refreshable {
            await weatherStore.load(
                cities: collectionPlaces.map(\.city),
                forceRefresh: true,
                locale: locale
            )
        }
        .accessibilityLabel("Saved places")
    }

    private func placeRow(
        _ presentation: SavedPlacePresentation
    ) -> some View {
        NavigationLink(
            value: AppRoute.place(
                id: presentation.id,
                date: selectedDate
            )
        ) {
            SavedPlaceForecastRow(
                presentation: presentation,
                displayName: displayName(for: presentation.place)
            )
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !placesStore.collections.isEmpty {
                Button {
                    membershipPlace = presentation.place
                } label: {
                    Label("Collections", systemImage: "folder")
                }
                .tint(.accentColor)
            }
        }
        .swipeActions(edge: .trailing) {
            if let selectedCollection {
                Button(role: .destructive) {
                    remove(
                        presentation.place,
                        from: selectedCollection
                    )
                } label: {
                    Label("Remove", systemImage: "folder.badge.minus")
                }
            } else {
                Button(role: .destructive) {
                    pendingDeletion = presentation.place
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .contextMenu {
            if !placesStore.collections.isEmpty {
                Button {
                    membershipPlace = presentation.place
                } label: {
                    Label("Edit Collections", systemImage: "folder")
                }
            }

            Button(role: .destructive) {
                pendingDeletion = presentation.place
            } label: {
                Label("Delete Place", systemImage: "trash")
            }
        }
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
                            Label(collection.name, systemImage: "checkmark")
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
            router.placesPath.append(.collections)
        } label: {
            Label("Manage Collections", systemImage: "folder")
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort Places", selection: $sortMode) {
                ForEach(WeatherListSortMode.allCases) { mode in
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
            Label("Sort and Refresh", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityHint(
            "Changes how places are ordered or refreshes their forecasts."
        )
    }

    private var deletionIsPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletion = nil
                }
            }
        )
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

    private func conditionTint(
        _ condition: RecommendationConditionGroup
    ) -> Color {
        switch condition {
        case .sunny:
            theme.colors.dotSun
        case .partlySunny:
            theme.colors.dotPartlyCloudy
        case .mixed:
            theme.colors.dotCloudy
        case .wet:
            theme.colors.dotRain
        }
    }

    private func selectCollection(_ collectionID: PlaceCollection.ID?) {
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

    private func restoreCollectionSelectionIfNeeded() {
        guard !restoredPersistedCollection else { return }
        restoredPersistedCollection = true

        if router.selectedCollectionID == nil {
            router.selectedCollectionID = placesStore.selectedCollectionID
        } else if router.selectedCollectionID != placesStore.selectedCollectionID {
            persistCollectionSelection(router.selectedCollectionID)
        }
    }

    private func validateCollectionSelection() {
        guard let collectionID = router.selectedCollectionID,
              !placesStore.collections.contains(where: { $0.id == collectionID }) else {
            return
        }
        selectCollection(nil)
    }

    private func remove(
        _ place: SavedPlace,
        from collection: PlaceCollection
    ) {
        do {
            try placesStore.setMembership(
                of: place.id,
                in: collection.id,
                isMember: false
            )
        } catch {
            present(error)
        }
    }

    private func deletePlace(_ place: SavedPlace) {
        do {
            try placesStore.deletePlace(id: place.id)
            if router.selectedMapPlaceID == place.id {
                router.selectedMapPlaceID = nil
            }
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        presentedError = PlacesUIError(
            message: localizedPlacesErrorDescription(
                error,
                locale: locale
            )
        )
    }
}

private struct SavedPlacePresentation: Identifiable {
    let place: SavedPlace
    let recommendation: PlaceRecommendation?
    let isLoading: Bool
    let failureMessage: String?

    var id: SavedPlace.ID { place.id }
}

private struct PlacesWeatherSection: Identifiable {
    let condition: RecommendationConditionGroup
    let presentations: [SavedPlacePresentation]

    var id: RecommendationConditionGroup { condition }
}

private struct PlacesUIError: Identifiable {
    let id = UUID()
    let message: String
}

private struct SavedPlaceForecastRow: View {
    let presentation: SavedPlacePresentation
    let displayName: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    var body: some View {
        if let recommendation = presentation.recommendation {
            PlaceRecommendationRow(
                recommendation: recommendation,
                displayName: displayName
            )
        } else if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    statusIcon
                        .frame(minWidth: 32, minHeight: 32)
                        .accessibilityHidden(true)

                    Text(displayName)
                        .font(.headline)
                }

                if !presentation.place.city.country.isEmpty {
                    Text(presentation.place.city.country)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(statusDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 5)
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: 14) {
                statusIcon
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.headline)
                        .lineLimit(2)

                    if !presentation.place.city.country.isEmpty {
                        Text(presentation.place.city.country)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 5)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if presentation.isLoading {
            ProgressView()
        } else {
            Image(systemName: "exclamationmark.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
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
}

private struct PlacesLibraryMap: View {
    let presentations: [SavedPlacePresentation]
    @Binding var selectedPlaceID: SavedPlace.ID?
    let selectedDate: Date
    let displayName: (SavedPlace) -> String
    let weatherAttribution: WeatherAttribution?

    @State private var position: MapCameraPosition = .automatic
    @Environment(\.appTheme) private var theme

    private var selectedPresentation: SavedPlacePresentation? {
        guard let selectedPlaceID else { return nil }
        return presentations.first { $0.id == selectedPlaceID }
    }

    private var placeIDs: [SavedPlace.ID] {
        presentations.map(\.id)
    }

    var body: some View {
        Map(position: $position, selection: $selectedPlaceID) {
            ForEach(presentations) { presentation in
                Marker(
                    displayName(presentation.place),
                    systemImage: presentation.recommendation?
                        .condition
                        .displayIcon ?? "mappin",
                    coordinate: CLLocationCoordinate2D(
                        latitude: presentation.place.city.latitude,
                        longitude: presentation.place.city.longitude
                    )
                )
                .tint(markerTint(for: presentation.recommendation))
                .tag(presentation.id)
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let selectedPresentation {
                    MapPlaceSelectionCard(
                        presentation: selectedPresentation,
                        displayName: displayName(selectedPresentation.place),
                        selectedDate: selectedDate,
                        clearSelection: {
                            selectedPlaceID = nil
                        }
                    )
                }

                if let weatherAttribution, !presentations.isEmpty {
                    WeatherAttributionView(attribution: weatherAttribution)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.regularMaterial)
                }
            }
        }
        .onChange(of: placeIDs, initial: true) {
            position = .automatic
            if let selectedPlaceID,
               !placeIDs.contains(selectedPlaceID) {
                self.selectedPlaceID = nil
            }
        }
        .accessibilityLabel("Map of saved places")
    }

    private func markerTint(
        for recommendation: PlaceRecommendation?
    ) -> Color {
        switch recommendation?.conditionGroup {
        case .sunny:
            theme.colors.dotSun
        case .partlySunny:
            theme.colors.dotPartlyCloudy
        case .mixed:
            theme.colors.dotCloudy
        case .wet:
            theme.colors.dotRain
        case nil:
            theme.colors.accent
        }
    }
}

private struct MapPlaceSelectionCard: View {
    let presentation: SavedPlacePresentation
    let displayName: String
    let selectedDate: Date
    let clearSelection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Group {
                    if let recommendation = presentation.recommendation {
                        PlaceRecommendationRow(
                            recommendation: recommendation,
                            displayName: displayName
                        )
                    } else {
                        SavedPlaceForecastRow(
                            presentation: presentation,
                            displayName: displayName
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("Close", systemImage: "xmark.circle.fill") {
                    clearSelection()
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
            }

            NavigationLink(
                "View Forecast",
                value: AppRoute.place(
                    id: presentation.id,
                    date: selectedDate
                )
            )
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
    }
}

private struct PlacesEmptyView: View {
    let collectionName: String?
    let addPlace: () -> Void
    let manageCollections: () -> Void
    @Environment(\.locale) private var locale

    private var title: String {
        collectionName == nil
            ? localizedString("No Places Yet", locale: locale)
            : localizedString("No Places in This Collection", locale: locale)
    }

    private var description: String {
        if let collectionName {
            return localizedString(
                "Save a new place here or add one of your existing places to \(collectionName).",
                locale: locale
            )
        }
        return localizedString(
            "Save cities you care about. You can organize them into optional collections later.",
            locale: locale
        )
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "mappin.and.ellipse")
        } description: {
            Text(description)
        } actions: {
            Button("Add Place", systemImage: "plus", action: addPlace)
                .buttonStyle(.borderedProminent)

            if collectionName != nil {
                Button(
                    "Manage Collections",
                    systemImage: "folder",
                    action: manageCollections
                )
            }
        }
    }
}

private struct PlacesLibraryUnavailableView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Places Unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again", systemImage: "arrow.clockwise", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}
