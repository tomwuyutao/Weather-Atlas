//
//  RootView.swift
//  Weather
//
//  Purpose: Defines the app shell: navigation stack, settings/list sheets,
//  first-launch flow, and lifecycle hooks.
//

import SwiftUI

extension ContentView {
    // MARK: - Root View Assembly

    @ViewBuilder
    private var rootContent: some View {
        appNavigationStack
    }

    var rootView: some View {
        viewAlerts
    }

    private var viewLifecycle: some View {
        rootContent
            .task { await onAppearLoad() }
            .background {
                homeScreenShortcutReceiver
            }
            .onChange(of: weatherService.activeListID) { _, newListID in
                visibleListIDs.insert(newListID.rawValue)
                AppDelegate.updateHomeScreenListShortcuts()
                scheduleDaytimeSunninessRefetch()
            }
            .onChange(of: selectedDayOffset) { _, _ in
                scheduleDaytimeSunninessRefetch()
            }
            .onChange(of: searchText) { _, newValue in
                scheduleCitySearch(for: newValue)
            }
            .onChange(of: theme.style) { _, _ in
                if isMapRoute {
                    centerMapOnDots()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                forceReloadMapDots()
                if isMapRoute {
                    centerMapOnDots(useListCoordinates: true)
                }
            }
    }

    private var viewStateObservers: some View {
        viewLifecycle
            .onChange(of: showingMapExpandedCard) { _, showing in
                if !showing {
                    if temporaryMapSearchCity != nil {
                        temporaryMapSearchCity = nil
                        mapRecenterRequest = .listCoordinates
                    }
                }
            }
            .onChange(of: showingSettings) { wasShowing, isShowing in
                if isShowing {
                    themeStyleBeforeSettings = theme.style
                } else if wasShowing {
                    if themeStyleBeforeSettings != theme.style, isMapRoute {
                        forceReloadMapDots()
                        centerMapOnDots()
                    }
                    themeStyleBeforeSettings = nil
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
                        showingReplayTutorial = true
                    }
                )
            }
            .fullScreenCover(isPresented: $showingFirstLaunchTutorial) {
                TutorialView(
                    includesContinentSelection: true,
                    continentLists: continentListTutorialLists,
                    selectedContinentListIDs: $continentListTutorialSelectedIDs,
                    onToggleContinentList: toggleContinentListTutorialSelection,
                    onFinish: applyContinentListTutorialSelection,
                    onCancel: nil
                )
            }
            .fullScreenCover(isPresented: $showingReplayTutorial) {
                TutorialView(
                    includesContinentSelection: false,
                    continentLists: [],
                    selectedContinentListIDs: $continentListTutorialSelectedIDs,
                    onToggleContinentList: { _ in },
                    onFinish: { showingReplayTutorial = false },
                    onCancel: nil
                )
            }
            .sheet(isPresented: Binding(
                get: { showingSearchSheet },
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
            .sheet(isPresented: $showingCountryListSearchSheet) {
                countryListSearchSheet
                    .presentationDetents([.fraction(0.82), .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(theme.colors.background)
            }
            .sheet(isPresented: $showingAddListOptionsSheet) {
                addListOptionsSheet
                    .presentationDetents([.fraction(0.42), .medium])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(theme.colors.background)
            }
            .sheet(isPresented: $showingContinentListSearchSheet) {
                continentListSearchSheet
                    .presentationDetents([.fraction(0.82), .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(theme.colors.background)
            }
            .overlay {
                resetListsLoadingOverlay
            }
    }

    private var viewAlerts: some View {
        viewSheetsAndOverlays
        .onChange(of: showingRenameAlert) { _, isShowing in
            if isShowing {
                Task { @MainActor in
                    await Task.yield()
                    renameAlertFocused = true
                }
            } else {
                renameAlertFocused = false
            }
        }
        .alert(localizedString("Rename", locale: locale), isPresented: $showingRenameAlert) {
            TextField(localizedString("Name", locale: locale), text: $renameAlertText)
                .focused($renameAlertFocused)
            Button(localizedString("Cancel", locale: locale), role: .cancel) { }
            Button(localizedString("OK", locale: locale)) {
                let trimmed = renameAlertText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if let listToRenameID {
                        weatherService.renameList(listToRenameID, to: trimmed)
                    } else {
                        weatherService.renameCurrentList(to: trimmed)
                    }
                }
                listToRenameID = nil
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
            Button(localizedString("Cancel", locale: locale), role: .cancel) { }
            Button(localizedString("Delete", locale: locale), role: .destructive) {
                weatherService.deleteCurrentList()
            }
        } message: {
            Text(String(
                format: localizedString("Are you sure you want to delete \"%@\"? This cannot be undone.", locale: locale),
                weatherService.activeListID.localizedDisplayName(locale: locale)
            ))
        }
        .toolbar {
            nativeBottomToolbarItems
        }
    }

    var homeScreenShortcutReceiver: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .weatherOpenListShortcut)) { notification in
                guard let rawValue = notification.object as? String else { return }
                handleOpenListShortcut(rawValue: rawValue)
            }
    }

    var appNavigationStack: some View {
        NavigationStack(path: $navigationPath) {
            homeView
            .animation(.spring(response: 0.32, dampingFraction: 0.88), value: showingSearchSheet)
            .navigationDestination(for: AppNavigationRoute.self) { route in
                switch route {
                case .map:
                    fullMapDestination
                case .list:
                    fullListDestination
                case .cityDetail(let cityID):
                    cityDetailDestination(for: cityID)
                case .addCityDetail:
                    addCityDetailDestination
                case .listPreview:
                    listPreviewDestination
                }
            }
        }
    }

    // MARK: - Primary Destinations

    var homeView: some View {
        homeContent(previewActive: false)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                showingMapExpandedCard = false
            }
    }

    var fullMapDestination: some View {
        mapTabContent
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(false)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                centerMapOnDots(useListCoordinates: true)
                showMapDateSliderTutorialIfNeeded()
            }
    }

    var fullListDestination: some View {
        listView
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                showingMapExpandedCard = false
                listEditMode = false
            }
    }

