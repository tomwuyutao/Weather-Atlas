//
//  PlacesView.swift
//  Weather
//
//  Purpose: Presents the place-owned library as a compact native list.
//  Collections are optional filters, never owners of places.
//

import SwiftUI

/// Content for the Places tab.
///
/// The app shell owns the tab's `NavigationStack`; this view contributes
/// value-based links and native navigation-bar content to that stack.
struct PlacesView: View {
    let placesStore: PlacesStore
    let weatherStore: PlaceWeatherStore

    @Bindable var router: AppRouter
    @Binding var selectedDate: Date

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.appTheme) private var theme

    @State private var searchText = ""
    @State private var sortMode: WeatherMetricMode = .sunny
    @State private var membershipPlace: SavedPlace?
    @State private var pendingDeletion: SavedPlace?
    @State private var presentedError: PlacesUIError?
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit")
    private var distanceUnitRaw = DistanceUnit.defaultRawValue

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

    private var rankByPlaceID: [SavedPlace.ID: Int] {
        Dictionary(
            uniqueKeysWithValues: sortedPresentations.enumerated().map {
                ($0.element.id, $0.offset + 1)
            }
        )
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
        selectedCollection?.name ?? localizedString("Places", locale: locale)
    }

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic
    }

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    var body: some View {
        VStack(spacing: 0) {
            ForecastDateStrip(
                selection: $selectedDate,
                availableDates: forecastDates
            )

            Divider()

            placesContent
        }
        .weatherAtlasScreenBackground()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
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
        .onChange(
            of: router.selectedCollectionID,
            initial: true
        ) { _, collectionID in
            guard placesStore.selectedCollectionID != collectionID else {
                return
            }
            persistCollectionSelection(collectionID)
        }
        .onChange(of: placesStore.collections.map(\.id)) {
            validateCollectionSelection()
        }
        .sensoryFeedback(.selection, trigger: sortMode.rawValue)
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
            placesList
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
                        .font(.body.weight(.bold))
                        .foregroundStyle(theme.colors.primaryText)
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
                Section {
                    ForEach(sortedPresentations) { presentation in
                        placeRow(presentation)
                    }
                } header: {
                    Label(
                        sortMode.title(locale: locale),
                        systemImage: sortMode.icon
                    )
                    .font(.body.weight(.bold))
                    .foregroundStyle(theme.colors.primaryText)
                }
            }

            if let attribution = weatherStore.weatherAttribution,
               !sortedPresentations.isEmpty {
                Section {
                    WeatherAttributionView(attribution: attribution)
                }
                .listRowBackground(theme.colors.background)
            }
        }
        .listStyle(.plain)
        .weatherAtlasScrollableBackground()
        .contentMargins(.top, 12, for: .scrollContent)
        .contentMargins(.bottom, 16, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 1)
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
            CompactSavedPlaceRow(
                presentation: presentation,
                displayName: displayName(for: presentation.place),
                rank: presentation.recommendation == nil
                    ? nil
                    : rankByPlaceID[presentation.id],
                sortMode: sortMode,
                temperatureUnit: temperatureUnit,
                distanceUnit: distanceUnit
            )
        }
        .listRowInsets(
            EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        )
        .listRowSeparator(.hidden)
        .listRowBackground(theme.colors.background)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !placesStore.collections.isEmpty {
                Button {
                    membershipPlace = presentation.place
                } label: {
                    Label("Collections", systemImage: "folder")
                }
                .tint(theme.colors.accent)
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
            Label("Sort and Refresh", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityHint(
            localizedString(
                "Changes how places are ordered or refreshes their forecasts.",
                locale: locale
            )
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
        } catch {
            present(error)
        }
    }

    private func persistCollectionSelection(
        _ collectionID: PlaceCollection.ID?
    ) {
        do {
            try placesStore.selectCollection(id: collectionID)
        } catch {
            router.selectedCollectionID = placesStore.selectedCollectionID
            present(error)
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

private struct PlacesWeatherSection: Identifiable {
    let condition: RecommendationConditionGroup
    let presentations: [SavedPlacePresentation]

    var id: RecommendationConditionGroup { condition }
}

private struct PlacesUIError: Identifiable {
    let id = UUID()
    let message: String
}

private struct CompactSavedPlaceRow: View {
    let presentation: SavedPlacePresentation
    let displayName: String
    let rank: Int?
    let sortMode: WeatherMetricMode
    let temperatureUnit: TemperatureUnit
    let distanceUnit: DistanceUnit

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.appTheme) private var theme
    @ScaledMetric(relativeTo: .body)
    private var rankColumnWidth: CGFloat = 32
    @ScaledMetric(relativeTo: .caption)
    private var metricColumnWidth: CGFloat = 76

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                compactLayout
            }
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(displayName)
        .accessibilityValue(accessibilityValue)
    }

    private var compactLayout: some View {
        HStack(spacing: 5) {
            rankOrStatusIcon

            Text(displayName)
                .font(.body.weight(.medium))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let recommendation = presentation.recommendation {
                compactMetric(for: recommendation)
            } else {
                Text(compactStatusLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let rank {
                    Text(rank, format: .number)
                        .font(.headline)
                        .foregroundStyle(theme.colors.secondaryText)
                        .monospacedDigit()
                }

                Text(displayName)
                    .font(.headline)
                    .foregroundStyle(theme.colors.primaryText)
            }

            if let recommendation = presentation.recommendation {
                let details = metricDetails(for: recommendation)
                Label(
                    "\(details.label): \(details.value)",
                    systemImage: details.icon
                )
                .font(.subheadline)
                .foregroundStyle(theme.colors.secondaryText)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    statusIcon
                        .accessibilityHidden(true)

                    Text(statusDescription)
                        .font(.subheadline)
                        .foregroundStyle(theme.colors.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private var rankOrStatusIcon: some View {
        if let rank {
            Text(rank, format: .number)
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.colors.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: rankColumnWidth, alignment: .leading)
        } else {
            statusIcon
                .frame(width: rankColumnWidth, alignment: .leading)
                .accessibilityHidden(true)
        }
    }

    private func compactMetric(
        for recommendation: PlaceRecommendation
    ) -> some View {
        let details = metricDetails(for: recommendation)

        return HStack(spacing: 3) {
            Image(systemName: details.icon)
                .font(.caption.weight(.medium))
                .accessibilityHidden(true)

            Text(details.value)
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
        .foregroundStyle(theme.colors.secondaryText)
        .lineLimit(1)
        .frame(width: metricColumnWidth, alignment: .trailing)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if presentation.isLoading {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: "exclamationmark.circle")
                .font(.body)
                .foregroundStyle(theme.colors.secondaryText)
        }
    }

    private var compactStatusLabel: String {
        presentation.isLoading
            ? localizedString("Loading forecast…", locale: locale)
            : localizedString("Forecast Unavailable", locale: locale)
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

    private var accessibilityValue: String {
        var components: [String] = []

        if let rank {
            components.append(localizedString("Rank \(rank)", locale: locale))
        }

        if let recommendation = presentation.recommendation {
            let details = metricDetails(for: recommendation)
            components.append("\(details.label): \(details.value)")
        } else {
            components.append(statusDescription)
        }

        return components.joined(separator: ", ")
    }

    private func metricDetails(
        for recommendation: PlaceRecommendation
    ) -> (value: String, icon: String, label: String) {
        switch sortMode {
        case .sunny:
            return (
                String(recommendation.sunnyHourCount),
                sortMode.icon,
                localizedString("Sunny Hours", locale: locale)
            )
        case .cloud:
            return (
                percentage(recommendation.cloudCover),
                "cloud",
                localizedString("Cloud Cover", locale: locale)
            )
        case .temperature:
            return (
                temperatureUnit.display(recommendation.forecast.dailyHigh),
                sortMode.icon,
                sortMode.title(locale: locale)
            )
        case .feelsLike:
            return (
                recommendation.maximumFeelsLike.map(
                    temperatureUnit.display
                ) ?? "—",
                sortMode.icon,
                sortMode.title(locale: locale)
            )
        case .rainChance:
            return (
                recommendation.precipitationChance.map(percentage) ?? "—",
                sortMode.icon,
                sortMode.title(locale: locale)
            )
        case .visibility:
            return (
                recommendation.maximumVisibilityKilometers.map(
                    distanceUnit.display
                ) ?? "—",
                sortMode.icon,
                sortMode.title(locale: locale)
            )
        case .uvIndex:
            return (
                recommendation.forecast.uvIndex.map(String.init) ?? "—",
                sortMode.icon,
                sortMode.title(locale: locale)
            )
        }
    }

    private func percentage(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
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
