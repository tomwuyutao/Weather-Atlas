//
//  ContentView.swift
//  Weather
//
//  Purpose: Defines the native Your Location, Saved Places, and Map tab shell
//  with a dedicated system search role, independent navigation histories,
//  shared routes, modal destinations, quick actions, and widget deep links.
//

import CoreLocation
import SwiftUI

/// Native app shell with local weather, saved-place planning, and an immersive Map.
struct ContentView: View {
    // MARK: - Shared Dependencies

    let model: WeatherModel
    @Bindable var router: AppNavigation
    let missingDataAlerts: MissingDataAlertCenter
    let networkConnectivity: NetworkConnectivity
    /// App-level state for first-run gating, replay, and contextual tips.
    let tutorial: TutorialPresentationState
    // MARK: - Environment and View-Owned State

    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appTheme) private var theme
    /// The root app policy has already capped this to the app's selectable
    /// Small...Large range. Publishing changes keeps WidgetKit typography in
    /// lockstep when Follow System is enabled.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Reuses the former first-launch key so existing installs are not seeded
    /// again after starter places replaced setup.
    @AppStorage("hasLaunchedBefore") private var didSeedPlaces = false
    /// One selected day is intentionally shared across all tabs and pushed
    /// reports, making the date control feel global rather than per-screen.
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    /// Invalidates any starter-place task that outlives a full reset. A reset
    /// must never persist the initial library before onboarding establishes its
    /// new location.
    @State private var starterSeedGeneration = 0
    /// Deep links can arrive while first-run education owns the root view.
    /// Keep the latest supported intent until the app shell is available.
    @State private var pendingExternalURL: URL?

    // MARK: - Tab Shell

    var body: some View {
        Group {
            if tutorial.shouldPresent {
                TutorialFlow(
                    model: model,
                    complete: completeTutorial
                )
            } else {
                appShell
            }
        }
        .environment(model)
        .environment(model.placesStore)
        .environment(model.weatherStore)
        .environment(model.locationProvider)
        .onOpenURL(perform: receiveExternalURL)
    }

    private var appShell: some View {
        tabShell
            // Forecast APIs and date formatting use the resolved current-location
            // calendar, so dates stay anchored to the place being forecast.
            .environment(\.calendar, model.forecastCalendar)
            // One root overlay keeps save feedback centered and visually
            // identical across every tab, pushed report, and Map card.
            .overlay {
                ZStack {
                    if let notification = currentSavedPlaceNotification {
                        SavedNotifications(notification: notification)
                            .id(notification.id)
                            .padding(.horizontal, 28)
                            .transition(
                                .scale(scale: 0.94)
                                    .combined(with: .opacity)
                            )
                            .allowsHitTesting(false)
                            .task(id: notification.id) {
                                do {
                                    try await Task.sleep(for: .milliseconds(2400))
                                } catch {
                                    return
                                }
                                model.placesStore.consumeSavedPlaceNotification(
                                    id: notification.id
                                )
                            }
                    }
                }
                // Limit the transition transaction to the popup so a saved
                // row's simultaneous insertion/removal does not also animate.
                .animation(
                    .smooth(duration: 0.24),
                    value: currentSavedPlaceNotification?.id
                )
            }
            .sheet(isPresented: $router.isSettingsPresented) {
                SettingsView(
                    model: model,
                    onResetApp: resetApp,
                    onReplayTutorial: {
                        tutorial.replay()
                        router.isSettingsPresented = false
                    }
                )
            }
            .alert(
                missingDataAlerts.currentAlert?.title ?? "",
                isPresented: showsMissingDataAlert,
                presenting: missingDataAlerts.currentAlert
            ) { _ in
                Button("OK") {}
            } message: { alert in
                Text(alert.message)
            }
            .task {
                await performInitialHydration()
            }
            .onChange(of: locale.identifier, initial: true) {
                AppDelegate.updateHomeScreenShortcuts()
                model.publishWidgetCatalog(locale: locale)
                model.locationProvider.requestLocationIfAuthorized(
                    preferredLocale: locale
                )
            }
            .onChange(of: model.placesStore.document, initial: true) {
                previousDocument, currentDocument in
                handlePlacesDocumentChange(
                    previous: previousDocument,
                    current: currentDocument
                )
            }
            // The Current Location entry is a stable widget configuration, but
            // its coordinate and locality are live. Republish that one small
            // contract whenever the app receives a new location or its weather
            // response supplies the authoritative city/timezone.
            .onChange(of: widgetCurrentLocationIdentity) {
                model.pruneIneligibleRecentCities()
                model.publishWidgetCatalog(locale: locale)
            }
            .onChange(of: dynamicTypeSize) {
                model.publishWidgetCatalog(locale: locale)
            }
            .onChange(of: model.isUsingHomeLocation) {
                // Home Screen copy must follow the same Current-versus-Home
                // location meaning as the in-app Map controls.
                AppDelegate.updateHomeScreenShortcuts()
            }
            .onChange(
                of: model.placesStore.loadErrorDescription,
                initial: true,
                handlePlacesLoadErrorChange
            )
            .onChange(
                of: networkConnectivity.status,
                handleConnectivityStatusChange
            )
            .onChange(of: scenePhase, handleScenePhaseChange)
            .onChange(of: router.selectedTab, initial: true) { _, newTab in
                tutorial.presentFeatureTipIfNeeded(
                    for: newTab,
                    hasActiveNativeAlert: missingDataAlerts.currentAlert != nil
                )
            }
            .onChange(of: missingDataAlerts.currentAlert) { _, alert in
                // A first-visit explanation should never appear behind a
                // native data alert. Recheck the current tab after that alert
                // is dismissed instead.
                guard alert == nil else { return }
                tutorial.presentFeatureTipIfNeeded(
                    for: router.selectedTab,
                    hasActiveNativeAlert: missingDataAlerts.currentAlert != nil
                )
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .weatherOpenMainViewShortcut
                )
            ) { notification in
                guard let rawValue = notification.object as? String,
                      let destination = HomeScreenShortcutDestination.decode(rawValue)
                else { return }
                handleShortcut(destination)
            }
    }

    private var tabShell: some View {
        TabView(selection: $router.selectedTab) {
            // Each visible tab owns a distinct navigation path. Returning to a
            // tab therefore restores its own back stack rather than another
            // tab's screen.
            Tab(
                "Location",
                systemImage: "location.fill",
                value: AppTab.yourLocation
            ) {
                NavigationStack(path: $router.yourLocationPath) {
                    screenWithOfflineBanner(YourLocationView(
                        model: model,
                        router: router,
                        selectedDate: $selectedDate
                    ))
                    .navigationDestination(for: AppRoute.self) {
                        destination(for: $0)
                    }
                }
            }

            Tab(
                "Saved",
                systemImage: "bookmark",
                value: AppTab.savedPlaces
            ) {
                NavigationStack(path: $router.savedPlacesPath) {
                    screenWithOfflineBanner(SavedPlacesView(
                        model: model,
                        router: router,
                        selectedDate: $selectedDate
                    ))
                    .navigationDestination(for: AppRoute.self) {
                        destination(for: $0)
                    }
                }
                .overlay {
                    TutorialFeatureTipOverlay(
                        tip: tutorial.activeFeatureTip,
                        tab: .savedPlaces,
                        isSelected: router.selectedTab == .savedPlaces,
                        dismiss: tutorial.dismissActiveFeatureTip
                    )
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
                .overlay {
                    TutorialFeatureTipOverlay(
                        tip: tutorial.activeFeatureTip,
                        tab: .map,
                        isSelected: router.selectedTab == .map,
                        dismiss: tutorial.dismissActiveFeatureTip
                    )
                }
            }

            Tab(
                "Search",
                systemImage: "magnifyingglass",
                value: AppTab.search,
                role: .search
            ) {
                NavigationStack(path: $router.searchPath) {
                    screenWithOfflineBanner(PlaceSearchView(
                        model: model,
                        router: router,
                        selectedDate: $selectedDate
                    ))
                    .navigationDestination(for: AppRoute.self) {
                        destination(for: $0)
                    }
                }
            }
        }
    }

    // MARK: - Shared Tab Adornments

    /// The store queues only successful user-initiated single-city mutations.
    /// Reading the head here keeps presentation state derived and centralized.
    private var currentSavedPlaceNotification: SavedPlaceNotification? {
        model.placesStore.pendingSavedPlaceNotifications.first
    }

    /// Non-map tabs lift the offline banner above the floating native tab bar.
    /// Map owns a separate bottom-surface layout and is intentionally excluded.
    @ViewBuilder
    private func screenWithOfflineBanner<Content: View>(
        _ content: Content
    ) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if networkConnectivity.isOffline,
               !networkConnectivity.isOfflineBannerDismissed {
                OfflineBanner(
                    lastUpdated: model.weatherStore.latestCachedWeatherDate,
                    dismiss: networkConnectivity.dismissOfflineBanner
                )
                .padding(.horizontal, 16)
                .padding(.bottom, MapCardLayout.bottomPadding)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// Equatable facts that change the widget's default-location identity,
    /// mode, or display name. Keeping it value-based avoids publishing on
    /// unrelated `WeatherModel` updates.
    private var widgetCurrentLocationIdentity: WidgetCurrentLocationIdentity {
        WidgetCurrentLocationIdentity(
            defaultLocationKind: model.isUsingHomeLocation
                ? .homeLocation
                : .currentLocation,
            latitude: model.locationProvider.coordinate?.latitude,
            longitude: model.locationProvider.coordinate?.longitude,
            metadata: model.locationProvider.metadata,
            weatherCityName: model.locationWeather?.city.name,
            weatherTimeZoneIdentifier: model.locationWeather?.timeZone.identifier
        )
    }

    // MARK: - Root Lifecycle

    /// Restores the saved library and its forecasts when the app shell appears.
    private func performInitialHydration() async {
        await seedStarterPlacesIfNeeded()
        guard !Task.isCancelled, !tutorial.shouldPresent else { return }

        model.retainWeatherScope()
        await model.loadSavedWeather()
        guard !Task.isCancelled, !tutorial.shouldPresent else { return }

        if model.isUsingHomeLocation {
            await model.ensureCurrentLocationWeather(locale: locale)
        }
    }

    /// Keeps transient forecast retention and cross-process widget metadata in
    /// step with the newly verified Saved Places document.
    private func handlePlacesDocumentChange(
        previous: PlacesLibraryDocument,
        current: PlacesLibraryDocument
    ) {
        // A place can be deleted from Map or another window while one tab still
        // owns its Detail route. Retain the removed city as session-only route
        // context before cache pruning makes that destination unresolvable.
        let currentIDs = Set(current.places.map(\.id))
        let removedCities = previous.places
            .filter { !currentIDs.contains($0.id) }
            .map(\.city)
        model.registerTransientCities(removedCities)
        model.pruneIneligibleRecentCities()
        model.publishWidgetCatalog(locale: locale)
    }

    private func handlePlacesLoadErrorChange(
        _ previousErrorDescription: String?,
        _ errorDescription: String?
    ) {
        let key = "places-library-load"
        if errorDescription != nil {
            let report = MissingDataAlertReport(
                key: key,
                title: localizedString("Data Missing", locale: locale),
                message: localizedString(
                    "Saved Places could not be loaded. Try again.",
                    locale: locale
                )
            )
            // A document read can fail transiently while iCloud or the app
            // group container is becoming available. Keep the library blank,
            // retry that exact read once, and alert only if it remains absent.
            Task {
                await missingDataAlerts.retryThenReport(
                    report,
                    recoveryKey: "places-library-load",
                    retry: {
                        model.placesStore.retryLoading()
                    },
                    isStillMissing: {
                        model.placesStore.loadErrorDescription != nil
                    }
                )
            }
        } else {
            missingDataAlerts.resolve(key: key)
            // A first-run store can become available only after its initial
            // load/retry episode. Resume normal starter seeding once that
            // recovery clears the storage error; existing libraries and
            // intentionally empty ones still exit through the seed guards.
            guard previousErrorDescription != nil else { return }
            Task {
                await seedStarterPlacesIfNeeded()
            }
        }
    }

    /// Initial evaluation and recovery can both make network work viable after
    /// an earlier hydration attempt deliberately preserved only cached data.
    private func handleConnectivityStatusChange(
        _ previousStatus: NetworkConnectivityStatus,
        _ status: NetworkConnectivityStatus
    ) {
        guard previousStatus != .available, status == .available else { return }
        Task {
            await refreshWeather(
                forceRefresh: previousStatus == .offline
            )
        }
    }

    /// On foregrounding, refreshes only data that may have become stale while
    /// the process was inactive.
    private func handleScenePhaseChange(
        _: ScenePhase,
        _ newPhase: ScenePhase
    ) {
        guard newPhase == .active else { return }
        model.locationProvider.requestLocationIfAuthorized(
            preferredLocale: locale
        )
        Task {
            await refreshWeather()
        }
    }

    /// Applies the app's common refresh policy to saved and current weather.
    private func refreshWeather(forceRefresh: Bool = false) async {
        await model.loadSavedWeather(forceRefresh: forceRefresh)
        if model.locationProvider.hasUsableCoordinate {
            await model.ensureCurrentLocationWeather(
                forceRefresh: forceRefresh,
                locale: locale
            )
        }
    }

    // MARK: - Date and Navigation Helpers

    /// Registers the same value destinations in each tab's independent stack.
    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case let .place(id):
            DetailView(
                placeID: id,
                selectedDate: $selectedDate,
                model: model,
                router: router
            )
        case .currentLocation:
            YourLocationView(
                model: model,
                router: router,
                selectedDate: $selectedDate
            )
        case .savedPlacesLibrary:
            ManageSavedPlaces(
                placesStore: model.placesStore,
                router: router
            )
        }
    }

    // MARK: - First-Run and Reset

    /// Seeds a first-run library with a fixed, globally recognisable overview.
    /// A starter city within 20 km of the location chosen during onboarding is
    /// omitted so that the library never duplicates the person's local area.
    /// Existing and intentionally emptied libraries are left untouched.
    private func seedStarterPlacesIfNeeded() async {
        let alertKey = "starter-places-seed"
        guard !tutorial.shouldPresent,
              !didSeedPlaces,
              model.placesStore.loadErrorDescription == nil else {
            return
        }
        guard model.placesStore.allPlaces.isEmpty else {
            didSeedPlaces = true
            return
        }
        let seedGeneration = starterSeedGeneration

        do {
            let starterCities = try await starterCitiesAfterOneCatalogRetry()
            guard isCurrentStarterSeed(seedGeneration),
                  model.placesStore.loadErrorDescription == nil,
                  model.placesStore.allPlaces.isEmpty else {
                return
            }
            let cities = starterCitiesExcludingInitialLocation(starterCities)
            guard !cities.isEmpty else { return }
            _ = try model.placesStore.savePlaces(cities)
            didSeedPlaces = true
            missingDataAlerts.resolve(key: alertKey)
        } catch {
            guard isCurrentStarterSeed(seedGeneration) else { return }

            let message: String
            switch error {
            case let issue as WeatherDataIssue:
                message = weatherDataIssueMessage(
                    issue,
                    cityName: localizedString("starter places", locale: locale),
                    locale: locale
                )
            case let catalogError as CitiesCatalogError:
                switch catalogError {
                case .missingStarterCities(let labels):
                    message = String(
                        format: localizedString(
                            "Starter place catalog data is missing for: %@.",
                            locale: locale
                        ),
                        locale: locale,
                        labels.joined(separator: ", ")
                    )
                default:
                    message = localizedString(
                        "Starter place catalog data is missing.",
                        locale: locale
                    )
                }
            default:
                message = localizedString(
                    "Starter place data is missing.",
                    locale: locale
                )
            }

            missingDataAlerts.report(
                key: alertKey,
                title: localizedString("Data Missing", locale: locale),
                message: message
            )
        }
    }

    /// A full reset or an in-progress onboarding transition invalidates a
    /// suspended seed task.
    private func isCurrentStarterSeed(_ seedGeneration: Int) -> Bool {
        !tutorial.shouldPresent
            && starterSeedGeneration == seedGeneration
            && !didSeedPlaces
    }

    /// Retries the bundled starter catalog once if its first parse fails.
    private func starterCitiesAfterOneCatalogRetry() async throws -> [City] {
        do {
            return try await model.starterCities()
        } catch is CitiesCatalogError {
            await model.citiesCatalog.reload()
            return try await model.starterCities()
        }
    }

    /// Avoids adding a starter city that duplicates the onboarding location.
    private func starterCitiesExcludingInitialLocation(
        _ cities: [City]
    ) -> [City] {
        let coordinate = model.homeLocation.map {
            CLLocationCoordinate2D(
                latitude: $0.latitude,
                longitude: $0.longitude
            )
        } ?? model.locationProvider.coordinate

        guard let coordinate,
              CLLocationCoordinate2DIsValid(coordinate) else {
            return cities
        }

        let initialLocation = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        return cities.filter { city in
            CLLocation(latitude: city.latitude, longitude: city.longitude)
                .distance(from: initialLocation) >= 20_000
        }
    }

    /// Clears app-owned state and returns to first-run onboarding.
    private func resetApp() throws {
        try model.placesStore.resetToEmptyLibrary()
        model.weatherStore.clearAllWeather()
        model.recentSearches.reset()
        WidgetDataStore.removeAll()
        model.resetLocation()
        missingDataAlerts.reset()
        starterSeedGeneration &+= 1
        AppPreferences.reset()
        theme.style = .automatic
        tutorial.resetForFullAppReset()

        selectedDate = Calendar.current.startOfDay(for: Date())
        pendingExternalURL = nil
        router.resetForFullAppReset()
        didSeedPlaces = false
        AppDelegate.updateHomeScreenShortcuts()
    }

    // MARK: - External Navigation

    private func completeTutorial() {
        tutorial.complete()

        guard let pendingExternalURL else {
            router.selectedTab = .yourLocation
            return
        }

        self.pendingExternalURL = nil
        handleExternalURL(pendingExternalURL)
    }

    /// Maps the current Home Screen quick actions into the existing tab and
    /// Find Sun routes through the existing tab and Map workflows.
    private func handleShortcut(
        _ destination: HomeScreenShortcutDestination
    ) {
        router.isSettingsPresented = false

        switch destination {
        case .findSunNearMe:
            router.showMap()
        case .map:
            router.showMap()
        case .places:
            router.showSavedPlacesRoot()
        }
    }

    /// Routes app and widget URLs to their native destination. Generic or stale
    /// Places/list URLs return to the dashboard; a valid city payload opens its
    /// forecast even when an old widget still uses the legacy `list` host.
    private func receiveExternalURL(_ url: URL) {
        guard url.scheme == "weatheratlas",
              ["place", "places", "list", "map"]
                .contains(url.host ?? "") else {
            return
        }

        guard tutorial.shouldPresent else {
            handleExternalURL(url)
            return
        }

        // If the system delivers several URLs before setup completes, the
        // most recent one represents the person's current navigation intent.
        pendingExternalURL = url
    }

    private func handleExternalURL(_ url: URL) {
        // Match Home Screen shortcuts: a URL should reveal its destination,
        // not navigate underneath an already presented Settings sheet.
        router.isSettingsPresented = false

        switch url.host {
        case "place", "list":
            openWidgetPlace(url)
        case "places":
            router.showSavedPlacesRoot()
            showWidgetIssue(url)
        case "map":
            handleShortcut(.map)
        default:
            break
        }
    }

    /// Opens a widget's configured Saved Place in the same Detail destination
    /// used by city rows. Current Location is not a saved-place route, so its
    /// widget correctly opens the Your Location report instead.
    private func openWidgetPlace(_ url: URL) {
        defer { showWidgetIssue(url) }

        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ),
        let cityIdentifier = components.queryItems?
            .first(where: { $0.name == "cityID" })?.value else {
            // A malformed or stale city widget should still leave the person at
            // the useful generic Places destination rather than doing nothing.
            router.showSavedPlacesRoot()
            return
        }

        if cityIdentifier == WidgetDataStore.currentLocationIdentifier {
            selectCurrentWidgetToday()
            router.yourLocationPath = []
            router.selectedTab = .yourLocation
            return
        }

        guard let savedPlace = savedPlace(forWidgetCityIdentifier: cityIdentifier) else {
            // The widget can outlive a delete or rename. The dashboard is the
            // useful safe fallback when its city no longer resolves in the
            // app's current library.
            router.showSavedPlacesRoot()
            return
        }

        selectWidgetDestinationToday(
            in: widgetTimeZone(for: savedPlace, identifier: cityIdentifier)
        )
        router.selectedTab = .savedPlaces
        router.savedPlacesPath = [.place(id: savedPlace.id)]
    }

    /// Resolves both UUID-backed widget identifiers and identifiers persisted
    /// by pre-migration App Intent configurations. The published catalog owns
    /// the alias mapping, while the final fallback supports a legacy deep link
    /// received before the catalog has been republished by this app version.
    private func savedPlace(forWidgetCityIdentifier identifier: String) -> SavedPlace? {
        if let savedPlaceID = WidgetDataStore.savedPlaceID(from: identifier),
           let place = model.placesStore.place(id: savedPlaceID) {
            return place
        }
        if let catalogCity = WidgetDataStore.catalog()?.cities.first(where: {
            $0.matchesWidgetIdentifier(identifier)
        }),
           let savedPlaceID = WidgetDataStore.savedPlaceID(from: catalogCity.id),
           let place = model.placesStore.place(id: savedPlaceID) {
            return place
        }
        return model.placesStore.allPlaces.first { place in
            WidgetDataStore.cityIdentifier(
                country: place.city.country,
                latitude: place.city.latitude,
                longitude: place.city.longitude
            ) == identifier
        }
    }

    /// Resets the shared selector before a Current/Home Location widget route.
    /// While location state is restoring, the published widget zone still
    /// supplies the correct local midnight for that navigation request.
    private func selectCurrentWidgetToday() {
        let destinationTimeZone = model.locationTimeZone
            ?? model.currentLocationPlaceCity?.timeZoneIdentifier.flatMap(
                TimeZone.init(identifier:)
            )
            ?? WidgetDataStore.catalog()?.currentLocation?.timeZoneIdentifier
                .flatMap(TimeZone.init(identifier:))
            ?? model.forecastCalendar.timeZone
        var destinationCalendar = model.forecastCalendar
        destinationCalendar.timeZone = destinationTimeZone
        selectedDate = destinationCalendar.startOfDay(for: .now)
    }

    /// Resets a Saved Place route to that city's local Today while retaining the
    /// shared selector's calendar representation used across the app's tabs.
    private func selectWidgetDestinationToday(in destinationTimeZone: TimeZone) {
        var destinationCalendar = model.forecastCalendar
        destinationCalendar.timeZone = destinationTimeZone
        let localToday = destinationCalendar.dateComponents(
            [.year, .month, .day],
            from: .now
        )
        let selectionCalendar = model.forecastCalendar
        guard let selectionDate = selectionCalendar.date(from: localToday) else {
            return
        }
        selectedDate = selectionCalendar.startOfDay(for: selectionDate)
    }

    /// Uses app weather first, then persisted city/catalog metadata, so both a
    /// healthy widget and its unavailable-state link resolve the same local day.
    private func widgetTimeZone(
        for savedPlace: SavedPlace,
        identifier: String
    ) -> TimeZone {
        model.weatherStore.weather(for: savedPlace.id)?.timeZone
            ?? savedPlace.city.timeZoneIdentifier.flatMap(
                TimeZone.init(identifier:)
            )
            ?? WidgetDataStore.catalog()?.cities.first {
                $0.matchesWidgetIdentifier(identifier)
            }?.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? model.forecastCalendar.timeZone
    }

    /// Recovers the Current/Home widget from the location-backed source rather
    /// than borrowing any Saved Place with a similar display name. A cold device-
    /// location launch waits briefly for the authorized one-shot request before
    /// retrying the current-coordinate forecast.
    private func retryCurrentWidgetWeather() async {
        if !model.isUsingHomeLocation,
           !model.locationProvider.hasUsableCoordinate {
            guard model.locationProvider.hasLocationAuthorization else { return }
            model.locationProvider.requestLocationIfAuthorized(
                preferredLocale: locale
            )

            for _ in 0..<40 where !model.locationProvider.hasUsableCoordinate {
                guard !Task.isCancelled else { return }
                switch model.locationProvider.status {
                case .denied, .restricted, .servicesDisabled, .failed:
                    return
                default:
                    break
                }
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
            }
        }

        guard model.locationProvider.hasUsableCoordinate else { return }
        await model.ensureCurrentLocationWeather(
            forceRefresh: true,
            locale: locale
        )
    }

    /// Presents precise widget diagnostics without exposing internal developer
    /// logging to the user.
    private func showWidgetIssue(_ url: URL) {
        // Widget URLs may contain a user-safe missing-data explanation. Parse
        // only the supported query values before presenting an alert.
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
        let dateValue = components.queryItems?
            .first(where: { $0.name == "missingDate" })?.value
        let forecastDate = dateValue.flatMap {
            ISO8601DateFormatter().date(from: $0)
        }
        let issue = WeatherDataIssue(
            kind: kind,
            detail: detail,
            forecastDate: forecastDate
        )
        let cityIdentifier = components.queryItems?
            .first(where: { $0.name == "cityID" })?.value
        let alertKey = [
            "widget",
            cityIdentifier ?? cityName,
            issue.kind.rawValue,
            detail ?? "",
            dateValue ?? ""
        ].joined(separator: "-")
        let report = MissingDataAlertReport(
            key: alertKey,
            title: localizedString("Data Missing", locale: locale),
            message: weatherDataIssueMessage(
                issue,
                cityName: cityName,
                locale: locale
            )
        )

        let isCurrentLocationWidget = cityIdentifier
            == WidgetDataStore.currentLocationIdentifier
        let savedPlace = isCurrentLocationWidget
            ? nil
            : cityIdentifier.flatMap(savedPlace(forWidgetCityIdentifier:))

        // A widget can render between app launches, so its missing snapshot may
        // already be stale by the time a person opens the app. Re-fetch the
        // exact source once before carrying that widget diagnostic into the
        // app's native alert queue. Current/Home Location deliberately never
        // falls back to a same-name saved city.
        Task {
            await missingDataAlerts.retryThenReport(
                report,
                recoveryKey: isCurrentLocationWidget
                    ? "widget-weather-current-location"
                    : "widget-weather-\(savedPlace?.id.uuidString ?? cityIdentifier ?? cityName)",
                retry: {
                    if isCurrentLocationWidget {
                        await retryCurrentWidgetWeather()
                        return
                    }
                    guard let savedPlace else { return }
                    _ = await model.weatherStore.retryMissingData(
                        for: savedPlace.city
                    )
                },
                isStillMissing: {
                    if isCurrentLocationWidget {
                        return !model.hasWeatherForCurrentLocation
                    }
                    guard let savedPlace else {
                        return true
                    }
                    return model.weatherStore.weather(for: savedPlace.id) == nil
                        || model.weatherStore.failuresByID[savedPlace.id] != nil
                }
            )
        }
    }

    private var showsMissingDataAlert: Binding<Bool> {
        // `.alert` expects a Boolean binding, while the optional message also
        // carries the alert's title and body. This bridges those two shapes.
        Binding(
            get: { missingDataAlerts.currentAlert != nil },
            set: { isPresented in
                if !isPresented {
                    missingDataAlerts.dismissCurrent()
                }
            }
        )
    }
}

/// Minimal app-side trigger for publishing the special widget default-location
/// entry. It intentionally excludes live forecast arrays so ordinary weather
/// updates do not force unnecessary WidgetKit timeline reloads.
private struct WidgetCurrentLocationIdentity: Equatable {
    let defaultLocationKind: WidgetDefaultLocationKind
    let latitude: Double?
    let longitude: Double?
    let metadata: CurrentLocationMetadata?
    let weatherCityName: String?
    let weatherTimeZoneIdentifier: String?
}
