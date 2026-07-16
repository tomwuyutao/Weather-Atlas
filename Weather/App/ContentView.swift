//
//  ContentView.swift
//  Weather
//
//  Created by Tom on 25/02/2026.
//
//  Purpose: Owns app state and the single iOS shell. Feature-specific UI is
//  split into extension files.
//

import SwiftUI
import UIKit
import MapKit

// MARK: - Haptics

enum Haptics {
    static func lightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

struct CitySearchPresentationState {
    var isPresented = false
    var query = ""
    var manager = CitySearchManager()
    var isLoading = false
    var loadingResultID: String?
    var confirmation: String?
    var debounceTask: Task<Void, Never>?
    var isSettled = true
    var targetListID: CityListID?
    var temporaryMapCity: CityWeather?
    var showsListPicker = false
}

struct TutorialPresentationState {
    var showsFirstLaunch = false
    var showsReplay = false
    var selectedContinentIDs: Set<String> = []
    var selectedCountryIDs: Set<String> = []
}

struct ListManagementState {
    var isPresented = false
    var showsAddOptions = false
    var showsContinentPicker = false
    var showsCountryPicker = false
    var dismissAction: ListManagementDismissAction?
    var editMode: EditMode = .inactive
    var renamingListID: CityListID?
    var renameText = ""
    var countryQuery = ""
}

struct GeneratedListPreviewState {
    var name: String?
    var nameSource: CityListNameSource?
    var allCities: [City] = []
    var cityCount = CountryCityCatalog.defaultCountryCityCount
}

// MARK: - Shared State

struct ContentView: View {
    @State var weatherService = WeatherService()
    @Environment(\.appTheme) var theme

    // MARK: Startup Setup

    init(initialRoute: AppNavigationRoute? = nil) {
        if let initialRoute {
            _navigationPath = State(initialValue: [initialRoute])
        }
    }

    // MARK: Selection and Navigation State

    @State var selectedDayOffset: Int = 0
    @Namespace var detailDaySelectionNamespace
    @State var selectedMapCityID: UUID?
    @AppStorage("weatherListSortMode") var listSortMode: String = WeatherListSortMode.sunny.rawValue
    @AppStorage("hasLaunchedBefore") var hasLaunchedBefore: Bool = false
    @State var citySearchState = CitySearchPresentationState()

    // MARK: Map Overlay State

    @State var filterSunny: Bool = false

    // MARK: Map Camera and Settings State

    @State var mapCameraPosition: MapCameraPosition = .automatic
    @AppStorage("temperatureUnit") var temperatureUnitRaw: String = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit") var distanceUnitRaw: String = DistanceUnit.defaultRawValue
    @State var showingSettings: Bool = false
    @State var tutorialState = TutorialPresentationState()
    @State var listManagementState = ListManagementState()
    @FocusState var inlineListNameFocused: Bool
    @State var listPreviewState = GeneratedListPreviewState()
    @State var daytimeScoreRefetchKeys: Set<String> = []
    @AppStorage("showLegend") var showLegend: Bool = true
    @AppStorage("mapOverlayMode") var mapOverlayMode: String = "weather"
    @State var allListsWeatherData: [CityWeather] = []
    @State var allListsSourceListIDs: [String: CityListID] = [:]
    @State var isShowingAllLists = false

    // Accessibility: Moves VoiceOver directly to the map card that appears after a
    // marker or search result is selected, without changing visual focus or navigation.
    @AccessibilityFocusState var mapCardAccessibilityFocused: Bool

    // MARK: Environment

    @Environment(\.locale) var locale
    @Environment(\.colorScheme) var colorScheme
    // Accessibility: Drives large-text layouts and additional non-color cues in feature views.
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.accessibilityDifferentiateWithoutColor) var differentiateWithoutColor
    // Accessibility: Drives high-contrast palette details that cannot be expressed
    // through the shared theme alone, such as chart labels and map-safe outlines.
    @Environment(\.colorSchemeContrast) var colorSchemeContrast
    @Environment(\.scenePhase) var scenePhase

    // MARK: Active City Collections