    // MARK: - Map Destination

    var mapTopListMenu: some View {
        listSwitcher(titleOverride: nil)
        .menuOrder(.fixed)
    }

    var mapTabContent: some View {
        ZStack(alignment: .bottom) {
            weatherMapView
                .overlay(alignment: .topLeading) {
                    if isMapRoute, !showingSearchSheet {
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
                    if !showingSearchSheet {
                        HStack(spacing: 8) {
                            mapTopListMenu
                            Spacer(minLength: 8)
                        }
                        .padding(.leading, 16)
                        .padding(.trailing, 16)
                        .safeAreaPadding(.top, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .overlay {
                    if showingMapDateSliderTutorial {
                        Color.black.opacity((colorScheme == .dark ? 0.68 : 0.52) * (isFadingMapDateSliderTutorial ? 0 : 1))
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                            .animation(.easeOut(duration: 0.5), value: isFadingMapDateSliderTutorial)
                    }
                }
                .overlay(alignment: .trailing) {
                    mapDateSliderOverlay
                }
                .overlay(alignment: .trailing) {
                    if showingMapDateSliderTutorial {
                        mapDateSliderTutorialOverlay
                            .opacity(isFadingMapDateSliderTutorial ? 0 : 1)
                            .animation(.easeOut(duration: 0.32).delay(isFadingMapDateSliderTutorial ? 0.12 : 0), value: isFadingMapDateSliderTutorial)
                            .transition(.opacity)
                    }
                }
                .allowsHitTesting(!showingSearchSheet)

            if !showingSearchSheet {
                mainOverlays
            }

        }
        .tint(.primary)
    }

    // MARK: - Startup and External Entry Points

    func onAppearLoad() async {
        AppDelegate.updateHomeScreenListShortcuts()
        if !hasLaunchedBefore {
            showLegend = true
            prepareContinentListTutorialSelection()
            showingFirstLaunchTutorial = true
        }
        if visibleListIDs.isEmpty {
            visibleListIDs = [weatherService.activeListID.rawValue]
        }
        centerMapOnDots(useListCoordinates: true)
        await weatherService.fetchWeatherForAllCities()
        await refreshCitiesMissingDaytimeSunninessData()
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
        continentListTutorialSelectedIDs = [
            CityListID.europe.rawValue,
            CityListID.asia.rawValue
        ]
    }

    func toggleContinentListTutorialSelection(_ listID: CityListID) {
        if continentListTutorialSelectedIDs.contains(listID.rawValue) {
            continentListTutorialSelectedIDs.remove(listID.rawValue)
        } else {
            continentListTutorialSelectedIDs.insert(listID.rawValue)
        }
        Haptics.lightImpact()
    }

    func applyContinentListTutorialSelection() {
        guard !continentListTutorialSelectedIDs.isEmpty else { return }
        let selectedIDs = continentListTutorialSelectedIDs
        let selectedLists = CityListID.builtInLists.filter { selectedIDs.contains($0.rawValue) }
        guard let firstList = selectedLists.first else { return }

        CityListID.keepBuiltInLists(withRawValues: selectedIDs)
        visibleListIDs = selectedIDs
        refreshListOrder()
        hasLaunchedBefore = true
        showingFirstLaunchTutorial = false

        Task {
            await switchToList(firstList)
            await MainActor.run {
                mapRecenterRequest = .listCoordinates
                centerMapOnDots(useListCoordinates: true)
                AppDelegate.updateHomeScreenListShortcuts()
            }
        }
    }

    func handleOpenListShortcut(rawValue: String) {
        guard let listID = CityListID.allLists.first(where: { $0.rawValue == rawValue }) else { return }
        selectedDayOffset = 0
        showingSettings = false
        showingSearchSheet = false
        searchFieldPresented = false
        showingMapExpandedCard = false
        tappedCity = nil
        temporaryMapSearchCity = nil
        clearGeneratedListPreview(playsHaptic: false)
        navigationPath = []

        Task {
            await switchToList(listID)
            await MainActor.run {
                visibleListIDs.insert(listID.rawValue)
                mapRecenterRequest = .listCoordinates
                centerMapOnDots(useListCoordinates: true)
                AppDelegate.updateHomeScreenListShortcuts()
            }
        }
    }
}

extension ContentView {
    // MARK: - Add City and First Launch Flows

    @ViewBuilder
    var addCityDetailDestination: some View {
        if let city = addCityDetailCity {
            cityDetailView(for: city, route: .addCityDetail)
        }
    }

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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                showingMapExpandedCard = false
                mapRecenterRequest = .listCoordinates
                centerMapOnDots(useListCoordinates: true)
            }
    }

    func previewGeneratedList(name: String, cities: [City]) {
        listPreviewName = name
        listPreviewAllCities = cities
        listPreviewCityCount = min(CountryCityCatalog.defaultCountryCityCount, min(CountryCityCatalog.maxCountryCityCount, cities.count))
        showingSearchSheet = false
        showingAddListOptionsSheet = false
        showingContinentListSearchSheet = false
        showingCountryListSearchSheet = false
        showingMapExpandedCard = false
        tappedCity = nil
        temporaryMapSearchCity = nil
        navigationPath.removeAll { $0 == .listPreview }
        Haptics.lightImpact()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            pushRoute(.listPreview)
        }
    }

    func previewContinentList(_ listID: CityListID) {
        let populationSortedCities = CountryCityCatalog.topCities(
            forContinentRawValue: listID.rawValue,
            limit: CountryCityCatalog.maxCountryCityCount
        )
        previewGeneratedList(
            name: listID.localizedDisplayName(locale: locale),
            cities: populationSortedCities.isEmpty ? listID.defaultCities : populationSortedCities
        )
    }

    func previewCountryList(_ country: CountryListOption) {
        previewGeneratedList(
            name: country.localizedName(locale: locale),
            cities: CountryCityCatalog.topCities(for: country, limit: CountryCityCatalog.maxCountryCityCount)
        )
    }

    func cancelGeneratedListPreview() {
        dismissRoute(.listPreview)
    }

    func clearGeneratedListPreview(playsHaptic: Bool = true) {
        listPreviewName = nil
        listPreviewAllCities = []
        listPreviewCityCount = CountryCityCatalog.defaultCountryCityCount
        mapRecenterRequest = .listCoordinates
        if playsHaptic {
            Haptics.lightImpact()
        }
    }

    func confirmGeneratedListPreview() {
        guard let previewName = listPreviewName,
              !listPreviewCities.isEmpty else { return }
        let uniqueName = CityListID.availableListName(for: previewName)
        let cities = listPreviewCities
        cancelGeneratedListPreview()

        Task {
            let listID = await weatherService.createCustomList(name: uniqueName, cities: cities)
            await MainActor.run {
                visibleListIDs.insert(listID.rawValue)
                refreshListOrder()
                mapRecenterRequest = .listCoordinates
                centerMapOnDots(useListCoordinates: true)
                AppDelegate.updateHomeScreenListShortcuts()
            }
        }
    }

    @ViewBuilder
    var resetListsLoadingOverlay: some View {
        if isResettingListsToDefaults {
            theme.colors.modalOverlay
                .ignoresSafeArea()

            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
                .tint(theme.colors.accent)
                .padding(24)
                .background(theme.colors.listCardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 0.7)
                )
                .shadow(color: .black.opacity(0.24), radius: 22, y: 12)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .zIndex(1000)
        }
    }

}

// MARK: - Loading Overlay

private struct LoadingWeatherOverlay: View {
    let progress: Double
    let locale: Locale

    var body: some View {
        HStack(spacing: 10) {
            ProgressView(value: progress)
                .progressViewStyle(.circular)

            Text(localizedString("Loading Weather", locale: locale))
                .font(.avenir(.subheadline, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
