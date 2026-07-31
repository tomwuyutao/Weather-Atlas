//
//  PlaceDetailView.swift
//  Weather
//
//  Purpose: Presents a recommendation-first native place report reached from
//  either Home or Places, with optional save and collection actions.
//

import SwiftUI

/// Shared value-routed report for saved and discovered places.
struct PlaceDetailView: View {
    /// Stable identity carried by AppRoute rather than a replaceable snapshot.
    let placeID: City.ID
    /// Root domain model used to resolve the latest place and forecast values.
    let model: WeatherAtlasModel
    /// Active-tab navigation coordinator.
    @Bindable var router: AppRouter

    @State private var selectedDate: Date
    @State private var showingDeleteConfirmation = false
    @State private var mutationError: PlaceDetailMutationError?

    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue

    init(
        placeID: City.ID,
        initialDate: Date,
        model: WeatherAtlasModel,
        router: AppRouter
    ) {
        self.placeID = placeID
        self.model = model
        self.router = router
        _selectedDate = State(
            initialValue: Calendar.current.startOfDay(for: initialDate)
        )
    }

    private var savedPlace: SavedPlace? {
        model.placesStore.place(id: placeID)
    }

    private var city: City? {
        savedPlace?.city
            ?? model.nearbyCities.first(where: { $0.id == placeID })
    }

    private var cityWeather: CityWeather? {
        model.weatherStore.weather(for: placeID)
    }

    private var forecast: DailyForecast? {
        cityWeather?.forecastIfAvailable(on: selectedDate)
    }

    private var recommendation: PlaceRecommendation? {
        guard let cityWeather else { return nil }
        return RecommendationEngine.recommendation(
            for: cityWeather,
            on: selectedDate,
            source: savedPlace == nil ? .nearby : .saved
        )
    }

