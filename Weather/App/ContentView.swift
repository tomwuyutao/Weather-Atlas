//
//  ContentView.swift
//  Weather
//
//  Created by Tom on 25/02/2026.
//
//  Purpose: Owns root app state, app-shell presentation, lifecycle work,
//  refresh coordination, and app-to-widget publication.
//

import Foundation
import SwiftUI
import MapKit

// MARK: - Root View State

/// Root state owner whose feature-specific presentation lives in extensions.
struct ContentView: View {
    // MARK: Dependencies

    /// Shared model for lists, WeatherKit results, loading, and persistence.
    @State var weatherService: WeatherService
    /// Current observable theme injected by `ThemeRoot`.
    @Environment(\.appTheme) var theme

    // MARK: Initialization

    /// Creates the root state after launch migrations and optionally seeds a route.
    @MainActor
    init(
        weatherService: WeatherService? = nil,
        initialRoute: AppNavigationRoute? = nil
    ) {
        _weatherService = State(initialValue: weatherService ?? WeatherService())

        // Prime onboarding before SwiftUI renders the empty home screen. Waiting
        // for `.task` allowed missing-data notices and the full-screen cover to
        // compete during the first frame, which could leave a new install stuck
        // on an unfetched default list with no tutorial.
        let isRunningInXcodePreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let shouldPrimeFirstLaunchTutorial = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
            // Respect a cold-launch shortcut without consuming it before navigation.
            && UserDefaults.standard.string(forKey: "pendingShortcutDestination") == nil
            && !isRunningInXcodePreview
        _tutorialState = State(initialValue: TutorialPresentationState(
            showsFirstLaunch: shouldPrimeFirstLaunchTutorial
        ))

        if let initialRoute {
            _navigationPath = State(initialValue: [initialRoute])
        }
    }

    // MARK: Primary Selection and Navigation State

    /// The literal calendar day selected by the user in the device calendar.
    /// Cities whose local forecast range does not include it are omitted.
    @State var selectedForecastDate: Date = Calendar.current.startOfDay(for: Date())
    /// Stable identity of the map marker whose floating card is open.
    @State var selectedMapCityID: UUID?
    /// Persisted ordering rule for city rows and rankings.
    @AppStorage("weatherListSortMode") var listSortMode: String = WeatherListSortMode.sunny.rawValue
    /// First-launch flag controlling onboarding presentation.
    @AppStorage("hasLaunchedBefore") var hasLaunchedBefore: Bool = false
    /// Search query, sheet, result, and temporary-map presentation state.
    @State var citySearchState = CitySearchPresentationState()

    // MARK: Map Overlay State

    /// Whether the map hides annotations whose condition is not sunny.
    @State var filterSunny: Bool = false

    // MARK: Map, Settings, and Workflow State

    /// Complete map camera retained while the user remains in Map View.
    @State var mapCameraPosition: MapCameraPosition = .automatic
    /// Raw persisted temperature preference, decoded through `tempUnit`.
    @AppStorage("temperatureUnit") var temperatureUnitRaw: String = TemperatureUnit.defaultRawValue
    /// Controls presentation of the Settings sheet.
    @State var showingSettings: Bool = false
    /// First-launch and replay tutorial presentation state.
    @State var tutorialState = TutorialPresentationState()
    /// Add, rename, reorder, and delete-list workflow state.
    @State var listManagementState = ListManagementState()
    /// List-creation workflow opened directly from the global Add menu.
    @State var addListState = AddListPresentationState()
    /// Focus binding for the inline list-name editor.
    @FocusState var inlineListNameFocused: Bool
    /// Generated country/continent list preview and requested city count.
    @State var listPreviewState = GeneratedListPreviewState()
    /// Number staged by the native list-preview count alert.
    @State var listPreviewCityCountEntry: Int?
    /// Controls direct keyboard entry for the generated-list city count.
    @State var showingListPreviewCityCountEntry = false
    /// Per-city/date retry keys preventing repeated daytime-data refetch loops.
    @State var daytimeScoreRefetchKeys: Set<String> = []
    /// Distinguishes a genuinely empty loaded list from startup before first fetch.
    @State var hasCompletedInitialWeatherLoad = false
    /// Persisted visibility of the explanatory map legend.
    @AppStorage("showLegend") var showLegend: Bool = true
    /// Persisted raw identifier of the metric rendered by map markers and cards.
    @AppStorage("mapOverlayMode") var mapOverlayMode: String = "weather"