    /// Cities to display on the map: the active list or aggregate list plus any temporary searched city.
    var mapCities: [CityWeather] {
        if isListPreviewActive {
            return []
        }
        var result = isShowingAllLists ? allListsWeatherData : weatherService.cityWeatherData
        if let preview = citySearchState.temporaryMapCity, !result.contains(where: { $0.city.name == preview.city.name }) {
            result.append(preview)
        }
        return result
    }

    var mapFitCities: [City] {
        if isListPreviewActive {
            return listPreviewCities
        }
        if isShowingAllLists {
            return allListsWeatherData.map(\.city)
        }
        return weatherService.cityListCoordinates()
    }

    var selectedMapCity: CityWeather? {
        get {
            guard let selectedMapCityID else { return nil }
            return mapCities.first(where: { $0.id == selectedMapCityID })
                ?? allListsWeatherData.first(where: { $0.id == selectedMapCityID })
        }
        nonmutating set {
            selectedMapCityID = newValue?.id
        }
    }

    var showingMapExpandedCard: Bool {
        get { selectedMapCityID != nil }
        nonmutating set {
            if !newValue {
                selectedMapCityID = nil
            }
        }
    }

    var listPreviewCities: [City] {
        Array(listPreviewState.allCities.prefix(listPreviewState.cityCount))
    }

    var listPreviewMaximumCount: Int {
        min(CountryCityCatalog.maxCountryCityCount, listPreviewState.allCities.count)
    }

    var isListPreviewActive: Bool {
        currentRoute == .listPreview && listPreviewState.name != nil
    }

    func cityCountText(_ count: Int) -> String {
        if count == 1 {
            return "\(count) \(localizedString("City", locale: locale))"
        }
        return "\(count) \(localizedString("Cities", locale: locale))"
    }

    func localizedCityName(for city: City) -> String {
        CityNameLocalizationCatalog.localizedName(for: city, locale: locale)
            ?? city.localizedName(locale: locale)
    }

    var tempUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic
    }

    // MARK: Refresh Timing

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
            let hours = minutes / 60
            return "\(hours) h"
        }
    }

    var body: some View {
        viewAlerts
    }

    // MARK: - App Shell State
    @State var dateSwitcherForward: Bool = true
    @State var showingDatePopover: Bool = false

    @State var showingDeleteListConfirmation: Bool = false
    @State var listToDeleteID: CityListID?
    @State var showingCityRenameAlert: Bool = false
    @State var cityRenameText: String = ""
    @FocusState var searchFieldFocused: Bool
    @State var cityToRename: City?
    @State var listEditMode: Bool = false
    @State var newListName: String = ""
    @State var showingAddListAlert: Bool = false
    @State var navigationPath: [AppNavigationRoute] = []
    @State var developerWarning: DeveloperWarning?

    var toolbarTitle: String {
        if isShowingAllLists {
            return localizedString("All Cities", locale: locale)
        }
        return weatherService.activeListID.localizedDisplayName(locale: locale)
    }

    // Map controls are in MapView.swift.
    // Floating and expanded card content is in FloatingCard.swift.
    var dateSwitcherText: String {
        dateSwitcherText(for: selectedDayOffset)
    }


}

// MARK: - App Shell

