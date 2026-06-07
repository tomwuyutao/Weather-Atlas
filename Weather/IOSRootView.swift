//
//  IOSRootView.swift
//  Weather
//
//  iPhone root shell and iOS presentation flow.
//

import SwiftUI

#if os(iOS)
extension ContentView {
    @ViewBuilder
    private var iOSRootContent: some View {
        if shouldUseIPadLayout {
            iOSNavigationSplitRoot
        } else {
            iPhoneNavigationStack
        }
    }

    var iOSView: some View {
        AnyView(iOSViewAlerts)
    }

    private var iOSViewLifecycle: some View {
        AnyView(iOSRootContent)
            .task { await iOSOnAppear() }
            .background {
                iOSShortcutCommandReceiver
            }
            .onChange(of: weatherService.activeListID) { _, newListID in
                visibleListIDs.insert(newListID.rawValue)
                AppDelegate.updateHomeScreenListShortcuts()
            }
            .onChange(of: inlineSearchText) { _, newValue in
                inlineSearchSelectionIndex = 0
                inlineSearchManager.search(query: newValue)
            }
            .onChange(of: selectedTab) { _, _ in
                AppTheme.shared.isDetailedMapMode = false
            }
            .onChange(of: theme.style) { _, _ in
                if selectedTab == 1 {
                    centerMapOnDots()
                }
            }
    }

    private var iOSViewStateObservers: some View {
        AnyView(iOSViewLifecycle)
            .onChange(of: selectedDayOffset) { oldValue, _ in
                iOSPreviousDayOffset = oldValue
            }
            .onChange(of: showingMapExpandedCard) { _, showing in
                if !showing {
                    if previewCity != nil {
                        previewCity = nil
                        recenterOnAllCities = true
                    }
                }
            }
            .onChange(of: showingSettings) { wasShowing, isShowing in
                if isShowing {
                    settingsOpenedThemeStyle = theme.style
                } else if wasShowing {
                    if settingsOpenedThemeStyle != theme.style, selectedTab == 1 {
                        forceReloadMapDots()
                        centerMapOnDots()
                    }
                    settingsOpenedThemeStyle = nil
                }
            }
            .onChange(of: showingCityDetail) { _, showing in
                iOSHandleCityDetailDismiss(showing: showing)
            }
    }