    // MARK: App Environment

    /// App-selected locale used independently of the device language.
    @Environment(\.locale) var locale
    /// Resolved appearance after the selected theme applies its preference.
    @Environment(\.colorScheme) var colorScheme
    /// Horizontal size class used for iPhone/iPad and split-view adaptations.
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    /// Drives text layouts and additional non-color cues in feature views.
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    /// Accessibility preference requiring symbols or patterns in addition to hue.
    @Environment(\.accessibilityDifferentiateWithoutColor) var differentiateWithoutColor
    /// Drives palette details that the shared theme cannot express alone, such
    /// as chart labels and stronger high-contrast outlines.
    @Environment(\.colorSchemeContrast) var colorSchemeContrast
    /// Application lifecycle phase used to refresh data after returning active.
    @Environment(\.scenePhase) var scenePhase

    /// Returns a city name translated and formatted for the selected app locale.
    func localizedCityName(for city: City) -> String {
        localizedCityDisplayName(for: city, locale: locale)
    }

    /// Validated temperature preference with `.automatic` as migration fallback.
    var tempUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic
    }

    // MARK: App-Wide Presentation State

    /// Direction used by the date switcher's push transition.
    @State var dateSwitcherForward: Bool = true
    /// Controls the graphical date-picker popover.
    @State var showingDatePopover: Bool = false

    /// Controls the destructive list-removal confirmation.
    @State var showingDeleteListConfirmation: Bool = false
    /// Identity captured while a delete confirmation is pending.
    @State var listToDeleteID: CityListID?
    /// Controls the native city-rename alert.
    @State var showingCityRenameAlert: Bool = false
    /// Editable text staged by the city-rename alert.
    @State var cityRenameText: String = ""
    /// Focus binding for the city search field.
    @FocusState var searchFieldFocused: Bool
    /// City captured while a rename operation is pending.
    @State var cityToRename: City?
    /// Whether List View exposes its editing actions.
    @State var listEditMode: Bool = false
    /// Editable name used by the create-list workflow.
    @State var newListName: String = ""
    /// Controls the native new-list naming alert.
    @State var showingAddListAlert: Bool = false
    /// Typed route stack shared by all main destinations.
    @State var navigationPath: [AppNavigationRoute] = []
    /// Missing-data or developer warning currently presented as a native alert.
    @State var developerWarning: DeveloperWarning?
    /// FIFO warnings awaiting presentation behind the active alert.
    @State var pendingDeveloperWarnings: [DeveloperWarning] = []
    /// Guards warning transitions while SwiftUI dismisses the current alert.
    @State var isDismissingDeveloperWarning: Bool = false

    // Map controls are in MapView.swift.
    // Floating map-card content is in MapFloatingCard.swift.
}

// MARK: - View Entry Point

extension ContentView {
    /// Exposes the fully composed shell as the root view body.
    var body: some View {
        viewAlerts
    }
}

// MARK: - Widget Catalog Publication

extension ContentView {
    /// Publishes only widget-selectable identity metadata into the app group.
    ///
    /// Weather snapshots are fetched and owned by the widget extension so an
    /// app refresh cannot replace the widget's last-known-good forecast.
    func publishWidgetCatalog() {
        guard !isListPreviewActive else { return }
        WidgetDataStore.save(
            WidgetDataCatalog(
                // Convert each persisted app list into WidgetKit's selection model.
                lists: managedLists.map { listID in
                    return WidgetDataList(
                        id: listID.rawValue,
                        displayName: listID.localizedDisplayName(locale: locale),
                        cities: weatherService.cityListCoordinates(for: listID).map { sourceCity in
                            widgetIdentityCity(for: sourceCity, listID: listID)
                        }
                    )
                },
                appLanguageIdentifier: locale.identifier
            )
        )
    }