extension ContentView {
    private var viewLifecycle: some View {
        appNavigationStack
            .task {
                await onAppearLoad()
                updateBestSunnyPlacesWidget()
            }
            .background {
                homeScreenShortcutReceiver
            }
            .onChange(of: weatherService.activeListID) { _, _ in
                AppDelegate.updateHomeScreenListShortcuts()
                scheduleDaytimeSunninessRefetch()
                updateBestSunnyPlacesWidget()
            }
            .onChange(of: selectedDayOffset) { _, _ in
                scheduleDaytimeSunninessRefetch()
            }
            .onChange(of: weatherService.weatherDataByListID) { _, _ in
                updateBestSunnyPlacesWidget()
            }
            .onChange(of: weatherService.availableLists) { _, _ in
                updateBestSunnyPlacesWidget()
            }
            .onChange(of: locale.identifier) { _, _ in
                updateBestSunnyPlacesWidget()
            }
            .onChange(of: citySearchState.query) { _, newValue in
                scheduleCitySearch(for: newValue)
            }
            .onChange(of: weatherService.errorMessage) { _, message in
                // Accessibility: Announce asynchronous errors that may not receive VoiceOver focus.
                if let message {
                    UIAccessibility.post(notification: .announcement, argument: message)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                if isMapRoute {
                    centerMapOnDots(useListCoordinates: true)
                }
                guard !tutorialState.showsFirstLaunch, !tutorialState.showsReplay else { return }
                Task {
                    await weatherService.fetchWeatherForAllCities()
                    await refreshCitiesMissingDaytimeSunninessData()
                }
            }
    }

    private var viewStateObservers: some View {
        viewLifecycle
            .onChange(of: showingMapExpandedCard) { _, showing in
                if !showing, citySearchState.temporaryMapCity != nil {
                    citySearchState.temporaryMapCity = nil
                    centerMapOnDots(useListCoordinates: true)
                }
            }
            .onChange(of: selectedMapCityID) { _, selectedID in
                // Accessibility: Wait until the newly identified conditional card has
                // entered the hierarchy before assigning VoiceOver focus to it.
                if selectedID != nil {
                    DispatchQueue.main.async {
                        mapCardAccessibilityFocused = true
                    }
                } else {
                    mapCardAccessibilityFocused = false
                }
            }
    }

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
            }
            .fullScreenCover(isPresented: $tutorialState.showsFirstLaunch) {
                TutorialView(
                    includesContinentSelection: true,
                    continentLists: continentListTutorialLists,
                    selectedContinentListIDs: $tutorialState.selectedContinentIDs,
                    selectedCountryListIDs: $tutorialState.selectedCountryIDs,
                    creationProgress: weatherService.loadingProgress,
                    onSelectContinentList: finishTutorialWithContinentList,
                    onSelectCountryList: finishTutorialWithCountryList,
                    onFinish: applyContinentListTutorialSelection,
                    onCancel: nil
                )
            }
            .fullScreenCover(isPresented: $tutorialState.showsReplay) {
                TutorialView(
                    includesContinentSelection: false,
                    continentLists: [],
                    selectedContinentListIDs: $tutorialState.selectedContinentIDs,
                    selectedCountryListIDs: $tutorialState.selectedCountryIDs,
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
                    .presentationDetents([.fraction(0.82), .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(theme.colors.background)
            }
            .sheet(isPresented: $listManagementState.isPresented, onDismiss: performListManagementDismissAction) {
                listManagementSheet
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(theme.colors.mapOcean)
            }
            .overlay {
                cityAddedConfirmationOverlay
            }
    }

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
                    }
                    cityToRename = nil
                }
            }
            .alert(localizedString("New List", locale: locale), isPresented: $showingAddListAlert) {
                TextField(localizedString("Name", locale: locale), text: $newListName)
                Button(localizedString("Cancel", locale: locale), role: .cancel) {
                    newListName = ""
                }
                Button(localizedString("Add", locale: locale)) {
                    commitListManagerNewList()
                }
            }
            .alert(developerWarning?.title ?? "Unexpected App Issue", isPresented: Binding(
                get: { developerWarning != nil },
                set: { isPresented in
                    if !isPresented {
                        developerWarning = nil
                    }
                }
            )) {
                Button(localizedString("OK", locale: locale), role: .cancel) {
                    developerWarning = nil
                }
            } message: {
                Text(developerWarning?.message ?? "")
            }
            .onReceive(NotificationCenter.default.publisher(for: DeveloperWarningCenter.notification)) { notification in
                developerWarning = notification.object as? DeveloperWarning
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
                nativeBottomToolbarItems
            }
    }

    @ViewBuilder
    private var cityAddedConfirmationOverlay: some View {
        if let message = citySearchState.confirmation {
            CityAddedConfirmationView(message: message)
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.86).combined(with: .opacity))
                .animation(.spring(response: 0.32, dampingFraction: 0.72), value: message)
        }
    }

    func showCityAddedConfirmation(_ message: String) {
        // Accessibility: Speak the transient confirmation before its visual overlay disappears.
        UIAccessibility.post(notification: .announcement, argument: message)
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

    var homeScreenShortcutReceiver: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .weatherOpenListShortcut)) { notification in
                let notifiedListID = notification.object as? String
                guard let rawValue = AppDelegate.takePendingListShortcutID() ?? notifiedListID else { return }
                handleOpenListShortcut(rawValue: rawValue)
            }
    }

    var appNavigationStack: some View {
        NavigationStack(path: $navigationPath) {
            homeView
                .navigationDestination(for: AppNavigationRoute.self) { route in
                    switch route {
                    case .map:
                        fullMapDestination
                    case .list:
                        fullListDestination
                    case .cityDetail(let city):
                        cityDetailView(for: city)
                    case .addCityDetail(let city):
                        cityDetailView(for: city)
                    case .listPreview:
                        listPreviewDestination
                    }
                }
        }
        // Accessibility: Match the system two-finger scrub with the app's Back action.
        .accessibilityAction(.escape) {
            popCurrentRoute()
        }
    }

    // MARK: Primary Destinations

    var homeView: some View {
        homeContent(previewActive: false)
            .navigationTitle(toolbarTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                showingMapExpandedCard = false
            }
    }

    var fullMapDestination: some View {
        mapTabContent
            .navigationTitle(localizedString("Weather", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(false)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                centerMapOnDots(useListCoordinates: true)
            }
    }

    var fullListDestination: some View {
        listView
            .navigationTitle(toolbarTitle)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                showingMapExpandedCard = false
                listEditMode = false
            }
    }

    // MARK: Map Destination

    var mapTabContent: some View {
        ZStack(alignment: .bottom) {
            mapView
                .overlay(alignment: .topLeading) {
                    if isMapRoute, !citySearchState.isPresented {
                        VStack(alignment: .leading, spacing: 8) {
                            if weatherService.isLoading {
                                LoadingWeatherOverlay(
                                    progress: weatherService.loadingProgress,
                                    locale: locale
                                )
                                .allowsHitTesting(false)
                                .transition(.scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity))
                            }

                            if showLegend {
                                MapFloatingLegend(overlayMode: mapOverlayMode) {
                                    withAnimation(.smooth(duration: 0.2)) {
                                        showLegend = false
                                    }
                                }
                                .transition(.scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity))
                            }
                        }
                        .padding(.leading, 16)
                        .padding(.top, 72)
                    }
                }
                .animation(.smooth(duration: 0.22), value: showLegend)
                .animation(.smooth(duration: 0.22), value: weatherService.isLoading)
                .overlay(alignment: .topLeading) {
                    if !citySearchState.isPresented {
                        topToolbar {
                            mapControls
                        }
                        .padding(.horizontal, 16)
                        .safeAreaPadding(.top, 12)
                        .contentShape(Rectangle())
                        .background(Color.clear)
                        .zIndex(120)
                    }
                }
                .allowsHitTesting(!citySearchState.isPresented)

            if !citySearchState.isPresented {
                mainOverlays
            }
        }
        .tint(theme.colors.accent)
    }

    // MARK: Startup and External Entry Points

    func onAppearLoad() async {
        AppDelegate.updateHomeScreenListShortcuts()
        // Previews should show the requested screen immediately. TutorialView's
        // dedicated previews instantiate it directly, so they remain unaffected.
        let isRunningInXcodePreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let shouldShowFirstLaunchTutorial = !isRunningInXcodePreview && !hasLaunchedBefore
        if shouldShowFirstLaunchTutorial {
            showLegend = true
            prepareContinentListTutorialSelection()
            tutorialState.showsFirstLaunch = true
        }
        centerMapOnDots(useListCoordinates: true)
        if !shouldShowFirstLaunchTutorial {
            await weatherService.fetchWeatherForAllCities()
            await refreshCitiesMissingDaytimeSunninessData()
        }
        if !mapCities.isEmpty {
            centerMapOnDots(useListCoordinates: true)
        }
        if let pendingShortcutID = AppDelegate.takePendingListShortcutID() {
            handleOpenListShortcut(rawValue: pendingShortcutID)
        }
    }

    var continentListTutorialLists: [CityListID] {
        CityListID.builtInLists
    }

    func prepareContinentListTutorialSelection() {
        tutorialState.selectedContinentIDs = []
        tutorialState.selectedCountryIDs = []
    }

    func finishTutorialWithContinentList(_ listID: CityListID) async {
        tutorialState.selectedContinentIDs = [listID.rawValue]
        tutorialState.selectedCountryIDs = []
        await applyContinentListTutorialSelectionAndLoad()
    }

    func finishTutorialWithCountryList(_ country: CountryListOption) async {
        tutorialState.selectedContinentIDs = []
        tutorialState.selectedCountryIDs = [country.id]
        await applyContinentListTutorialSelectionAndLoad()
    }

    func applyContinentListTutorialSelection() {
        Task {
            await applyContinentListTutorialSelectionAndLoad()
        }
    }

    func applyContinentListTutorialSelectionAndLoad() async {
        let selectedContinentIDs = tutorialState.selectedContinentIDs
        let selectedCountryIDs = tutorialState.selectedCountryIDs
        guard !selectedContinentIDs.isEmpty || !selectedCountryIDs.isEmpty else { return }
        let selectedLists = CityListID.builtInLists.filter { selectedContinentIDs.contains($0.rawValue) }

        CityListID.keepBuiltInLists(withRawValues: selectedContinentIDs)
        refreshListOrder()
        navigationPath = []

        var firstList = selectedLists.first
        let selectedCountries = CountryCityCatalog.countries(locale: locale).filter {
            selectedCountryIDs.contains($0.id)
        }

        for country in selectedCountries {
            let identity = CityListID.availableGeneratedListIdentity(
                for: .country(iso2: country.iso2, duplicateIndex: nil),
                locale: locale
            )
            let listID = await weatherService.createCustomList(
                name: identity.displayName,
                cities: CountryCityCatalog.topCities(for: country),
                nameSource: identity.nameSource
            )
            if firstList == nil {
                firstList = listID
            }
        }

        if let firstList {
            if firstList.rawValue == weatherService.activeListID.rawValue {
                await weatherService.fetchWeatherForAllCities()
            } else {
                await switchToList(firstList)
            }
        }

        refreshListOrder()
        centerMapOnDots(useListCoordinates: true)
        AppDelegate.updateHomeScreenListShortcuts()

        if !mapCities.isEmpty {
            await refreshCitiesMissingDaytimeSunninessData()
        }

        hasLaunchedBefore = true
        tutorialState.showsFirstLaunch = false
    }

    func handleOpenListShortcut(rawValue: String) {
        guard let listID = CityListID.allLists.first(where: { $0.rawValue == rawValue }) else { return }
        selectedDayOffset = 0
        showingSettings = false
        citySearchState.isPresented = false
        showingMapExpandedCard = false
        selectedMapCity = nil
        citySearchState.temporaryMapCity = nil
        clearGeneratedListPreview(playsHaptic: false)
        navigationPath = []

        Task {
            await switchToList(listID)
            await MainActor.run {
                AppDelegate.updateHomeScreenListShortcuts()
            }
        }
    }
}

