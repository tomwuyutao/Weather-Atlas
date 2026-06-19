//
//  MacRootView.swift
//  Weather
//
//  macOS root shell, toolbar, and keyboard handling.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct LoadingWeatherOverlay: View {
    let progress: Double
    let locale: Locale

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(theme.colors.accent)

            Capsule()
                .fill(theme.colors.primaryText.opacity(0.15))
                .frame(width: 78, height: 3)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(theme.colors.accent)
                        .frame(width: 78 * max(0, min(1, progress)), height: 3)
                }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .themedGlass(in: .capsule)
        .fixedSize()
    }
}

private struct LoadingWeatherAnimationPreview: View {
    @Environment(\.locale) private var locale
    @Environment(\.appTheme) private var theme
    @State private var progress = 0.12

    var body: some View {
        ZStack {
            theme.colors.mapOcean.ignoresSafeArea()

            LoadingWeatherOverlay(
                progress: progress,
                locale: locale
            )
        }
        .frame(width: 360, height: 300)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    withAnimation(.snappy(duration: 0.42)) {
                        progress = progress >= 0.92 ? 0.12 : progress + 0.16
                    }
                }
            }
        }
    }
}

#Preview("Loading Icon Animation") {
    LoadingWeatherAnimationPreview()
}

extension ContentView {
    #if os(macOS)
    var macOSView: some View {
        AnyView(macOSRootView)
    }

    var macOSRootView: some View {
        AnyView(
            NavigationSplitView(columnVisibility: $macSidebarVisibility) {
                macSidebarContent
            } detail: {
                macNavigationContent
            }
        )
        .task { await macOnAppear() }
        .onChange(of: weatherService.activeListID) { _, newListID in
            visibleListIDs.insert(newListID.rawValue)
        }
        .onAppear {
            AppTheme.shared.isDetailedMapMode = false
        }
        .onChange(of: theme.style) { _, _ in
            centerMapOnDots()
        }
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
        .onChange(of: showingCityDetail) { _, showing in
            guard showing else {
                iPadInspectorPinned = false
                if !showingMapExpandedCard {
                    macMapExpandedCardFocusesMarker = false
                    macExpandedCardShowsDetails = false
                }
                return
            }
            withAnimation(iPadInspectorMorphAnimation) {
                showingMapExpandedCard = false
                previewCity = nil
                macHoverPresentedCardCityID = nil
                macExpandedCardShowsDetails = true
            }
        }
        .background {
            macCommandReceivers
        }
        .overlay {
            iOSDeleteListConfirmationOverlay
        }
        .alert(localizedString("New List", locale: locale), isPresented: $sidebarShowingAddListAlert) {
            TextField(localizedString("Name", locale: locale), text: $sidebarNewListName)
            Button(localizedString("Cancel", locale: locale), role: .cancel) {
                sidebarNewListName = ""
            }
            Button(localizedString("Add", locale: locale)) {
                commitListManagerNewList()
            }
        }
        .confirmationDialog(localizedString("New List", locale: locale), isPresented: $showingAddListTypeMenu) {
            Button("Add Custom List") {
                beginCreatingCustomList()
            }
            Button("Add Country List") {
                beginCreatingCountryList()
            }
            Button(localizedString("Cancel", locale: locale), role: .cancel) {}
        }
        .animation(.easeOut(duration: 0.2), value: showingDeleteListConfirmation)
    }

