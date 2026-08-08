//
//  Detail.swift
//  Weather
//
//  Purpose: Presents the shared card-based Saved Place report.
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

    /// App-wide forecast day controlled by the tab-bar date accessory.
    @Binding private var selectedDate: Date
    @State private var showingDeleteConfirmation = false
    @State private var mutationError: PlaceDetailMutationError?
    @State private var isDetailLargeTitleVisible = true

    @Environment(\.locale) private var locale
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue

    init(
        placeID: City.ID,
        selectedDate: Binding<Date>,
        model: WeatherAtlasModel,
        router: AppRouter
    ) {
        self.placeID = placeID
        self.model = model
        self.router = router
        _selectedDate = selectedDate
    }

    private var savedPlace: SavedPlace? {
        model.placesStore.place(id: placeID)
    }

    private var city: City? {
        model.city(for: placeID)
    }

    private var cityWeather: CityWeather? {
        model.weatherStore.weather(for: placeID)
    }

    private var forecast: DailyForecast? {
        cityWeather?.forecastIfAvailable(
            on: selectedDate,
            selectionCalendar: model.forecastCalendar
        )
    }

    private var displayName: String {
        savedPlace?.displayName
            ?? city?.displayName
            ?? localizedString("Place", locale: locale)
    }

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .systemDefault
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
                        "This place is no longer available in your library or recommendations."
                    )
                )
            }
        }
        .weatherAtlasScreenBackground()
        // Keep the city in the navigation item for native back history while
        // suppressing its principal rendering until the in-content title has
        // scrolled away.
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isDetailLargeTitleVisible {
                ToolbarItem(placement: .principal) {
                    Color.clear
                        .frame(width: 1, height: 1)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                placeActionsMenu
            }
            // Keep the date capsule in its own native toolbar group. The
            // spacer prevents iOS from clustering it with the More menu.
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                TopForecastDateSwitcher(
                    selection: $selectedDate,
                    availableDates: ForecastDateHorizon.dates(in: model.forecastCalendar)
                )
            }
        }
        .task(id: placeID) {
            isDetailLargeTitleVisible = true
            guard let city,
                  model.weatherStore.weather(for: placeID) == nil else {
                return
            }
            await model.weatherStore.refresh(city: city, locale: locale)
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
            Text("The place will be removed from Saved Places.")
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

    private func detailList(_ cityWeather: CityWeather) -> some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if let forecast {
                    detailHeader(forecast)

                    DetailMetricGrid(
                        city: cityWeather,
                        forecast: forecast,
                        temperatureUnit: temperatureUnit,
                        usesLandscapeIPadLayout: false,
                        selectedForecastDate: $selectedDate
                    )

                    SunnyHoursOverviewCard(
                        city: cityWeather,
                        selectedDate: $selectedDate
                    )
                } else {
                    ContentUnavailableView(
                        "No Forecast for This Date",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Choose another available date.")
                    )
                    .padding(WeatherCardLayout.padding)
                    .detailTranslucentCard(
                        colorScheme: colorScheme,
                        in: RoundedRectangle(
                            cornerRadius: WeatherCardLayout.cornerRadius,
                            style: .continuous
                        )
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(theme.colors.background)
        .refreshable {
            guard let city else { return }
            await model.weatherStore.refresh(city: city, locale: locale)
        }
    }

    private func detailHeader(_ forecast: DailyForecast) -> some View {
        let condition = SunninessScoring.condition(for: forecast)
        let icon = condition?.displayIcon ?? forecast.symbolName

        return VStack(spacing: 9) {
            Text(displayName)
                .font(.system(.largeTitle, design: .serif).weight(.bold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
                .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                    isDetailLargeTitleVisible = isVisible
                }

            if condition != nil {
                Image(systemName: icon)
                    .weatherIconStyle(for: icon)
                    .font(.system(size: 52, weight: .semibold))
                    .frame(width: 62, height: 58)
                    .padding(.vertical, 8)

                Text(
                    condition?.localizedDisplayName(locale: locale)
                        ?? localizedString("Forecast", locale: locale)
                )
                .font(.callout)
                .foregroundStyle(theme.colors.primaryText)
                .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    /// Native menu presents the one-level Saved Places actions.
    @ViewBuilder
    private var placeActionsMenu: some View {
        if savedPlace == nil {
            Button("Save Place", systemImage: "bookmark") {
                savePlace()
            }
        } else {
            Menu("Place Actions", systemImage: "ellipsis") {
                Button("Delete Place", systemImage: "trash", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
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
            switch router.selectedTab {
            case .home:
                if !router.homePath.isEmpty {
                    router.homePath.removeLast()
                }
            case .map:
                router.selectedMapPlaceID = nil
                if !router.mapPath.isEmpty {
                    router.mapPath.removeLast()
                }
            case .places:
                if !router.placesPath.isEmpty {
                    router.placesPath.removeLast()
                }
            case .search:
                break
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
