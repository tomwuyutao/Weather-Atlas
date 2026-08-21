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
    // MARK: Shared Dependencies

    /// `@Bindable` exposes bindings into the shared observable models for the
    /// tab selection, sheet destination, and app-wide data updates below.
    @Bindable var model: WeatherModel
    @Bindable var router: AppNavigation
    @Bindable var missingDataAlerts: MissingDataAlertCenter
    @Bindable var networkConnectivity: NetworkConnectivity
    /// App-level state for first-run gating, replay, and contextual tips.
    let tutorial: TutorialPresentationState

    // MARK: Environment and View-Owned State

    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appTheme) private var theme
    /// Reuses the former first-launch key so existing installs are not seeded
    /// again after starter places replaced setup.
    @AppStorage("hasLaunchedBefore") private var didSeedPlaces = false
    /// One selected day is intentionally shared across all tabs and pushed
    /// reports, making the date control feel global rather than per-screen.
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    /// Preserves the user's selected relative forecast day when location
    /// metadata changes the app-wide calendar from the device to local time.
    @State private var dateTimeZone = TimeZone.autoupdatingCurrent
    @State private var resetID = UUID()
    /// Deep links can arrive while first-run education owns the root view.
    /// Keep the latest supported intent until the app shell is available.
    @State private var pendingExternalURL: URL?

    // MARK: Tab Shell

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
            .onChange(
                of: model.locationTimeZone?.identifier,
                handleLocationTimeZoneChange
            )
            // Rebuild the shell after a full reset so local view state cannot leak
            // from the discarded user library into the newly seeded library.
            .id(resetID)
            // A single item-driven sheet prevents two root modals being presented
            // at once and lets AppNavigation describe the destination declaratively.
            .sheet(item: $router.presentedSheet) { destination in
                sheet(for: destination)
            }
            .alert(
                missingDataAlerts.currentAlert?.title ?? "",
                isPresented: showsMissingDataAlert,
                presenting: missingDataAlerts.currentAlert
            ) { _ in
                Button("OK") {
                    missingDataAlerts.dismissCurrent()
                }
            } message: { alert in
                Text(alert.message)
            }
            .task {
                await performInitialHydration()
            }
            .task(id: locale.identifier) {
                refreshLocaleDependencies()
            }
            .onChange(of: model.placesStore.document) {
                handlePlacesDocumentChange()
            }
            // The Current Location entry is a stable widget configuration, but
            // its coordinate and locality are live. Republish that one small
            // contract whenever the app receives a new location or its weather
            // response supplies the authoritative city/timezone.
            .onChange(of: widgetCurrentLocationIdentity) {
                model.publishWidgetCatalog(locale: locale)
            }
            .onChange(
                of: model.placesStore.loadErrorDescription,
                initial: true,
                handlePlacesLoadErrorChange
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
                ),
                perform: handleShortcutNotification
            )
    }

    private var tabShell: some View {
        TabView(selection: $router.selectedTab) {
            // Each visible tab owns a distinct navigation path. Returning to a
            // tab therefore restores its own back stack rather than another
            // tab's screen.
            Tab(
                "Your Location",
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
                "Saved Places",
                systemImage: "bookmark",
                value: AppTab.savedPlaces
            ) {
                NavigationStack(path: $router.savedPlacesPath) {
                    screenWithOfflineBanner(SavedPlacesView(
                        model: model,
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

    /// Non-map tabs use the same bottom control lane as Map's Find Sun button.
    /// The child safe area already excludes the native tab bar, so this never
    /// overlaps the tab controls.
    @ViewBuilder
    private func screenWithOfflineBanner<Content: View>(
        _ content: Content
    ) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: MapCardLayout.bottomPadding) {
            if networkConnectivity.isOffline,
               !networkConnectivity.isOfflineBannerDismissed {
                OfflineBanner(
                    lastUpdated: model.weatherStore.latestCachedWeatherDate,
                    dismiss: networkConnectivity.dismissOfflineBanner
                )
                .padding(.horizontal, 16)
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

    // MARK: Root Lifecycle

    private func handleLocationTimeZoneChange(
        _: String?,
        _ newIdentifier: String?
    ) {
        guard let newIdentifier,
              let newTimeZone = TimeZone(identifier: newIdentifier),
              newTimeZone != dateTimeZone else {
            return
        }
        rebaseSelectedDate(from: dateTimeZone, to: newTimeZone)
        dateTimeZone = newTimeZone
    }

    private func performInitialHydration() async {
        // Restore persisted weather, publish widget snapshots, then ask Core
        // Location only when authorization already exists.
        await seedStarterPlacesIfNeeded()
        model.retainWeatherScope()
        await model.loadSavedWeather()
        model.publishWidgetCatalog(locale: locale)
        if !model.isUsingHomeLocation {
            model.locationProvider.requestLocationIfAuthorized(
                preferredLocale: locale
            )
        }
        handlePendingShortcut()
    }

    private func refreshLocaleDependencies() {
        AppDelegate.updateHomeScreenShortcuts()
        model.publishWidgetCatalog(locale: locale)
        if !model.isUsingHomeLocation {
            model.locationProvider.requestLocationIfAuthorized(
                preferredLocale: locale
            )
        }
    }

    private func handlePlacesDocumentChange() {
        model.retainWeatherScope()
        model.publishWidgetCatalog(locale: locale)
    }

    private func handlePlacesLoadErrorChange(
        _ previousErrorDescription: String?,
        _ errorDescription: String?
    ) {
        let key = "places-library-load"
        if let errorDescription {
            let report = MissingDataAlertReport(
                key: key,
                title: localizedString("Data Missing", locale: locale),
                message: String(
                    format: localizedString(
                        "Saved Places data is missing because the library could not be loaded: %@",
                        locale: locale
                    ),
                    locale: locale,
                    errorDescription
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

    private func handleScenePhaseChange(
        _: ScenePhase,
        _ newPhase: ScenePhase
    ) {
        guard newPhase == .active else { return }
        handlePendingShortcut()
        if !model.isUsingHomeLocation {
            model.locationProvider.requestLocationIfAuthorized(
                preferredLocale: locale
            )
        }
        Task {
            await model.loadSavedWeather()
            model.publishWidgetCatalog(locale: locale)
        }
    }

    private func handleShortcutNotification(_ notification: Notification) {
        let notifiedDestination = (notification.object as? String)
            .flatMap(HomeScreenShortcutDestination.init(rawValue:))
        let pendingDestination = AppDelegate.takePendingHomeScreenShortcut()
        guard let destination = pendingDestination ?? notifiedDestination else {
            return
        }
        handleShortcut(destination)
    }

    // MARK: Date and Navigation Helpers

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
            DetailView(
                placeID: id,
                selectedDate: $selectedDate,
                model: model
            )
        case .savedPlacesLibrary:
            ManageSavedPlaces(
                placesStore: model.placesStore,
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
                onResetApp: resetApp,
                onReplayTutorial: {
                    tutorial.replay()
                    router.presentedSheet = nil
                }
            )
        }
    }

    // MARK: First-Run and Reset

    /// Seeds a first-run library with a fixed, globally recognisable overview.
    /// A starter city within 20 km of the location chosen during onboarding is
    /// omitted so that the library never duplicates the person's local area.
    /// Existing and intentionally emptied libraries are left untouched.
    private func seedStarterPlacesIfNeeded() async {
        let alertKey = "starter-places-seed"
        guard !didSeedPlaces else { return }
        guard model.placesStore.loadErrorDescription == nil else { return }
        guard model.placesStore.allPlaces.isEmpty else {
            didSeedPlaces = true
            return
        }

        do {
            // Restore the fixed library first, then load its forecasts. A
            // reset should never depend on WeatherKit before places reappear.
            let cities = starterCitiesExcludingInitialLocation(
                try await starterCitiesAfterOneCatalogRetry()
            )
            guard !cities.isEmpty else { return }
            _ = try model.placesStore.savePlaces(cities)
            model.retainWeatherScope()
            await model.weatherStore.load(cities: cities)
            model.publishWidgetCatalog(locale: locale)
            didSeedPlaces = true
            missingDataAlerts.resolve(key: alertKey)
        } catch let issue as WeatherDataIssue {
            // The library remains blank. The alert names the exact source field
            // rather than silently substituting unresolved starter metadata.
            missingDataAlerts.report(
                key: alertKey,
                title: localizedString("Data Missing", locale: locale),
                message: weatherDataIssueMessage(
                    issue,
                    cityName: localizedString("starter places", locale: locale),
                    locale: locale
                )
            )
        } catch CitiesCatalogError.missingStarterCities(let labels) {
            missingDataAlerts.report(
                key: alertKey,
                title: localizedString("Data Missing", locale: locale),
                message: String(
                    format: localizedString(
                        "Starter place catalog data is missing for: %@.",
                        locale: locale
                    ),
                    locale: locale,
                    labels.joined(separator: ", ")
                )
            )
        } catch is CitiesCatalogError {
            missingDataAlerts.report(
                key: alertKey,
                title: localizedString("Data Missing", locale: locale),
                message: localizedString(
                    "Starter place catalog data is missing.",
                    locale: locale
                )
            )
        } catch {
            // Leave the flag unset so a transient catalog or persistence
            // failure can be retried when the app next becomes active.
            missingDataAlerts.report(
                key: alertKey,
                title: localizedString("Data Missing", locale: locale),
                message: localizedString(
                    "Starter place data is missing.",
                    locale: locale
                )
            )
        }
    }

    /// The bundled world-city catalog is normally immutable, but the first
    /// parse can still be interrupted during launch. Retry a failed catalog
    /// read once before starter-place setup is allowed to present its final
    /// missing-data alert.
    private func starterCitiesAfterOneCatalogRetry() async throws -> [City] {
        do {
            return try await model.starterCities()
        } catch is CitiesCatalogError {
            await model.citiesCatalog.reload()
            return try await model.starterCities()
        }
    }

    /// Onboarding always resolves either a saved home city or a usable device
    /// coordinate before the app shell begins first-run seeding. Keep this
    /// filtering here, rather than in the catalog, because the catalog itself
    /// remains the same fixed global overview for every user.
    private func starterCitiesExcludingInitialLocation(
        _ cities: [City]
    ) -> [City] {
        guard let initialLocationCoordinate else { return cities }

        let initialLocation = CLLocation(
            latitude: initialLocationCoordinate.latitude,
            longitude: initialLocationCoordinate.longitude
        )
        return cities.filter { city in
            CLLocation(latitude: city.latitude, longitude: city.longitude)
                .distance(from: initialLocation) >= 20_000
        }
    }

    /// Prefer the explicit home selection. Otherwise use the live coordinate
    /// obtained from the mandatory current-location tutorial step.
    private var initialLocationCoordinate: CLLocationCoordinate2D? {
        if let homeLocation = model.homeLocation {
            return CLLocationCoordinate2D(
                latitude: homeLocation.latitude,
                longitude: homeLocation.longitude
            )
        }

        guard let coordinate = model.locationProvider.coordinate,
              CLLocationCoordinate2DIsValid(coordinate) else {
            return nil
        }
        return coordinate
    }

    /// Clears user-owned state, then restores the fixed first-run overview.
    private func resetApp() throws {
        // First clear data owned by the user and cache, then reset lightweight
        // display preferences before rebuilding the fresh-root state.
        try model.placesStore.resetToEmptyLibrary()
        model.weatherStore.clearAllWeather()
        WidgetDataStore.removeAll()
        model.resetLocation()
        missingDataAlerts.reset()

        let defaults = UserDefaults.standard
        let resetLanguage = AppLanguageDefaults.preferredDeviceLanguage()
        defaults.set(
            TemperatureUnit.defaultRawValue,
            forKey: "temperatureUnit"
        )
        defaults.set(DistanceUnit.defaultRawValue, forKey: "distanceUnit")
        defaults.set(resetLanguage, forKey: AppLanguageDefaults.storageKey)
        defaults.set(true, forKey: "useSystemTextSize")
        defaults.set(
            AppTextSizeLevel.defaultRawValue,
            forKey: "appTextSizeLevel"
        )
        defaults.set(true, forKey: "showsMapSunnyHoursLegend")
        theme.style = .automatic

        tutorial.resetForFullAppReset()

        selectedDate = Calendar.current.startOfDay(for: Date())
        router.yourLocationPath = []
        router.savedPlacesPath = []
        router.resetMapHandoffState()
        router.selectedTab = .yourLocation
        resetID = UUID()
        didSeedPlaces = false
        model.publishWidgetCatalog(locale: Locale(identifier: resetLanguage))
        router.presentedSheet = nil

        Task {
            // This is intentionally asynchronous: the reset can finish and
            // dismiss Settings before catalog look-up and weather loading run.
            await seedStarterPlacesIfNeeded()
        }
    }

    // MARK: External Navigation

    private func completeTutorial() {
        tutorial.complete()

        guard let pendingExternalURL else {
            router.selectedTab = .yourLocation
            return
        }

        self.pendingExternalURL = nil
        handleExternalURL(pendingExternalURL)
    }

    private func handlePendingShortcut() {
        guard let destination = AppDelegate.takePendingHomeScreenShortcut() else {
            return
        }
        handleShortcut(destination)
    }

    /// Maps the current Home Screen quick actions into the existing tab and
    /// Find Sun routes. A legacy location value remains decode-only so old
    /// SpringBoard entries never lead to a dead end after an app update.
    private func handleShortcut(
        _ destination: HomeScreenShortcutDestination
    ) {
        router.presentedSheet = nil

        switch destination {
        case .findSunNearMe:
            router.showMap(findingSunIn: .nearMe)
        case .legacyHome:
            router.yourLocationPath = []
            router.selectedTab = .yourLocation
        case .map:
            router.mapPath = []
            router.showMap()
        case .places:
            router.savedPlacesPath = []
            router.selectedTab = .savedPlaces
        }
    }

    /// Routes app and widget URLs to their native destination. Older generic
    /// Places URLs still open the manager; city widget URLs now open the city's
    /// forecast directly when that saved place still exists.
    private func receiveExternalURL(_ url: URL) {
        guard isSupportedExternalURL(url) else { return }

        guard tutorial.shouldPresent else {
            handleExternalURL(url)
            return
        }

        // If the system delivers several URLs before setup completes, the
        // most recent one represents the person's current navigation intent.
        pendingExternalURL = url
    }

    private func handleExternalURL(_ url: URL) {
        guard isSupportedExternalURL(url) else { return }
        // Match Home Screen shortcuts: a URL should reveal its destination,
        // not navigate underneath an already presented Settings sheet.
        router.presentedSheet = nil

        switch url.host {
        case "place":
            openWidgetPlace(url)
        case "places":
            router.savedPlacesPath = []
            router.showPlacesLibrary()
            showWidgetIssue(url)
        case "home":
            router.yourLocationPath = []
            router.selectedTab = .yourLocation
        case "map":
            handleShortcut(.map)
        default:
            break
        }
    }

    private func isSupportedExternalURL(_ url: URL) -> Bool {
        guard url.scheme == "weatheratlas" else { return false }

        switch url.host {
        case "place", "places", "home", "map":
            return true
        default:
            return false
        }
    }

    /// Opens a widget's configured Saved Place in the same Detail destination
    /// used by city rows. Current Location is not a saved-place route, so its
    /// widget correctly opens the Your Location report instead.
    private func openWidgetPlace(_ url: URL) {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ),
        let cityIdentifier = components.queryItems?
            .first(where: { $0.name == "cityID" })?.value else {
            // A malformed or stale city widget should still leave the person at
            // the useful generic Places destination rather than doing nothing.
            router.savedPlacesPath = []
            router.showPlacesLibrary()
            showWidgetIssue(url)
            return
        }

        if cityIdentifier == WidgetDataStore.currentLocationIdentifier {
            router.yourLocationPath = []
            router.selectedTab = .yourLocation
            showWidgetIssue(url)
            return
        }

        guard let savedPlace = savedPlace(forWidgetCityIdentifier: cityIdentifier) else {
            // The widget can outlive a delete or rename. Preserve the historic
            // Places behavior as the safe fallback when its city no longer
            // resolves in the app's current library.
            router.savedPlacesPath = []
            router.showPlacesLibrary()
            showWidgetIssue(url)
            return
        }

        router.selectedTab = .savedPlaces
        router.savedPlacesPath = [.place(id: savedPlace.id)]
        showWidgetIssue(url)
    }

    /// Resolves the stable cross-process widget identifier to the app's saved
    /// UUID. Widget identifiers intentionally derive from coordinates because
    /// they must survive between the app and widget extension processes.
    private func savedPlace(forWidgetCityIdentifier identifier: String) -> SavedPlace? {
        model.placesStore.allPlaces.first { place in
            WidgetDataStore.cityIdentifier(
                country: place.city.country,
                latitude: place.city.latitude,
                longitude: place.city.longitude
            ) == identifier
        }
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

        let savedPlace = cityIdentifier.flatMap(savedPlace(forWidgetCityIdentifier:))
            ?? model.placesStore.allPlaces.first {
            $0.displayName.localizedCaseInsensitiveCompare(cityName)
                == .orderedSame
        }

        // A widget can render between app launches, so its missing snapshot may
        // already be stale by the time a person opens the app. Re-fetch the
        // matching saved place once before carrying that widget diagnostic into
        // the app's native alert queue.
        Task {
            await missingDataAlerts.retryThenReport(
                report,
                recoveryKey: "widget-weather-\(savedPlace?.id.uuidString ?? cityIdentifier ?? cityName)",
                retry: {
                    guard let savedPlace else { return }
                    _ = await model.weatherStore.retryMissingData(
                        for: savedPlace.city
                    )
                },
                isStillMissing: {
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
