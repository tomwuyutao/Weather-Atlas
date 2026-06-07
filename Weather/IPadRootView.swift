//
//  IPadRootView.swift
//  Weather
//
//  iPad split -view shell.
//

import SwiftUI

#if os(iOS)
extension ContentView {
    var iOSNavigationSplitRoot: some View {
        NavigationSplitView(columnVisibility: $iPadSidebarVisibility, preferredCompactColumn: $iPadPreferredCompactColumn) {
            NavigationStack {
                iPadSidebarContent
            }
            .overlay(alignment: .topTrailing) {
                iPadSidebarToggleTutorialTarget
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            iOSNativeDetailNavigationStack
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            selectedTab = 1
            iPadPreferredCompactColumn = .detail
            if sidebarExpandedListIDs.isEmpty {
                sidebarExpandedListIDs = Set(sidebarLists.map(\.rawValue))
            }
        }
    }

    @ViewBuilder
    var iOSNativeDetailNavigationStack: some View {
        if shouldUseIPadLayout {
            iPadMapNavigationStack
        } else {
            nativeCitySearch(
                NavigationStack {
                    iPhoneMapTabContent
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                        .navigationDestination(isPresented: $showingCityDetail) {
                            AnyView(self.selectedCityDetailDestination)
                        }
                        .navigationDestination(isPresented: $showingAddCityDetail) {
                            AnyView(iOSAddCityDetailDestination)
                        }
                }
            )
        }
    }

    var iPadRootView: some View {
        NavigationSplitView(columnVisibility: $iPadSidebarVisibility, preferredCompactColumn: $iPadPreferredCompactColumn) {
            NavigationStack {
                iPadSidebarContent
            }
            .overlay(alignment: .topTrailing) {
                iPadSidebarToggleTutorialTarget
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            iPadMapNavigationStack
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            selectedTab = 1
            if sidebarExpandedListIDs.isEmpty {
                sidebarExpandedListIDs = Set(sidebarLists.map(\.rawValue))
            }
        }
    }

    var iPadSidebarToggleTutorialTarget: some View {
        Color.clear
            .frame(width: 44, height: 44)
            .padding(.top, 28)
            .padding(.trailing, 8)
            .weatherTutorialTarget(.listManager)
            .allowsHitTesting(false)
    }

    var iPadMapNavigationStack: some View {
        NavigationStack {
            iPadMapContent
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: $showingAddCityDetail) {
                    AnyView(iOSAddCityDetailDestination)
                }
        }
        .onChange(of: inlineSearchText) { _, newValue in
            inlineSearchManager.search(query: newValue)
            inlineSearchSelectionIndex = 0
        }
        .onChange(of: inlineSearchFieldPresented) { _, isPresented in
            if !isPresented {
                showingInlineSearch = false
                resetNativeCitySearch()
            }
        }
        .onChange(of: showingCityDetail) { _, isShowing in
            guard isShowing else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showingMapExpandedCard = false
                previewCity = nil
                macHoverPresentedCardCityID = nil
                macMapExpandedCardFocusesMarker = false
                macExpandedCardShowsDetails = true
            }
        }
        .onSubmit(of: .search) {
            confirmInlineSearchSelection()
        }
        .toolbar {
            iPadMapToolbarContent
        }
    }