private struct CityAddedConfirmationView: View {
    let message: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(theme.colors.accent)
                .symbolEffect(.bounce, value: message)
                .accessibilityHidden(true)

            Text(message)
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: 300)
        .background(theme.colors.listCardFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        // Accessibility: Read the transient card once instead of exposing its decorative icon.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

#Preview("City Added Confirmation") {
    CityAddedConfirmationView(message: "Oxford was added to Europe.")
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemeColors.light.background)
        .environment(\.appTheme, AppTheme.shared)
}

// MARK: - Add City and First Launch Flows

extension ContentView {
    func scheduleDaytimeSunninessRefetch() {
        Task {
            await refreshCitiesMissingDaytimeSunninessData()
        }
    }

    func refreshCitiesMissingDaytimeSunninessData() async {
        let dayOffset = selectedDayOffset
        let citiesToRefresh = mapCities.filter { cityWeather in
            let forecast = cityWeather.forecast(for: dayOffset)
            return !SunninessScoring.hasDaytimeHourlyScoreData(for: forecast, timeZone: cityWeather.timeZone)
        }

        for cityWeather in citiesToRefresh {
            let refetchKey = "\(cityWeather.id.uuidString)-\(dayOffset)"
            guard !daytimeScoreRefetchKeys.contains(refetchKey) else { continue }
            daytimeScoreRefetchKeys.insert(refetchKey)
            _ = await weatherService.refreshWeatherForCity(cityWeather)
        }
    }