    var macCommandReceivers: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .weatherPreviousDayCommand)) { _ in
                if showingInlineSearch, !inlineSearchText.isEmpty {
                    moveInlineSearchSelection(-1)
                    return
                }
                stepSelectedDay(-1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .weatherNextDayCommand)) { _ in
                if showingInlineSearch, !inlineSearchText.isEmpty {
                    moveInlineSearchSelection(1)
                    return
                }
                stepSelectedDay(1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .weatherPreviousListCommand)) { _ in
                switchListByOffset(-1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .weatherNextListCommand)) { _ in
                switchListByOffset(1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .weatherCenterMapCommand)) { _ in
                centerMapOnVisibleCities()
            }
            .onReceive(NotificationCenter.default.publisher(for: .weatherRefreshCommand), perform: handleWeatherRefreshCommand)
            .onReceive(NotificationCenter.default.publisher(for: .weatherSearchCommand)) { _ in
                activateInlineSearch()
            }
            .onReceive(NotificationCenter.default.publisher(for: .weatherNewCountryListCommand)) { _ in
                beginCreatingCountryList()
            }
            .onReceive(NotificationCenter.default.publisher(for: .weatherToggleSunnyFilterCommand), perform: handleWeatherToggleSunnyFilterCommand)
            .onReceive(NotificationCenter.default.publisher(for: .weatherToggleLegendCommand), perform: handleWeatherToggleLegendCommand)
            .onReceive(NotificationCenter.default.publisher(for: .weatherOverlayCommand), perform: handleWeatherOverlayCommand)
            .onReceive(NotificationCenter.default.publisher(for: .weatherSwitchListCommand), perform: handleWeatherSwitchListCommand)
            .onReceive(NotificationCenter.default.publisher(for: .weatherNewListCommand), perform: handleWeatherNewListCommand)
            .onReceive(NotificationCenter.default.publisher(for: .weatherToggleSidebarCommand), perform: handleWeatherToggleSidebarCommand)
    }

    func macOnAppear() async {
        selectedTab = 1
        hasLaunchedBefore = true
        if visibleListIDs.isEmpty {
            visibleListIDs = [weatherService.activeListID.rawValue]
        }
        if sidebarExpandedListIDs.isEmpty {
            sidebarExpandedListIDs = Set(sidebarLists.map(\.rawValue))
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
        await weatherService.fetchWeatherForAllCities()
        if !mapCities.isEmpty {
            centerMapOnDots(useListCoordinates: true)
        }
    }

    var macSidebarContent: some View {
        NavigationStack {
            macListManagerSidebar
        }
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 54)
                    .contentShape(Rectangle())
                    .zIndex(50)

                Spacer(minLength: 0)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
    }

    var macNavigationContent: some View {
        NavigationStack {
            macMapAndDetailContent
                .navigationDestination(isPresented: $showingAddCityDetail) {
                    AnyView(iOSAddCityDetailDestination)
                }
        }
    }

    var macMapAndDetailContent: some View {
        macMapContent
    }

    var macMapContent: some View {
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

                            if showLegend && !countryListSearchMode {
                                MapFloatingLegend(overlayMode: mapOverlayMode, compact: true) {
                                    withAnimation(.smooth(duration: 0.2)) {
                                        showLegend = false
                                    }
                                }
                                .transition(.scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity))
                            }
                        }
                        .padding(.leading, 18)
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
                macIPadStyleFloatingMapOverlays
            }

            if countryListSearchMode {
                GeometryReader { geometry in
                    countryListPreviewControls()
                        .frame(width: macIPadFloatingCardSize.width)
                        .position(macIPadFloatingCardCenter(in: geometry.size))
                        .transition(.opacity)
                        .zIndex(12)
                }
            }

            if !inlineSearchText.isEmpty && !inlineSortedSearchResults.isEmpty {
                macSearchSuggestionsList
                    .background(macInspectorBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.42), lineWidth: 0.8)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.26 : 0.14), radius: 20, y: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 62)
                    .padding(.trailing, 12)
                    .transition(.scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity))
                    .zIndex(30)
            }

            if macQuickSwitcherVisible {
                macQuickSwitcherOverlay
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                    .zIndex(40)
            }

            if macOverlaySwitcherVisible {
                macOverlaySwitcherOverlay
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                    .zIndex(41)
            }

            macWindowDragTopArea
        }
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: inlineSearchText) { _, newValue in
            inlineSearchManager.search(query: newValue)
            inlineSearchSelectionIndex = 0
        }
        .onChange(of: showingInlineSearch) { _, isPresented in
            if !isPresented {
                resetNativeCitySearch()
            }
        }
        .onChange(of: inlineSearchFieldPresented) { _, isPresented in
            showingInlineSearch = isPresented
        }
        .onMoveCommand { direction in
            guard showingInlineSearch, !inlineSearchText.isEmpty else { return }
            switch direction {
            case .up:
                moveInlineSearchSelection(-1)
            case .down:
                moveInlineSearchSelection(1)
            default:
                break
            }
        }
        .onSubmit(of: .search) {
            if showingInlineSearch, !inlineSearchText.isEmpty {
                confirmInlineSearchSelection()
            }
        }
        .background {
            macKeyboardShortcuts
            macTabSwitcherKeyMonitor
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                macToolbarListTitle
            }

            if #available(macOS 26.0, *) {
                ToolbarSpacer(.flexible, placement: .primaryAction)
            } else {
                ToolbarItem(placement: .principal) {
                    Spacer()
                        .frame(minWidth: 120, maxWidth: .infinity)
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                macCenterMapButton
                mapOverlayMenu
                macLegendButton
                macFilterSunnyButton
                macRefreshButton
            }
        }
        .searchable(
            text: $inlineSearchText,
            isPresented: $inlineSearchFieldPresented,
            placement: .toolbar,
            prompt: Text(localizedString("Search for a city", locale: locale))
        )
    }

    var macWindowDragTopArea: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 54)
                .contentShape(Rectangle())

            Spacer(minLength: 0)
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    var macCenterMapButton: some View {
        Button {
            centerMapOnVisibleCities()
        } label: {
            Image(systemName: "dot.squareshape.split.2x2")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
        }
        .tint(.primary)
        .help(localizedString("Center on Map", locale: locale))
    }

    var macLegendButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.2)) {
                showLegend.toggle()
            }
        } label: {
            Image(systemName: showLegend ? "eye.slash" : "eye")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
        }
        .tint(.primary)
        .help(localizedString("Legend", locale: locale))
    }

    var macRefreshButton: some View {
        Button {
            refreshActiveWeather()
        } label: {
            Image(systemName: "arrow.clockwise")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
        }
        .tint(.primary)
        .disabled(weatherService.isLoading)
        .help(localizedString("Refresh", locale: locale))
    }

    var macFilterSunnyButton: some View {
        Button {
            withAnimation {
                filterSunny.toggle()
            }
        } label: {
            Image(systemName: filterSunny ? "sun.max.fill" : "sun.max")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
        }
        .tint(.primary)
        .help(localizedString("Filter Sunny", locale: locale))
    }

    var macToolbarMoreMenu: some View {
        Menu {
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
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
        }
        .menuIndicator(.hidden)
        .menuOrder(.fixed)
        .tint(.primary)
    }

    var macSearchSuggestionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            nativeCitySearchSuggestions
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .frame(width: 348)
    }

    var macRightSidebarButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showingCityDetail.toggle()
            }
        } label: {
            Image(systemName: "sidebar.right")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
        }
        .tint(.primary)
        .disabled(tappedCity == nil)
        .help(localizedString("Details", locale: locale))
    }

    var macListSwitcherChevron: some View {
        Menu {
            ForEach(sidebarLists) { listID in
                Button(listID.localizedDisplayName(locale: locale)) {
                    Task {
                        await switchToList(listID)
                    }
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
        }
        .menuIndicator(.hidden)
        .menuOrder(.fixed)
        .tint(.primary)
        .help(localizedString("Switch List", locale: locale))
    }

    var macToolbarListTitle: some View {
        Menu {
            ForEach(sidebarLists) { listID in
                Button(listID.localizedDisplayName(locale: locale)) {
                    Task {
                        await switchToList(listID)
                    }
                }
            }

            Button {
                beginCreatingListFromSwitcher()
            } label: {
                HStack {
                    Text(localizedString("New List", locale: locale))
                    Spacer()
                    Image(systemName: "plus")
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.monochrome)

                Text(toolbarTitle)
                    .font(.headline)
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .tint(.primary)
        .help(localizedString("Switch List", locale: locale))
    }

    var macMainOverlays: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if selectedTab == 1, !isMapSpecialMode, showingMapExpandedCard, let city = tappedCity {
                    mapExpandedCard(for: city)
                        .id(city.city.id)
                        .frame(width: 262, height: macExpandedCardShowsDetails ? 620 : 306)
                        .offset(macExpandedCardOffset(in: geometry.size))
                        .gesture(
                            DragGesture()
                                .updating($macMapExpandedCardGestureOffset) { value, state, _ in
                                    state = value.translation
                                }
                                .onEnded { value in
                                    macMapExpandedCardBaseOffset.width += value.translation.width
                                    macMapExpandedCardBaseOffset.height += value.translation.height
                                }
                        )
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.12, anchor: macExpandedCardRevealAnchor(in: geometry.size)).combined(with: .opacity),
                                removal: .scale(scale: 0.12, anchor: macExpandedCardRevealAnchor(in: geometry.size)).combined(with: .opacity)
                            )
                        )
                        .zIndex(12)
                }

            }
            .onAppear {
                macMapViewportSize = geometry.size
            }
            .onChange(of: geometry.size) { _, newSize in
                macMapViewportSize = newSize
            }
        }
    }

    var macIPadStyleFloatingMapOverlays: some View {
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
                        .frame(width: macIPadFloatingCardSize.width, height: macIPadFloatingCardSize.height)
                        .matchedGeometryEffect(id: macIPadMapDetailMorphID(for: city), in: iPadMapDetailNamespace, properties: .frame, anchor: .center)
                        .position(macIPadFloatingCardCenter(in: geometry.size))
                        .transition(.opacity)
                        .zIndex(12)
                }

                if showingCityDetail, let city = tappedCity {
                    let panelWidth = macIPadInspectorWidth
                    let panelHeight = min(max(440, geometry.size.height - 104), max(380, geometry.size.height - 84))

                    macIPadFloatingDetailWindow(for: city)
                        .frame(width: panelWidth, height: panelHeight)
                        .matchedGeometryEffect(id: macIPadMapDetailMorphID(for: city), in: iPadMapDetailNamespace, properties: .frame, anchor: .center)
                        .offset(x: geometry.size.width - panelWidth - macIPadFloatingCardTrailingGap, y: geometry.size.height - panelHeight - macIPadInspectorBottomGap)
                        .transition(.opacity)
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
        .animation(iPadInspectorMorphAnimation, value: showingMapExpandedCard)
        .animation(iPadInspectorMorphAnimation, value: showingCityDetail)
    }

    var macInspectorBackground: Color {
        colorScheme == .dark ? Color(hex: 0x262052) : theme.colors.background
    }

    func macIPadFloatingDetailWindow(for city: CityWeather) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                        iPadInspectorPinned.toggle()
                    }
                } label: {
                    Image(systemName: iPadInspectorPinned ? "pin.fill" : "pin")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(iPadInspectorPinned ? theme.colors.accent : theme.colors.primaryText)
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .tint(iPadInspectorPinned ? theme.colors.accent : theme.colors.primaryText)
                .help(localizedString(iPadInspectorPinned ? "Unpin" : "Pin", locale: locale))

                Spacer(minLength: 8)

                Text(city.city.localizedName(locale: locale))
                    .font(.avenir(.headline, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
                    .opacity(iPadDetailHeaderShowsCityName ? 1 : 0)
                    .animation(.smooth(duration: 0.18), value: iPadDetailHeaderShowsCityName)
                    .allowsHitTesting(false)

                Spacer(minLength: 8)

                Button {
                    withAnimation(iPadInspectorMorphAnimation) {
                        showingCityDetail = false
                        iPadInspectorPinned = false
                        macMapExpandedCardFocusesMarker = false
                        macExpandedCardShowsDetails = false
                        selectedDayOffset = -1
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
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

            Color.clear
                .frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    Color.clear
                        .frame(height: 1)
                        .id("MacIPadDetailTop")

                    mapExpandedCard(
                        for: city,
                        forceMacStyle: true,
                        forceIPhoneDetailSizing: false,
                        plainBackground: true
                    )
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .onChange(of: city.id) { _, _ in
                    iPadDetailHeaderShowsCityName = false
                    proxy.scrollTo("MacIPadDetailTop", anchor: .top)
                }
            }
        }
        .background(macInspectorBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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

    var macIPadInspectorWidth: CGFloat { 340 }
    var macIPadFloatingCardTrailingGap: CGFloat { 24 }
    var macIPadFloatingCardBottomGap: CGFloat { 28 }
    var macIPadInspectorBottomGap: CGFloat { 34 }

    var macIPadFloatingCardSize: CGSize {
        CGSize(width: 286, height: 118)
    }

    var iPadInspectorMorphAnimation: Animation {
        .spring(response: 0.5, dampingFraction: 0.92, blendDuration: 0.08)
    }

    func macIPadFloatingCardCenter(in mapSize: CGSize) -> CGPoint {
        CGPoint(
            x: mapSize.width / 2,
            y: mapSize.height - macIPadFloatingCardBottomGap - macIPadFloatingCardSize.height / 2
        )
    }

    func macIPadMapDetailMorphID(for city: CityWeather) -> String {
        "mac-ipad-map-detail-\(city.id.uuidString)"
    }

    func macExpandedCardTopLeft(in size: CGSize) -> CGSize {
        let cardSize = CGSize(width: 262, height: macExpandedCardShowsDetails ? 620 : 306)
        let margin: CGFloat = 16
        let toolbarClearance: CGFloat = 58
        let markerGap: CGFloat = 210
        let anchor = macMapExpandedCardAnchor ?? CGPoint(
            x: size.width - cardSize.width - margin,
            y: size.height - cardSize.height - margin
        )
        let proposed = CGPoint(
            x: anchor.x - cardSize.width - markerGap,
            y: anchor.y - (cardSize.height / 2)
        )
        let clamped = CGPoint(
            x: min(max(proposed.x, margin), size.width - cardSize.width - margin),
            y: min(max(proposed.y, toolbarClearance), size.height - cardSize.height - margin)
        )
        return CGSize(width: clamped.x, height: clamped.y)
    }

    func macExpandedCardOffset(in size: CGSize) -> CGSize {
        let cardSize = CGSize(width: 262, height: macExpandedCardShowsDetails ? 620 : 306)
        let margin: CGFloat = 16
        let toolbarClearance: CGFloat = 58
        let base = macExpandedCardTopLeft(in: size)
        let proposed = CGSize(
            width: base.width + macMapExpandedCardBaseOffset.width + macMapExpandedCardGestureOffset.width,
            height: base.height + macMapExpandedCardBaseOffset.height + macMapExpandedCardGestureOffset.height
        )
        return CGSize(
            width: min(max(proposed.width, margin), size.width - cardSize.width - margin),
            height: min(max(proposed.height, toolbarClearance), size.height - cardSize.height - margin)
        )
    }

    func macExpandedCardRevealAnchor(in size: CGSize) -> UnitPoint {
        guard let markerAnchor = macMapExpandedCardAnchor else {
            return .trailing
        }

        let cardSize = CGSize(width: 262, height: macExpandedCardShowsDetails ? 620 : 306)
        let cardOrigin = macExpandedCardOffset(in: size)
        return UnitPoint(
            x: (markerAnchor.x - cardOrigin.width) / cardSize.width,
            y: (markerAnchor.y - cardOrigin.height) / cardSize.height
        )
    }

    var macKeyboardShortcuts: some View {
        Group {
            Button("") { stepSelectedDay(-1) }
                .keyboardShortcut(.upArrow, modifiers: [])
                .disabled(showingInlineSearch)
            Button("") { stepSelectedDay(1) }
                .keyboardShortcut(.downArrow, modifiers: [])
                .disabled(showingInlineSearch)
            Button("") { activateInlineSearch() }
                .keyboardShortcut("f", modifiers: .command)
            Button("") { switchListByOffset(-1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
            Button("") { switchListByOffset(1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .shift])
            Button("") { switchListByIndex(0) }
                .keyboardShortcut("1", modifiers: .command)
            Button("") { switchListByIndex(1) }
                .keyboardShortcut("2", modifiers: .command)
            Button("") { switchListByIndex(2) }
                .keyboardShortcut("3", modifiers: .command)
            Button("") { switchListByIndex(3) }
                .keyboardShortcut("4", modifiers: .command)
            Button("") { switchListByIndex(4) }
                .keyboardShortcut("5", modifiers: .command)
            Button("") { switchListByIndex(5) }
                .keyboardShortcut("6", modifiers: .command)
            Button("") { switchListByIndex(6) }
                .keyboardShortcut("7", modifiers: .command)
            Button("") { switchListByIndex(7) }
                .keyboardShortcut("8", modifiers: .command)
            Button("") { switchListByIndex(8) }
                .keyboardShortcut("9", modifiers: .command)
            Button("") {
                if showingInlineSearch {
                    dismissInlineSearch()
                } else if macQuickSwitcherVisible || macOverlaySwitcherVisible {
                    withAnimation(.easeOut(duration: 0.12)) {
                        macQuickSwitcherVisible = false
                        macOverlaySwitcherVisible = false
                    }
                } else if showingMapExpandedCard {
                    dismissMapExpandedCard()
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    var macTabSwitcherKeyMonitor: some View {
        MacTabSwitcherKeyMonitor(
            onListSwitch: { delta in handleMacQuickSwitcher(delta: delta) },
            onOverlaySwitch: { delta in handleMacOverlaySwitcher(delta: delta) },
            onSearchMove: { delta in
                guard showingInlineSearch, !inlineSearchText.isEmpty, !inlineSortedSearchResults.isEmpty else {
                    return false
                }
                moveInlineSearchSelection(delta)
                return true
            }
        )
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    func centerMapOnVisibleCities() {
        recenterOnAllCities = false
        DispatchQueue.main.async {
            recenterOnAllCities = true
        }
    }

    func stepSelectedDay(_ delta: Int) {
        if showingInlineSearch {
            return
        }
        selectedDayOffset = max(-1, min(9, selectedDayOffset + delta))
    }

    func switchListByOffset(_ delta: Int) {
        let lists = sidebarLists
        guard let currentIndex = lists.firstIndex(of: weatherService.activeListID), !lists.isEmpty else { return }
        let nextIndex = (currentIndex + delta + lists.count) % lists.count
        Task { await switchToList(lists[nextIndex]) }
    }

    func switchListByIndex(_ index: Int) {
        let lists = sidebarLists
        guard lists.indices.contains(index) else { return }
        Task { await switchToList(lists[index]) }
    }

    var macQuickSwitcherOverlay: some View {
        let lists = sidebarLists
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lists.enumerated()), id: \.element.id) { index, listID in
                let isSelected = index == macQuickSwitcherIndex
                HStack(spacing: 10) {
                    Text(listID.localizedDisplayName(locale: locale))
                        .font(.headline.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? theme.colors.primaryText : theme.colors.primaryText.opacity(0.68))
                        .lineLimit(1)

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isSelected ? theme.colors.accent.opacity(colorScheme == .dark ? 0.22 : 0.14) : Color.clear)
                }
            }
        }
        .frame(width: 220)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.colors.primaryText.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 20, x: 0, y: 10)
    }

    var macOverlaySwitcherOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(mapOverlayOptions.enumerated()), id: \.element.mode) { index, option in
                let isSelected = index == macOverlaySwitcherIndex
                HStack(spacing: 10) {
                    Image(systemName: option.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? theme.colors.accent : theme.colors.primaryText.opacity(0.54))
                        .frame(width: 18)

                    Text(option.label)
                        .font(.headline.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? theme.colors.primaryText : theme.colors.primaryText.opacity(0.68))
                        .lineLimit(1)

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isSelected ? theme.colors.accent.opacity(colorScheme == .dark ? 0.22 : 0.14) : Color.clear)
                }
            }
        }
        .frame(width: 220)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.colors.primaryText.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 20, x: 0, y: 10)
    }

    func handleMacQuickSwitcher(delta: Int) {
        let lists = sidebarLists
        guard !lists.isEmpty else { return }
        let currentIndex = macQuickSwitcherVisible
            ? macQuickSwitcherIndex
            : (lists.firstIndex(of: weatherService.activeListID) ?? 0)
        let nextIndex = (currentIndex + delta + lists.count) % lists.count
        macQuickSwitcherIndex = nextIndex
        macQuickSwitcherPendingListID = lists[nextIndex]
        macQuickSwitcherDismissToken += 1
        let token = macQuickSwitcherDismissToken

        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            macOverlaySwitcherVisible = false
            macQuickSwitcherVisible = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard macQuickSwitcherDismissToken == token else { return }
            let pendingListID = macQuickSwitcherPendingListID
            macQuickSwitcherPendingListID = nil
            withAnimation(.easeOut(duration: 0.16)) {
                macQuickSwitcherVisible = false
            }
            if let pendingListID {
                Task { await switchToList(pendingListID) }
            }
        }
    }

    func handleMacOverlaySwitcher(delta: Int) {
        let options = mapOverlayOptions
        guard !options.isEmpty else { return }
        let currentIndex = macOverlaySwitcherVisible
            ? macOverlaySwitcherIndex
            : (options.firstIndex(where: { $0.mode == mapOverlayMode }) ?? 0)
        let nextIndex = (currentIndex + delta + options.count) % options.count
        macOverlaySwitcherIndex = nextIndex
        macOverlaySwitcherDismissToken += 1
        let token = macOverlaySwitcherDismissToken

        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            macQuickSwitcherVisible = false
            macOverlaySwitcherVisible = true
            mapOverlayMode = options[nextIndex].mode
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard macOverlaySwitcherDismissToken == token else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                macOverlaySwitcherVisible = false
            }
        }
    }

    func handleWeatherRefreshCommand(_ notification: Notification) {
        refreshActiveWeather()
    }

    func handleWeatherToggleSunnyFilterCommand(_ notification: Notification) {
        withAnimation {
            filterSunny.toggle()
            UserDefaults.standard.set(filterSunny, forKey: "menuFilterSunnyState")
        }
    }

    func handleWeatherToggleLegendCommand(_ notification: Notification) {
        withAnimation(.smooth(duration: 0.2)) {
            showLegend.toggle()
        }
    }

    func handleWeatherOverlayCommand(_ notification: Notification) {
        guard let mode = notification.object as? String else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            mapOverlayMode = mode
        }
    }

    func handleWeatherSwitchListCommand(_ notification: Notification) {
        guard let rawValue = notification.object as? String,
              let listID = sidebarLists.first(where: { $0.rawValue == rawValue }) else { return }
        Task { await switchToList(listID) }
    }

    func handleWeatherNewListCommand(_ notification: Notification) {
        beginCreatingListFromSwitcher()
    }

    func handleWeatherToggleSidebarCommand(_ notification: Notification) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            macSidebarVisibility = macSidebarVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    #endif

