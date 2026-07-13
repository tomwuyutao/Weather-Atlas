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
                    selectedCountryListIDs: $countryListTutorialSelectedIDs,
                    creationProgress: weatherService.loadingProgress,
                    onSelectContinentList: finishTutorialWithContinentList,
                    onSelectCountryList: finishTutorialWithCountryList,
                    onFinish: applyContinentListTutorialSelection,
                    onCancel: nil
                )
            }
            .fullScreenCover(isPresented: $showingReplayTutorial) {
                TutorialView(
                    includesContinentSelection: false,
                    continentLists: [],
                    selectedContinentListIDs: $continentListTutorialSelectedIDs,
                    selectedCountryListIDs: $countryListTutorialSelectedIDs,
                    creationProgress: 0,
                    onSelectContinentList: { _ in },
                    onSelectCountryList: { _ in },
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
            .sheet(isPresented: $showingListManagementSheet) {
                listManagementSheet
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(theme.colors.mapOcean)
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
            .overlay {
                cityAddedConfirmationOverlay
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
        .onChange(of: showingCityRenameAlert) { _, isShowing in
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
        .alert(localizedString("Rename", locale: locale), isPresented: $showingCityRenameAlert) {
            TextField(localizedString("Name", locale: locale), text: $renameAlertText)
                .focused($renameAlertFocused)
            Button(localizedString("Cancel", locale: locale), role: .cancel) {
                cityToRename = nil
            }
            Button(localizedString("OK", locale: locale)) {
                let trimmed = renameAlertText.trimmingCharacters(in: .whitespacesAndNewlines)
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
        if let message = addedCityConfirmation {
            CityAddedConfirmationView(message: message)
                .allowsHitTesting(false)
            .transition(.scale(scale: 0.86).combined(with: .opacity))
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: message)
        }
    }

    func showCityAddedConfirmation(_ message: String) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            addedCityConfirmation = message
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard addedCityConfirmation == message else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                addedCityConfirmation = nil
            }
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
                .allowsHitTesting(!showingSearchSheet)

            if !showingSearchSheet {
                mainOverlays
            }

        }
        .tint(theme.colors.accent)
    }

    // MARK: - Startup and External Entry Points

    func onAppearLoad() async {
        AppDelegate.updateHomeScreenListShortcuts()
        let shouldShowFirstLaunchTutorial = !hasLaunchedBefore
        if shouldShowFirstLaunchTutorial {
            showLegend = true
            prepareContinentListTutorialSelection()
            showingFirstLaunchTutorial = true
        }
        if visibleListIDs.isEmpty {
            visibleListIDs = [weatherService.activeListID.rawValue]
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
        continentListTutorialSelectedIDs = []
        countryListTutorialSelectedIDs = []
    }

    func finishTutorialWithContinentList(_ listID: CityListID) async {
        continentListTutorialSelectedIDs = [listID.rawValue]
        countryListTutorialSelectedIDs = []
        await applyContinentListTutorialSelectionAndLoad()
    }

    func finishTutorialWithCountryList(_ country: CountryListOption) async {
        continentListTutorialSelectedIDs = []
        countryListTutorialSelectedIDs = [country.id]
        await applyContinentListTutorialSelectionAndLoad()
    }

    func toggleContinentListTutorialSelection(_ listID: CityListID) {
        if continentListTutorialSelectedIDs.contains(listID.rawValue) {
            continentListTutorialSelectedIDs.remove(listID.rawValue)
        } else {
            continentListTutorialSelectedIDs.insert(listID.rawValue)
        }
        Haptics.lightImpact()
    }

    func toggleCountryListTutorialSelection(_ country: CountryListOption) {
        if countryListTutorialSelectedIDs.contains(country.id) {
            countryListTutorialSelectedIDs.remove(country.id)
        } else {
            countryListTutorialSelectedIDs.insert(country.id)
        }
        Haptics.lightImpact()
    }

    func applyContinentListTutorialSelection() {
        Task {
            await applyContinentListTutorialSelectionAndLoad()
        }
    }

    func applyContinentListTutorialSelectionAndLoad() async {
        let selectedContinentIDs = continentListTutorialSelectedIDs
        let selectedCountryIDs = countryListTutorialSelectedIDs
        guard !selectedContinentIDs.isEmpty || !selectedCountryIDs.isEmpty else { return }
        let selectedLists = CityListID.builtInLists.filter { selectedContinentIDs.contains($0.rawValue) }

        CityListID.keepBuiltInLists(withRawValues: selectedContinentIDs)
        visibleListIDs = selectedContinentIDs
        refreshListOrder()
        navigationPath = []

        var firstList = selectedLists.first
        var createdCountryListIDs: [CityListID] = []
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
            createdCountryListIDs.append(listID)
        }

        if let firstList {
            if firstList.rawValue == weatherService.activeListID.rawValue {
                await weatherService.fetchWeatherForAllCities()
            } else {
                await switchToList(firstList)
            }
        }

        visibleListIDs.formUnion(createdCountryListIDs.map(\.rawValue))
        refreshListOrder()
        mapRecenterRequest = .listCoordinates
        centerMapOnDots(useListCoordinates: true)
        AppDelegate.updateHomeScreenListShortcuts()

        if !mapCities.isEmpty {
            await refreshCitiesMissingDaytimeSunninessData()
        }

        hasLaunchedBefore = true
        showingFirstLaunchTutorial = false
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

    func previewGeneratedList(name: String, cities: [City], nameSource: CityListNameSource? = nil) {
        listPreviewName = name
        listPreviewNameSource = nameSource
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
        dismissRoute(.listPreview)
    }

    func clearGeneratedListPreview(playsHaptic: Bool = true) {
        listPreviewName = nil
        listPreviewNameSource = nil
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
        let generatedIdentity = listPreviewNameSource.map {
            CityListID.availableGeneratedListIdentity(for: $0, locale: locale)
        }
        let uniqueName = generatedIdentity?.displayName ?? CityListID.availableListName(for: previewName)
        let nameSource = generatedIdentity?.nameSource
        let cities = listPreviewCities
        cancelGeneratedListPreview()

        Task {
            let listID = await weatherService.createCustomList(name: uniqueName, cities: cities, nameSource: nameSource)
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
                .foregroundStyle(AppTheme.shared.colors.primaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