    /// Creates the lightweight city contract shared with the widget extension.
    private func widgetIdentityCity(
        for sourceCity: City,
        listID: CityListID
    ) -> WidgetDataCity {
        let resolvedTimeZoneIdentifier = weatherService.weatherData(for: listID)
            .first { weatherService.citiesMatch($0.city, sourceCity) }?
            .timeZone.identifier
            ?? sourceCity.timeZoneIdentifier
        let cityID = WidgetDataStore.cityIdentifier(
            country: sourceCity.country,
            latitude: sourceCity.latitude,
            longitude: sourceCity.longitude,
            listID: listID.rawValue
        )

        return WidgetDataCity(
            id: cityID,
            cityName: localizedCityDisplayName(for: sourceCity, locale: locale),
            timeZoneIdentifier: resolvedTimeZoneIdentifier,
            latitude: sourceCity.latitude,
            longitude: sourceCity.longitude,
            daytimeHours: [],
            sunnyHours: [],
            partlySunnyHours: [],
            currentConditionSymbolName: nil,
            daylightBounds: nil,
            sunnyWindowDays: nil,
            dataIssue: nil
        )
    }
}

// MARK: - App Shell

extension ContentView {
    /// Attaches startup, lifecycle, preference, search, and data observers.
    private var viewLifecycle: some View {
        appNavigationStack
            .task {
                await onAppearLoad()
                publishWidgetCatalog()
            }
            .background {
                homeScreenShortcutReceiver
            }
            .onOpenURL(perform: handleWidgetURL)
            .onChange(of: weatherService.activeListID) { _, _ in
                scheduleDaytimeSunninessRefetch()
                publishWidgetCatalog()
            }
            .onChange(of: selectedForecastDate) { _, _ in
                scheduleDaytimeSunninessRefetch()
            }
            // A temporary search result must not change the active list's date union.
            .onChange(of: availableForecastDates(for: weatherService.cityWeatherData)) { _, _ in
                selectedForecastDate = Calendar.current.startOfDay(for: selectedForecastDate)
            }
            .onChange(of: weatherService.weatherDataByListID) { _, _ in
                publishWidgetCatalog()
            }
            .onChange(of: weatherService.availableLists) { _, _ in
                publishWidgetCatalog()
            }
            .onChange(of: locale.identifier) { _, _ in
                AppDelegate.updateHomeScreenShortcuts()
                publishWidgetCatalog()
            }
            .onChange(of: citySearchState.query) { _, newValue in
                scheduleCitySearch(for: newValue)
            }
            .onChange(of: weatherService.errorMessage) { _, message in
                if let message {
                    DeveloperWarningCenter.showMissingData(message: message, locale: locale)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                // Remove any time component without coercing into a city's zone.
                selectedForecastDate = Calendar.current.startOfDay(for: selectedForecastDate)
                if isMapRoute {
                    centerMapOnDots()
                }
                guard !tutorialState.showsFirstLaunch, !tutorialState.showsReplay else { return }
                Task {
                    await weatherService.fetchWeatherForAllCities()
                    await refreshCitiesMissingDaytimeSunninessData()
                }
            }
    }

    /// Reconciles transient map selections whenever their source state changes.
    private var viewStateObservers: some View {
        viewLifecycle
            .onChange(of: isMapCardPresented) { _, showing in
                if !showing, citySearchState.temporaryMapCity != nil {
                    citySearchState.temporaryMapCity = nil
                    centerMapOnDots()
                }
            }
            .onChange(of: filterSunny) { _, _ in
                dismissInvalidMapCard()
            }
            .onChange(of: mapOverlayMode) { _, _ in
                dismissInvalidMapCard()
            }
            .onChange(of: selectedForecastDate) { _, _ in
                dismissInvalidMapCard()
            }
            .onChange(of: weatherService.weatherDataByListID) { _, _ in
                dismissInvalidMapCard()
            }
    }

    /// Presents Settings, tutorials, search, list management, and confirmations.
    private var viewSheetsAndOverlays: some View {
        viewStateObservers
            .sheet(isPresented: $showingSettings) {
                SettingsView(
                    weatherService: weatherService,
                    onReplayTutorial: {
                        showingSettings = false
                        tutorialState.showsReplay = true
                    }
                )
                // iPad: Use the native centred form presentation in regular-width
                // windows. Compact Split View keeps the existing phone-style sheet.
                .if(horizontalSizeClass == .regular) { view in
                    view.presentationSizing(.form)
                }
            }
            .fullScreenCover(isPresented: $tutorialState.showsFirstLaunch) {
                TutorialView(
                    includesListSelection: true,
                    // Offer every built-in continent identity during first-run setup.
                    continentLists: CityListID.builtInLists,
                    creationProgress: weatherService.loadingProgress,
                    onSelectContinentList: { listID in
                        // Apply one continent choice before the shared initial load.
                        tutorialState.selectedContinentIDs = [listID.rawValue]
                        tutorialState.selectedCountryIDs = []
                        await applyTutorialListSelectionAndLoad()
                    },
                    onSelectCountryList: { country in
                        // Apply one country choice before the shared initial load.
                        tutorialState.selectedContinentIDs = []
                        tutorialState.selectedCountryIDs = [country.id]
                        await applyTutorialListSelectionAndLoad()
                    },
                    onFinish: {
                        // Persist first-launch completion from the final tutorial action.
                        Task {
                            await applyTutorialListSelectionAndLoad()
                        }
                    },
                    onCancel: nil
                )
            }
            .fullScreenCover(isPresented: $tutorialState.showsReplay) {
                TutorialView(
                    includesListSelection: false,
                    continentLists: [],
                    creationProgress: 0,
                    onSelectContinentList: { _ in },
                    onSelectCountryList: { _ in },
                    onFinish: { tutorialState.showsReplay = false },
                    onCancel: nil
                )
            }
            .sheet(isPresented: Binding(
                get: { citySearchState.isPresented },
                set: { isPresented in
                    if !isPresented {
                        dismissNativeCitySearchAndRecenter()
                    }
                }
            )) {
                searchSheet
                    // iPad: A regular-width search is a native form sheet rather than
                    // an unnecessarily wide bottom sheet.
                    .if(horizontalSizeClass == .regular) { view in
                        view.presentationSizing(.form)
                    }
                    .if(horizontalSizeClass != .regular) { view in
                        view
                            .presentationDetents([.fraction(0.82), .large])
                            .presentationDragIndicator(.visible)
                    }
                    .presentationBackground(theme.colors.background)
            }
            .sheet(isPresented: $addListState.isPresented, onDismiss: {
                let action = addListState.dismissAction
                addListState.dismissAction = nil
                addListState.showsContinentPicker = false
                addListState.showsCountryPicker = false
                addListState.countryQuery = ""
                if let action {
                    performListCreationDismissAction(action)
                }
            }) {
                addListSheet
                    .if(horizontalSizeClass == .regular) { view in
                        view.presentationSizing(.form)
                    }
                    .if(horizontalSizeClass != .regular) { view in
                        view
                            .presentationDetents([.medium, .large])
                            .presentationDragIndicator(.visible)
                    }
                    .presentationBackground(theme.colors.background)
            }
            .sheet(isPresented: $listManagementState.isPresented, onDismiss: {
                // Open the selected destination after the manager sheet closes.
                guard let action = listManagementState.dismissAction else { return }
                listManagementState.dismissAction = nil
                performListCreationDismissAction(action)
            }) {
                listManagementSheet
                    // iPad: Keep this short navigation hierarchy in the system form
                    // size; narrow windows retain the existing draggable detents.
                    .if(horizontalSizeClass == .regular) { view in
                        view.presentationSizing(.form)
                    }
                    .if(horizontalSizeClass != .regular) { view in
                        view
                            .presentationDetents([.medium, .large])
                            .presentationDragIndicator(.visible)
                    }
                    .presentationBackground(theme.colors.background)
            }
            .overlay {
                // Render the transient nonmodal confirmation after a city is saved.
                if let message = citySearchState.confirmation {
                    CityAddedConfirmationView(message: message)
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 0.86).combined(with: .opacity))
                        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: message)
                }
            }
    }

    /// Owns native alert presentation and serial warning delivery.
    private var viewAlerts: some View {
        viewSheetsAndOverlays
            .alert(localizedString("Rename", locale: locale), isPresented: $showingCityRenameAlert) {
                TextField(localizedString("Name", locale: locale), text: $cityRenameText)
                Button(localizedString("Cancel", locale: locale), role: .cancel) {
                    cityToRename = nil
                }
                Button(localizedString("OK", locale: locale)) {
                    let trimmed = cityRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let cityToRename, !trimmed.isEmpty {
                        CityListID.saveCustomCityName(trimmed, for: cityToRename)
                        publishWidgetCatalog()
                    }
                    cityToRename = nil
                }
                .disabled(cityRenameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .alert(localizedString("New List", locale: locale), isPresented: $showingAddListAlert) {
                TextField(localizedString("Name", locale: locale), text: $newListName)
                Button(localizedString("Cancel", locale: locale), role: .cancel) {
                    newListName = ""
                }
                Button(localizedString("Add", locale: locale)) {
                    commitListManagerNewList()
                }
                .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .alert(developerWarning?.title ?? "Unexpected App Issue", isPresented: Binding(
                get: { developerWarning != nil },
                set: { isPresented in
                    if !isPresented {
                        dismissDeveloperWarning()
                    }
                }
            )) {
                // SwiftUI updates the alert binding when this native cancel
                // button is tapped; the binding is the single queue owner.
                Button(localizedString("OK", locale: locale), role: .cancel) { }
            } message: {
                Text(developerWarning?.message ?? "")
            }
            .onReceive(NotificationCenter.default.publisher(for: DeveloperWarningCenter.notification)) { notification in
                guard let warning = notification.object as? DeveloperWarning else { return }
                enqueueDeveloperWarning(warning)
            }
            .alert(localizedString("Delete List", locale: locale), isPresented: $showingDeleteListConfirmation) {
                Button(localizedString("Cancel", locale: locale), role: .cancel) {
                    listToDeleteID = nil
                }
                Button(localizedString("Delete", locale: locale), role: .destructive) {
                    if let listToDeleteID {
                        weatherService.deleteList(listToDeleteID)
                        refreshListOrder()
                    }
                    self.listToDeleteID = nil
                }
            } message: {
                Text(String(
                    format: localizedString("Are you sure you want to delete \"%@\"? This cannot be undone.", locale: locale),
                    (listToDeleteID ?? weatherService.activeListID).localizedDisplayName(locale: locale)
                ))
            }
            .toolbar {
                bottomToolbarItems
            }
    }

    /// Presents a warning immediately or appends it to the FIFO alert queue.
    private func enqueueDeveloperWarning(_ warning: DeveloperWarning) {
        let isAlreadyPresented = developerWarning.map {
            $0.title == warning.title && $0.message == warning.message
        } ?? false
        let isAlreadyQueued = pendingDeveloperWarnings.contains {
            $0.title == warning.title && $0.message == warning.message
        }
        guard !isAlreadyPresented, !isAlreadyQueued else { return }

        if developerWarning == nil, !isDismissingDeveloperWarning {
            developerWarning = warning
        } else {
            pendingDeveloperWarnings.append(warning)
        }
    }

    /// Advances the warning queue only after the current native alert disappears.
    private func dismissDeveloperWarning() {
        guard developerWarning != nil else { return }
        developerWarning = nil
        isDismissingDeveloperWarning = true
        Task { @MainActor in
            // Native alerts animate out after their binding becomes false. Wait
            // for that transition before assigning the next queued warning;
            // assigning it in the same run-loop turn can leave the state set
            // without presenting another alert.
            try? await Task.sleep(for: .milliseconds(350))
            isDismissingDeveloperWarning = false
            guard developerWarning == nil, !pendingDeveloperWarnings.isEmpty else { return }
            developerWarning = pendingDeveloperWarnings.removeFirst()
        }
    }

    /// Displays a short-lived saved-city confirmation above the current screen.
    func showCityAddedConfirmation(_ message: String) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            citySearchState.confirmation = message
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard citySearchState.confirmation == message else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                citySearchState.confirmation = nil
            }
        }
    }

    /// Builds localized confirmation copy with city and destination-list names.
    func cityAddedConfirmationMessage(cityName: String, listName: String) -> String {
        String(
            format: localizedString("%1$@ was added to %2$@.", locale: locale),
            locale: locale,
            cityName,
            listName
        )
    }
}

