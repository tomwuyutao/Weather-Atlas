//
//  WeatherAtlasRootView.swift
//  Weather
//
//  Purpose: Defines the native Home, Map, and Places tab shell with a dedicated
//  system search role, independent navigation histories, shared routes, modal
//  destinations, quick actions, and widget deep links.
//

import SwiftUI

/// Native app shell with Home recommendations, immersive Map, and Places.
struct WeatherAtlasRootView: View {
    @Bindable var model: WeatherAtlasModel
    @Bindable var router: AppRouter

    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appTheme) private var theme
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var externalRouteMessage: ExternalRouteMessage?
    @State private var presentedTutorial: WeatherAtlasTutorialMode?
    @State private var deferredTutorial: WeatherAtlasTutorialMode?
    @State private var startingCityImportIDs: Set<SavedPlace.ID> = []
    @State private var appResetID = UUID()

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Home", systemImage: "sun.max", value: AppTab.home) {
                NavigationStack(path: $router.homePath) {
                    HomeView(
                        model: model,
                        router: router,
                        selectedDate: $selectedDate
                    )
                    .navigationDestination(for: AppRoute.self) {
                        destination(for: $0)
                    }
                }
            }

            Tab("Map", systemImage: "map", value: AppTab.map) {
                NavigationStack(path: $router.mapPath) {
                    MapView(
                        model: model,
                        router: router,
                        selectedDate: $selectedDate
                    )
                    .navigationDestination(for: AppRoute.self) {
                        destination(for: $0)
                    }
                }
            }

            Tab("Places", systemImage: "mappin.and.ellipse", value: AppTab.places) {
                NavigationStack(path: $router.placesPath) {
                    PlacesView(
                        placesStore: model.placesStore,
                        weatherStore: model.weatherStore,
                        router: router,
                        selectedDate: $selectedDate
                    )
                    .navigationDestination(for: AppRoute.self) {
                        destination(for: $0)
                    }
                }
            }

            Tab(
                "Search",
                systemImage: "magnifyingglass",
                value: AppTab.search,
                role: .search
            ) {
                NavigationStack {
                    PlaceSearchView(
                        placesStore: model.placesStore,
                        weatherStore: model.weatherStore
                    ) { _ in
                        router.placesPath = []
                        router.showPlaces()
                    }
                    .navigationTitle("Search")
                    .navigationBarTitleDisplayMode(.large)
                }
            }
        }
        .id(appResetID)
        .sheet(
            item: $router.presentedSheet,
            onDismiss: presentDeferredTutorialIfNeeded
        ) { destination in
            sheet(for: destination)
        }
        .fullScreenCover(
            item: $presentedTutorial,
            onDismiss: { startingCityImportIDs = [] }
        ) { mode in
            WeatherAtlasTutorialView(
                mode: mode,
                importProgress: startingCityImportProgress,
                onAddStartingCities: importStartingCities,
                onFinish: finishTutorial
            )
        }
        .alert(
            externalRouteMessage?.title ?? "",
            isPresented: externalRouteMessageIsPresented,
            presenting: externalRouteMessage
        ) { _ in
            Button("OK") {
                externalRouteMessage = nil
            }
        } message: { message in
            Text(message.message)
        }
        .task {
            if !hasLaunchedBefore, presentedTutorial == nil {
                presentedTutorial = .firstLaunch
            }
            model.reconcileRetainedWeather()
            await model.loadSavedWeather(locale: locale)
            model.publishWidgetCatalog(locale: locale)
            model.locationProvider.requestCurrentLocationIfAuthorized(
                preferredLocale: locale
            )
            handlePendingHomeScreenShortcut()
        }
        .task(id: locale.identifier) {
            AppDelegate.updateHomeScreenShortcuts()
            model.publishWidgetCatalog(locale: locale)
            model.locationProvider.requestCurrentLocationIfAuthorized(
                preferredLocale: locale
            )
        }
        .onChange(of: model.placesStore.document) {
            model.reconcileRetainedWeather()
            model.publishWidgetCatalog(locale: locale)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            handlePendingHomeScreenShortcut()
            model.locationProvider.requestCurrentLocationIfAuthorized(
                preferredLocale: locale
            )
            Task {
                await model.loadSavedWeather(locale: locale)
                model.publishWidgetCatalog(locale: locale)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .weatherOpenMainViewShortcut
            )
        ) { notification in
            let notifiedDestination = (notification.object as? String)
                .flatMap(HomeScreenShortcutDestination.init(rawValue:))
            if let destination = AppDelegate.takePendingHomeScreenShortcut()
                ?? notifiedDestination {
                handleHomeScreenShortcut(destination)
            }
        }
        .onOpenURL(perform: handleExternalURL)
        .environment(model)
        .environment(model.placesStore)
        .environment(model.weatherStore)
        .environment(model.locationProvider)
    }

    /// Registers the same value destinations in each tab's independent stack.
    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case let .place(id):
            PlaceDetailView(
                placeID: id,
                selectedDate: $selectedDate,
                model: model,
                router: router
            )
        }
    }

    /// One item-driven sheet switch owns every root modal workflow.
    @ViewBuilder
    private func sheet(for destination: AppSheetDestination) -> some View {
        switch destination {
        case .addPlaces:
            AddPlacesSheet(placesStore: model.placesStore)
        case .settings:
            SettingsView(
                model: model,
                onReplayTutorial: deferTutorialUntilSettingsDismisses,
                onResetApp: resetAppToFirstLaunch
            )
        }
    }

    /// Dismisses Settings before replaying the root-owned tutorial.
    private func deferTutorialUntilSettingsDismisses() {
        deferredTutorial = .replay
        router.presentedSheet = nil
    }

    /// Presents a deferred full-screen tutorial after the sheet is fully gone.
    private func presentDeferredTutorialIfNeeded() {
        guard let tutorial = deferredTutorial else { return }
        deferredTutorial = nil
        presentedTutorial = tutorial
    }

    /// Adds one geographic preset directly to Saved Places, then prepares its
    /// forecasts before first-run onboarding completes.
    private func importStartingCities(_ cities: [City]) async throws {
        let savedIDs = try model.placesStore.savePlaces(cities)
        startingCityImportIDs = Set(savedIDs)
        model.reconcileRetainedWeather()
        let importedCities = savedIDs.compactMap {
            model.placesStore.place(id: $0)?.city
        }
        await model.weatherStore.load(cities: importedCities, locale: locale)
        model.publishWidgetCatalog(locale: locale)
    }

    /// Persists tutorial completion only after any starting-city import has
    /// finished successfully.
    private func finishTutorial() {
        hasLaunchedBefore = true
        presentedTutorial = nil
    }

    /// Reports completed or terminal forecast requests for the imported set.
    private var startingCityImportProgress: Double {
        guard !startingCityImportIDs.isEmpty else { return 0 }
        let completedCount = startingCityImportIDs.reduce(into: 0) {
            completedCount, placeID in
            if !model.weatherStore.isLoading(placeID)
                && (model.weatherStore.weather(for: placeID) != nil
                    || model.weatherStore.failuresByPlaceID[placeID] != nil) {
                completedCount += 1
            }
        }
        return Double(completedCount) / Double(startingCityImportIDs.count)
    }

    /// Clears user-owned state and transient UI, then restarts first-run setup.
    private func resetAppToFirstLaunch() throws {
        try model.placesStore.resetToEmptyLibrary()
        model.weatherStore.retainWeather(for: [])
        WidgetDataStore.removeAll()
        model.nearestSunnySearchRadius = .kilometers100
        model.resetHomeWeatherState()

        let defaults = UserDefaults.standard
        defaults.set(
            TemperatureUnit.defaultRawValue,
            forKey: "temperatureUnit"
        )
        defaults.set(DistanceUnit.defaultRawValue, forKey: "distanceUnit")
        defaults.set("en", forKey: AppLanguageDefaults.storageKey)
        defaults.set(true, forKey: "useSystemTextSize")
        defaults.set(
            AppTextSizeLevel.defaultRawValue,
            forKey: "appTextSizeLevel"
        )
        defaults.set(true, forKey: "showLegend")
        theme.style = .automatic

        selectedDate = Calendar.current.startOfDay(for: Date())
        router.homePath = []
        router.mapPath = []
        router.placesPath = []
        router.selectedMapPlaceID = nil
        router.selectedTab = .home
        appResetID = UUID()
        hasLaunchedBefore = false
        startingCityImportIDs = []
        model.publishWidgetCatalog(locale: locale)

        deferredTutorial = .firstLaunch
        router.presentedSheet = nil
    }

    private func handlePendingHomeScreenShortcut() {
        guard let destination = AppDelegate.takePendingHomeScreenShortcut() else {
            return
        }
        handleHomeScreenShortcut(destination)
    }

    /// Maps Home, Map, and Places quick actions to their native tabs.
    private func handleHomeScreenShortcut(
        _ destination: HomeScreenShortcutDestination
    ) {
        router.presentedSheet = nil

        switch destination {
        case .home:
            router.homePath = []
            router.selectedTab = .home
        case .map:
            router.mapPath = []
            router.showMap()
        case .places:
            router.placesPath = []
            router.showPlaces()
        }
    }

    /// Opens the Places scope encoded by a widget URL.
    private func handleExternalURL(_ url: URL) {
        guard url.scheme == "weatheratlas" else { return }

        if url.host == "places" {
            router.placesPath = []
            router.showPlaces()
            presentWidgetIssueIfNeeded(url)
            return
        }

        switch url.host {
        case "home":
            handleHomeScreenShortcut(.home)
        case "map":
            handleHomeScreenShortcut(.map)
        case "places":
            handleHomeScreenShortcut(.places)
        default:
            break
        }
    }

    /// Presents precise widget diagnostics without exposing internal developer
    /// logging to the user.
    private func presentWidgetIssueIfNeeded(_ url: URL) {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ),
        let kindValue = components.queryItems?
            .first(where: { $0.name == "missingKind" })?.value,
        let kind = WeatherDataIssue.Kind(rawValue: kindValue),
        let cityName = components.queryItems?
            .first(where: { $0.name == "city" })?.value else {
            return
        }

        let detail = components.queryItems?
            .first(where: { $0.name == "missingDetail" })?.value
        let issue = WeatherDataIssue(kind: kind, detail: detail)
        externalRouteMessage = ExternalRouteMessage(
            title: localizedString("Weather Data Unavailable", locale: locale),
            message: weatherDataIssueMessage(
                issue,
                cityName: cityName,
                locale: locale
            )
        )
    }

    private var externalRouteMessageIsPresented: Binding<Bool> {
        Binding(
            get: { externalRouteMessage != nil },
            set: { isPresented in
                if !isPresented {
                    externalRouteMessage = nil
                }
            }
        )
    }
}

private struct ExternalRouteMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
