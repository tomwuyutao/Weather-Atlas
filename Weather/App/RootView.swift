//
//  RootView.swift
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
    /// Reuses the former first-launch key so existing installs are not seeded
    /// again after starter places replaced setup.
    @AppStorage("hasLaunchedBefore") private var hasSeededStarterPlaces = false
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    /// Preserves the user's selected relative forecast day when location
    /// metadata changes the app-wide calendar from the device to local time.
    @State private var selectedDateTimeZone = TimeZone.autoupdatingCurrent
    @State private var externalRouteMessage: ExternalRouteMessage?
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
                NavigationStack(path: $router.searchPath) {
                    PlaceSearchView(
                        model: model,
                        router: router
                    )
                    .navigationTitle("Search")
                    .navigationBarTitleDisplayMode(.large)
                    .navigationDestination(for: AppRoute.self) {
                        destination(for: $0)
                    }
                }
            }
        }
        .environment(\.calendar, model.forecastCalendar)
        .onChange(of: model.currentLocationTimeZone.identifier) { _, identifier in
            guard let newTimeZone = TimeZone(identifier: identifier),
                  newTimeZone != selectedDateTimeZone else {
                return
            }
            rebaseSelectedDate(from: selectedDateTimeZone, to: newTimeZone)
            selectedDateTimeZone = newTimeZone
        }
        .id(appResetID)
        .sheet(item: $router.presentedSheet) { destination in
            sheet(for: destination)
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
            await seedStarterPlacesIfNeeded()
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

    /// Keeps “tomorrow” as tomorrow when the current location resolves to a
    /// different time zone, rather than reinterpreting a device-midnight
    /// instant as a neighbouring local calendar day.
    private func rebaseSelectedDate(from oldTimeZone: TimeZone, to newTimeZone: TimeZone) {
        var oldCalendar = Calendar.autoupdatingCurrent
        oldCalendar.timeZone = oldTimeZone
        var newCalendar = Calendar.autoupdatingCurrent
        newCalendar.timeZone = newTimeZone
        let offset = oldCalendar.dateComponents(
            [.day],
            from: oldCalendar.startOfDay(for: Date()),
            to: oldCalendar.startOfDay(for: selectedDate)
        ).day ?? 0
        let newToday = newCalendar.startOfDay(for: Date())
        selectedDate = newCalendar.date(byAdding: .day, value: offset, to: newToday)
            ?? newToday
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
        case .settings:
            SettingsView(
                model: model,
                onResetApp: resetAppToStarterPlaces
            )
        }
    }

    /// Seeds a first-run library with a fixed, globally recognisable overview.
    /// Existing and intentionally emptied libraries are left untouched.
    private func seedStarterPlacesIfNeeded() async {
        guard !hasSeededStarterPlaces else { return }
        guard model.placesStore.loadErrorDescription == nil else { return }
        guard model.placesStore.allPlaces.isEmpty else {
            hasSeededStarterPlaces = true
            return
        }

        do {
            let cities = try await model.starterCities()
            guard !cities.isEmpty else { return }
            _ = try model.placesStore.savePlaces(cities)
            model.reconcileRetainedWeather()
            await model.weatherStore.load(cities: cities, locale: locale)
            model.publishWidgetCatalog(locale: locale)
            hasSeededStarterPlaces = true
        } catch {
            // Leave the flag unset so a transient catalog or persistence
            // failure can be retried when the app next becomes active.
        }
    }

    /// Clears user-owned state, then restores the fixed first-run overview.
    private func resetAppToStarterPlaces() throws {
        try model.placesStore.resetToEmptyLibrary()
        model.weatherStore.retainWeather(for: [])
        WidgetDataStore.removeAll()
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
        hasSeededStarterPlaces = false
        model.publishWidgetCatalog(locale: locale)
        router.presentedSheet = nil

        Task {
            await seedStarterPlacesIfNeeded()
        }
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

    /// Opens Places from a widget URL.
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
