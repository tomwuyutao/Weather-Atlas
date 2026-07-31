//
//  WeatherAtlasRootView.swift
//  Weather
//
//  Purpose: Defines the native two-tab shell with a dedicated system search
//  role, independent navigation histories, shared routes, modal destinations,
//  quick actions, and widget deep links.
//

import SwiftUI

/// Native app shell with Home recommendations and the Places library.
struct WeatherAtlasRootView: View {
    @Bindable var model: WeatherAtlasModel
    @Bindable var router: AppRouter

    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var externalRouteMessage: ExternalRouteMessage?

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Home", systemImage: "sun.max", value: AppTab.home) {
                NavigationStack(path: $router.homePath) {
                    HomeTabView(
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
                    PlacesTabView(
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
                        placesStore: model.placesStore,
                        weatherStore: model.weatherStore
                    ) { _ in
                        router.searchPath = []
                        router.placesPath = []
                        router.showPlaces(mode: .list)
                    }
                    .navigationTitle("Search")
                    .navigationBarTitleDisplayMode(.large)
                    .navigationDestination(for: AppRoute.self) {
                        destination(for: $0)
                    }
                }
            }
        }
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
            await model.loadSavedWeather(locale: locale)
            model.publishWidgetCatalog(locale: locale)
            if model.isNearbyDiscoveryEnabled {
                model.locationProvider.requestCurrentLocationIfAuthorized(
                    preferredLocale: locale
                )
            }
            handlePendingHomeScreenShortcut()
        }
        .task(id: locale.identifier) {
            AppDelegate.updateHomeScreenShortcuts()
            model.publishWidgetCatalog(locale: locale)
        }
        .onChange(of: model.placesStore.document) {
            model.reconcileRetainedWeather()
            model.publishWidgetCatalog(locale: locale)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            handlePendingHomeScreenShortcut()
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
        case let .place(id, date):
            PlaceDetailView(
                placeID: id,
                initialDate: date,
                model: model,
                router: router
            )
        case .collections:
            ManageCollectionsView(placesStore: model.placesStore)
        }
    }

    /// One item-driven sheet switch owns every root modal workflow.
    @ViewBuilder
    private func sheet(for destination: AppSheetDestination) -> some View {
        switch destination {
        case .addPlace(let collectionID):
            AddPlaceSheet(
                placesStore: model.placesStore,
                weatherStore: model.weatherStore,
                targetCollectionID: collectionID
            )
        case .createCollection(let placeID):
            CreateCollectionSheet(
                placesStore: model.placesStore,
                placeID: placeID
            )
        case .nearbyDiscovery:
            NearbyDiscoverySettingsSheet(
                preferences: $model.nearbyPreferences,
                isEnabled: $model.isNearbyDiscoveryEnabled,
                locationProvider: model.locationProvider
            )
            .onDisappear {
                Task {
                    await model.refreshNearbyRecommendations(locale: locale)
                    normalizeSelectedDate()
                }
            }
        case .settings:
            NativeSettingsView(model: model)
        }
    }

    private func handlePendingHomeScreenShortcut() {
        guard let destination = AppDelegate.takePendingHomeScreenShortcut() else {
            return
        }
        handleHomeScreenShortcut(destination)
    }

    /// Keeps existing Home/Map/List quick actions useful in the two-tab model.
    private func handleHomeScreenShortcut(
        _ destination: HomeScreenShortcutDestination
    ) {
        selectedDate = Calendar.current.startOfDay(for: Date())
        router.presentedSheet = nil

        switch destination {
        case .home:
            router.homePath = []
            router.selectedTab = .home
        case .map:
            router.placesPath = []
            router.showPlaces(mode: .map)
        case .list:
            router.placesPath = []
            router.showPlaces(mode: .list)
        }
    }

    /// Preserves installed widget URLs by mapping old list IDs to migrated
    /// collection IDs, with All Places as the new default scope.
    private func handleExternalURL(_ url: URL) {
        guard url.scheme == "weatheratlas" else { return }

        if url.host == "list",
           let rawValue = url.pathComponents.dropFirst().first,
           !rawValue.isEmpty {
            let collectionID: PlaceCollection.ID?
            if rawValue == "all-places" {
                collectionID = nil
            } else if model.placesStore.collections.contains(
                where: { $0.id == rawValue }
            ) {
                collectionID = rawValue
            } else {
                collectionID = nil
            }
            router.placesPath = []
            router.showPlaces(mode: .list, collectionID: collectionID)
            presentWidgetIssueIfNeeded(url)
            return
        }

        switch url.host {
        case "home":
            handleHomeScreenShortcut(.home)
        case "map":
            handleHomeScreenShortcut(.map)
        case "places":
            handleHomeScreenShortcut(.list)
        default:
            break
        }
    }

    /// Keeps precise widget diagnostics visible without coupling them to the
    /// legacy ContentView warning queue.
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

    private func normalizeSelectedDate() {
        let dates = model.availableForecastDates
        guard !dates.isEmpty,
              !dates.contains(where: {
                  Calendar.current.isDate($0, inSameDayAs: selectedDate)
              }) else {
            return
        }
        selectedDate = dates[0]
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