/// Compact glass confirmation used after a successful city save.
private struct CityAddedConfirmationView: View {
    /// Fully localized message supplied by the owning workflow.
    let message: String

    /// Palette used for the glass surface and status symbol.
    @Environment(\.appTheme) private var theme

    /// Builds the confirmation capsule.
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(theme.colors.accent)
                .symbolEffect(.bounce, value: message)

            Text(message)
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: 300)
        .background(theme.colors.listCardFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: theme.colors.shadow.opacity(0.16), radius: 18, y: 8)
    }
}

#Preview("City Added Confirmation") {
    CityAddedConfirmationView(message: "Oxford was added to Europe.")
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemeColors.light.background)
        .environment(\.appTheme, AppTheme.shared)
}

// MARK: - Initial Load

extension ContentView {
    /// Performs ordered cold-start work after the root view enters the hierarchy.
    func onAppearLoad() async {
        AppDelegate.updateHomeScreenShortcuts()

        // Publish list and city identities before WeatherKit finishes so the
        // widget gallery can immediately resolve the first city in the first list.
        publishWidgetCatalog()

        // A cold-launch quick action is supplied while the scene connects. Apply
        // it before tutorial checks or WeatherKit loading so its destination is
        // the first screen the user sees.
        let launchShortcut = AppDelegate.takePendingHomeScreenShortcut()
        if let launchShortcut {
            handleHomeScreenShortcut(launchShortcut)
        }

        // Previews should show the requested screen immediately. TutorialView's
        // dedicated previews instantiate it directly, so they remain unaffected.
        let isRunningInXcodePreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let shouldShowFirstLaunchTutorial = launchShortcut == nil
            && !isRunningInXcodePreview
            && !hasLaunchedBefore
        if shouldShowFirstLaunchTutorial {
            showLegend = true
            // Seed the first-run picker with no stale continent or country selection.
            tutorialState.selectedContinentIDs = []
            tutorialState.selectedCountryIDs = []
            tutorialState.showsFirstLaunch = true
        }

        centerMapOnDots()
        if !shouldShowFirstLaunchTutorial {
            await weatherService.fetchWeatherForAllCities()
            await refreshCitiesMissingDaytimeSunninessData()
            hasCompletedInitialWeatherLoad = true
        }
        if !mapCities.isEmpty {
            centerMapOnDots()
        }
    }
}