    private var displayName: String {
        savedPlace?.displayName
            ?? city?.localizedName(locale: locale)
            ?? localizedString("Place", locale: locale)
    }

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic
    }

    var body: some View {
        Group {
            if let cityWeather {
                detailList(cityWeather)
            } else if let city {
                ContentUnavailableView {
                    Label("Loading Forecast", systemImage: "sun.max")
                } description: {
                    Text("Weather Atlas is preparing the forecast for \(displayName).")
                } actions: {
                    if model.weatherStore.isLoading(city.id) {
                        ProgressView()
                    } else {
                        Button("Try Again", systemImage: "arrow.clockwise") {
                            Task {
                                await model.weatherStore.refresh(
                                    city: city,
                                    locale: locale
                                )
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Place Not Found",
                    systemImage: "mappin.slash",
                    description: Text(
                        "This place is no longer available in your library or nearby results."
                    )
                )
            }
        }
        .weatherAtlasScreenBackground()
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                placeActionsMenu
            }
        }
        .task(id: placeID) {
            guard let city,
                  model.weatherStore.weather(for: placeID) == nil else {
                normalizeSelectedDate()
                return
            }
            await model.weatherStore.refresh(city: city, locale: locale)
            normalizeSelectedDate()
        }
        .confirmationDialog(
            "Delete \(displayName)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Place", role: .destructive) {
                deleteSavedPlace()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The place will also be removed from every collection.")
        }
        .alert(
            "Places",
            isPresented: mutationErrorIsPresented,
            presenting: mutationError
        ) { _ in
            Button("OK") {
                mutationError = nil
            }
        } message: { error in
            Text(error.message)
        }
    }

    /// Uses a standard inset-grouped List so typography, selection, contrast,
    /// and Dynamic Type behavior remain system-owned.
    private func detailList(_ cityWeather: CityWeather) -> some View {
        List {
            Section {
                ForecastDateStrip(
                    selection: $selectedDate,
                    availableDates: availableDates(for: cityWeather)
                )
                .listRowInsets(
                    EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
                )
            }

            if let recommendation {
                verdictSection(recommendation)
                reasonSection(recommendation)
            }

            if let forecast {
                Section("Forecast Details") {
                    DetailMetricGrid(
                        city: cityWeather,
                        forecast: forecast,
                        temperatureUnit: temperatureUnit,
                        usesLandscapeIPadLayout: false,
                        selectedForecastDate: $selectedDate
                    )
                    .padding(.vertical, 4)
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "No Forecast for This Date",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Choose another available date.")
                    )
                }
            }

            if let attribution = model.weatherStore.weatherAttribution {
                Section {
                    WeatherAttributionView(attribution: attribution)
                }
            }
        }
        .listStyle(.insetGrouped)
        .weatherAtlasScrollableBackground()
        .refreshable {
            guard let city else { return }
            await model.weatherStore.refresh(city: city, locale: locale)
        }
    }

    /// Plain-language result appears before individual weather metrics.
    private func verdictSection(
        _ recommendation: PlaceRecommendation
    ) -> some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 5) {
                    Text(verdictTitle(for: recommendation))
                        .font(.headline)
                    Text(verdictDescription(for: recommendation))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: recommendation.condition.displayIcon)
                    .weatherIconStyle(for: recommendation.condition.displayIcon)
            }

            if let range = recommendation.bestSunnyWindow {
                LabeledContent("Best Sunny Window") {
                    Text(sunnyWindowLabel(range))
                        .fontWeight(.semibold)
                }
            }
        }
    }

    /// Source-backed factors explain the ranking without a hidden score.
    private func reasonSection(
        _ recommendation: PlaceRecommendation
    ) -> some View {
        Section("Why this is recommended") {
            LabeledContent("Sunny Hours") {
                Text(recommendation.sunnyHourCount, format: .number)
            }

            LabeledContent("Cloud Cover") {
                Text(
                    recommendation.cloudCover,
                    format: .percent.precision(.fractionLength(0))
                )
            }

            if let rainChance = recommendation.precipitationChance {
                LabeledContent("Rain Chance") {
                    Text(
                        rainChance,
                        format: .percent.precision(.fractionLength(0))
                    )
                }
            }

            LabeledContent("Temperature") {
                Text(
                    "\(temperatureUnit.display(recommendation.forecast.dailyLow))–\(temperatureUnit.display(recommendation.forecast.dailyHigh))"
                )
            }
        }
    }

    /// Native menu adapts between Save and many-to-many collection management.
    @ViewBuilder
    private var placeActionsMenu: some View {
        if savedPlace == nil {
            Button("Save Place", systemImage: "bookmark") {
                savePlace()
            }
        } else {
            Menu("Place Actions", systemImage: "ellipsis") {
                if !model.placesStore.collections.isEmpty {
                    Section("Collections") {
                        ForEach(model.placesStore.collections) { collection in
                            Toggle(
                                collection.name,
                                isOn: collectionMembershipBinding(collection.id)
                            )
                        }
                    }
                }

                Button("Delete Place", systemImage: "trash", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
    }

    private func collectionMembershipBinding(
        _ collectionID: PlaceCollection.ID
    ) -> Binding<Bool> {
        Binding(
            get: {
                model.placesStore.collections(containing: placeID)
                    .contains { $0.id == collectionID }
            },
            set: { isMember in
                do {
                    try model.placesStore.setMembership(
                        of: placeID,
                        in: collectionID,
                        isMember: isMember
                    )
                } catch {
                    mutationError = PlaceDetailMutationError(
                        message: localizedPlacesErrorDescription(
                            error,
                            locale: locale
                        )
                    )
                }
            }
        )
    }

    private var mutationErrorIsPresented: Binding<Bool> {
        Binding(
            get: { mutationError != nil },
            set: { isPresented in
                if !isPresented {
                    mutationError = nil
                }
            }
        )
    }

    private func verdictTitle(
        for recommendation: PlaceRecommendation
    ) -> String {
        switch recommendation.conditionGroup {
        case .sunny:
            return localizedString("Excellent for a sunny day", locale: locale)
        case .partlySunny:
            return localizedString("A good sunny option", locale: locale)
        case .mixed:
            return localizedString("Conditions are mixed", locale: locale)
        case .wet:
            return localizedString("Rain may limit this plan", locale: locale)
        }
    }

    private func verdictDescription(
        for recommendation: PlaceRecommendation
    ) -> String {
        if recommendation.sunnyHourCount > 0 {
            return localizedString(
                "\(recommendation.sunnyHourCount) expected sunny hours with \(Int((recommendation.cloudCover * 100).rounded()))% cloud cover.",
                locale: locale
            )
        }
        return recommendation.condition.localizedDisplayName(locale: locale)
    }

    private func sunnyWindowLabel(_ range: ClosedRange<Int>) -> String {
        let start = SunninessScoring.compactHourLabel(range.lowerBound, locale: locale)
        let end = SunninessScoring.compactHourLabel(range.upperBound + 1, locale: locale)
        return localizedString("\(start)–\(end)", locale: locale)
    }

    private func availableDates(for weather: CityWeather) -> [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return weather.dailyForecasts.compactMap {
            weather.selectionDate(for: $0)
        }
        .filter { $0 >= today }
    }

    private func normalizeSelectedDate() {
        guard let cityWeather else { return }
        let dates = availableDates(for: cityWeather)
        guard !dates.contains(where: {
            Calendar.current.isDate($0, inSameDayAs: selectedDate)
        }), let firstDate = dates.first else {
            return
        }
        selectedDate = firstDate
    }

    private func savePlace() {
        guard let city else { return }
        do {
            _ = try model.placesStore.savePlace(city)
        } catch {
            mutationError = PlaceDetailMutationError(
                message: localizedPlacesErrorDescription(
                    error,
                    locale: locale
                )
            )
        }
    }

    private func deleteSavedPlace() {
        do {
            try model.placesStore.deletePlace(id: placeID)
            if router.selectedTab == .home {
                if !router.homePath.isEmpty {
                    router.homePath.removeLast()
                }
            } else if !router.placesPath.isEmpty {
                router.placesPath.removeLast()
            }
        } catch {
            mutationError = PlaceDetailMutationError(
                message: localizedPlacesErrorDescription(
                    error,
                    locale: locale
                )
            )
        }
    }
}

/// Item-driven native error presentation for persistence mutations.
private struct PlaceDetailMutationError: Identifiable {
    let id = UUID()
    let message: String
}
