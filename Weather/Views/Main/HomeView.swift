//
//  HomeView.swift
//  Weather
//
//  Purpose: Provides the image-free recommendation Home tab for one selected
//  date, combining saved places with opt-in nearby discovery.
//

import SwiftUI

/// Calm recommendation surface that answers where conditions are sunniest.
struct HomeView: View {
    /// Shared root domain model.
    let model: WeatherAtlasModel
    /// Value-navigation and item-driven presentation coordinator.
    @Bindable var router: AppRouter
    /// Literal date shared with Map, Places, and Detail.
    @Binding var selectedDate: Date

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.appTheme) private var theme
    @State private var recentlySavedPlaceID: SavedPlace.ID?
    @State private var saveErrorMessage: String?

    private var recommendations: [PlaceRecommendation] {
        model.homeRecommendations(on: selectedDate)
    }

    private var savedPlaceIDs: Set<SavedPlace.ID> {
        Set(model.placesStore.allPlaces.map(\.id))
    }

    var body: some View {
        List {
            dateSection
            recommendationContent
            nearbyDiscoverySection
            if !recommendations.isEmpty,
               let attribution = model.weatherStore.weatherAttribution {
                Section {
                    WeatherAttributionView(attribution: attribution)
                }
            }
        }
        .listStyle(.insetGrouped)
        .weatherAtlasScrollableBackground()
        .navigationTitle("Home")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Nearby Discovery", systemImage: "location.magnifyingglass") {
                    router.presentedSheet = .nearbyDiscovery
                }

                Button("Settings", systemImage: "gearshape") {
                    router.presentedSheet = .settings
                }
            }
        }
        .refreshable {
            if model.isNearbyDiscoveryEnabled
                && model.locationProvider.hasUsableCoordinate {
                await model.refreshNearbyRecommendations(
                    forceRefresh: true,
                    locale: locale
                )
            } else {
                await model.loadSavedWeather(
                    forceRefresh: true,
                    locale: locale
                )
            }
        }
        .task(id: model.placesStore.allPlaces.map(\.id)) {
            await model.loadSavedWeather(locale: locale)
            normalizeSelectedDate()
        }
        .onChange(of: model.availableForecastDates) {
            normalizeSelectedDate()
        }
        .onChange(of: model.locationProvider.status) { _, newStatus in
            guard newStatus == .ready || newStatus == .readyWithoutCountry else {
                return
            }
            Task {
                await model.refreshNearbyRecommendations(locale: locale)
                normalizeSelectedDate()
            }
        }
        .alert(
            "Nearby Discovery",
            isPresented: nearbyErrorIsPresented,
            actions: {
                Button("Try Again") {
                    Task {
                        await model.refreshNearbyRecommendations(
                            forceRefresh: true,
                            locale: locale
                        )
                    }
                }
                Button("OK", role: .cancel) {
                    model.clearNearbyDiscoveryError()
                }
            },
            message: {
                if let error = model.nearbyDiscoveryError {
                    Text(error)
                }
            }
        )
        .alert(
            "Unable to Save Place",
            isPresented: saveErrorIsPresented
        ) {
            Button("OK") {
                saveErrorMessage = nil
            }
        } message: {
            if let saveErrorMessage {
                Text(saveErrorMessage)
            }
        }
        .sensoryFeedback(.success, trigger: recentlySavedPlaceID)
    }

    /// Places the native horizontal date control immediately below the title.
    private var dateSection: some View {
        Section {
            ForecastDateStrip(
                selection: $selectedDate,
                availableDates: dateChoices
            )
            .listRowInsets(
                EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
            )
        }
    }

    @ViewBuilder
    private var recommendationContent: some View {
        if recommendations.isEmpty {
            if !model.weatherStore.loadingPlaceIDs.isEmpty
                || model.isRefreshingNearby {
                Section("Finding the sunniest places") {
                    PlaceWeatherLoadingRow()
                    PlaceWeatherLoadingRow()
                }
            } else if model.placesStore.allPlaces.isEmpty
                        && (
                            !model.isNearbyDiscoveryEnabled
                                || !model.locationProvider.hasUsableCoordinate
                        ) {
                Section {
                    ContentUnavailableView {
                        Label("No Places Yet", systemImage: "sun.max")
                    } description: {
                        Text(
                            "Save a place or set up nearby discovery to compare sunny conditions."
                        )
                    }

                    Button("Add a Place", systemImage: "plus") {
                        router.presentedSheet = .addPlace(collectionID: nil)
                    }

                    Button("Discover Nearby", systemImage: "location") {
                        router.presentedSheet = .nearbyDiscovery
                    }
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "No Forecast for This Date",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text(
                            "Choose another date or refresh to compare available forecasts."
                        )
                    )
                }
            }
        } else {
            Section {
                ForEach(Array(recommendations.prefix(5).enumerated()), id: \.element.id) {
                    index,
                    recommendation in
                    recommendationLink(
                        recommendation,
                        rank: index + 1
                    )
                }
            } header: {
                Label {
                    Text("Best sunny places")
                } icon: {
                    Image(systemName: "sun.max.fill")
                        .foregroundStyle(theme.colors.sunIconColor)
                }
            }

            if recommendations.count > 5 && !savedPlaceIDs.isEmpty {
                Section {
                    Button("View Saved Places", systemImage: "list.bullet") {
                        router.showPlaces()
                    }
                }
            }
        }
    }

    /// Keeps discovery controls contextual and makes the population-first method
    /// visible without turning Home into a filter dashboard.
    private var nearbyDiscoverySection: some View {
        Section {
            if model.isNearbyDiscoveryEnabled
                && model.locationProvider.hasUsableCoordinate {
                LabeledContent("Search Radius") {
                    Text(
                        model.nearbyPreferences.radius.measurement,
                        format: .measurement(width: .abbreviated)
                    )
                }

                LabeledContent("Candidate Cities") {
                    if model.isRefreshingNearby {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Finding nearby cities")
                    } else {
                        Text(model.nearbyCandidates.count, format: .number)
                    }
                }

                Button("Change Nearby Discovery", systemImage: "map") {
                    router.presentedSheet = .nearbyDiscovery
                }
            } else if model.isNearbyDiscoveryEnabled {
                Button("Set Up Nearby Discovery", systemImage: "location") {
                    router.presentedSheet = .nearbyDiscovery
                }
            } else {
                Button("Enable Nearby Recommendations", systemImage: "location") {
                    router.presentedSheet = .nearbyDiscovery
                }
            }
        } header: {
            Text("Nearby")
        } footer: {
            Text(
                "Weather Atlas checks up to ten of the most populated cities in your chosen area, then recommends the sunniest."
            )
        }
    }

    /// Uses a normal NavigationLink and native swipe action for discovered rows.
    private func recommendationLink(
        _ recommendation: PlaceRecommendation,
        rank: Int
    ) -> some View {
        NavigationLink(
            value: AppRoute.place(
                id: recommendation.id,
                date: selectedDate
            )
        ) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rank \(rank)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        recommendationRow(recommendation)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(rank, format: .number)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .trailing)
                            .accessibilityLabel("Rank \(rank)")

                        recommendationRow(recommendation)
                    }
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !savedPlaceIDs.contains(recommendation.id) {
                Button("Save", systemImage: "bookmark") {
                    save(recommendation)
                }
                .tint(.accentColor)
            }
        }
    }

    private func recommendationRow(
        _ recommendation: PlaceRecommendation
    ) -> some View {
        PlaceRecommendationRow(
            recommendation: recommendation,
            displayName: model.placesStore.place(id: recommendation.id)?
                .displayName
        )
    }

    private var dateChoices: [Date] {
        guard !model.availableForecastDates.isEmpty else {
            return Self.fallbackDates
        }
        return model.availableForecastDates
    }

    private var nearbyErrorIsPresented: Binding<Bool> {
        Binding(
            get: { model.nearbyDiscoveryError != nil },
            set: { isPresented in
                if !isPresented {
                    model.clearNearbyDiscoveryError()
                }
            }
        )
    }

    private var saveErrorIsPresented: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    saveErrorMessage = nil
                }
            }
        )
    }

    private func normalizeSelectedDate() {
        guard !dateChoices.contains(where: {
            Calendar.current.isDate($0, inSameDayAs: selectedDate)
        }) else {
            return
        }
        selectedDate = dateChoices.first ?? selectedDate
    }

    private func save(_ recommendation: PlaceRecommendation) {
        do {
            recentlySavedPlaceID = try model.saveRecommendation(recommendation)
        } catch {
            saveErrorMessage = localizedPlacesErrorDescription(
                error,
                locale: locale
            )
        }
    }

    /// Upcoming fallback horizon shown before the first forecast response.
    private static var fallbackDates: [Date] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return (0..<10).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }
}