    @ToolbarContentBuilder
    var iPadMapToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            mapTopListMenu
                .foregroundStyle(theme.colors.primaryText)
                .tint(theme.colors.primaryText)
                .weatherTutorialTarget(.listSwitcher)
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                centerMapOnDots()
            } label: {
                Image(systemName: "dot.squareshape.split.2x2")
                    .foregroundStyle(.primary)
                    .foregroundColor(.primary)
            }
            .tint(.primary)
            .help(localizedString("Center on Map", locale: locale))

            mapOverlayMenu

            iPadToolbarMoreMenu
        }

        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }

        if showingCityDetail {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    inlineSearchFieldPresented = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.primary)
                        .foregroundColor(.primary)
                }
                .tint(.primary)
                .help(localizedString("Search", locale: locale))
                .popover(isPresented: $inlineSearchFieldPresented) {
                    iPadInspectorSearchPopover
                }
            }
        } else {
            ToolbarItemGroup(placement: .topBarTrailing) {
                iPadToolbarSearchBar
            }
        }
    }

    var iPadToolbarMoreMenu: some View {
        Menu {
            Button {
                showingSettings = true
            } label: {
                Label {
                    Text(localizedString("Settings", locale: locale))
                } icon: {
                    Image(systemName: "gearshape")
                }
            }

            Divider()

            Toggle(isOn: Binding(
                get: { showLegend },
                set: { newValue in withAnimation(.smooth(duration: 0.3)) { showLegend = newValue } }
            )) {
                Label {
                    Text(localizedString("Legend", locale: locale))
                } icon: {
                    Image(systemName: "eye")
                }
            }

            Button {
                refreshActiveWeather()
            } label: {
                Label {
                    Text(localizedString("Refresh", locale: locale) + (timeSinceRefreshText().isEmpty ? "" : " (\(timeSinceRefreshText()))"))
                } icon: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(weatherService.isLoading)

            Toggle(isOn: Binding(
                get: { filterSunny },
                set: { newValue in withAnimation { filterSunny = newValue } }
            )) {
                Label {
                    Text(localizedString("Filter Sunny", locale: locale))
                } icon: {
                    Image(systemName: "sun.max")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.primary)
                .foregroundColor(.primary)
        }
        .menuOrder(.fixed)
    }

    var iPadToolbarSearchBar: some View {
        IPadNativeSearchBar(
            text: $inlineSearchText,
            isPresented: $inlineSearchFieldPresented,
            placeholder: localizedString("Search for a city", locale: locale),
            onSubmit: confirmInlineSearchSelection
        )
        .frame(width: 230, height: 36)
        .weatherTutorialTarget(.search)
        .popover(isPresented: Binding(
            get: { !inlineSearchText.isEmpty && !inlineSortedSearchResults.isEmpty },
            set: { isPresented in
                if !isPresented && !inlineSearchFieldPresented {
                    resetNativeCitySearch()
                }
            }
        )) {
            iPadSearchSuggestionsList
        }
    }

    var iPadInspectorSearchPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            IPadNativeSearchBar(
                text: $inlineSearchText,
                isPresented: $inlineSearchFieldPresented,
                placeholder: localizedString("Search for a city", locale: locale),
                onSubmit: confirmInlineSearchSelection
            )
            .frame(width: 300, height: 36)

            if !inlineSearchText.isEmpty && !inlineSortedSearchResults.isEmpty {
                iPadSearchSuggestionsList
            }
        }
        .padding(12)
        .frame(width: 340)
        .presentationCompactAdaptation(.popover)
    }

    var iPadSearchSuggestionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            nativeCitySearchSuggestions
        }
        .padding(10)
        .frame(width: 320)
        .presentationCompactAdaptation(.popover)
    }

    var iPadSidebarContent: some View {
        macListManagerSidebar
            .navigationTitle(localizedString("Lists", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sidebarShowingAddListAlert = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.primary)
                            .foregroundColor(.primary)
                    }
                    .tint(.primary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sidebarEditMode = sidebarEditMode.isEditing ? .inactive : .active
                        }
                    } label: {
                        Image(systemName: sidebarEditMode.isEditing ? "checkmark" : "pencil")
                            .foregroundStyle(.primary)
                            .foregroundColor(.primary)
                    }
                    .tint(.primary)
                }
            }
            .toolbarBackground(.automatic, for: .navigationBar)
            .tint(.primary)
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

    var iPadMapContent: some View {
        ZStack {
            iOSMapView
                .overlay(alignment: .topLeading) {
                    if !showingInlineSearch {
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
                                MapFloatingLegend(overlayMode: mapOverlayMode, compact: true) {
                                    withAnimation(.smooth(duration: 0.2)) {
                                        showLegend = false
                                    }
                                }
                                .transition(.scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity))
                            }
                        }
                        .padding(.leading, 12)
                        .padding(.top, 92)
                    }
                }
                .animation(.smooth(duration: 0.22), value: showLegend)
                .animation(.smooth(duration: 0.22), value: weatherService.isLoading)
                .overlay(alignment: .trailing) {
                    if !showingCityDetail {
                        AnyView(iOSDateSliderOverlay)
                    }
                }
                .allowsHitTesting(!showingInlineSearch)

            if !showingInlineSearch {
                iPadFloatingMapOverlays
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .tint(.primary)
        .if(showingInlineSearch) { view in
            view
        }
    }

    var iPadFloatingMapOverlays: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if showingMapExpandedCard {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissMapExpandedCard()
                        }
                        .zIndex(10)
                }

                if showingMapExpandedCard, let city = tappedCity {
                    mapExpandedCard(for: city, forceIPhoneStyle: true)
                        .id(city.city.id)
                        .frame(width: iPadFloatingCardSize.width, height: iPadFloatingCardSize.height)
                        .offset(iPadFloatingCardOffset(in: geometry.size))
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.92, anchor: iPadFloatingCardLocalRevealAnchor(in: geometry.size)).combined(with: .opacity),
                                removal: .scale(scale: 0.92, anchor: iPadFloatingCardLocalRevealAnchor(in: geometry.size)).combined(with: .opacity)
                            )
                        )
                        .zIndex(12)
                }

                if showingCityDetail, let city = tappedCity {
                    let maxAvailableWidth = max(320, geometry.size.width - 48)
                    let panelWidth = min(max(380, geometry.size.width * 0.38), min(460, maxAvailableWidth))
                    let panelHeight = min(max(500, geometry.size.height - 128), max(420, geometry.size.height - 96))

                    iPadFloatingDetailWindow(for: city)
                        .frame(width: panelWidth, height: panelHeight)
                        .offset(x: geometry.size.width - panelWidth - 24, y: 76)
                        .transition(.scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity))
                        .zIndex(20)
                }

            }
            .onAppear {
                macMapViewportSize = geometry.size
            }
            .onChange(of: geometry.size) { _, newSize in
                macMapViewportSize = newSize
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showingMapExpandedCard)
    }

    var iPadInspectorBackground: Color {
        colorScheme == .dark ? Color(hex: 0x262052) : theme.colors.background
    }

    func iPadFloatingDetailWindow(for city: CityWeather) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(city.city.localizedName(locale: locale))
                    .font(.avenir(.headline, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) {
                        showingCityDetail = false
                        iPadInspectorPresentedCityID = nil
                        selectedDayOffset = -1
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .foregroundColor(.primary)
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .tint(.primary)
                .help(localizedString("Close", locale: locale))
            }
            .padding(.leading, 18)
            .padding(.trailing, 10)
            .padding(.vertical, 10)

            Divider()
                .opacity(0.45)

            ScrollView(.vertical, showsIndicators: false) {
                mapExpandedCard(
                    for: city,
                    forceMacStyle: true,
                    forceIPhoneDetailSizing: true,
                    plainBackground: true
                )
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .scrollContentBackground(.hidden)
        }
        .background(iPadInspectorBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.42), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.16), radius: 24, y: 10)
        .onAppear {
            if let overlayChartMetric {
                macExpandedCardChartMetric = overlayChartMetric
            }
            macExpandedCardShowsDetails = true
        }
        .onDisappear {
            macExpandedCardShowsDetails = false
        }
    }

    var iPadFloatingCardSize: CGSize {
        CGSize(width: 312, height: 144)
    }

    func iPadFloatingCardOffset(in size: CGSize) -> CGSize {
        let cardSize = iPadFloatingCardSize
        let margin: CGFloat = 16
        let toolbarClearance: CGFloat = 58
        let markerGap: CGFloat = 50
        let anchor = macMapExpandedCardAnchor ?? CGPoint(
            x: size.width / 2,
            y: size.height / 2
        )
        let proposedRightX = anchor.x + markerGap
        let proposedLeftX = anchor.x - markerGap - cardSize.width
        let hasRoomRight = proposedRightX + cardSize.width <= size.width - margin
        let proposedX = hasRoomRight ? proposedRightX : proposedLeftX
        let proposedY = anchor.y + markerGap

        return CGSize(
            width: min(max(proposedX, margin), size.width - cardSize.width - margin),
            height: min(max(proposedY, toolbarClearance), size.height - cardSize.height - margin)
        )
    }

    func iPadFloatingCardLocalRevealAnchor(in size: CGSize) -> UnitPoint {
        .topLeading
    }

    func iPadMapDetailMorphID(for city: CityWeather) -> String {
        "ipad-map-detail-\(city.id.uuidString)"
    }
}
#endif
