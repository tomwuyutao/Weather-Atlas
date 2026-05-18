//
//  ContentView.swift
//  Weather
//
//  Created by Tom on 25/02/2026.
//

import SwiftUI
import CoreLocation
import MapKit
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @State var weatherService = WeatherService()
    @Environment(\.appTheme) var theme
    var previewLoading: Bool = false

    @State var centerOnCityTrigger: CityWeather?

    @State var selectedDayOffset: Int = -1
    @State var showingCityDetail: Bool = false
    @State var tappedCity: CityWeather?
    @State var showingMapExpandedCard: Bool = false
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore: Bool = false
    @State var selectedTab: Int = 0
    @State private var lastRefreshText: String = ""
    @State var showingAddCityView: Bool = false
    @State var showingAddCityDetail: Bool = false
    @State var addCityDetailCity: CityWeather?
    @State var previewCity: CityWeather?
    @State var previewSearchText: String = ""
    private var showCloudCover: Bool { mapOverlayMode == "cloudCover" }
    private var overlayChartMetric: WeatherChartMetric? {
        switch mapOverlayMode {
        case "cloudCover":     return .cloudCover
        case "precipitation":  return .precipitation
        case "windSpeed":      return .windSpeed
        case "uvIndex":        return .uvIndex
        case "humidity":       return .humidity
        case "visibility":     return .visibility
        default:               return nil
        }
    }
    @State var filterSunny: Bool = false
    @State var showingInlineSearch: Bool = false
    @State var inlineSearchText: String = ""
    @State var inlineSearchManager = CitySearchManager()
    @State var inlineIsLoadingCity = false
    @State var inlineSearchSelectionIndex: Int = 0
    
    @State var recenterOnAllCities: Bool = false
    @AppStorage("temperatureUnit") var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    @AppStorage("distanceUnit") var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue
    @State var showingSettings: Bool = false
    @AppStorage("showLegend") var showLegend: Bool = true
    @State var showingInfo: Bool = false
    @AppStorage("mapOverlayMode") var mapOverlayMode: String = "weather"
    @AppStorage("showDateSlider") var showDateSlider: Bool = true
    @State var visibleListIDs: Set<String> = []
    @Environment(\.locale) var locale
    @Environment(\.colorScheme) var colorScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    #if os(macOS)
    @Environment(\.openSettings) var openSettings
    #endif
    
    /// Cities to display on the map — from the active list + preview city
    private var mapCities: [CityWeather] {
        var result = weatherService.cityWeatherData
        // Include temporary preview city from search
        if let preview = previewCity, !result.contains(where: { $0.city.name == preview.city.name }) {
            result.append(preview)
        }
        return result
    }
    
    /// Cities to display in the list view — from the active list
    var listViewCities: [CityWeather] {
        weatherService.cityWeatherData
    }

    var tempUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
    }

    func timeSinceRefreshText() -> String {
        guard let lastFetch = weatherService.lastFetchDate else {
            return ""
        }
        let elapsed = Date().timeIntervalSince(lastFetch)
        let minutes = Int(elapsed / 60)
        if minutes < 1 {
            return localizedString("Now", locale: locale)
        } else if minutes < 60 {
            return localizedString("\(minutes) m", locale: locale)
        } else {
            let hours = minutes / 60
            return localizedString("\(hours) h", locale: locale)
        }
    }

    var body: some View {
        #if os(macOS)
        macOSView
        #else
        iOSView
        #endif
    }

    #if os(iOS)
    var shouldUseIPadLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    #endif

    var usesFloatingMapCardLayout: Bool {
        #if os(macOS)
        true
        #elseif os(iOS)
        shouldUseIPadLayout
        #else
        false
        #endif
    }

    // MARK: - iOS View
    @Namespace private var tabBarNamespace
    @Namespace var bottomBarNS
    @State var iOSPreviousDayOffset: Int = 0
    @State var dateSwitcherForward: Bool = true
    @State var showingDatePopover: Bool = false
    @State var isDraggingDateSlider: Bool = false
    @State var sliderDragStartDay: Int = 0
    @State var sliderDragFraction: CGFloat = 0

    @AppStorage("isGridView") var isGridView: Bool = false
    @State var gridDragItem: CityWeather?
    @State var listContentOpacity: Double = 1.0
    @State var longPressedCity: CityWeather?
    @State var isEditingListName: Bool = false
    @State var editingListName: String = ""
    @FocusState var listNameFieldFocused: Bool
    @State var showingDeleteListConfirmation: Bool = false
    @State var showingRenameAlert: Bool = false
    @State var renameAlertText: String = ""
    @FocusState var renameAlertFocused: Bool
    @State var showingCityRenameAlert: Bool = false
    @State var cityRenameText: String = ""
    @FocusState var cityRenameFocused: Bool
    @State var cityToRename: CityWeather?
    @State var cityToRenameListID: CityListID?
    @State var listToRenameID: CityListID?
    @State var showingListSwitcher: Bool = false
    @State var showingMapSidebar: Bool = false
    @State var sidebarExpandedListIDs: Set<String> = []
    @State var sidebarEditing: Bool = false
    @State var sidebarAddingList: Bool = false
    @State var sidebarNewListName: String = ""
    @State var sidebarRenamingListID: CityListID?
    @State var sidebarRenamingCityContextID: String?
    @State var sidebarRenameText: String = ""
    @State var sidebarShowingAddListAlert: Bool = false
    @FocusState var sidebarNewListFocused: Bool
    @FocusState var sidebarRenameFocused: Bool
    @State var listManagerIsEditing: Bool = false
    @State var listRenameDrafts: [String: String] = [:]
    @State var listSheetDetent: PresentationDetent = .medium
    @State var showingCountrySearch: Bool = false
    @State var countrySearchText: String = ""
    @FocusState var countrySearchFocused: Bool
    @State var pendingCountryList: String?
    @State var isLoadingPendingCountry: Bool = false
    @State var allCountries: [String] = []
    @State var showingMapStylePopover: Bool = false
    @State var showingMapStyleSheet: Bool = false
    @State var inlineAddTargetListID: CityListID?
    #if os(iOS)
    @State var sidebarEditMode: EditMode = .inactive
    #endif
    #if os(macOS) || os(iOS)
    @State private var macSidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var macMapExpandedCardAnchor: CGPoint?
    @State private var macMapExpandedCardBaseOffset: CGSize = .zero
    @GestureState private var macMapExpandedCardGestureOffset: CGSize = .zero
    @State private var macHoverPresentedCardCityID: UUID?
    @State private var macMapExpandedCardFocusesMarker: Bool = false
    @State var macExpandedCardShowsDetails: Bool = false
    @State var macExpandedCardChartMetric: WeatherChartMetric = .temperature
    @State var macExpandedCardChartRange: WeatherChartTimeRange = .daytime
    @State var macSidebarSelection: String?
    @State var macSidebarDropTarget: String?
    @State var macSidebarContextTarget: String?
    @State var macSidebarRefreshTick: Int = 0
    @State var macExpandedCardHoveredDay: Int?
    @State var macQuickSwitcherVisible: Bool = false
    @State var macQuickSwitcherIndex: Int = 0
    @State var macQuickSwitcherDismissToken: Int = 0
    @State var macQuickSwitcherPendingListID: CityListID?
    @State var macOverlaySwitcherVisible: Bool = false
    @State var macOverlaySwitcherIndex: Int = 0
    @State var macOverlaySwitcherDismissToken: Int = 0
    @State var macMapLookupTaskID: Int = 0
    @State var macMapLookupPreviewCityID: UUID?
    @State var macMapViewportSize: CGSize = .zero
    #endif
    #if os(iOS)
    @State var iPadSidebarVisibility: NavigationSplitViewVisibility = .all
    @State var iPadPreferredCompactColumn: NavigationSplitViewColumn = .detail
    #endif

    var toolbarTitle: String {
        weatherService.activeListID.localizedDisplayName(locale: locale)
    }

    @State var isLoadingMapList: Bool = false
    @State var capsuleSwipeFromTrailing: Bool = true

    // Map style sheet is in ContentView+MapStyleSheet.swift

    // Map expanded card is in ContentView+MapExpandedCard.swift
    // Map date slider is in ContentView+MapDateSlider.swift

    var iOSDateText: String {
        if selectedDayOffset == -1 { return localizedString("Now", locale: locale) }
        if selectedDayOffset == 0 { return localizedString("Today", locale: locale) }
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMMdEEE", options: 0, locale: locale)
        formatter.locale = locale
        return formatter.string(from: Calendar.current.date(byAdding: .day, value: selectedDayOffset, to: Date()) ?? Date())
    }

    private var iOSView: some View {
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
        .toolbar(removing: .title)
        .animation(.easeOut(duration: 0.2), value: showingDeleteListConfirmation)
    }

    #if os(macOS)
    private var macOSView: some View {
        AnyView(macOSRootView)
    }

    private var macOSRootView: some View {
        AnyView(
            NavigationSplitView(columnVisibility: $macSidebarVisibility) {
                macSidebarContent
            } detail: {
                macNavigationContent
            }
        )
        .task { await iOSOnAppear() }
        .onChange(of: weatherService.activeListID) { _, newListID in
            visibleListIDs.insert(newListID.rawValue)
        }
        .onAppear {
            AppTheme.shared.isDetailedMapMode = false
        }
        .onChange(of: selectedDayOffset) { oldValue, _ in
            iOSPreviousDayOffset = oldValue
        }
        .onChange(of: weatherService.isLoading) { wasLoading, isLoading in
            if wasLoading && !isLoading {
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
        .background {
            macCommandReceivers
        }
        .sheet(isPresented: $showingInfo) {
            InfoView(source: .map)
                .frame(minWidth: 420, minHeight: 520)
        }
        .overlay {
            iOSDeleteListConfirmationOverlay
        }
        .containerBackground(theme.colors.background, for: .window)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar(removing: .title)
        .animation(.easeOut(duration: 0.2), value: showingDeleteListConfirmation)
    }

    private var macCommandReceivers: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .weatherPreviousDayCommand)) { _ in
                stepSelectedDay(-1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .weatherNextDayCommand)) { _ in
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
            .onReceive(NotificationCenter.default.publisher(for: .weatherToggleSunnyFilterCommand), perform: handleWeatherToggleSunnyFilterCommand)
            .onReceive(NotificationCenter.default.publisher(for: .weatherToggleLegendCommand), perform: handleWeatherToggleLegendCommand)
            .onReceive(NotificationCenter.default.publisher(for: .weatherOverlayCommand), perform: handleWeatherOverlayCommand)
            .onReceive(NotificationCenter.default.publisher(for: .weatherSwitchListCommand), perform: handleWeatherSwitchListCommand)
            .onReceive(NotificationCenter.default.publisher(for: .weatherNewListCommand), perform: handleWeatherNewListCommand)
            .onReceive(NotificationCenter.default.publisher(for: .weatherToggleSidebarCommand), perform: handleWeatherToggleSidebarCommand)
    }

    private var macSidebarContent: some View {
        NavigationStack {
            macListManagerSidebar
        }
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 54)
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
                    .allowsWindowActivationEvents(true)
                    .zIndex(50)

                Spacer(minLength: 0)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
    }

    private var macNavigationContent: some View {
        NavigationStack {
            macMapAndDetailContent
                .navigationDestination(isPresented: $showingAddCityDetail) {
                    AnyView(iOSAddCityDetailDestination)
                }
        }
    }

    private var macMapAndDetailContent: some View {
        macMapContent
    }

    private var macMapContent: some View {
        ZStack {
            if showingInlineSearch {
                nativeCitySearchScreen
            } else {
                AnyView(
                    iOSMapView
                        .overlay(alignment: .bottomLeading) {
                            if showLegend {
                                MapFloatingLegend(overlayMode: mapOverlayMode, compact: true) {
                                    withAnimation(.smooth(duration: 0.2)) {
                                        showLegend = false
                                    }
                                }
                                    .padding(.leading, 24)
                                    .padding(.bottom, 24)
                                    .transition(.move(edge: .leading).combined(with: .opacity))
                                    .animation(.smooth(duration: 0.22), value: showLegend)
                            }
                        }
                        .overlay(alignment: .trailing) {
                            AnyView(iOSDateSliderOverlay)
                        }
                )

                macMainOverlays

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
            }

            macWindowDragTopArea
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                macToolbarListTitle
            }

            ToolbarSpacer(.flexible)

            ToolbarItemGroup {
                macCenterMapButton

                mapOverlayMenu
            }

            ToolbarItemGroup {
                macLegendButton
                macRefreshButton
                macFilterSunnyButton
            }

        }
        .if(showingInlineSearch) { view in
            view
                .searchable(text: $inlineSearchText, isPresented: $showingInlineSearch, placement: .toolbar, prompt: Text(localizedString("Search for a city", locale: locale)))
                .searchSuggestions {
                    nativeCitySearchSuggestions
                }
                .searchPresentationToolbarBehavior(.avoidHidingContent)
                .onChange(of: inlineSearchText) { _, newValue in
                    inlineSearchManager.search(query: newValue)
                    inlineSearchSelectionIndex = 0
                }
                .onChange(of: showingInlineSearch) { _, isPresented in
                    if !isPresented {
                        resetNativeCitySearch()
                    }
                }
        }
        .onChange(of: showingInlineSearch) { _, isPresented in
            if !isPresented {
                resetNativeCitySearch()
            }
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
    }

    private var macWindowDragTopArea: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 54)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)

            Spacer(minLength: 0)
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    private var macCenterMapButton: some View {
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

    private var macLegendButton: some View {
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

    private var macRefreshButton: some View {
        Button {
            Task { await weatherService.refreshWeather() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
        }
        .tint(.primary)
        .disabled(weatherService.isLoading)
        .help(localizedString("Refresh", locale: locale))
    }

    private var macFilterSunnyButton: some View {
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

    private var macRightSidebarButton: some View {
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

    private var macListSwitcherChevron: some View {
        Menu {
            ForEach(CityListID.allLists) { listID in
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

    private var macToolbarListTitle: some View {
        Menu {
            ForEach(CityListID.allLists) { listID in
                Button(listID.localizedDisplayName(locale: locale)) {
                    Task {
                        await switchToList(listID)
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chevron.down")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 8, height: 8)
                    .fontWeight(.semibold)
                Text(toolbarTitle)
                    .font(.headline)
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.leading, 4)
            .padding(.trailing, 18)
            .fixedSize(horizontal: true, vertical: false)
        }
        .menuIndicator(.hidden)
        .menuOrder(.fixed)
        .tint(.primary)
        .help(localizedString("Switch List", locale: locale))
    }

    private var macMainOverlays: some View {
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

                if showingCountrySearch, !countrySearchText.isEmpty {
                    iOSCountrySearchResults
                        .transition(.opacity)
                        .zIndex(10)
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

    private func macExpandedCardTopLeft(in size: CGSize) -> CGSize {
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

    private func macExpandedCardOffset(in size: CGSize) -> CGSize {
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

    private func macExpandedCardRevealAnchor(in size: CGSize) -> UnitPoint {
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

    private var macKeyboardShortcuts: some View {
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

    private var macTabSwitcherKeyMonitor: some View {
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

    private func centerMapOnVisibleCities() {
        recenterOnAllCities = false
        DispatchQueue.main.async {
            recenterOnAllCities = true
        }
    }

    private func stepSelectedDay(_ delta: Int) {
        if showingInlineSearch {
            return
        }
        selectedDayOffset = max(-1, min(9, selectedDayOffset + delta))
    }

    private func switchListByOffset(_ delta: Int) {
        let lists = CityListID.allLists
        guard let currentIndex = lists.firstIndex(of: weatherService.activeListID), !lists.isEmpty else { return }
        let nextIndex = (currentIndex + delta + lists.count) % lists.count
        Task { await switchToList(lists[nextIndex]) }
    }

    private func switchListByIndex(_ index: Int) {
        let lists = CityListID.allLists
        guard lists.indices.contains(index) else { return }
        Task { await switchToList(lists[index]) }
    }

    private var macQuickSwitcherOverlay: some View {
        let lists = CityListID.allLists
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

    private var macOverlaySwitcherOverlay: some View {
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

    private func handleMacQuickSwitcher(delta: Int) {
        let lists = CityListID.allLists
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

    private func handleMacOverlaySwitcher(delta: Int) {
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

    private func handleWeatherRefreshCommand(_ notification: Notification) {
        Task { await weatherService.refreshWeather() }
    }

    private func handleWeatherToggleSunnyFilterCommand(_ notification: Notification) {
        withAnimation {
            filterSunny.toggle()
            UserDefaults.standard.set(filterSunny, forKey: "menuFilterSunnyState")
        }
    }

    private func handleWeatherToggleLegendCommand(_ notification: Notification) {
        withAnimation(.smooth(duration: 0.2)) {
            showLegend.toggle()
        }
    }

    private func handleWeatherOverlayCommand(_ notification: Notification) {
        guard let mode = notification.object as? String else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            mapOverlayMode = mode
        }
    }

    private func handleWeatherSwitchListCommand(_ notification: Notification) {
        guard let rawValue = notification.object as? String,
              let listID = CityListID.allLists.first(where: { $0.rawValue == rawValue }) else { return }
        Task { await switchToList(listID) }
    }

    private func handleWeatherNewListCommand(_ notification: Notification) {
        createListAtBottom()
    }

    private func handleWeatherToggleSidebarCommand(_ notification: Notification) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            macSidebarVisibility = macSidebarVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    #endif

    #if os(iOS)
    private var iOSNavigationSplitRoot: some View {
        NavigationSplitView(columnVisibility: $iPadSidebarVisibility, preferredCompactColumn: $iPadPreferredCompactColumn) {
            NavigationStack {
                iPadSidebarContent
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
                sidebarExpandedListIDs = Set(CityListID.allLists.map(\.rawValue))
            }
        }
    }

    private var iOSNativeDetailNavigationStack: some View {
        nativeCitySearch(
            NavigationStack {
                Group {
                    if shouldUseIPadLayout {
                        iPadMapContent
                    } else {
                        iPhoneMapTabContent
                    }
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: $showingCityDetail) {
                    AnyView(selectedCityDetailDestination)
                }
                .navigationDestination(isPresented: $showingAddCityDetail) {
                    AnyView(iOSAddCityDetailDestination)
                }
            }
        )
    }

    private var iPadRootView: some View {
        NavigationSplitView(columnVisibility: $iPadSidebarVisibility, preferredCompactColumn: $iPadPreferredCompactColumn) {
            NavigationStack {
                iPadSidebarContent
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            NavigationStack {
                iPadMapContent
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationDestination(isPresented: $showingCityDetail) {
                        AnyView(selectedCityDetailDestination)
                    }
                    .navigationDestination(isPresented: $showingAddCityDetail) {
                        AnyView(iOSAddCityDetailDestination)
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            selectedTab = 1
            if sidebarExpandedListIDs.isEmpty {
                sidebarExpandedListIDs = Set(CityListID.allLists.map(\.rawValue))
            }
        }
    }

    private var iPadSidebarContent: some View {
        macListManagerSidebar
            .scrollContentBackground(.hidden)
            .background(theme.colors.mapOcean)
            .navigationTitle(localizedString("Lists", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sidebarShowingAddListAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sidebarEditMode = sidebarEditMode.isEditing ? .inactive : .active
                        }
                    } label: {
                        Image(systemName: sidebarEditMode.isEditing ? "checkmark" : "pencil")
                    }
                }
            }
            .toolbarBackground(theme.colors.mapOcean, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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

    private var iPadMapContent: some View {
        ZStack {
            if showingInlineSearch {
                nativeCitySearchScreen
            } else {
                iOSMapView
                    .overlay(alignment: .topLeading) {
                        if showLegend {
                            MapFloatingLegend(overlayMode: mapOverlayMode, compact: true) {
                                withAnimation(.smooth(duration: 0.2)) {
                                    showLegend = false
                                }
                            }
                            .padding(.leading, 24)
                            .padding(.top, 68)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .overlay(alignment: .trailing) {
                        AnyView(iOSDateSliderOverlay)
                    }

                iPadFloatingMapOverlays
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text(toolbarTitle)
                    .font(.headline)
                    .lineLimit(1)
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    recenterOnAllCities = false
                    DispatchQueue.main.async {
                        recenterOnAllCities = true
                    }
                } label: {
                    Image(systemName: "dot.squareshape.split.2x2")
                }
                .help(localizedString("Center on Map", locale: locale))

                mapOverlayMenu

                Button {
                    withAnimation(.smooth(duration: 0.2)) {
                        showLegend.toggle()
                    }
                } label: {
                    Image(systemName: showLegend ? "eye.slash" : "eye")
                }
                .help(localizedString("Legend", locale: locale))

                Button {
                    Task { await weatherService.refreshWeather() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(weatherService.isLoading)
                .help(localizedString("Refresh", locale: locale))

                Button {
                    withAnimation {
                        filterSunny.toggle()
                    }
                } label: {
                    Image(systemName: filterSunny ? "sun.max.fill" : "sun.max")
                }
                .help(localizedString("Filter Sunny", locale: locale))

                iOSNativeMenu
            }
        }
        .if(showingInlineSearch) { view in
            view
        }
    }

    private var iPadFloatingMapOverlays: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if showingMapExpandedCard, let city = tappedCity {
                    mapExpandedCard(for: city)
                        .id(city.city.id)
                        .frame(width: 262, height: macExpandedCardShowsDetails ? 620 : 306)
                        .offset(iPadExpandedCardOffset(in: geometry.size))
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
                                insertion: .scale(scale: 0.12, anchor: iPadExpandedCardRevealAnchor(in: geometry.size)).combined(with: .opacity),
                                removal: .scale(scale: 0.12, anchor: iPadExpandedCardRevealAnchor(in: geometry.size)).combined(with: .opacity)
                            )
                        )
                        .zIndex(12)
                }

                if showingCountrySearch, !countrySearchText.isEmpty {
                    iOSCountrySearchResults
                        .transition(.opacity)
                        .zIndex(10)
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

    private func iPadExpandedCardTopLeft(in size: CGSize) -> CGSize {
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

    private func iPadExpandedCardOffset(in size: CGSize) -> CGSize {
        let cardSize = CGSize(width: 262, height: macExpandedCardShowsDetails ? 620 : 306)
        let margin: CGFloat = 16
        let toolbarClearance: CGFloat = 58
        let base = iPadExpandedCardTopLeft(in: size)
        let proposed = CGSize(
            width: base.width + macMapExpandedCardBaseOffset.width + macMapExpandedCardGestureOffset.width,
            height: base.height + macMapExpandedCardBaseOffset.height + macMapExpandedCardGestureOffset.height
        )
        return CGSize(
            width: min(max(proposed.width, margin), size.width - cardSize.width - margin),
            height: min(max(proposed.height, toolbarClearance), size.height - cardSize.height - margin)
        )
    }

    private func iPadExpandedCardRevealAnchor(in size: CGSize) -> UnitPoint {
        guard let markerAnchor = macMapExpandedCardAnchor else {
            return .trailing
        }

        let cardSize = CGSize(width: 262, height: macExpandedCardShowsDetails ? 620 : 306)
        let cardOrigin = iPadExpandedCardOffset(in: size)
        return UnitPoint(
            x: (markerAnchor.x - cardOrigin.width) / cardSize.width,
            y: (markerAnchor.y - cardOrigin.height) / cardSize.height
        )
    }
    #endif

    private var iPhoneNavigationStack: some View {
        nativeCitySearch(
            NavigationStack {
                iPhoneMapTabContent
                    .navigationTitle("")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(showingInlineSearch ? .visible : .hidden, for: .navigationBar)
                    #endif
                    .navigationDestination(isPresented: $showingCityDetail) {
                        AnyView(selectedCityDetailDestination)
                    }
                    .navigationDestination(isPresented: $showingAddCityDetail) {
                        AnyView(iOSAddCityDetailDestination)
                    }
            }
        )
        .onAppear {
            selectedTab = 1
        }
    }

    private var mapTopListMenu: some View {
        Menu {
            ForEach(CityListID.allLists) { listID in
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

    private var iPhoneShowsNativeToolbar: Bool {
        selectedTab != 2 && !isMapSpecialMode && !showingInlineSearch && !showingCountrySearch && previewCity == nil
    }

    private var iPhoneMapTabContent: some View {
        ZStack(alignment: .bottom) {
            if showingInlineSearch {
                nativeCitySearchScreen
            } else {
                AnyView(
                    iOSMapView
                        .overlay(alignment: .topLeading) {
                            if selectedTab == 1, showLegend {
                                MapFloatingLegend(overlayMode: mapOverlayMode) {
                                    withAnimation(.smooth(duration: 0.2)) {
                                        showLegend = false
                                    }
                                }
                                    .padding(.leading, 16)
                                    .padding(.top, 72)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .overlay(alignment: .top) {
                            HStack {
                                Spacer()
                                mapTopListMenu
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            .safeAreaPadding(.top, 8)
                        }
                        .overlay(alignment: .trailing) {
                            AnyView(iOSDateSliderOverlay)
                        }
                )

                iOSMainOverlays
            }
        }
        .overlay(alignment: .bottom) {
            if !showingInlineSearch {
                mapBottomToolbar
                    .padding(.horizontal, 28)
                    .padding(.bottom, -6)
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .bottom)
                    .contentShape(Rectangle())
                    .zIndex(100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showingMapSidebar) {
            iPhoneNativeListManager
        }
        #else
        .sheet(isPresented: $showingMapSidebar) {
            listManagerNavigation
        }
        #endif
    }

    #if os(iOS)
    private var iPhoneNativeListManager: some View {
        NavigationStack {
            macListManagerSidebar
                .scrollContentBackground(.hidden)
                .background(theme.colors.mapOcean)
                .navigationTitle(localizedString("Lists", locale: locale))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingMapSidebar = false
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            sidebarShowingAddListAlert = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                sidebarEditMode = sidebarEditMode.isEditing ? .inactive : .active
                            }
                        } label: {
                            Image(systemName: sidebarEditMode.isEditing ? "checkmark" : "pencil")
                        }
                    }
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
        }
        .background(theme.colors.mapOcean.ignoresSafeArea())
    }
    #endif

    private func iOSOnAppear() async {
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

    private func iOSHandleCityDetailDismiss(showing: Bool) {
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

    @ViewBuilder
    private var iOSDateSliderOverlay: some View {
        // Date slider only on map tab — list tab uses the date switcher capsule
        if selectedTab == 1, !showingInlineSearch, !isMapSpecialMode {
            #if os(macOS)
            GeometryReader { geometry in
                let topClearance: CGFloat = 34
                let bottomClearance: CGFloat = 174
                let availableHeight = max(190, geometry.size.height - topClearance - bottomClearance)
                let sliderHeight = min(300, max(220, availableHeight * 0.52))

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Color.clear
                        .frame(width: 60, height: sliderHeight)
                        .contentShape(Rectangle())
                        .overlay(alignment: .trailing) {
                            mapDateSlider(height: sliderHeight)
                        }
                        .padding(.trailing, 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.top, topClearance)
                .padding(.bottom, bottomClearance)
            }
            .transition(.opacity)
            #else
            Color.clear
                .frame(width: 80, height: 500)
                .contentShape(Rectangle())
                .overlay(alignment: .trailing) {
                    mapDateSlider(height: 420)
                }
                .padding(.bottom, 380)
                .padding(.trailing, 1)
                .transition(.opacity)
            #endif
        }
    }

    private var iOSDatePickerPopover: some View {
        DatePicker(
            "",
            selection: Binding(
                get: {
                    Calendar.current.date(byAdding: .day, value: max(0, selectedDayOffset), to: Date()) ?? Date()
                },
                set: { newDate in
                    let calendar = Calendar.current
                    let components = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: newDate))
                    if let days = components.day {
                        withAnimation(.smooth(duration: 0.2)) {
                            selectedDayOffset = max(0, min(9, days))
                        }
                    }
                }
            ),
            in: Date()...(Calendar.current.date(byAdding: .day, value: 9, to: Date()) ?? Date()),
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
        .frame(width: 280, height: 300)
        .padding(8)
        .presentationCompactAdaptation(.popover)
    }

    // Overlays for country/radial search, expanded card, toolbar
    // Uses AnyView to type-erase and prevent stack overflow from deep generic nesting on device
    private var iOSMainOverlays: some View {
        AnyView(_iOSMainOverlaysContent)
    }

    @ViewBuilder
    private var _iOSMainOverlaysContent: some View {
        if selectedTab == 1, !isMapSpecialMode, showingMapExpandedCard {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showingMapExpandedCard = false
                                tappedCity = nil
                                if previewCity != nil {
                                    previewCity = nil
                                    recenterOnAllCities = true
                                }
                            }
                        }
                        .frame(width: max(0, geometry.size.width - 92))

                    Color.clear
                        .frame(width: 92)
                        .allowsHitTesting(false)
                }
            }
            .zIndex(10)
        }

        if selectedTab == 1, !isMapSpecialMode, showingMapExpandedCard, let city = tappedCity {
            mapExpandedCard(for: city, hideCityName: shouldHideInlineMapCardCityName)
                .id(city.city.id)
                .padding(.horizontal, 26)
                .padding(.vertical, shouldAddInlineMapCardVerticalPadding ? 8 : 0)
                .padding(.bottom, previewCity != nil ? 92 : 64)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.4, anchor: .bottom).combined(with: .opacity).combined(with: .offset(y: 20)),
                        removal: .scale(scale: 0.4, anchor: .bottom).combined(with: .opacity).combined(with: .offset(y: 20))
                    )
                )
                .zIndex(12)
        }

        // Country search results overlay
        if showingCountrySearch, !countrySearchText.isEmpty {
            iOSCountrySearchResults
                .transition(.opacity)
                .zIndex(10)
        }

        // Preview flows still use the transitional bottom bar; the native search tab owns search UI.
        if false {
            iOSUnifiedBottomBar
                .zIndex(11)
        }
    }

    private var iOSMapControlsCapsule: some View {
        HStack(spacing: 8) {
            Button {
                PlatformFeedback.lightImpact()
                recenterOnAllCities = false
                DispatchQueue.main.async {
                    recenterOnAllCities = true
                }
            } label: {
                Image(systemName: "dot.squareshape.split.2x2")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            mapOverlayMenu
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .padding(6)
        .themedGlass(in: .capsule)
        .transition(.scale.combined(with: .opacity))
    }

    private func handleMapMarkerTap(_ city: CityWeather, anchor: CGPoint? = nil) {
        #if os(iOS)
        if !shouldUseIPadLayout, showingMapExpandedCard, tappedCity?.id == city.id {
            return
        }
        #endif
        showMapMarkerCard(city, anchor: anchor, expanded: false, focusesMarker: true)
    }

    private func handleMapBackgroundClick(_ coordinate: CLLocationCoordinate2D, anchor: CGPoint? = nil) {
        #if os(macOS) || os(iOS)
        guard usesFloatingMapCardLayout else {
            dismissMapExpandedCard()
            return
        }

        if showingMapExpandedCard {
            dismissMapExpandedCard()
            return
        }

        macMapLookupTaskID += 1
        let taskID = macMapLookupTaskID
        macMapLookupPreviewCityID = nil
        macMapExpandedCardAnchor = anchor
        macMapExpandedCardBaseOffset = .zero
        Task {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let mapItems: [MKMapItem]
            if let request = MKReverseGeocodingRequest(location: location) {
                mapItems = (try? await request.mapItems) ?? []
            } else {
                mapItems = []
            }
            let mapItem = mapItems.first
            let address = mapItem?.addressRepresentations
            let name = address?.cityName
                ?? mapItem?.name
                ?? address?.regionName
                ?? String(format: "%.2f, %.2f", coordinate.latitude, coordinate.longitude)
            let country = address?.regionName ?? ""
            let city = City(name: name, country: country, latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let cityWeather = await weatherService.fetchWeatherForCity(city) else {
                return
            }
            guard taskID == macMapLookupTaskID else { return }

            await MainActor.run {
                macMapLookupPreviewCityID = cityWeather.id
                previewCity = cityWeather
                tappedCity = cityWeather
                macMapExpandedCardFocusesMarker = true
                macMapExpandedCardAnchor = anchor
                macMapExpandedCardBaseOffset = .zero
                macExpandedCardShowsDetails = false
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    showingMapExpandedCard = true
                }
            }
        }
        #else
        dismissMapExpandedCard()
        #endif
    }

    func dismissMapExpandedCard() {
        #if os(macOS)
        let shouldRecenterAfterDismiss = previewCity != nil && previewCity?.id != macMapLookupPreviewCityID
        #else
        let shouldRecenterAfterDismiss = previewCity != nil
        #endif
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingMapExpandedCard = false
            tappedCity = nil
            previewCity = nil
            if shouldRecenterAfterDismiss {
                recenterOnAllCities = true
            }
            #if os(macOS) || os(iOS)
            macHoverPresentedCardCityID = nil
            macMapExpandedCardFocusesMarker = false
            macMapExpandedCardAnchor = nil
            macMapExpandedCardBaseOffset = .zero
            macExpandedCardShowsDetails = false
            macMapLookupPreviewCityID = nil
            #endif
        }
    }

    func showMapMarkerCard(_ city: CityWeather, anchor: CGPoint? = nil, expanded: Bool, focusesMarker: Bool) {
        #if os(macOS) || os(iOS)
        if usesFloatingMapCardLayout {
            macHoverPresentedCardCityID = nil
            macMapExpandedCardFocusesMarker = focusesMarker
            macExpandedCardShowsDetails = expanded
            macMapExpandedCardAnchor = anchor ?? (focusesMarker ? macCenteredMapMarkerAnchor() : nil)
            macMapExpandedCardBaseOffset = .zero
        }
        #endif

        if showingMapExpandedCard && tappedCity?.id == city.id {
            if usesFloatingMapCardLayout {
                #if os(macOS) || os(iOS)
                macHoverPresentedCardCityID = nil
                macMapExpandedCardFocusesMarker = focusesMarker
                #endif
                return
            } else {
                showingCityDetail = true
                return
            }
        }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            tappedCity = city
            showingMapExpandedCard = true
        }
    }

    private func macCenteredMapMarkerAnchor() -> CGPoint? {
        #if os(macOS) || os(iOS)
        guard macMapViewportSize.width > 0, macMapViewportSize.height > 0 else { return nil }
        return CGPoint(
            x: macMapViewportSize.width / 2 + CGFloat(macMapLeadingFitPadding) * 0.88,
            y: macMapViewportSize.height / 2
        )
        #else
        return nil
        #endif
    }

    #if os(macOS) || os(iOS)
    private func deleteMapCity(_ city: CityWeather) {
        weatherService.removeCity(city)
        if previewCity?.id == city.id {
            previewCity = nil
        }
        showingMapExpandedCard = false
        tappedCity = nil
        selectedDayOffset = -1
        recenterOnAllCities = true
    }

    private func handleMapMarkerCommandHover(_ city: CityWeather?, anchor: CGPoint?) {
        guard let city else {
            if macHoverPresentedCardCityID == tappedCity?.id {
                showingMapExpandedCard = false
                tappedCity = nil
                macHoverPresentedCardCityID = nil
                macMapExpandedCardFocusesMarker = false
                macExpandedCardShowsDetails = false
            }
            return
        }

        guard !showingMapExpandedCard || macHoverPresentedCardCityID != nil else { return }
        macHoverPresentedCardCityID = city.id
        macMapExpandedCardFocusesMarker = false
        macMapExpandedCardAnchor = anchor
        macMapExpandedCardBaseOffset = .zero
        macExpandedCardShowsDetails = false
        tappedCity = city
        showingMapExpandedCard = true
    }
    #endif

    private func renamedCityMatching(_ city: CityWeather) -> CityWeather? {
        weatherService.cityWeatherData.first { candidate in
            candidate.city.latitude == city.city.latitude && candidate.city.longitude == city.city.longitude
        }
    }

    private func detailActionsMenu(for city: CityWeather) -> some View {
        Menu {
            Button {
                showingSettings = true
            } label: {
                Label(localizedString("Settings", locale: locale), systemImage: "gearshape")
            }

            if cityIsInSidebar(city) {
                Button {
                    cityToRename = city
                    cityRenameText = city.city.localizedName(locale: locale)
                    showingCityRenameAlert = true
                } label: {
                    Label {
                        Text(localizedString("Rename", locale: locale))
                    } icon: {
                        Image(systemName: "pencil")
                            .foregroundStyle(.primary)
                    }
                }

                Button(role: .destructive) {
                    weatherService.removeCity(city)
                    showingCityDetail = false
                    showingMapExpandedCard = false
                    tappedCity = nil
                    selectedDayOffset = -1
                    if selectedTab == 1 {
                        recenterOnAllCities = true
                    }
                } label: {
                    Label {
                        Text(localizedString("Delete City", locale: locale))
                    } icon: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
            } else {
                Button {
                    Task {
                        await addCityToSidebar(city)
                        showingCityDetail = false
                        if selectedTab == 1 {
                            recenterOnAllCities = true
                        }
                    }
                } label: {
                    Label(localizedString("Add City", locale: locale), systemImage: "plus")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        #if os(macOS)
        .menuIndicator(.hidden)
        #endif
        .menuOrder(.fixed)
    }

    @ViewBuilder
    private var selectedCityDetailDestination: some View {
        if let city = tappedCity {
            #if os(iOS)
            if !shouldUseIPadLayout {
                iPhoneMapExpandedCardDetailDestination(for: city)
            } else {
                fullWeatherDetailDestination(for: city)
            }
            #else
            fullWeatherDetailDestination(for: city)
            #endif
        }
    }

    private func iPhoneDetailBottomToolbar(for city: CityWeather, dismissAction: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button {
                dismissAction()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .themedGlass(in: .circle)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            detailActionsMenu(for: city)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
                .tint(theme.colors.primaryText)
                .frame(width: 44, height: 44)
                .themedGlass(in: .circle)
                .contentShape(Circle())
        }
    }

    private func iPhoneMapExpandedCardDetailDestination(for city: CityWeather) -> some View {
        expandedCardDetailDestination(for: city, dismissAction: {
            showingCityDetail = false
            selectedDayOffset = -1
        })
    }

    private func expandedCardDetailDestination(for city: CityWeather, dismissAction: @escaping () -> Void) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            mapExpandedCard(for: city, forceMacStyle: true, plainBackground: true)
                .padding(.horizontal, 6)
                .padding(.top, 12)
                .padding(.bottom, 96)
                .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(theme.colors.background.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            iPhoneDetailBottomToolbar(for: city, dismissAction: dismissAction)
                .padding(.horizontal, 28)
                .padding(.bottom, -6)
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .bottom)
                .zIndex(100)
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        #endif
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

    private func fullWeatherDetailDestination(for city: CityWeather) -> some View {
        expandedCardDetailDestination(for: city, dismissAction: {
            showingCityDetail = false
            selectedDayOffset = -1
        })
    }

    private var iOSAddCitySheet: some View {
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
                    }
                }
            )
            .navigationDestination(isPresented: $showingAddCityDetail) {
                iOSAddCityDetailDestination
            }
        }
    }

    @ViewBuilder
    private var iOSAddCityDetailDestination: some View {
        if let city = addCityDetailCity {
            expandedCardDetailDestination(for: city, dismissAction: {
                showingAddCityDetail = false
            })
        }
    }

    @ViewBuilder
    private var iOSDeleteListConfirmationOverlay: some View {
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




    






    @State var isAddingNewList: Bool = false
    
    private var iOSMapView: some View {
        mapView
    }

    private var mapView: some View {
        ZStack {
            MapLibreWebMapView(
                cities: mapCities,
                selectedDayOffset: selectedDayOffset,
                overlayMode: mapOverlayMode,
                filterSunny: filterSunny,
                tappedCity: $tappedCity,
                recenterOnAllCities: $recenterOnAllCities,
                centerOnCity: centerOnCityTrigger,
                leadingFitPadding: macMapLeadingFitPadding,
                focusSelectedMarker: mapFocusSelectedMarker,
                allowsMarkerHover: mapAllowsMarkerHover,
                cameraProfile: mapCameraProfile,
                onMarkerTap: { city, point in
                    handleMapMarkerTap(city, anchor: point)
                },
                onMapClick: { coordinate, point in
                    handleMapBackgroundClick(coordinate, anchor: point)
                },
                onMarkerCommandHover: { city, point in
                    #if os(macOS) || os(iOS)
                    if usesFloatingMapCardLayout {
                        handleMapMarkerCommandHover(city, anchor: point)
                    }
                    #endif
                }
            )
            .ignoresSafeArea()

            if weatherService.isLoading {
                GeometryReader { geo in
                    VStack(spacing: 12) {
                        Image(systemName: "cloud.sun.fill")
                            #if os(macOS)
                            .font(.system(size: 28, weight: .medium))
                            #else
                            .font(.system(size: 40, weight: .medium))
                            #endif
                            .weatherIconStyle(for: "cloud.sun.fill")
                        Text(localizedString("Loading Weather", locale: locale))
                            #if os(macOS)
                            .font(.headline.weight(.semibold))
                            #else
                            .font(.avenir(.title3, weight: .semibold))
                            #endif
                        Capsule()
                            .fill(theme.colors.primaryText.opacity(0.15))
                            .frame(width: 118, height: 3)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(theme.colors.accent)
                                    .frame(width: 118 * weatherService.loadingProgress, height: 3)
                            }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(theme.colors.primaryText.opacity(0.12), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.14), radius: 20, x: 0, y: 10)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .allowsHitTesting(false)
            }

        }
        .background(Color(hex: 0xDDE9EF).ignoresSafeArea())
        .ignoresSafeArea()
    }

    private var macMapLeadingFitPadding: Double {
        #if os(macOS)
        macSidebarVisibility == .detailOnly ? 0 : 220
        #else
        0
        #endif
    }

    private var mapFocusSelectedMarker: Bool {
        #if os(iOS)
        shouldUseIPadLayout ? macMapExpandedCardFocusesMarker : showingMapExpandedCard
        #elseif os(macOS)
        usesFloatingMapCardLayout ? macMapExpandedCardFocusesMarker : false
        #else
        false
        #endif
    }

    private var mapAllowsMarkerHover: Bool {
        #if os(iOS)
        shouldUseIPadLayout
        #else
        true
        #endif
    }

    private var shouldHideInlineMapCardCityName: Bool {
        false
    }

    private var shouldAddInlineMapCardVerticalPadding: Bool {
        #if os(iOS)
        !shouldUseIPadLayout
        #else
        false
        #endif
    }

    private var mapCameraProfile: MapCameraProfile {
        #if os(macOS)
        .desktop
        #else
        .mobile
        #endif
    }

    func cityIsInSidebar(_ cityWeather: CityWeather) -> Bool {
        weatherService.cityWeatherData.contains(where: { $0.city.name == cityWeather.city.name && $0.city.country == cityWeather.city.country })
    }

    private func addCityToSidebar(_ cityWeather: CityWeather) async {
        await weatherService.addCity(cityWeather.city)
        PlatformFeedback.lightImpact()
        // Update the tapped city to the newly added one from the sidebar
        if let newCity = weatherService.cityWeatherData.first(where: { $0.city.name == cityWeather.city.name && $0.city.country == cityWeather.city.country }) {
            tappedCity = newCity
        }
    }

    @ViewBuilder
    func addCityButton(dismissExpanded: Bool) -> some View {
        let allLists = CityListID.allLists
        if allLists.count > 1 {
            Menu {
                ForEach(allLists) { listID in
                    Button(listID.localizedDisplayName(locale: locale)) {
                        if let city = previewCity {
                            Task {
                                if listID == weatherService.activeListID {
                                    await addCityToSidebar(city)
                                } else {
                                    await weatherService.addCityToList(city.city, listID: listID)
                                    PlatformFeedback.lightImpact()
                                }
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    if dismissExpanded { showingMapExpandedCard = false }
                                    previewCity = nil
                                }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
        } else {
            Button {
                if let city = previewCity {
                    Task {
                        await addCityToSidebar(city)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if dismissExpanded { showingMapExpandedCard = false }
                            previewCity = nil
                        }
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
        }
    }
}

enum MarkerDisplayMode {
    case card
    case dot
}

private struct SelectedPulseRing: View {
    enum Shape { case circle, roundedRect }
    let shape: Shape
    var color: Color = .white
    @State private var isPulsing = false

    var body: some View {
        Group {
            switch shape {
            case .circle:
                Circle()
                    .stroke(color.opacity(isPulsing ? 0.3 : 0.8), lineWidth: isPulsing ? 1.5 : 2.5)
                    .frame(width: 30, height: 30)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
            case .roundedRect:
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(isPulsing ? 0.4 : 0.9), lineWidth: isPulsing ? 2.5 : 3)
            }
        }
        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isPulsing)
        .onAppear { isPulsing = true }
    }
}

struct WeatherMarker: View {
    let cityWeather: CityWeather
    let dayOffset: Int
    let isCompact: Bool
    let namespace: Namespace.ID
    let showCloudCover: Bool
    var overlayMode: String = "weather"
    var filterSunny: Bool = false
    var passesFilter: Bool = true
    var displayMode: MarkerDisplayMode = .card
    var isSelected: Bool = false
    var hideCityName: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue
    
    private var tempUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
    }

    private var distUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    private var isNow: Bool { dayOffset == -1 }

    private var forecast: DailyForecast {
        cityWeather.forecast(for: max(0, dayOffset))
    }

    private var showAsDot: Bool { displayMode == .dot }
    private var showAsCard: Bool { displayMode == .card }

    /// Whether the data required by the current overlay mode is available.
    /// When false the entire marker should be hidden.
    private var hasOverlayData: Bool {
        if isNow {
            switch overlayMode {
            case "cloudCover":    return cityWeather.currentCloudCover != nil
            case "precipitation": return true // derived from condition
            case "windSpeed":     return cityWeather.currentWindSpeed != nil
            case "uvIndex":       return cityWeather.currentUVIndex != nil
            case "humidity":      return cityWeather.currentHumidity != nil
            case "visibility":    return cityWeather.currentVisibility != nil
            default:              return true
            }
        }
        switch overlayMode {
        case "cloudCover":    return forecast.cloudCover != nil
        case "precipitation": return forecast.precipitationChance != nil
        case "windSpeed":     return forecast.windSpeed != nil
        case "uvIndex":       return forecast.uvIndex != nil
        case "humidity":      return forecast.maxHumidity != nil
        case "visibility":    return forecast.maxVisibility != nil
        default:              return true // "weather" / "temperature" always available
        }
    }

    private var overlayPinText: String {
        switch overlayMode {
        case "cloudCover":
            if isNow {
                guard let cc = cityWeather.currentCloudCover else { return "—" }
                return "\(Int(cc * 100))%"
            }
            guard let cc = forecast.cloudCoverPercent else { return "—" }
            return "\(cc)%"
        case "precipitation":
            if isNow {
                let isRaining = [.rain, .drizzle, .snow].contains(cityWeather.condition)
                return isRaining ? "100%" : "0%"
            }
            guard let pc = forecast.precipitationChance else { return "—" }
            return "\(Int(pc * 100))%"
        case "windSpeed":
            if isNow {
                guard let ws = cityWeather.currentWindSpeed else { return "—" }
                return distUnit.displayWindSpeed(ws)
            }
            guard let ws = forecast.windSpeed else { return "—" }
            return distUnit.displayWindSpeed(ws)
        case "uvIndex":
            if isNow {
                guard let uv = cityWeather.currentUVIndex else { return "—" }
                return "\(uv)"
            }
            guard let uv = forecast.uvIndex else { return "—" }
            return "\(uv)"
        case "humidity":
            if isNow {
                guard let hum = cityWeather.currentHumidity else { return "—" }
                return "\(Int(hum * 100))%"
            }
            guard let hum = forecast.maxHumidity else { return "—" }
            return "\(Int(hum * 100))%"
        case "visibility":
            if isNow {
                guard let km = cityWeather.currentVisibility else { return "—" }
                return km >= 10 ? "\(Int(km))" : String(format: "%.1f", km)
            }
            guard let km = forecast.maxVisibility else { return "—" }
            return km >= 10 ? "\(Int(km))" : String(format: "%.1f", km)
        default:
            return tempUnit.display(isNow ? cityWeather.temperature : forecast.dailyHigh)
        }
    }

    private var dotColor: Color {
        // Temperature overlay: use current temp for "Now", daily high otherwise
        let tempForColor = isNow ? cityWeather.temperature : forecast.dailyHigh
        // Temperature overlay: dark blue #1579C7 (≤-20°C) → cyan #57D3E5 (0°C) → green #8BBD9F (10°C) → yellow #FDA409 (20°C) → red #FB4368 (≥40°C)
        if overlayMode == "temperature" {
            let tempC = tempForColor
            if tempC <= 0 {
                // Dark blue → Cyan: -20 to 0
                let t = Double(max(0, min(1, (tempC - (-20)) / 20.0)))
                return Color(
                    red: Double(0x15) / 255.0 + t * Double(0x57 - 0x15) / 255.0,
                    green: Double(0x79) / 255.0 + t * Double(0xD3 - 0x79) / 255.0,
                    blue: Double(0xC7) / 255.0 + t * Double(0xE5 - 0xC7) / 255.0
                )
            } else if tempC <= 10 {
                // Cyan → Green: 0 to 10
                let t = Double(max(0, min(1, tempC / 10.0)))
                return Color(
                    red: Double(0x57) / 255.0 + t * Double(0x7D - 0x57) / 255.0,
                    green: Double(0xD3) / 255.0 + t * Double(0xD4 - 0xD3) / 255.0,
                    blue: Double(0xE5) / 255.0 + t * Double(0xA0 - 0xE5) / 255.0
                )
            } else if tempC <= 20 {
                // Green → Yellow: 10 to 20
                let t = Double(max(0, min(1, (tempC - 10) / 10.0)))
                return Color(
                    red: Double(0x7D) / 255.0 + t * Double(0xFD - 0x7D) / 255.0,
                    green: Double(0xD4) / 255.0 + t * Double(0xA4 - 0xD4) / 255.0,
                    blue: Double(0xA0) / 255.0 + t * Double(0x09 - 0xA0) / 255.0
                )
            } else {
                // Yellow → Red: 20 to 40
                let t = Double(max(0, min(1, (tempC - 20) / 20.0)))
                return Color(
                    red: Double(0xFD) / 255.0 + t * Double(0xFB - 0xFD) / 255.0,
                    green: Double(0xA4) / 255.0 + t * Double(0x43 - 0xA4) / 255.0,
                    blue: Double(0x09) / 255.0 + t * Double(0x68 - 0x09) / 255.0
                )
            }
        }
        // Cloud cover overlay: dark blue #1579C7 (0% clear) → white (100% cloudy)
        if overlayMode == "cloudCover" {
            let cloudCoverVal: Double? = isNow ? cityWeather.currentCloudCover : forecast.cloudCover
            guard let cloudCoverVal else { return .gray }
            let cover = CGFloat(cloudCoverVal) // 0.0 (clear) to 1.0 (cloudy)
            return Color(
                red: Double(0x15) / 255.0 + Double(cover) * (1.0 - Double(0x15) / 255.0),
                green: Double(0x79) / 255.0 + Double(cover) * (1.0 - Double(0x79) / 255.0),
                blue: Double(0xC7) / 255.0 + Double(cover) * (1.0 - Double(0xC7) / 255.0)
            )
        }
        // Precipitation overlay: white (0%) → cyan #57D3E5 (100%)
        if overlayMode == "precipitation" {
            let chance: CGFloat
            if isNow {
                chance = [.rain, .drizzle, .snow].contains(cityWeather.condition) ? 1.0 : 0.0
            } else {
                guard let precipVal = forecast.precipitationChance else { return .gray }
                chance = CGFloat(precipVal)
            }
            return Color(
                red: 1.0 + Double(chance) * (Double(0x57) / 255.0 - 1.0),
                green: 1.0 + Double(chance) * (Double(0xD3) / 255.0 - 1.0),
                blue: 1.0 + Double(chance) * (Double(0xE5) / 255.0 - 1.0)
            )
        }
        // Wind speed overlay: white (0 km/h) → yellow #FDA409 (100 km/h)
        if overlayMode == "windSpeed" {
            let ws: Double? = isNow ? cityWeather.currentWindSpeed : forecast.windSpeed
            guard let ws else { return .gray }
            let wind = min(1.0, ws / 100.0)
            return Color(
                red: 1.0 + wind * (Double(0xFD) / 255.0 - 1.0),
                green: 1.0 + wind * (Double(0xA4) / 255.0 - 1.0),
                blue: 1.0 + wind * (Double(0x09) / 255.0 - 1.0)
            )
        }
        // UV index overlay: white (0) → red #FB4368 (11+)
        if overlayMode == "uvIndex" {
            let uvVal: Int? = isNow ? cityWeather.currentUVIndex : forecast.uvIndex
            guard let uvVal else { return .gray }
            let uv = min(1.0, Double(uvVal) / 11.0)
            return Color(
                red: 1.0 + uv * (Double(0xFB) / 255.0 - 1.0),
                green: 1.0 + uv * (Double(0x43) / 255.0 - 1.0),
                blue: 1.0 + uv * (Double(0x68) / 255.0 - 1.0)
            )
        }
        // Humidity overlay: white (0%) → purple #BE9AED (100%)
        if overlayMode == "humidity" {
            let hum: Double? = isNow ? cityWeather.currentHumidity : forecast.maxHumidity
            guard let hum else { return .gray }
            return Color(
                red: 1.0 + hum * (Double(0xBE) / 255.0 - 1.0),
                green: 1.0 + hum * (Double(0x9A) / 255.0 - 1.0),
                blue: 1.0 + hum * (Double(0xED) / 255.0 - 1.0)
            )
        }
        // Visibility overlay: white (0 km) → dark blue #1579C7 (30+ km)
        if overlayMode == "visibility" {
            let visVal: Double? = isNow ? cityWeather.currentVisibility : forecast.maxVisibility
            guard let visVal else { return .gray }
            let vis = min(1.0, visVal / 30.0)
            return Color(
                red: 1.0 + vis * (Double(0x15) / 255.0 - 1.0),
                green: 1.0 + vis * (Double(0x79) / 255.0 - 1.0),
                blue: 1.0 + vis * (Double(0xC7) / 255.0 - 1.0)
            )
        }
        // Moon icon in "Now" mode uses purple
        if isNow && baseIcon.contains("moon") {
            return AppTheme.shared.colors.moonIconColor
        }
        // Default weather dot color
        return displayCondition.dotColor
    }

    private var baseCondition: AppWeatherCondition {
        isNow ? cityWeather.condition : forecast.condition
    }

    private var baseIcon: String {
        isNow ? cityWeather.weatherIcon : forecast.weatherIcon
    }

    private var displayIcon: String {
        if filterSunny {
            return passesFilter ? "sun.max.fill" : baseIcon
        }
        // Use plain cloud for rain/drizzle/snow — the animation shows the precipitation
        if baseCondition == .rain || baseCondition == .drizzle || baseCondition == .snow {
            return "cloud.fill"
        }
        return baseIcon
    }

    private var displayCondition: AppWeatherCondition {
        if filterSunny && passesFilter {
            return .clear
        }
        // Match animation to the displayed icon, not raw condition
        let icon = displayIcon
        if icon == "cloud.fill" {
            switch baseCondition {
            case .rain: return .rain
            case .drizzle: return .drizzle
            case .snow: return .snow
            default: return .cloudy
            }
        }
        return baseCondition
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Pulse ring behind everything
            if isSelected {
                SelectedPulseRing(shape: .circle, color: dotColor)
                    .frame(width: 10, height: 10)
            }

            // Dot layer — always present as anchor
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .shadow(color: dotColor.opacity(isSelected ? 0.8 : 0.5), radius: isSelected ? 12 : 4)
                .scaleEffect(isSelected ? 1.5 : 1.0)

            // Pin label layer — floats above the dot
            if showAsCard {
                pinView
                    .fixedSize()
                    .transition(.scale(scale: 0.01, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 10, height: 10, alignment: .bottom)
        .contentShape(Rectangle())
        .opacity(hasOverlayData ? 1 : 0)
        .allowsHitTesting(hasOverlayData)
        .animation(.easeInOut(duration: 0.3), value: displayMode)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .animation(.smooth(duration: 0.4), value: dayOffset)
    }

    private var pinView: some View {
        VStack(spacing: 1) {
            // Temperature — primary, largest
            Text(overlayPinText)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppTheme.shared.colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.4), value: dayOffset)
                .offset(x: 2)
                .animation(.smooth(duration: 0.4), value: overlayMode)

            // City name — secondary, smaller (hidden when detail card is shown)
            if !hideCityName {
                Text(cityWeather.city.localizedName(locale: locale))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.shared.colors.primaryText.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .offset(y: -16)
    }
}

struct MacSidebarMoveDropDelegate: DropDelegate {
    let id: String
    let acceptedTypes: [UTType]
    let setTarget: (String) -> Void
    let clearTarget: (String) -> Void
    let perform: ([NSItemProvider]) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: acceptedTypes)
    }

    func dropEntered(info: DropInfo) {
        guard validateDrop(info: info) else { return }
        setTarget(id)
    }

    func dropExited(info: DropInfo) {
        clearTarget(id)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return nil }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        clearTarget(id)
        return perform(info.itemProviders(for: acceptedTypes + [.text]))
    }
}

extension UTType {
    static let weatherSidebarList = UTType(exportedAs: "com.tomsweather.sidebar-list")
    static let weatherSidebarCity = UTType(exportedAs: "com.tomsweather.sidebar-city")
}

#if os(macOS)
private struct MacTabSwitcherKeyMonitor: NSViewRepresentable {
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
        private var monitor: Any?

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



#Preview {
    let _ = UserDefaults.standard.set(false, forKey: "isGridView")
    let _ = UserDefaults.standard.set(false, forKey: "hasLaunchedBefore")
    ContentView()
}

#Preview("Loading") {
    ContentView(previewLoading: true)
}
