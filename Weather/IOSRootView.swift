//
//  IOSRootView.swift
//  Weather
//
//  iPhone root shell and iOS presentation flow.
//

import SwiftUI

#if os(iOS)
extension ContentView {
    var iOSView: some View {
        Group {
            #if os(iOS)
            if shouldUseIPadLayout {
                iOSNavigationSplitRoot
            } else {
                iPhoneNavigationStack
            }
            #else
            iPhoneNavigationStack
            #endif
        }
        .task { await iOSOnAppear() }
        .onChange(of: weatherService.activeListID) { _, newListID in
            visibleListIDs.insert(newListID.rawValue)
        }
        .onChange(of: inlineSearchText) { _, newValue in
            inlineSearchSelectionIndex = 0
            inlineSearchManager.search(query: newValue)
        }
        .onChange(of: selectedTab) { _, _ in
            AppTheme.shared.isDetailedMapMode = false
        }
        .onChange(of: selectedDayOffset) { oldValue, _ in
            iOSPreviousDayOffset = oldValue
        }
        .onChange(of: weatherService.isLoading) { wasLoading, isLoading in
            if wasLoading && !isLoading && selectedTab == 1 {
                recenterOnAllCities = true
            }
        }
        .onChange(of: showingMapExpandedCard) { _, showing in
            if !showing {
                if previewCity != nil {
                    previewCity = nil
                    recenterOnAllCities = true
                }
            }
        }
        .onChange(of: showingCityDetail) { _, showing in
            iOSHandleCityDetailDismiss(showing: showing)
        }
        .sheet(isPresented: $showingInfo) {
            InfoView(source: selectedTab == 1 ? .map : .list)
                .presentationSizing(.form)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                weatherService: weatherService,
                onResetLists: {
                    Task {
                        await weatherService.resetAllLists()
                    }
                }
            )
            .presentationSizing(.form)
        }
        .overlay {
            iOSDeleteListConfirmationOverlay
        }
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
        .toolbar(removing: .title)
        .animation(.easeOut(duration: 0.2), value: showingDeleteListConfirmation)
    }

    var iPhoneNavigationStack: some View {
        NavigationStack(path: $iPhoneNavigationPath) {
            iPhoneNativeListManager
                .navigationDestination(for: IPhoneNavigationRoute.self) { route in
                    switch route {
                    case .map:
                        AnyView(nativeCitySearch(iPhoneMapDestination))
                    case .cityDetail:
                        AnyView(self.selectedCityDetailDestination)
                    case .addCityDetail:
                        AnyView(iOSAddCityDetailDestination)
                    case .listManager:
                        EmptyView()
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
                        if selectedTab == 1, showLegend, !showingInlineSearch {
                            MapFloatingLegend(overlayMode: mapOverlayMode) {
                                withAnimation(.smooth(duration: 0.2)) {
                                    showLegend = false
                                }
                            }
                                .padding(.leading, 16)
                                .padding(.top, 72)
                                .transition(.scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity))
                        }
                    }
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

        }
        .toolbar {
            if !showingInlineSearch {
                iPhoneNativeBottomToolbar
            }
        }
        .tint(.primary)
    }

    #if os(iOS)
    var iPhoneNativeListManager: some View {
        macListManagerSidebar
            .scrollContentBackground(.hidden)
            .background(theme.colors.mapOcean)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        pushIPhoneRoute(.map)
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
            .toolbarBackground(.visible, for: .bottomBar)
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
    #endif

    func pushIPhoneRoute(_ route: IPhoneNavigationRoute) {
        guard !iPhoneNavigationPath.contains(route) else { return }
        iPhoneNavigationPath.append(route)
    }

    func dismissIPhoneRoute(_ route: IPhoneNavigationRoute) {
        if route == .map {
            iPhoneNavigationPath = []
        } else {
            iPhoneNavigationPath.removeAll { $0 == route }
        }
        switch route {
        case .map:
            showingMapSidebar = false
            showingMapExpandedCard = false
            tappedCity = nil
        case .cityDetail:
            showingCityDetail = false
        case .addCityDetail:
            showingAddCityDetail = false
        case .listManager:
            showingMapSidebar = false
        }
    }

    func iOSOnAppear() async {
        if hasLaunchedBefore {
            selectedTab = 1
        }
        if !hasLaunchedBefore {
            hasLaunchedBefore = true
        }
        if visibleListIDs.isEmpty {
            visibleListIDs = [weatherService.activeListID.rawValue]
        }
        if previewLoading {
            weatherService.isLoading = true
            weatherService.loadingProgress = 0.6
            return
        }
        await weatherService.fetchWeatherForAllCities()
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
    var iOSAddCitySheet: some View {
        NavigationStack {
            AddCitySearchView(
                cities: weatherService.cityWeatherData,
                citySearchManager: CitySearchManager(),
                weatherService: weatherService,
                onCitySelected: { cityWeather in
                    if selectedTab == 1 {
                        // On map: show as preview marker with expanded card
                        previewCity = cityWeather
                        previewSearchText = cityWeather.city.name
                        tappedCity = cityWeather
                        #if os(macOS)
                        macMapExpandedCardFocusesMarker = false
                        #endif
                        showingAddCityView = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            centerOnCityTrigger = cityWeather
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                showingMapExpandedCard = true
                            }
                        }
                    } else {
                        addCityDetailCity = cityWeather
                        showingAddCityDetail = true
                        pushIPhoneRoute(.addCityDetail)
                    }
                }
            )
            .navigationDestination(isPresented: $showingAddCityDetail) {
                iOSAddCityDetailDestination
            }
        }
    }

    @ViewBuilder
    var iOSAddCityDetailDestination: some View {
        if let city = addCityDetailCity {
            expandedCardDetailDestination(for: city, dismissAction: {
                dismissIPhoneRoute(.addCityDetail)
            })
        }
    }

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