    private var iOSViewSheetsAndOverlays: some View {
        AnyView(iOSViewStateObservers)
            .sheet(isPresented: $showingInfo) {
                InfoView(source: selectedTab == 1 ? .map : .list)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(
                    weatherService: weatherService,
                    onResetLists: {
                        Task {
                            let expandedListIDs = sidebarExpandedListIDs
                            await weatherService.resetAllLists(preloadListIDs: expandedListIDs)
                            await MainActor.run {
                                sidebarExpandedListIDs = Set(CityListID.builtInLists.map(\.rawValue)).intersection(expandedListIDs)
                                sidebarExpandedListIDs.insert(weatherService.activeListID.rawValue)
                                refreshSidebarListOrder()
                                refreshSidebarCityOrder()
                                recenterOnAllCities = true
                                showingSettings = false
                                prepareFirstLaunchListPickerSelection()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                        showingFirstLaunchListPicker = true
                                    }
                                }
                            }
                        }
                    },
                    onPlayTutorial: {
                        showingSettings = false
                        prepareFirstLaunchListPickerSelection()
                        shouldShowFirstLaunchListPickerAfterTutorial = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            startWeatherTutorial()
                        }
                    }
                )
            }
            .onPreferenceChange(WeatherTutorialTargetFramePreferenceKey.self) { frames in
                tutorialTargetFrames = frames
            }
            .overlay {
                iOSDeleteListConfirmationOverlay
            }
            .overlay {
                weatherTutorialOverlay
            }
            .overlay {
                firstLaunchListPickerOverlay
            }
    }

    private var iOSViewAlerts: some View {
        AnyView(iOSViewSheetsAndOverlays)
        .onChange(of: showingRenameAlert) { _, isShowing in
            if isShowing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    renameAlertFocused = true
                }
            } else {
                renameAlertFocused = false
            }
        }
        .onChange(of: showingCityRenameAlert) { _, isShowing in
            if isShowing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    cityRenameFocused = true
                }
            } else {
                cityRenameFocused = false
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
            TextField(localizedString("Name", locale: locale), text: $cityRenameText)
                .focused($cityRenameFocused)
            Button(localizedString("Cancel", locale: locale), role: .cancel) { }
            Button(localizedString("OK", locale: locale)) {
                let trimmed = cityRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, let city = cityToRename {
                    if let cityToRenameListID {
                        weatherService.renameCity(city, in: cityToRenameListID, to: trimmed)
                    } else {
                        weatherService.renameCity(city, to: trimmed)
                    }
                }
                cityToRenameListID = nil
            }
        }
        .animation(.easeOut(duration: 0.2), value: showingDeleteListConfirmation)
    }

    var iOSShortcutCommandReceiver: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .weatherOpenListShortcutCommand)) { notification in
                guard let rawValue = notification.object as? String else { return }
                handleOpenListShortcut(rawValue: rawValue)
            }
    }

    var iPhoneNavigationStack: some View {
        NavigationStack(path: $iPhoneNavigationPath) {
            ZStack {
                nativeCitySearch(iPhoneMapDestination)
                    .allowsHitTesting(!showingMapSidebar)

                if showingMapSidebar {
                    iPhoneNativeListManager
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .animation(.smooth(duration: 0.24), value: showingMapSidebar)
            .navigationDestination(for: IPhoneNavigationRoute.self) { route in
                switch route {
                case .map:
                    EmptyView()
                case .cityDetail:
                    AnyView(self.selectedCityDetailDestination)
                case .addCityDetail:
                    AnyView(iOSAddCityDetailDestination)
                case .listManager:
                    AnyView(iPhoneNativeListManager)
                }
            }
        }
        .onAppear {
            selectedTab = 1
        }
    }

    var iPhoneMapDestination: some View {
        iPhoneMapTabContent
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(showingInlineSearch ? .visible : .hidden, for: .navigationBar)
            #endif
    }

    var mapTopListMenu: some View {
        Menu {
            ForEach(sidebarLists) { listID in
                Button(listID.localizedDisplayName(locale: locale)) {
                    Task {
                        await switchToList(listID)
                    }
                }
            }
        } label: {
            #if os(macOS)
            HStack(spacing: 0) {
                Text(toolbarTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 4)
            .frame(minWidth: 88)
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(Rectangle())
            #else
            HStack(spacing: 8) {
                Text(toolbarTitle)
                    .font(.headline)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(Capsule())
            #endif
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .weatherTutorialTarget(.listSwitcher)
        #endif
        #if os(macOS)
        .tint(.primary)
        .menuIndicator(.hidden)
        #endif
        .menuOrder(.fixed)
    }

    var iPhoneShowsNativeToolbar: Bool {
        selectedTab != 2 && !isMapSpecialMode && !showingInlineSearch && previewCity == nil
    }

    var iPhoneMapTabContent: some View {
        ZStack(alignment: .bottom) {
            AnyView(
                iOSMapView
                    .overlay(alignment: .topLeading) {
                        if selectedTab == 1, !showingInlineSearch {
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
                    .overlay(alignment: .top) {
                        if !showingInlineSearch {
                            HStack {
                                Spacer()
                                mapTopListMenu
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            .safeAreaPadding(.top, 8)
                        }
                    }
                    .overlay(alignment: .trailing) {
                        AnyView(iOSDateSliderOverlay)
                    }
            )
            .allowsHitTesting(!showingInlineSearch)

            if !showingInlineSearch {
                iOSMainOverlays
            }

            if !showingInlineSearch && !showingMapSidebar {
                iPhoneFloatingBottomToolbarFallback
                    .padding(.horizontal, 16)
                    .padding(.bottom, -2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

        }
        .toolbar {
            if #available(iOS 26.0, *), !showingInlineSearch && !showingMapSidebar {
                iPhoneNativeBottomToolbar
            }
        }
        .tint(.primary)
    }

    #if os(iOS)
    var iPhoneNativeListManager: some View {
        ZStack(alignment: .bottom) {
            macListManagerSidebar
                .scrollContentBackground(.hidden)
                .background(theme.colors.mapOcean)
                .tint(.primary)

            iPhoneListManagerFloatingToolbarFallback
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
                                pushIPhoneRoute(.map)
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
                                sidebarShowingAddListAlert = true
                            } label: {
                                Image(systemName: "plus")
                                    .foregroundStyle(.primary)
                                    .foregroundColor(.primary)
                                    .frame(width: 44, height: 44)
                            }
                            .tint(.primary)

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    sidebarEditMode = sidebarEditMode.isEditing ? .inactive : .active
                                }
                            } label: {
                                Image(systemName: sidebarEditMode.isEditing ? "checkmark" : "pencil")
                                    .foregroundStyle(.primary)
                                    .foregroundColor(.primary)
                                    .frame(width: 44, height: 44)
                            }
                            .tint(.primary)
                        }
                    }
                }
            }
            .iPhoneNativeBottomToolbarBackground()
            .alert(localizedString("New List", locale: locale), isPresented: $sidebarShowingAddListAlert) {
                TextField(localizedString("Name", locale: locale), text: $sidebarNewListName)
                Button(localizedString("Cancel", locale: locale), role: .cancel) {
                    sidebarNewListName = ""
                }
                Button(localizedString("Add", locale: locale)) {
                    commitListManagerNewList()
                }
            }
    }
    @ViewBuilder
    var iPhoneListManagerFloatingToolbarFallback: some View {
        if #available(iOS 26.0, *) {
            EmptyView()
        } else {
            HStack(spacing: 0) {
                Button {
                    withAnimation(.smooth(duration: 0.24)) {
                        pushIPhoneRoute(.map)
                    }
                } label: {
                    Image(systemName: "map")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.plain)
                .tint(.primary)
                .iPhoneFloatingToolbarCapsule()

                Spacer(minLength: 12)

                HStack(spacing: 0) {
                    Button {
                        sidebarShowingAddListAlert = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 21, weight: .regular))
                            .foregroundStyle(.primary)
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(.plain)
                    .tint(.primary)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sidebarEditMode = sidebarEditMode.isEditing ? .inactive : .active
                        }
                    } label: {
                        Image(systemName: sidebarEditMode.isEditing ? "checkmark" : "pencil")
                            .font(.system(size: 21, weight: .regular))
                            .foregroundStyle(.primary)
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(.plain)
                    .tint(.primary)
                }
                .iPhoneFloatingToolbarCapsule()
            }
        }
    }
    #endif

    func pushIPhoneRoute(_ route: IPhoneNavigationRoute) {
        if route == .map {
            iPhoneNavigationPath = []
            showingMapSidebar = false
            return
        }
        guard !iPhoneNavigationPath.contains(route) else { return }
        iPhoneNavigationPath.append(route)
    }

    func dismissIPhoneRoute(_ route: IPhoneNavigationRoute) {
        switch route {
        case .map:
            withAnimation(.smooth(duration: 0.24)) {
                showingMapSidebar = true
                showingMapExpandedCard = false
                tappedCity = nil
            }
        case .cityDetail:
            iPhoneNavigationPath.removeAll { $0 == route }
            showingCityDetail = false
        case .addCityDetail:
            iPhoneNavigationPath.removeAll { $0 == route }
            showingAddCityDetail = false
        case .listManager:
            iPhoneNavigationPath.removeAll { $0 == route }
            showingMapSidebar = false
        }
    }

    func iOSOnAppear() async {
        AppDelegate.updateHomeScreenListShortcuts()
        let isFirstLaunch = !hasLaunchedBefore
        if hasLaunchedBefore {
            selectedTab = 1
        } else {
            hasLaunchedBefore = true
            selectedTab = 1
            showLegend = true
            prepareFirstLaunchListPickerSelection()
            shouldShowFirstLaunchListPickerAfterTutorial = true
        }
        if visibleListIDs.isEmpty {
            visibleListIDs = [weatherService.activeListID.rawValue]
        }
        if previewLoading {
            weatherService.isLoading = true
            weatherService.loadingProgress = 0.6
            return
        }
        if previewSkipsInitialWeatherFetch {
            return
        }
        centerMapOnDots(useListCoordinates: true)
        if isFirstLaunch {
            startWeatherTutorial()
        }
        await weatherService.fetchWeatherForAllCities()
        if let pendingShortcutID = AppDelegate.takePendingListShortcutID() {
            handleOpenListShortcut(rawValue: pendingShortcutID)
        }
    }

    func handleOpenListShortcut(rawValue: String) {
        guard let listID = CityListID.allLists.first(where: { $0.rawValue == rawValue }) else { return }
        selectedTab = 1
        selectedDayOffset = -1
        showingSettings = false
        showingInfo = false
        showingInlineSearch = false
        inlineSearchFieldPresented = false
        showingMapSidebar = false
        showingMapExpandedCard = false
        showingCityDetail = false
        tappedCity = nil
        previewCity = nil
        #if os(iOS)
        iPhoneNavigationPath = []
        iPadPreferredCompactColumn = .detail
        #endif

        Task {
            await switchToList(listID)
            await MainActor.run {
                visibleListIDs.insert(listID.rawValue)
                sidebarExpandedListIDs.insert(listID.rawValue)
                recenterOnAllCities = true
                centerMapOnDots(useListCoordinates: true)
                AppDelegate.updateHomeScreenListShortcuts()
            }
        }
    }

    func iOSHandleCityDetailDismiss(showing: Bool) {
        if !showing, showingMapExpandedCard, let city = tappedCity {
            if !weatherService.cityWeatherData.contains(where: { $0.city.name == city.city.name }) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showingMapExpandedCard = false
                    tappedCity = nil
                    recenterOnAllCities = true
                }
            }
        }
    }
}
#endif