#if os(macOS)
struct MacTabSwitcherKeyMonitor: NSViewRepresentable {
    let onListSwitch: (Int) -> Void
    let onOverlaySwitch: (Int) -> Void
    let onSearchMove: (Int) -> Bool

    func makeNSView(context: Context) -> EventView {
        let view = EventView()
        view.onListSwitch = onListSwitch
        view.onOverlaySwitch = onOverlaySwitch
        view.onSearchMove = onSearchMove
        return view
    }

    func updateNSView(_ nsView: EventView, context: Context) {
        nsView.onListSwitch = onListSwitch
        nsView.onOverlaySwitch = onOverlaySwitch
        nsView.onSearchMove = onSearchMove
        nsView.updateMonitor()
    }

    final class EventView: NSView {
        var onListSwitch: (Int) -> Void = { _ in }
        var onOverlaySwitch: (Int) -> Void = { _ in }
        var onSearchMove: (Int) -> Bool = { _ in false }
        var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateMonitor()
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        func updateMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.window === event.window else { return event }

                let flags = event.modifierFlags
                let relevantModifiers = flags.intersection([.command, .control, .option, .shift])

                if relevantModifiers.isEmpty {
                    if event.keyCode == 126, self.onSearchMove(-1) {
                        return nil
                    }
                    if event.keyCode == 125, self.onSearchMove(1) {
                        return nil
                    }
                }

                guard event.keyCode == 48 else { return event }

                let delta = flags.contains(.shift) ? -1 : 1
                if flags.contains(.control), !flags.contains(.command) {
                    self.onListSwitch(delta)
                    return nil
                }
                if flags.contains(.option), !flags.contains(.command) {
                    self.onOverlaySwitch(delta)
                    return nil
                }
                return event
            }
        }
    }
}
#endif
}