// MARK: - Weather Refresh

extension ContentView {
    /// Returns a compact localized age for the most recent successful fetch.
    func timeSinceRefreshText() -> String {
        guard let lastFetch = weatherService.lastFetchDate else {
            return ""
        }
        let elapsed = Date().timeIntervalSince(lastFetch)
        let minutes = Int(elapsed / 60)
        if minutes < 1 {
            return localizedString("Now", locale: locale)
        } else if minutes < 60 {
            return "\(minutes) m"
        } else {
            return "\(minutes / 60) h"
        }
    }

    /// Starts a user-requested full refresh and then refits available map dots.
    func refreshWeather() {
        // Remove cards whose underlying city value may be replaced by the refresh.
        if isMapCardPresented || selectedMapCity != nil {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isMapCardPresented = false
                selectedMapCity = nil
                citySearchState.temporaryMapCity = nil
            }
        }
        daytimeScoreRefetchKeys.removeAll()
        Task {
            await weatherService.refreshWeather()
            if !mapCities.isEmpty {
                centerMapOnDots()
            }
        }
    }

    /// Launches targeted repair work without blocking the caller's UI update.
    func scheduleDaytimeSunninessRefetch() {
        Task {
            await refreshCitiesMissingDaytimeSunninessData()
        }
    }

    /// Refetches each city/date once when a present forecast lacks hourly inputs.
    func refreshCitiesMissingDaytimeSunninessData() async {
        let selectedDate = selectedForecastDate
        let citiesToRefresh = mapCities.filter { cityWeather in
            // A shorter per-city WeatherKit forecast horizon is expected and
            // cannot be repaired by repeatedly fetching the same city.
            guard let forecast = cityWeather.forecastIfAvailable(on: selectedDate) else {
                return false
            }
            return !SunninessScoring.hasDaytimeHourlyScoreData(
                for: forecast,
                timeZone: cityWeather.timeZone
            )
        }

        for cityWeather in citiesToRefresh {
            let refetchKey = "\(cityWeather.id.uuidString)-\(selectedDate.timeIntervalSinceReferenceDate)"
            guard !daytimeScoreRefetchKeys.contains(refetchKey) else { continue }
            daytimeScoreRefetchKeys.insert(refetchKey)
            _ = await weatherService.refreshWeatherForCity(cityWeather)
        }
    }
}