extension ContentView {
    @ViewBuilder
    var iOSAddCityDetailDestination: some View {
        if let city = addCityDetailCity {
            expandedCardDetailDestination(for: city, dismissAction: {
                dismissIPhoneRoute(.addCityDetail)
            })
        }
    }

    #if os(iOS)
    @ViewBuilder
    var firstLaunchListPickerOverlay: some View {
        if showingFirstLaunchListPicker {
            theme.colors.modalOverlay
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(localizedString("Choose Lists", locale: locale))
                        .font(.avenir(.headline, weight: .bold))
                        .foregroundStyle(theme.colors.primaryText)

                    Text(localizedString("Pick one or more default continent lists to start with.", locale: locale))
                        .font(.avenir(.subheadline, weight: .regular))
                        .foregroundStyle(theme.colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 0) {
                    ForEach(CityListID.builtInLists) { listID in
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

                        if listID.rawValue != CityListID.builtInLists.last?.rawValue {
                            Divider()
                                .opacity(0.45)
                        }
                    }
                }

                Button {
                    applyFirstLaunchListSelection()
                } label: {
                    HStack {
                        Spacer(minLength: 0)
                        Text(localizedString("OK", locale: locale))
                            .font(.avenir(.body, weight: .semibold))
                        Spacer(minLength: 0)
                    }
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

    func prepareFirstLaunchListPickerSelection() {
        firstLaunchSelectedListIDs = Set(CityListID.builtInLists.map(\.rawValue))
    }

    func toggleFirstLaunchListSelection(_ listID: CityListID) {
        if firstLaunchSelectedListIDs.contains(listID.rawValue) {
            if firstLaunchSelectedListIDs.count > 1 {
                firstLaunchSelectedListIDs.remove(listID.rawValue)
            }
        } else {
            firstLaunchSelectedListIDs.insert(listID.rawValue)
        }
        PlatformFeedback.lightImpact()
    }

    func applyFirstLaunchListSelection() {
        guard !firstLaunchSelectedListIDs.isEmpty else { return }
        let selectedIDs = firstLaunchSelectedListIDs
        let selectedLists = CityListID.builtInLists.filter { selectedIDs.contains($0.rawValue) }
        guard let firstList = selectedLists.first else { return }

        CityListID.keepBuiltInLists(withRawValues: selectedIDs)
        visibleListIDs = selectedIDs
        sidebarExpandedListIDs = selectedIDs
        refreshSidebarListOrder()
        refreshSidebarCityOrder()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            showingFirstLaunchListPicker = false
        }

        Task {
            await switchToList(firstList)
            await MainActor.run {
                recenterOnAllCities = true
                centerMapOnDots(useListCoordinates: true)
                AppDelegate.updateHomeScreenListShortcuts()
            }
        }
    }

    #endif

    @ViewBuilder
    var iOSDeleteListConfirmationOverlay: some View {
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
                        Task {
                            await weatherService.deleteCurrentList()
                        }
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
