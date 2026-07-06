//
//  RootView.swift
//  Weather
//
//  Purpose: Defines the app shell: navigation stack, settings/list sheets,
//  first-launch flow, and lifecycle hooks.
//

import SwiftUI

// MARK: - Root Shell

extension ContentView {

    var listManagerBackground: Color {
        theme.resolvedScheme(for: colorScheme) == .dark ? theme.colors.mapOcean : theme.colors.mapLand
    }

}

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
            }
            .onChange(of: navigationPath) { _, newPath in
                if newPath.isEmpty {
                    routeShowsBackButton = false
                }
            }
            .onChange(of: searchText) { _, newValue in
                searchSelectionIndex = 0
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
                    onAddStarterLists: {
                        showingSettings = false
                        prepareStarterListPickerSelection(allowsCancel: true)
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            showingFirstLaunchListPicker = true
                        }
                    }
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
            .overlay {
                deleteListConfirmationOverlay
            }
            .overlay {
                resetListsLoadingOverlay
            }
            .overlay {
                firstLaunchListPickerOverlay
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
        .animation(.easeOut(duration: 0.2), value: showingDeleteListConfirmation)
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
            ZStack {
                homeView
                    .allowsHitTesting(!showingListManager)

                if showingListManager {
                    nativeListManager
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .zIndex(1)
                }

            }
            .animation(.smooth(duration: 0.24), value: showingListManager)
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
                case .listManager:
                    nativeListManager
                }
            }
        }
    }

    // MARK: - Primary Destinations

    var homeView: some View {
        homeContent
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottom) {
                if !showingSearchSheet {
                    homeBottomToolbar
                        .padding(.horizontal, 16)
                        .padding(.bottom, -2)
                }
            }
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
            .overlay(alignment: .bottom) {
                if !showingSearchSheet {
                    mapBottomToolbar
                        .padding(.horizontal, 16)
                        .padding(.bottom, -2)
                }
            }
            .onAppear {
                centerMapOnDots(useListCoordinates: true)
            }
    }

    var fullListDestination: some View {
        listView
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottom) {
                if !showingSearchSheet {
                    backDateBottomToolbar(.list)
                        .padding(.horizontal, 16)
                        .padding(.bottom, -2)
                }
            }
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
                .overlay(alignment: .trailing) {
                    mapDateSliderOverlay
                }
                .allowsHitTesting(!showingSearchSheet)

            if !showingSearchSheet {
                mainOverlays
            }


        }
        .tint(.primary)
    }

    // MARK: - List Manager Destination

    var nativeListManager: some View {
        ZStack(alignment: .bottom) {
            listManagerContent
                .scrollContentBackground(.hidden)
                .background(listManagerBackground)
                .tint(.primary)

            legacyListManagerFloatingToolbar
                .padding(.horizontal, 16)
                .padding(.bottom, -2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            withAnimation(.smooth(duration: 0.24)) {
                                pushRoute(.map)
                            }
                        } label: {
                            Image(systemName: "map")
                                .foregroundStyle(.primary)
                                .foregroundColor(.primary)
                        }
                        .tint(.primary)

                        Spacer()

                        HStack(spacing: 0) {
                            Button {
                                beginCreatingCustomList()
                            } label: {
                                Image(systemName: "plus")
                                    .foregroundStyle(.primary)
                                    .foregroundColor(.primary)
                                    .frame(width: 44, height: 44)
                            }
                            .tint(.primary)

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    listManagerEditMode = listManagerEditMode.isEditing ? .inactive : .active
                                }
                            } label: {
                                Image(systemName: listManagerEditMode.isEditing ? "checkmark" : "pencil")
                                    .foregroundStyle(.primary)
                                    .foregroundColor(.primary)
                                    .frame(width: 44, height: 44)
                            }
                            .tint(.primary)
                        }
                    }
                }
            }
            .nativeBottomToolbarBackground()
    }

    @ViewBuilder
    var legacyListManagerFloatingToolbar: some View {
        if #available(iOS 26.0, *) {
            EmptyView()
        } else {
            HStack(spacing: 0) {
                Button {
                    withAnimation(.smooth(duration: 0.24)) {
                        pushRoute(.map)
                    }
                } label: {
                    Image(systemName: "map")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.bordered)
                .tint(.primary)

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Button {
                        beginCreatingCustomList()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 21, weight: .regular))
                            .foregroundStyle(.primary)
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            listManagerEditMode = listManagerEditMode.isEditing ? .inactive : .active
                        }
                    } label: {
                        Image(systemName: listManagerEditMode.isEditing ? "checkmark" : "pencil")
                            .font(.system(size: 21, weight: .regular))
                            .foregroundStyle(.primary)
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                }
            }
            .controlSize(.regular)
        }
    }

    // MARK: - Startup and External Entry Points

    func onAppearLoad() async {
        AppDelegate.updateHomeScreenListShortcuts()
        if !hasLaunchedBefore {
            hasLaunchedBefore = true
            showLegend = true
            prepareStarterListPickerSelection(allowsCancel: false)
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                showingFirstLaunchListPicker = true
            }
        }
        if visibleListIDs.isEmpty {
            visibleListIDs = [weatherService.activeListID.rawValue]
        }
        centerMapOnDots(useListCoordinates: true)
        await weatherService.fetchWeatherForAllCities()
        if !mapCities.isEmpty {
            centerMapOnDots(useListCoordinates: true)
        }
        if let pendingShortcutID = AppDelegate.takePendingListShortcutID() {
            handleOpenListShortcut(rawValue: pendingShortcutID)
        }
    }

    func handleOpenListShortcut(rawValue: String) {
        guard let listID = CityListID.allLists.first(where: { $0.rawValue == rawValue }) else { return }
        selectedDayOffset = 0
        showingSettings = false
        showingSearchSheet = false
        searchFieldPresented = false
        showingListManager = false
        showingMapExpandedCard = false
        tappedCity = nil
        temporaryMapSearchCity = nil
        navigationPath = []

        Task {
            await switchToList(listID)
            await MainActor.run {
                visibleListIDs.insert(listID.rawValue)
                expandedListIDs.insert(listID.rawValue)
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

    @ViewBuilder
    var firstLaunchListPickerOverlay: some View {
        if showingFirstLaunchListPicker {
            theme.colors.modalOverlay
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(localizedString("Choose Starter Lists", locale: locale))
                        .font(.avenir(.headline, weight: .bold))
                        .foregroundStyle(theme.colors.primaryText)

                    Text(localizedString("Pick one or more starter lists to add.", locale: locale))
                        .font(.avenir(.subheadline, weight: .regular))
                        .foregroundStyle(theme.colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 0) {
                    ForEach(starterListPickerLists) { listID in
                        Button {
                            toggleFirstLaunchListSelection(listID)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: firstLaunchSelectedListIDs.contains(listID.rawValue) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(firstLaunchSelectedListIDs.contains(listID.rawValue) ? theme.colors.accent : theme.colors.secondaryText)
                                    .frame(width: 24)

                                Text(listID.localizedDisplayName(locale: locale))
                                    .font(.avenir(.body, weight: .medium))
                                    .foregroundStyle(theme.colors.primaryText)

                                Spacer(minLength: 8)
                            }
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if listID.rawValue != starterListPickerLists.last?.rawValue {
                            Divider()
                                .opacity(0.45)
                        }
                    }

                    if starterListPickerLists.isEmpty {
                        Text(localizedString("All starter lists have already been added.", locale: locale))
                            .font(.avenir(.subheadline, weight: .regular))
                            .foregroundStyle(theme.colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 11)
                    }
                }

                HStack(spacing: 10) {
                    if starterListPickerAllowsCancel {
                        Button {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                showingFirstLaunchListPicker = false
                            }
                        } label: {
                            Text(localizedString("Cancel", locale: locale))
                                .font(.avenir(.body, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.colors.primaryText)
                        .background(theme.colors.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    Button {
                        applyStarterListSelection()
                    } label: {
                        Text(localizedString("OK", locale: locale))
                            .font(.avenir(.body, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(
                        (firstLaunchSelectedListIDs.isEmpty ? theme.colors.secondaryText : theme.colors.accent),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .disabled(firstLaunchSelectedListIDs.isEmpty)
                }
            }
            .padding(18)
            .frame(width: min(340, UIScreen.main.bounds.width - 36))
            .background(theme.colors.listCardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 0.7)
            )
            .shadow(color: .black.opacity(0.24), radius: 22, y: 12)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
            .zIndex(1001)
        }
    }

    var starterListPickerLists: [CityListID] {
        if starterListPickerAllowsCancel {
            let availableIDs = Set(CityListID.allLists.map(\.rawValue))
            return CityListID.builtInLists.filter { !availableIDs.contains($0.rawValue) }
        }
        return CityListID.builtInLists
    }

    func prepareStarterListPickerSelection(allowsCancel: Bool) {
        starterListPickerAllowsCancel = allowsCancel
        firstLaunchSelectedListIDs = []
    }

    func toggleFirstLaunchListSelection(_ listID: CityListID) {
        if firstLaunchSelectedListIDs.contains(listID.rawValue) {
            firstLaunchSelectedListIDs.remove(listID.rawValue)
        } else {
            firstLaunchSelectedListIDs.insert(listID.rawValue)
        }
        Haptics.lightImpact()
    }

    func applyStarterListSelection() {
        guard !firstLaunchSelectedListIDs.isEmpty else { return }
        let selectedIDs = firstLaunchSelectedListIDs
        let selectedLists = CityListID.builtInLists.filter { selectedIDs.contains($0.rawValue) }
        guard let firstList = selectedLists.first else { return }

        if starterListPickerAllowsCancel {
            CityListID.addBuiltInLists(withRawValues: selectedIDs)
            visibleListIDs.formUnion(selectedIDs)
            expandedListIDs.formUnion(selectedIDs)
        } else {
            CityListID.keepBuiltInLists(withRawValues: selectedIDs)
            visibleListIDs = selectedIDs
            expandedListIDs = selectedIDs
        }
        refreshListOrder()
        refreshCityOrder()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            showingFirstLaunchListPicker = false
        }

        Task {
            await switchToList(firstList)
            await MainActor.run {
                mapRecenterRequest = .listCoordinates
                centerMapOnDots(useListCoordinates: true)
                AppDelegate.updateHomeScreenListShortcuts()
            }
        }
    }

    // MARK: - Destructive Confirmation Overlays

    @ViewBuilder
    var deleteListConfirmationOverlay: some View {
        if showingDeleteListConfirmation {
            theme.colors.modalOverlay
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showingDeleteListConfirmation = false
                    }
                }
            
            VStack(spacing: 0) {
                Text(localizedString("Delete List", locale: locale))
                    .font(.avenir(.headline, weight: .bold))
                    .padding(.top, 28)
                    .padding(.bottom, 10)
                
                Text(String(format: localizedString("Are you sure you want to delete \"%@\"? This cannot be undone.", locale: locale), weatherService.activeListID.localizedDisplayName(locale: locale)))
                    .font(.avenir(.subheadline, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                
                Divider()
                
                HStack(spacing: 0) {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showingDeleteListConfirmation = false
                        }
                    } label: {
                        Text(localizedString("Cancel", locale: locale))
                            .font(.avenir(.body, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Divider()
                        .frame(height: 44)
                    
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showingDeleteListConfirmation = false
                        }
                        weatherService.deleteCurrentList()
                    } label: {
                        Text(localizedString("Delete", locale: locale))
                            .font(.avenir(.body, weight: .semibold))
                            .foregroundStyle(theme.colors.destructive)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 280)
            .background(theme.colors.listCardFill, in: RoundedRectangle(cornerRadius: 16))
            .transition(.scale(scale: 0.9).combined(with: .opacity))
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