    var listPreviewDestination: some View {
        homeContent(previewActive: true)
            .navigationTitle(listPreviewState.name ?? localizedString("List of Cities", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                showingMapExpandedCard = false
                centerMapOnDots(useListCoordinates: true)
            }
    }

    func previewGeneratedList(name: String, cities: [City], nameSource: CityListNameSource? = nil) {
        listPreviewState.name = name
        listPreviewState.nameSource = nameSource
        listPreviewState.allCities = cities
        listPreviewState.cityCount = min(
            CountryCityCatalog.defaultCountryCityCount,
            min(CountryCityCatalog.maxCountryCityCount, cities.count)
        )
        citySearchState.isPresented = false
        showingMapExpandedCard = false
        selectedMapCity = nil
        citySearchState.temporaryMapCity = nil
        navigationPath.removeAll { $0 == .listPreview }
        Haptics.lightImpact()
        pushRoute(.listPreview)
    }

    func previewContinentList(_ listID: CityListID) {
        let populationSortedCities = CountryCityCatalog.topCities(
            forContinentRawValue: listID.rawValue,
            limit: CountryCityCatalog.maxCountryCityCount
        )
        previewGeneratedList(
            name: listID.localizedDisplayName(locale: locale),
            cities: populationSortedCities.isEmpty ? listID.defaultCities : populationSortedCities,
            nameSource: .continent(rawValue: listID.rawValue, duplicateIndex: nil)
        )
    }

    func previewCountryList(_ country: CountryListOption) {
        previewGeneratedList(
            name: country.localizedName(locale: locale),
            cities: CountryCityCatalog.topCities(for: country, limit: CountryCityCatalog.maxCountryCityCount),
            nameSource: .country(iso2: country.iso2, duplicateIndex: nil)
        )
    }

    func cancelGeneratedListPreview() {
        popRoute(.listPreview)
    }

    func clearGeneratedListPreview(playsHaptic: Bool = true) {
        listPreviewState.name = nil
        listPreviewState.nameSource = nil
        listPreviewState.allCities = []
        listPreviewState.cityCount = CountryCityCatalog.defaultCountryCityCount
        if playsHaptic {
            Haptics.lightImpact()
        }
    }

    func confirmGeneratedListPreview() {
        guard let previewName = listPreviewState.name,
              !listPreviewCities.isEmpty else { return }
        let generatedIdentity = listPreviewState.nameSource.map {
            CityListID.availableGeneratedListIdentity(for: $0, locale: locale)
        }
        let uniqueName = generatedIdentity?.displayName ?? CityListID.availableListName(for: previewName)
        let nameSource = generatedIdentity?.nameSource
        let cities = listPreviewCities
        cancelGeneratedListPreview()

        Task {
            _ = await weatherService.createCustomList(name: uniqueName, cities: cities, nameSource: nameSource)
            await MainActor.run {
                refreshListOrder()
                centerMapOnDots(useListCoordinates: true)
                AppDelegate.updateHomeScreenListShortcuts()
            }
        }
    }
}

// MARK: - Loading Overlay

private struct LoadingWeatherOverlay: View {
    let progress: Double
    let locale: Locale

    @Environment(\.appTheme) private var theme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        HStack(spacing: 10) {
            ProgressView(value: progress)
                .progressViewStyle(.circular)

            Text(localizedString("Loading Weather", locale: locale))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            if colorSchemeContrast == .increased {
                Capsule().fill(theme.colors.glassFill)
            } else {
                Capsule().fill(.regularMaterial)
            }
        }
        .overlay {
            if colorSchemeContrast == .increased {
                Capsule().stroke(theme.colors.primaryText, lineWidth: 1)
            }
        }
        // Accessibility: Expose determinate progress as one concise status element.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localizedString("Loading Weather", locale: locale))
        .accessibilityValue("\(Int((min(max(progress, 0), 1) * 100).rounded()))%")
    }
}
