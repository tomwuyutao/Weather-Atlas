//
//  Places.swift
//  Weather
//
//  Purpose: Presents the one-level Saved Places library as a compact list.
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

    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var forecastCalendar
    @Environment(\.appTheme) private var theme

    @State private var sortMode: WeatherMetricMode = .sunny
    @State private var isSorting = false
    @State private var listEditMode: EditMode = .inactive
    @State private var pendingDeletion: SavedPlace?
    @State private var renamingPlace: SavedPlace?
    @State private var presentedError: PlacesUIError?
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit")
    private var distanceUnitRaw = DistanceUnit.defaultRawValue
    @ScaledMetric(relativeTo: .body)
    private var leadingColumnWidth: CGFloat = 32

    private var savedPlaces: [SavedPlace] { placesStore.allPlaces }

    private var presentations: [SavedPlacePresentation] {
        savedPlaces.map { place in
            let weather = weatherStore.weather(for: place.id)
            return SavedPlacePresentation(
                place: place,
                recommendation: weather.flatMap {
                    RecommendationEngine.recommendation(
                        for: $0,
                        on: selectedDate,
                        selectionCalendar: forecastCalendar
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

    private var weatherLoadID: [City.ID] {
        savedPlaces.map(\.id)
    }

    private var navigationTitle: String {
        localizedString("Places", locale: locale)
    }

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .systemDefault
    }

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    var body: some View {
        placesContent
            .weatherAtlasScreenBackground()
            .environment(\.editMode, $listEditMode)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 8) {
                    Text(navigationTitle)
                        .font(.largeTitle.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    .layoutPriority(1)

                    Spacer(minLength: 8)

                    sortMenu
                        .frame(minWidth: 36, minHeight: 44)

                    EditButton()
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(savedPlaces.isEmpty)

                    if isSorting {
                        TopForecastDateSwitcher(
                            selection: $selectedDate,
                            availableDates: ForecastDateHorizon.dates(in: forecastCalendar)
                        )
                    }
                }
                .font(.title3)
                .buttonStyle(.plain)
                .foregroundStyle(theme.colors.primaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .confirmationDialog(
                "Delete Place?",
                isPresented: deletionIsPresented,
                presenting: pendingDeletion
            ) { place in
                Button(
                    "Delete \(displayName(for: place))",
                    role: .destructive
                ) {
                    deletePlace(place)
                }
                Button("Cancel", role: .cancel) {}
            } message: { place in
                Text(
                    "\(displayName(for: place)) will be removed from Saved Places."
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
            .sheet(item: $renamingPlace) { place in
                RenamePlaceSheet(place: place, placesStore: placesStore)
            }
            .task(id: weatherLoadID) {
                guard isSorting else { return }
                await weatherStore.load(
                    cities: savedPlaces.map(\.city),
                    locale: locale
                )
            }
            .onChange(of: isSorting) { _, sortingEnabled in
                guard sortingEnabled else { return }
                Task {
                    await weatherStore.load(
                        cities: savedPlaces.map(\.city),
                        locale: locale
                    )
                }
            }
            .sensoryFeedback(
                .selection,
                trigger: isSorting ? sortMode.rawValue : "unsorted"
            )
    }

    @ViewBuilder
    private var placesContent: some View {
        if let loadErrorDescription = placesStore.loadErrorDescription {
            PlacesLibraryUnavailableView(
                message: loadErrorDescription,
                retry: placesStore.retryLoading
            )
        } else if savedPlaces.isEmpty {
            PlacesEmptyView(
                searchPlaces: {
                    router.selectedTab = .search
                }
            )
        } else {
            placesList
        }
    }

    private var placesList: some View {
        List {
            if !isSorting {
                Section {
                    ForEach(presentations) { presentation in
                        placeRow(presentation)
                    }
                    .onDelete { offsets in
                        requestDeletion(offsets, from: presentations)
                    }
                }
            } else if sortMode == .sunny {
                ForEach(sunnySections) { section in
                    Section {
                        ForEach(section.presentations) { presentation in
                            placeRow(presentation)
                        }
                        .onDelete { offsets in
                            requestDeletion(offsets, from: section.presentations)
                        }
                    } header: {
                        HStack(spacing: 5) {
                            Image(systemName: section.condition.systemImage)
                                .weatherIconStyle(
                                    for: section.condition.systemImage
                                )
                                .frame(
                                    width: leadingColumnWidth,
                                    alignment: .leading
                                )

                            Text(section.condition.title(locale: locale))
                        }
                        .font(.body.weight(.bold))
                        .foregroundStyle(theme.colors.primaryText)
                        .textCase(nil)
                    }
                    // Restore the compact rule directly below each weather
                    // subheading from the earlier list design.
                    .listSectionSeparator(.visible, edges: .top)
                }

                if !loadingPresentations.isEmpty {
                    Section("Loading Forecasts") {
                        ForEach(loadingPresentations) { presentation in
                            placeRow(presentation)
                        }
                        .onDelete { offsets in
                            requestDeletion(offsets, from: loadingPresentations)
                        }
                    }
                }

                if !unavailablePresentations.isEmpty {
                    Section("Forecast Unavailable") {
                        ForEach(unavailablePresentations) { presentation in
                            placeRow(presentation)
                        }
                        .onDelete { offsets in
                            requestDeletion(
                                offsets,
                                from: unavailablePresentations
                            )
                        }
                    }
                }
            } else {
                Section {
                    ForEach(sortedPresentations) { presentation in
                        placeRow(presentation)
                    }
                    .onDelete { offsets in
                        requestDeletion(offsets, from: sortedPresentations)
                    }
                } header: {
                    HStack(spacing: 5) {
                        Image(systemName: sortMode.icon)
                            .frame(
                                width: leadingColumnWidth,
                                alignment: .leading
                            )
                        Text(sortMode.title(locale: locale))
                    }
                    .font(.body.weight(.bold))
                    .foregroundStyle(theme.colors.primaryText)
                    .textCase(nil)
                }
            }

        }
        .listStyle(.plain)
        .weatherAtlasScrollableBackground()
        .contentMargins(.top, 12, for: .scrollContent)
        .contentMargins(.bottom, 16, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 1)
        .refreshable {
            await weatherStore.load(
                cities: savedPlaces.map(\.city),
                forceRefresh: true,
                locale: locale
            )
        }
        .accessibilityLabel("Saved places")
    }

    @ViewBuilder
    private func placeRow(
        _ presentation: SavedPlacePresentation
    ) -> some View {
        Group {
            if listEditMode.isEditing {
                editablePlaceRow(presentation)
            } else {
                NavigationLink(
                    value: AppRoute.place(id: presentation.id)
                ) {
                    savedPlaceRow(presentation)
                }
            }
        }
        .listRowInsets(
            EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        )
        .listRowSeparator(.hidden)
        .listRowBackground(theme.colors.background)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                pendingDeletion = presentation.place
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                pendingDeletion = presentation.place
            } label: {
                Label("Delete Place", systemImage: "trash")
            }
        }
    }

    private func savedPlaceRow(
        _ presentation: SavedPlacePresentation
    ) -> some View {
        CompactSavedPlaceRow(
            presentation: presentation,
            displayName: displayName(for: presentation.place),
            rank: !isSorting || presentation.recommendation == nil
                ? nil
                : rankByPlaceID[presentation.id],
            sortMode: sortMode,
            showsWeatherDetails: isSorting,
            temperatureUnit: temperatureUnit,
            distanceUnit: distanceUnit
        )
    }

    private func editablePlaceRow(
        _ presentation: SavedPlacePresentation
    ) -> some View {
        HStack(spacing: 8) {
            savedPlaceRow(presentation)

            Button {
                renamingPlace = presentation.place
            } label: {
                Label("Rename", systemImage: "pencil")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Rename \(displayName(for: presentation.place))")
        }
    }

    private var sortMenu: some View {
        Menu {
            if isSorting {
                Picker("Sort Places", selection: $sortMode) {
                    ForEach(WeatherMetricMode.allCases) { mode in
                        Label(
                            mode.title(locale: locale),
                            systemImage: mode.icon
                        )
                        .tag(mode)
                    }
                }

                Button(localizedString("Stop Sorting", locale: locale), systemImage: "xmark") {
                    isSorting = false
                }
            } else {
                Button(
                    localizedString("Sort by Sunniness", locale: locale),
                    systemImage: WeatherMetricMode.sunny.icon
                ) {
                    sortMode = .sunny
                    isSorting = true
                }
            }

            Divider()

            Button {
                Task {
                    await weatherStore.load(
                        cities: savedPlaces.map(\.city),
                        forceRefresh: true,
                        locale: locale
                    )
                }
            } label: {
                Label("Refresh Forecasts", systemImage: "arrow.clockwise")
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
                .labelStyle(.iconOnly)
        }
        .accessibilityHint(
            localizedString(
                "Sorts places or refreshes their forecasts.",
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
        place.customName ?? place.city.displayName
    }

    private func deletePlace(_ place: SavedPlace) {
        do {
            try placesStore.deletePlace(id: place.id)
        } catch {
            present(error)
        }
    }

    private func requestDeletion(
        _ offsets: IndexSet,
        from presentations: [SavedPlacePresentation]
    ) {
        guard let offset = offsets.first,
              presentations.indices.contains(offset) else {
            return
        }
        pendingDeletion = presentations[offset].place
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

private struct RenamePlaceSheet: View {
    let place: SavedPlace
    let placesStore: PlacesStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var name: String
    @State private var error: PlacesUIError?

    init(place: SavedPlace, placesStore: PlacesStore) {
        self.place = place
        self.placesStore = placesStore
        _name = State(initialValue: place.customName ?? place.city.displayName)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Rename", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
            .navigationTitle("Rename")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
        .alert(
            "Unable to Update Places",
            isPresented: errorIsPresented,
            presenting: error
        ) { _ in
            Button("OK") { error = nil }
        } message: { error in
            Text(error.message)
        }
    }

    private func save() {
        do {
            try placesStore.renamePlace(id: place.id, customName: name)
            dismiss()
        } catch {
            self.error = PlacesUIError(
                message: localizedPlacesErrorDescription(error, locale: locale)
            )
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { error != nil },
            set: { isPresented in
                if !isPresented {
                    error = nil
                }
            }
        )
    }
}

private struct CompactSavedPlaceRow: View {
    let presentation: SavedPlacePresentation
    let displayName: String
    let rank: Int?
    let sortMode: WeatherMetricMode
    let showsWeatherDetails: Bool
    let temperatureUnit: TemperatureUnit
    let distanceUnit: DistanceUnit

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.appTheme) private var theme
    @ScaledMetric(relativeTo: .body)
    private var rankColumnWidth: CGFloat = 32
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
            if showsWeatherDetails {
                rankOrStatusIcon
            }

            Text(displayName)
                .font(.body.weight(.medium))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private var accessibilityLayout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if showsWeatherDetails {
                if let rank {
                    Text(rank, format: .number)
                        .font(.headline)
                        .foregroundStyle(theme.colors.secondaryText)
                        .monospacedDigit()
                } else {
                    statusIcon
                        .accessibilityHidden(true)
                }
            }

            Text(displayName)
                .font(.headline)
                .foregroundStyle(theme.colors.primaryText)

            Spacer(minLength: 0)
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
        guard showsWeatherDetails else { return "" }
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
    let searchPlaces: () -> Void
    @Environment(\.locale) private var locale

    private var title: String {
        localizedString("No Places Yet", locale: locale)
    }

    private var description: String {
        return localizedString(
            "Save cities you care about to compare their weather in one place.",
            locale: locale
        )
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "mappin.and.ellipse")
        } description: {
            Text(description)
        } actions: {
            Button(
                "Search for a Place",
                systemImage: "magnifyingglass",
                action: searchPlaces
            )
                .buttonStyle(.borderedProminent)
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
