//
//  ContentView.swift
//  Weather
//
//  Created by Tom on 25/02/2026.
//

import SwiftUI
import MapKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State var weatherService = WeatherService()
    @Environment(\.appTheme) var theme
    var previewLoading: Bool = false

    @State var countries: [CountryPath] = []
    @State var centerOnCityTrigger: CityWeather?

    @State var selectedCity: CityWeather?
    @State var selectedDayOffset: Int = -1
    @State var isEditMode: Bool = false
    @State private var isZoomedOut: Bool = true
    @State var showingCityDetail: Bool = false
    @State var tappedCity: CityWeather?
    @State var showingMapExpandedCard: Bool = false
    @State private var isFetchingTappedLocation: Bool = false
    @State private var fetchingTappedCoordinate: CLLocationCoordinate2D?
    @Namespace private var popupNamespace
    @State var searchText: String = ""
    @State private var citySearchManager = CitySearchManager()
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore: Bool = false
    @State var selectedTab: Int = 0
    @State private var showingSearchSheet: Bool = true
    @State private var selectedDetent: PresentationDetent = .height(80)
    @State private var lastRefreshText: String = ""
    @State var showingAddCityView: Bool = false
    @State private var showingAddCityDetail: Bool = false
    @State private var addCityDetailCity: CityWeather?
    @State var previewCity: CityWeather?
    @State private var previewSearchText: String = ""
    private var showCloudCover: Bool { mapOverlayMode == "cloudCover" }
    private var showTemperatureOverlay: Bool { mapOverlayMode == "temperature" }
    private var showPrecipitation: Bool { mapOverlayMode == "precipitation" }
    private var overlayChartMetric: WeatherDetailView.ChartMetric? {
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
    @State private var inlineSearchText: String = ""
    @FocusState private var inlineSearchFocused: Bool
    @State private var inlineSearchManager = CitySearchManager()
    
    @State private var mapScale: CGFloat = 10.0
    @State private var mapOffset: CGSize = .zero
    @State private var mapLastScale: CGFloat = 10.0
    @State private var mapLastOffset: CGSize = .zero
    @State var mapHasInitialized: Bool = false
    @State var recenterOnAllCities: Bool = false
    @State var detailOpenedFromList: Bool = false
    @State var listTappedCityID: UUID?
    @AppStorage("temperatureUnit") var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    @AppStorage("distanceUnit") var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue
    @State var showingSettings: Bool = false
    @AppStorage("showLegend") var showLegend: Bool = true
    @State var showingInfo: Bool = false
    @AppStorage("mapMode") var mapMode: String = "maplibre"
    @AppStorage("mapOverlayMode") var mapOverlayMode: String = "weather"
    @AppStorage("showDateSlider") var showDateSlider: Bool = true
    @State var visibleListIDs: Set<String> = []
    @Environment(\.locale) var locale
    @Environment(\.colorScheme) var colorScheme
    
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

    // MARK: - iOS View
    @Namespace private var tabBarNamespace
    @Namespace private var bottomBarNS
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
    @State var showingCityRenameAlert: Bool = false
    @State var cityRenameText: String = ""
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
    @State var sidebarRenameText: String = ""
    @FocusState var sidebarNewListFocused: Bool
    @FocusState var sidebarRenameFocused: Bool
    @State var listManagerIsEditing: Bool = false
    @State var listRenameDrafts: [String: String] = [:]
    @State var listSheetDetent: PresentationDetent = .medium
    @State var showingCountrySearch: Bool = false
    @State private var countrySearchText: String = ""
    @FocusState private var countrySearchFocused: Bool
    @State private var pendingCountryList: String?
    @State private var isLoadingPendingCountry: Bool = false
    @State private var allCountries: [String] = []
    @State var showingMapStylePopover: Bool = false
    @State var showingMapStyleSheet: Bool = false
    @State private var showingAddToListPopover: Bool = false
    @State var inlineAddTargetListID: CityListID?
    #if os(macOS)
    @State private var macSidebarVisibility: NavigationSplitViewVisibility = .all
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
        AnyView(iPhoneNavigationStack)
        .task { await iOSOnAppear() }
        .onChange(of: weatherService.activeListID) { _, newListID in
            visibleListIDs.insert(newListID.rawValue)
        }
        .onChange(of: inlineSearchText) { _, newValue in
            inlineSearchManager.search(query: newValue)
        }
        .onChange(of: mapMode, initial: true) { _, _ in
            AppTheme.shared.isDetailedMapMode = selectedTab == 1 && (mapMode == "detailed" || mapMode == "colorful")
        }
        .onChange(of: selectedTab) { _, _ in
            AppTheme.shared.isDetailedMapMode = selectedTab == 1 && (mapMode == "detailed" || mapMode == "colorful")
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
                fetchingTappedCoordinate = nil
            }
        }
        .onChange(of: showingCityDetail) { _, showing in
            iOSHandleCityDetailDismiss(showing: showing)
        }
        .sheet(isPresented: $showingInfo) {
            InfoView(source: selectedTab == 1 ? .map : .list)
                .presentationSizing(.form)
        }
        .sheet(isPresented: $showingMapStyleSheet) {
            mapStyleSheet
                .presentationDetents([.height(390)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
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
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar(removing: .title)
        .animation(.easeOut(duration: 0.2), value: showingDeleteListConfirmation)
    }

    #if os(macOS)
    private var macOSView: some View {
        NavigationSplitView(columnVisibility: $macSidebarVisibility) {
            macListManagerSidebar
        } detail: {
            NavigationStack {
                macMapContent
                    .navigationDestination(isPresented: $showingCityDetail) {
                        AnyView(iOSCityDetailDestination)
                    }
                    .navigationDestination(isPresented: $showingAddCityDetail) {
                        AnyView(iOSAddCityDetailDestination)
                    }
            }
        }
        .task { await iOSOnAppear() }
        .onChange(of: weatherService.activeListID) { _, newListID in
            visibleListIDs.insert(newListID.rawValue)
        }
        .onChange(of: inlineSearchText) { _, newValue in
            inlineSearchManager.search(query: newValue)
        }
        .onChange(of: mapMode, initial: true) { _, _ in
            AppTheme.shared.isDetailedMapMode = mapMode == "detailed" || mapMode == "colorful"
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
                fetchingTappedCoordinate = nil
            }
        }
        .onChange(of: showingCityDetail) { _, showing in
            iOSHandleCityDetailDismiss(showing: showing)
        }
        .sheet(isPresented: $showingInfo) {
            InfoView(source: .map)
                .frame(minWidth: 420, minHeight: 520)
        }
        .sheet(isPresented: $showingMapStyleSheet) {
            mapStyleSheet
                .frame(minWidth: 360, minHeight: 390)
                .presentationBackground(.regularMaterial)
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
            .frame(minWidth: 440, minHeight: 560)
        }
        .overlay {
            iOSDeleteListConfirmationOverlay
        }
        .containerBackground(.clear, for: .window)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar(removing: .title)
        .animation(.easeOut(duration: 0.2), value: showingDeleteListConfirmation)
    }

    private var macMapContent: some View {
        ZStack(alignment: .bottom) {
            AnyView(
                iOSMapView
                    .overlay(alignment: .top) {
                        if showLegend {
                            MapFloatingLegend(overlayMode: mapOverlayMode, compact: true)
                                .padding(.top, 16)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .overlay(alignment: .trailing) {
                        AnyView(iOSDateSliderOverlay)
                    }
            )

            iOSMainOverlays
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbar {
            ToolbarItem(placement: .principal) {
                mapTopListMenu
                    .fixedSize()
            }

            ToolbarItemGroup {
                Button {
                    recenterOnAllCities = false
                    DispatchQueue.main.async {
                        recenterOnAllCities = true
                    }
                } label: {
                    Image(systemName: "dot.squareshape.split.2x2")
                }

                Button {
                    showingMapStyleSheet = true
                } label: {
                    Image(systemName: "square.3.layers.3d")
                }

                if filterSunny {
                    Button {
                        withAnimation {
                            filterSunny = false
                        }
                    } label: {
                        Image(systemName: "sun.max.fill")
                    }
                }

                iOSNativeMenu

                if showingInlineSearch {
                    TextField(localizedString("Search for a city", locale: locale), text: $inlineSearchText)
                        .textFieldStyle(.roundedBorder)
                        .focused($inlineSearchFocused)
                        .frame(width: 240)

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showingInlineSearch = false
                            inlineSearchText = ""
                            inlineSearchFocused = false
                            inlineAddTargetListID = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                } else {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showingInlineSearch = true
                        }
                        DispatchQueue.main.async {
                            inlineSearchFocused = true
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
        }
    }

    private var macListManagerSidebar: some View {
        List {
            ForEach(CityListID.allLists) { listID in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { sidebarExpandedListIDs.contains(listID.rawValue) },
                        set: { isExpanded in
                            if isExpanded {
                                sidebarExpandedListIDs.insert(listID.rawValue)
                                Task { await weatherService.fetchWeatherForList(listID) }
                            } else {
                                sidebarExpandedListIDs.remove(listID.rawValue)
                            }
                        }
                    )
                ) {
                    let cities = weatherService.weatherData(for: listID)
                    if cities.isEmpty {
                        Text(localizedString("No cities", locale: locale))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(cities) { city in
                            Button {
                                revealCityOnMap(city, in: listID)
                            } label: {
                                Text(city.city.localizedName(locale: locale))
                                    .lineLimit(1)
                            }
                            .contextMenu {
                                cityActions(for: city, in: listID)
                            }
                        }
                        .onMove { source, destination in
                            weatherService.moveCity(in: listID, from: source, to: destination)
                        }
                        .onDelete { offsets in
                            removeCities(at: offsets, from: listID)
                        }
                    }
                } label: {
                    HStack {
                        Text(listID.localizedDisplayName(locale: locale))
                            .lineLimit(1)
                        Spacer()
                        if weatherService.activeListID.rawValue == listID.rawValue {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task {
                            await switchToList(listID)
                        }
                    }
                    .contextMenu {
                        listActions(for: listID)
                    }
                }
            }
            .onMove { source, destination in
                weatherService.moveLists(from: source, to: destination)
            }
            .onDelete { offsets in
                Task {
                    let lists = CityListID.allLists
                    for listID in offsets.map({ lists[$0] }) {
                        await weatherService.deleteList(listID)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(localizedString("Lists", locale: locale))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    createListAtBottom()
                } label: {
                    Image(systemName: "plus")
                }

                Button {
                    listManagerIsEditing.toggle()
                } label: {
                    Image(systemName: listManagerIsEditing ? "checkmark" : "pencil")
                }
            }
        }
        .onAppear {
            if sidebarExpandedListIDs.isEmpty {
                sidebarExpandedListIDs = Set(CityListID.allLists.map(\.rawValue))
            }
        }
    }
    #endif

    private var iPhoneNavigationStack: some View {
        NavigationStack {
            iPhoneMapTabContent
                .navigationTitle("")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                #endif
                .navigationDestination(isPresented: $showingCityDetail) {
                    AnyView(iOSCityDetailDestination)
                }
                .navigationDestination(isPresented: $showingAddCityDetail) {
                    AnyView(iOSAddCityDetailDestination)
                }
        }
        .onAppear {
            selectedTab = 1
        }
    }

    @ViewBuilder
    private var mapBottomToolbar: some View {
        if showingInlineSearch {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(localizedString("Search for a city", locale: locale), text: $inlineSearchText)
                    .textFieldStyle(.plain)
                    .focused($inlineSearchFocused)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showingInlineSearch = false
                        inlineSearchText = ""
                        inlineSearchFocused = false
                        inlineAddTargetListID = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .themedGlass(in: .capsule)
            .onAppear {
                inlineSearchFocused = true
            }
        } else {
            HStack(spacing: 14) {
                Button {
                    PlatformFeedback.lightImpact()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showingMapSidebar = true
                    }
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 50, height: 50)
                        .themedGlass(in: .circle)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 4) {
                    Button {
                        PlatformFeedback.lightImpact()
                        recenterOnAllCities = false
                        DispatchQueue.main.async {
                            recenterOnAllCities = true
                        }
                    } label: {
                        Image(systemName: "dot.squareshape.split.2x2")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingMapStyleSheet = true
                    } label: {
                        Image(systemName: "square.3.layers.3d")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if filterSunny {
                        Button {
                            withAnimation {
                                filterSunny = false
                            }
                        } label: {
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    iOSNativeMenu
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .padding(3)
                .themedGlass(in: .capsule)
                .contentShape(Capsule())

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showingInlineSearch = true
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 50, height: 50)
                        .themedGlass(in: .circle)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
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
        }
        .buttonStyle(.plain)
        .menuOrder(.fixed)
    }

    private var listManagerNavigation: some View {
        NavigationStack {
            ZStack {
                theme.colors.background.ignoresSafeArea()

                List {
                    if sidebarAddingList {
                        Section {
                            TextField(localizedString("New List", locale: locale), text: $sidebarNewListName)
                                .focused($sidebarNewListFocused)
                                .submitLabel(.done)
                                .onSubmit { commitListManagerNewList() }
                        }
                    }

                    ForEach(CityListID.allLists) { listID in
                        Section {
                            listManagerListRow(for: listID)

                            if sidebarExpandedListIDs.contains(listID.rawValue) {
                                ForEach(weatherService.weatherData(for: listID)) { city in
                                    listManagerCityRow(city, in: listID)
                                }
                                .onDelete { offsets in
                                    removeCities(at: offsets, from: listID)
                                }
                                .onMove { source, destination in
                                    weatherService.moveCity(in: listID, from: source, to: destination)
                                }
                            }
                        }
                        .textCase(nil)
                        .listSectionSeparator(.visible)
                    }
                    .onDelete { offsets in
                        Task {
                            let lists = CityListID.allLists
                            for listID in offsets.map({ lists[$0] }) {
                                await weatherService.deleteList(listID)
                            }
                        }
                    }
                    .onMove { source, destination in
                        weatherService.moveLists(from: source, to: destination)
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
                .contentMargins(.horizontal, 28, for: .scrollContent)
                .contentMargins(.bottom, 110, for: .scrollContent)
                .onAppear {
                    if sidebarExpandedListIDs.isEmpty {
                        sidebarExpandedListIDs = Set(CityListID.allLists.map(\.rawValue))
                    }
                }
            }
            .navigationTitle(localizedString("Lists", locale: locale))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        commitListManagerRenames()
                        showingMapSidebar = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        createListAtBottom()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                #else
                ToolbarItem {
                    Button {
                        commitListManagerRenames()
                        showingMapSidebar = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem {
                    Button {
                        createListAtBottom()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                #endif
            }
            #if os(iOS)
            .toolbarBackground(theme.colors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
        }
    }

    private func listManagerListRow(for listID: CityListID) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if listManagerIsEditing {
                TextField(
                    localizedString("List Name", locale: locale),
                    text: Binding(
                        get: { listRenameDrafts[listID.rawValue] ?? listID.localizedDisplayName(locale: locale) },
                        set: { listRenameDrafts[listID.rawValue] = $0 }
                    )
                )
                .submitLabel(.done)
                .onSubmit {
                    commitListManagerRename(listID)
                }
            } else {
                Text(listID.localizedDisplayName(locale: locale))
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            Menu {
                listActions(for: listID)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
                    .frame(width: 38, height: 36)
            }
            .menuOrder(.fixed)

            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    if sidebarExpandedListIDs.contains(listID.rawValue) {
                        sidebarExpandedListIDs.remove(listID.rawValue)
                    } else {
                        sidebarExpandedListIDs.insert(listID.rawValue)
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .rotationEffect(.degrees(sidebarExpandedListIDs.contains(listID.rawValue) ? 0 : -90))
                    .frame(width: 28, height: 36)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color.accentColor)
        .padding(.top, 26)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !listManagerIsEditing else { return }
            Task {
                await switchToList(listID)
                showingMapSidebar = false
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                beginRenamingList(listID)
            } label: {
                Label(localizedString("Rename", locale: locale), systemImage: "pencil")
            }
            .tint(.blue)

            Button(role: .destructive) {
                Task { await weatherService.deleteList(listID) }
            } label: {
                Label(localizedString("Delete", locale: locale), systemImage: "trash")
            }
        }
        .contextMenu {
            listActions(for: listID)
        }
    }

    private func listManagerCityRow(_ city: CityWeather, in listID: CityListID) -> some View {
        Text(city.city.localizedName(locale: locale))
            .font(.title3)
            .foregroundStyle(theme.colors.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                revealCityOnMap(city, in: listID)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    beginRenamingCity(city, in: listID)
                } label: {
                    Label(localizedString("Rename", locale: locale), systemImage: "pencil")
                }
                .tint(.blue)

                Button(role: .destructive) {
                    weatherService.removeCity(city, from: listID)
                } label: {
                    Label(localizedString("Delete", locale: locale), systemImage: "trash")
                }
            }
            .contextMenu {
                cityActions(for: city, in: listID)
            }
    }

    @ViewBuilder
    private func listActions(for listID: CityListID) -> some View {
        Button {
            Task {
                await switchToList(listID)
                showingMapSidebar = false
            }
        } label: {
            Label(localizedString("Reveal on Map", locale: locale), systemImage: "map")
        }

        Button {
            beginRenamingList(listID)
        } label: {
            Label(localizedString("Rename", locale: locale), systemImage: "pencil")
        }

        Button {
            beginAddingCity(to: listID)
        } label: {
            Label(localizedString("Add City", locale: locale), systemImage: "plus")
        }

        Button(role: .destructive) {
            Task {
                await weatherService.deleteList(listID)
            }
        } label: {
            Label(localizedString("Delete", locale: locale), systemImage: "trash")
        }
    }

    @ViewBuilder
    private func cityActions(for city: CityWeather, in listID: CityListID) -> some View {
        Button {
            revealCityOnMap(city, in: listID)
        } label: {
            Label(localizedString("Reveal on Map", locale: locale), systemImage: "map")
        }

        Button {
            beginRenamingCity(city, in: listID)
        } label: {
            Label(localizedString("Rename", locale: locale), systemImage: "pencil")
        }

        Button(role: .destructive) {
            weatherService.removeCity(city, from: listID)
        } label: {
            Label(localizedString("Delete", locale: locale), systemImage: "trash")
        }
    }

    private func beginRenamingList(_ listID: CityListID) {
        listToRenameID = listID
        renameAlertText = listID.localizedDisplayName(locale: locale)
        showingRenameAlert = true
    }

    private func beginRenamingCity(_ city: CityWeather, in listID: CityListID) {
        cityToRename = city
        cityToRenameListID = listID
        cityRenameText = city.city.localizedName(locale: locale)
        showingCityRenameAlert = true
    }

    private func beginAddingCity(to listID: CityListID) {
        inlineAddTargetListID = listID
        showingMapSidebar = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingInlineSearch = true
            inlineSearchText = ""
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            inlineSearchFocused = true
        }
    }

    private func createListAtBottom() {
        let newList = CityListID.createList(name: localizedString("New List", locale: locale))
        sidebarExpandedListIDs.insert(newList.rawValue)
        listToRenameID = newList
        renameAlertText = newList.localizedDisplayName(locale: locale)
        showingRenameAlert = true
    }

    private func revealCityOnMap(_ city: CityWeather, in listID: CityListID) {
        Task {
            await switchToList(listID)
            let revealedCity = weatherService.cityWeatherData.first {
                $0.city.latitude == city.city.latitude && $0.city.longitude == city.city.longitude
            } ?? city
            tappedCity = revealedCity
            centerOnCityTrigger = revealedCity
            showingMapExpandedCard = true
            showingMapSidebar = false
        }
    }

    private func commitListManagerNewList() {
        let trimmed = sidebarNewListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newList = CityListID.createList(name: trimmed)
        sidebarExpandedListIDs.insert(newList.rawValue)
        sidebarNewListName = ""
        sidebarAddingList = false
    }

    private func commitListManagerRename(_ listID: CityListID) {
        guard let draft = listRenameDrafts[listID.rawValue] else { return }
        weatherService.renameList(listID, to: draft)
        listRenameDrafts[listID.rawValue] = nil
    }

    private func commitListManagerRenames() {
        for listID in CityListID.allLists {
            commitListManagerRename(listID)
        }
    }

    private func removeCities(at offsets: IndexSet, from listID: CityListID) {
        let cities = weatherService.weatherData(for: listID)
        for city in offsets.map({ cities[$0] }) {
            weatherService.removeCity(city, from: listID)
        }
    }

    private func switchToList(_ listID: CityListID) async {
        guard listID.rawValue != weatherService.activeListID.rawValue else { return }
        await weatherService.switchList(to: listID)
        recenterOnAllCities = true
    }

    @ViewBuilder
    private var mapSidebarOverlay: some View {
        if showingMapSidebar {
            ZStack(alignment: .leading) {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showingMapSidebar = false
                        }
                    }

                mapSidebar
                    .frame(width: 310)
                    .padding(.top, 54)
                    .padding(.bottom, 86)
                    .padding(.leading, 12)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            .zIndex(30)
        }
    }

    private var mapSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localizedString("Lists", locale: locale))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        sidebarAddingList = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        sidebarNewListFocused = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        sidebarEditing.toggle()
                        sidebarRenamingListID = nil
                    }
                } label: {
                    Image(systemName: sidebarEditing ? "checkmark" : "pencil")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if sidebarAddingList {
                HStack(spacing: 8) {
                    TextField(localizedString("New List", locale: locale), text: $sidebarNewListName)
                        .textFieldStyle(.plain)
                        .focused($sidebarNewListFocused)
                        .submitLabel(.done)
                        .onSubmit { commitSidebarNewList() }
                    Button {
                        commitSidebarNewList()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Button {
                        sidebarAddingList = false
                        sidebarNewListName = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 10)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(CityListID.allLists) { listID in
                        sidebarListRow(for: listID)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
        }
        .themedGlass(in: .rect(cornerRadius: 24))
    }

    private func sidebarListRow(for listID: CityListID) -> some View {
        let isActive = weatherService.activeListID.rawValue == listID.rawValue
        let isExpanded = sidebarExpandedListIDs.contains(listID.rawValue)
        let cities = weatherService.weatherData(for: listID)

        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        if isExpanded {
                            sidebarExpandedListIDs.remove(listID.rawValue)
                        } else {
                            sidebarExpandedListIDs.insert(listID.rawValue)
                            Task { await weatherService.fetchWeatherForList(listID) }
                        }
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 20, height: 28)
                }
                .buttonStyle(.plain)

                if sidebarRenamingListID?.rawValue == listID.rawValue {
                    TextField("", text: $sidebarRenameText)
                        .textFieldStyle(.plain)
                        .focused($sidebarRenameFocused)
                        .submitLabel(.done)
                        .onSubmit { commitSidebarRename(listID) }
                } else {
                    Button {
                        Task {
                            await weatherService.switchList(to: listID)
                            recenterOnAllCities = true
                        }
                    } label: {
                        Text(listID.localizedDisplayName(locale: locale))
                            .font(.body.weight(isActive ? .semibold : .regular))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }

                if sidebarEditing {
                    sidebarListEditingControls(for: listID)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isActive ? Color.primary.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 14))

            if isExpanded {
                VStack(spacing: 4) {
                    if cities.isEmpty {
                        Text(localizedString("No cities", locale: locale))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 38)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(Array(cities.enumerated()), id: \.element.id) { index, city in
                            sidebarCityRow(city, at: index, in: listID, cities: cities)
                        }
                    }
                }
            }
        }
    }

    private func sidebarListEditingControls(for listID: CityListID) -> some View {
        HStack(spacing: 8) {
            Button {
                sidebarRenamingListID = listID
                sidebarRenameText = listID.localizedDisplayName(locale: locale)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    sidebarRenameFocused = true
                }
            } label: {
                Image(systemName: "pencil")
            }
            .disabled(CityListID.builtInLists.contains(where: { $0.rawValue == listID.rawValue }))

            Button {
                weatherService.moveList(listID, direction: .up)
            } label: {
                Image(systemName: "chevron.up")
            }

            Button {
                weatherService.moveList(listID, direction: .down)
            } label: {
                Image(systemName: "chevron.down")
            }

            Button(role: .destructive) {
                Task { await weatherService.deleteList(listID) }
            } label: {
                Image(systemName: "trash")
            }
        }
        .font(.caption.weight(.semibold))
    }

    private func sidebarCityRow(_ city: CityWeather, at index: Int, in listID: CityListID, cities: [CityWeather]) -> some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    if weatherService.activeListID.rawValue != listID.rawValue {
                        await weatherService.switchList(to: listID)
                    }
                    selectedTab = 1
                    tappedCity = city
                    centerOnCityTrigger = city
                    showingMapExpandedCard = true
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showingMapSidebar = false
                    }
                }
            } label: {
                Text(city.city.localizedName(locale: locale))
                    .font(.subheadline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if sidebarEditing {
                Button {
                    if index > 0 {
                        weatherService.moveCity(in: listID, from: IndexSet(integer: index), to: index - 1)
                    }
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(index == 0)

                Button {
                    if index < cities.count - 1 {
                        weatherService.moveCity(in: listID, from: IndexSet(integer: index), to: index + 2)
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(index >= cities.count - 1)

                Button(role: .destructive) {
                    weatherService.removeCity(city, from: listID)
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
            }
        }
        .font(.caption)
        .padding(.leading, 38)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
    }

    private func commitSidebarNewList() {
        let name = sidebarNewListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            await weatherService.addNewList(name: name)
            sidebarExpandedListIDs.insert(weatherService.activeListID.rawValue)
            sidebarNewListName = ""
            sidebarAddingList = false
            recenterOnAllCities = true
        }
    }

    private func commitSidebarRename(_ listID: CityListID) {
        weatherService.renameList(listID, to: sidebarRenameText)
        sidebarRenamingListID = nil
        sidebarRenameText = ""
    }

    private var iPhoneShowsNativeToolbar: Bool {
        selectedTab != 2 && !isMapSpecialMode && !showingInlineSearch && !showingCountrySearch && previewCity == nil
    }

    private var iPhoneMapTabContent: some View {
        ZStack(alignment: .bottom) {
            AnyView(
                iOSMapView
                    .overlay(alignment: .top) {
                        if selectedTab == 1, showLegend {
                            MapFloatingLegend(overlayMode: mapOverlayMode)
                                .padding(.top, 58)
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
                            .padding(.top, 8)
                    }
                    .overlay(alignment: .trailing) {
                        AnyView(iOSDateSliderOverlay)
                    }
            )

            iOSMainOverlays
        }
        .overlay(alignment: .bottom) {
            mapBottomToolbar
                .padding(.horizontal, 28)
                .padding(.bottom, -6)
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .bottom)
                .contentShape(Rectangle())
                .zIndex(100)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showingMapSidebar) {
            listManagerNavigation
        }
        #else
        .sheet(isPresented: $showingMapSidebar) {
            listManagerNavigation
        }
        #endif
    }

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
        if countries.isEmpty {
            countries = SVGMapParser.parse()
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
            Color.clear
                .frame(width: 80, height: 500)
                .contentShape(Rectangle())
                .overlay(alignment: .trailing) {
                    mapDateSlider(height: 420)
                }
                .padding(.bottom, 440)
                .padding(.trailing, 1)
                .transition(.opacity)
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
                .zIndex(10)
        }

        if selectedTab == 1, !isMapSpecialMode, showingMapExpandedCard, let city = tappedCity {
            mapExpandedCard(for: city)
                .id(city.city.id)
                .padding(.horizontal, 16)
                .padding(.bottom, previewCity != nil ? 104 : 76)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.4, anchor: .bottom).combined(with: .opacity).combined(with: .offset(y: 20)),
                        removal: .scale(scale: 0.4, anchor: .bottom).combined(with: .opacity).combined(with: .offset(y: 20))
                    )
                )
                .zIndex(12)
        }

        // Tap outside search bar dismisses search entirely
        if showingInlineSearch {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showingInlineSearch = false
                        inlineSearchText = ""
                        inlineSearchFocused = false
                        inlineAddTargetListID = nil
                    }
                }
                .zIndex(9)
        }

        // Search results overlay (only when typing)
        if showingInlineSearch, !inlineSearchText.isEmpty {
            iOSInlineSearchResults
                .transition(.opacity)
                .zIndex(10)
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

            Button {
                showingMapStyleSheet = true
            } label: {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .themedGlass(in: .capsule)
        .transition(.scale.combined(with: .opacity))
    }

    private func navigatableCity(offset: Int, from city: CityWeather) -> CityWeather? {
        let cities = detailOpenedFromList ? listViewCities : mapCities
        guard let idx = cities.firstIndex(where: { $0.city.name == city.city.name }) else { return nil }
        let newIdx = idx + offset
        guard cities.indices.contains(newIdx) else { return nil }
        return cities[newIdx]
    }

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

            Button {
                let revealCity = city
                showingCityDetail = false
                centerOnCityTrigger = nil
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    selectedTab = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    centerOnCityTrigger = revealCity
                }
            } label: {
                Label(localizedString("Reveal on Map", locale: locale), systemImage: "map")
            }

            if cityIsInSidebar(city) {
                Button {
                    cityToRename = city
                    cityRenameText = city.city.localizedName(locale: locale)
                    showingCityRenameAlert = true
                } label: {
                    Label(localizedString("Rename", locale: locale), systemImage: "pencil")
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
                    Label(localizedString("Delete City", locale: locale), systemImage: "trash")
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
        .menuOrder(.fixed)
    }

    @ViewBuilder
    private var iOSCityDetailDestination: some View {
        if let city = tappedCity {
            let cityInSidebar = cityIsInSidebar(city)
            let previousCity = navigatableCity(offset: -1, from: city)
            let nextCity = navigatableCity(offset: 1, from: city)

            WeatherDetailView(
                cityWeather: city,
                selectedDayOffset: $selectedDayOffset,
                namespace: popupNamespace,
                onDismiss: {
                    showingCityDetail = false
                    selectedDayOffset = -1
                },
                onAddCity: cityInSidebar ? nil : {
                    Task {
                        await addCityToSidebar(city)
                        showingCityDetail = false
                        if selectedTab == 1 {
                            recenterOnAllCities = true
                        }
                    }
                },
                onAddCityToList: cityInSidebar ? nil : { listID in
                    Task {
                        await weatherService.addCityToList(city.city, listID: listID)
                        PlatformFeedback.lightImpact()
                        showingCityDetail = false
                        if selectedTab == 1 {
                            recenterOnAllCities = true
                        }
                    }
                },
                availableLists: cityInSidebar ? [] : CityListID.allLists,
                onDeleteCity: cityInSidebar ? {
                    weatherService.removeCity(city)
                    showingCityDetail = false
                    showingMapExpandedCard = false
                    tappedCity = nil
                    selectedDayOffset = -1
                    if selectedTab == 1 {
                        recenterOnAllCities = true
                    }
                } : nil,
                onRenameCity: cityInSidebar ? { newName in
                    weatherService.renameCity(city, to: newName)
                    tappedCity = renamedCityMatching(city)
                } : nil,
                onRevealOnMap: {
                    let revealCity = city
                    showingCityDetail = false
                    centerOnCityTrigger = nil
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedTab = 1
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        centerOnCityTrigger = revealCity
                    }
                },
                onPreviousCity: previousCity != nil ? {
                    if let prev = previousCity {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            tappedCity = prev
                        }
                    }
                } : nil,
                onNextCity: nextCity != nil ? {
                    if let next = nextCity {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            tappedCity = next
                        }
                    }
                } : nil,
                onShowSettings: {
                    showingSettings = true
                },
                onSearch: { },
                onSearchCitySelected: { selectedCity in
                    // Navigate to the selected city in the detail view
                    tappedCity = selectedCity
                },
                weatherService: weatherService,
                isInSidebar: cityInSidebar,
                showCloudCover: showCloudCover,
                usesNativeToolbar: true,
                initialChartMetric: overlayChartMetric
            )
            .background(theme.colors.background)
            .navigationTitle(city.city.localizedName(locale: locale))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    detailActionsMenu(for: city)
                }
                #else
                ToolbarItem {
                    detailActionsMenu(for: city)
                }
                #endif
            }
        }
    }

    // MARK: - Inline Search Overlay (iPhone)

    // MARK: - Unified Bottom Bar (morphs between toolbar and search)

    // MARK: - Bottom Bar State Views (extracted to reduce stack depth)

    @ViewBuilder
    private var bottomBarSearchState: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField(localizedString("Search for a city", locale: locale), text: $inlineSearchText)
                .textFieldStyle(.plain)
                .font(.avenir(.subheadline, weight: .medium))
                .autocorrectionDisabled()
                .focused($inlineSearchFocused)
            if !inlineSearchText.isEmpty {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 14, weight: .medium))
                    .contentShape(Circle())
                    .onTapGesture { inlineSearchText = "" }
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .padding(6)
        .frame(maxWidth: .infinity)
        .matchedGeometryEffect(id: "bottomBarCenter", in: bottomBarNS)
        .themedGlass(in: .capsule)
        .glassEffectID("bottomBarCenter", in: bottomBarNS)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: inlineSearchText.isEmpty)

        Image(systemName: "xmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .padding(6)
            .matchedGeometryEffect(id: "bottomBarRight", in: bottomBarNS)
            .themedGlass(in: .circle)
            .glassEffectID("bottomBarRight", in: bottomBarNS)
            .contentShape(Circle())
            .onTapGesture {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showingInlineSearch = false
                    inlineSearchText = ""
                    inlineSearchFocused = false
                }
            }
    }

    @ViewBuilder
    private func bottomBarCountryConfirmState(pending: String) -> some View {
        Image(systemName: "xmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .padding(6)
            .matchedGeometryEffect(id: "bottomBarLeft", in: bottomBarNS)
            .themedGlass(in: .circle)
            .glassEffectID("bottomBarLeft", in: bottomBarNS)
            .contentShape(Circle())
            .onTapGesture {
                Task {
                    await weatherService.deleteCurrentList()
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    pendingCountryList = nil
                    isLoadingPendingCountry = false
                    recenterOnAllCities = true
                }
            }

        Text(pending)
            .font(.avenir(.subheadline, weight: .semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .padding(.horizontal, 14)
            .padding(6)
            .matchedGeometryEffect(id: "bottomBarCenter", in: bottomBarNS)
            .themedGlass(in: .capsule)
            .glassEffectID("bottomBarCenter", in: bottomBarNS)
            .contentShape(Capsule())

        if isLoadingPendingCountry {
            ProgressView()
                .frame(width: 36, height: 36)
                .padding(6)
                .matchedGeometryEffect(id: "bottomBarRight", in: bottomBarNS)
        } else {
            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showingCountrySearch = false
                    pendingCountryList = nil
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .matchedGeometryEffect(id: "bottomBarRight", in: bottomBarNS)
            .glassEffectID("bottomBarRight", in: bottomBarNS)
            .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var bottomBarCountrySearchState: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField(localizedString("Search for a country", locale: locale), text: $countrySearchText)
                .textFieldStyle(.plain)
                .font(.avenir(.subheadline, weight: .medium))
                .autocorrectionDisabled()
                .focused($countrySearchFocused)
            if !countrySearchText.isEmpty {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 14, weight: .medium))
                    .contentShape(Circle())
                    .onTapGesture { countrySearchText = "" }
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .padding(6)
        .matchedGeometryEffect(id: "bottomBarCenter", in: bottomBarNS)
        .themedGlass(in: .capsule)
        .glassEffectID("bottomBarCenter", in: bottomBarNS)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: countrySearchText.isEmpty)

        Image(systemName: "xmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .padding(6)
            .matchedGeometryEffect(id: "bottomBarRight", in: bottomBarNS)
            .themedGlass(in: .circle)
            .glassEffectID("bottomBarRight", in: bottomBarNS)
            .contentShape(Circle())
            .onTapGesture {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showingCountrySearch = false
                    countrySearchText = ""
                    countrySearchFocused = false
                    pendingCountryList = nil
                }
            }
    }

    @ViewBuilder
    private var bottomBarPreviewExpandedState: some View {
        Image(systemName: "xmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .padding(6)
            .matchedGeometryEffect(id: "bottomBarLeft", in: bottomBarNS)
            .themedGlass(in: .circle)
            .glassEffectID("bottomBarLeft", in: bottomBarNS)
            .contentShape(Circle())
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showingMapExpandedCard = false
                    previewCity = nil
                    recenterOnAllCities = true
                }
            }

        Text(toolbarTitle)
            .font(.avenir(.subheadline, weight: .semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .padding(.horizontal, 14)
            .padding(6)
            .matchedGeometryEffect(id: "bottomBarCenter", in: bottomBarNS)
            .themedGlass(in: .capsule)
            .glassEffectID("bottomBarCenter", in: bottomBarNS)
            .contentShape(Capsule())
            .onTapGesture {
                showingListSwitcher = true
            }

        addCityButton(dismissExpanded: true)
        .matchedGeometryEffect(id: "bottomBarRight", in: bottomBarNS)
        .glassEffectID("bottomBarRight", in: bottomBarNS)
    }

    @ViewBuilder
    private var bottomBarPreviewSearchState: some View {
        Image(systemName: "xmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .padding(6)
            .matchedGeometryEffect(id: "bottomBarLeft", in: bottomBarNS)
            .themedGlass(in: .circle)
            .glassEffectID("bottomBarLeft", in: bottomBarNS)
            .contentShape(Circle())
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showingMapExpandedCard = false
                    previewCity = nil
                    recenterOnAllCities = true
                }
            }

        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(previewSearchText)
                .font(.avenir(.subheadline, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .padding(6)
        .matchedGeometryEffect(id: "bottomBarCenter", in: bottomBarNS)
        .themedGlass(in: .capsule)
        .glassEffectID("bottomBarCenter", in: bottomBarNS)
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showingInlineSearch = true
                inlineSearchText = previewSearchText
            }
        }

        addCityButton(dismissExpanded: false)
        .matchedGeometryEffect(id: "bottomBarRight", in: bottomBarNS)
        .glassEffectID("bottomBarRight", in: bottomBarNS)
    }

    @ViewBuilder
    private var bottomBarNormalState: some View {
        HStack(spacing: 2) {
            bottomTabButton(title: localizedString("Map", locale: locale), systemImage: "map", tab: 1)
            bottomTabButton(title: localizedString("List", locale: locale), systemImage: isGridView ? "square.grid.2x2" : "list.bullet", tab: 0)
        }
        .padding(6)
        .matchedGeometryEffect(id: "bottomBarCenter", in: bottomBarNS)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID("bottomBarCenter", in: bottomBarNS)

        Button {
            PlatformFeedback.lightImpact()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showingInlineSearch = true
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 58, height: 58)
        }
        .buttonStyle(.plain)
        .matchedGeometryEffect(id: "bottomBarRight", in: bottomBarNS)
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectID("bottomBarRight", in: bottomBarNS)
        .contentShape(Circle())
    }

    private func bottomTabButton(title: String, systemImage: String, tab: Int) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            PlatformFeedback.lightImpact()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .symbolVariant(isSelected ? .fill : .none)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isSelected ? theme.colors.accent : theme.colors.primaryText)
            .frame(width: 82, height: 50)
            .contentShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(selectedTab == tab)
    }

    // MARK: - Unified Bottom Bar (morphs between toolbar and search)

    private var iOSUnifiedBottomBar: some View {
        GlassEffectContainer(spacing: 12) {
        HStack(spacing: 12) {
            if showingInlineSearch {
                bottomBarSearchState
            } else if showingCountrySearch, let pending = pendingCountryList {
                bottomBarCountryConfirmState(pending: pending)
            } else if showingCountrySearch {
                bottomBarCountrySearchState
            } else if previewCity != nil, showingMapExpandedCard {
                bottomBarPreviewExpandedState
            } else if previewCity != nil {
                bottomBarPreviewSearchState
            } else {
                bottomBarNormalState
            }
        }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, showingInlineSearch ? 12 : 4)
        .padding(.top, showingInlineSearch || previewCity != nil ? 0 : 20)
        .background {
            if !showingInlineSearch && previewCity == nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { }
            }
        }
        .onChange(of: inlineSearchText) { _, newValue in
            inlineSearchManager.search(query: newValue)
        }
        .onChange(of: showingInlineSearch) { _, newValue in
            if newValue {
                inlineSearchFocused = true
            } else {
                inlineSearchManager.search(query: "")
                inlineSearchFocused = false
            }
        }
        .onChange(of: showingCountrySearch) { _, newValue in
            if newValue {
                if allCountries.isEmpty {
                    allCountries = WorldCitiesParser.countriesWithEnoughCities()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    countrySearchFocused = true
                }
            } else {
                countrySearchFocused = false
            }
        }
        .alert(localizedString("Rename", locale: locale), isPresented: $showingRenameAlert) {
            TextField(localizedString("Name", locale: locale), text: $renameAlertText)
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
    }

    // MARK: - Inline Search Results (shown when typing)

    private var iOSInlineSearchResults: some View {
        VStack(spacing: 0) {
            if !inlineSearchManager.searchResults.isEmpty {
                List {
                    ForEach(inlineSortedSearchResults) { result in
                        let existing = inlineIsExistingCity(result)
                        Button {
                            Task {
                                await inlineSelectSearchResult(result)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Text(result.title)
                                    .font(.avenir(.body, weight: existing ? .semibold : .regular))
                                    .foregroundStyle(.primary)

                                if existing {
                                    Text(localizedString("Added", locale: locale))
                                        .font(.avenir(.caption2, weight: .medium))
                                        .foregroundStyle(theme.colors.accent)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(theme.colors.accent.opacity(0.12), in: Capsule())
                                }

                                Spacer()

                                if inlineIsLoadingCity {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text(result.subtitle)
                                        .font(.avenir(.headline, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .disabled(inlineIsLoadingCity)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.visible)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 80)
            } else {
                VStack(spacing: 16) {
                    Spacer()

                    Image(systemName: "map")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)

                    Text(localizedString("No results", locale: locale))
                        .font(.avenir(.title3, weight: .medium))

                    Text(localizedString("Try a different search term", locale: locale))
                        .font(.avenir(.body))
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(selectedTab == 0 ? theme.colors.background : theme.colors.searchOverlayBackground)
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Country Search Results

    private var filteredCountries: [String] {
        if countrySearchText.isEmpty {
            return allCountries
        }
        return allCountries.filter { $0.localizedCaseInsensitiveContains(countrySearchText) }
    }

    private var iOSCountrySearchResults: some View {
        VStack(spacing: 0) {
            if !filteredCountries.isEmpty {
                List {
                    ForEach(filteredCountries, id: \.self) { country in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                pendingCountryList = country
                                countrySearchText = ""
                                countrySearchFocused = false
                                isLoadingPendingCountry = true
                            }
                            Task {
                                visibleListIDs = []
                                await weatherService.addCountryList(country: country)
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isLoadingPendingCountry = false
                                }
                                recenterOnAllCities = true
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Text(country)
                                    .font(.avenir(.body, weight: .regular))
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.visible)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 80)
            } else {
                VStack(spacing: 16) {
                    Spacer()

                    Image(systemName: "globe")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)

                    Text(localizedString("No results", locale: locale))
                        .font(.avenir(.title3, weight: .medium))

                    Text(localizedString("Try a different search term", locale: locale))
                        .font(.avenir(.body))
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(selectedTab == 0 ? theme.colors.background : theme.colors.searchOverlayBackground)
        .ignoresSafeArea(edges: .bottom)
    }

    private func selectCountry(_ country: String) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            showingCountrySearch = false
            countrySearchText = ""
            countrySearchFocused = false
        }
        withAnimation(.easeOut(duration: 0.15)) {
            listContentOpacity = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            visibleListIDs = []
            await weatherService.addCountryList(country: country)
            withAnimation(.easeIn(duration: 0.2)) {
                listContentOpacity = 1
            }
            recenterOnAllCities = true
        }
    }

    @State private var inlineIsLoadingCity = false

    private func inlineIsExistingCity(_ result: CitySearchResult) -> Bool {
        let name = result.title.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? result.title
        let country = result.subtitle.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? result.subtitle
        let data = inlineAddTargetListID.map { weatherService.weatherData(for: $0) } ?? weatherService.cityWeatherData
        return data.contains(where: { $0.city.name == name && $0.city.country == country })
    }

    private var inlineSortedSearchResults: [CitySearchResult] {
        inlineSearchManager.searchResults.sorted { a, b in
            let aExists = inlineIsExistingCity(a)
            let bExists = inlineIsExistingCity(b)
            if aExists != bExists { return aExists }
            return false
        }
    }

    private func inlineSelectSearchResult(_ result: CitySearchResult) async {
        inlineIsLoadingCity = true
        defer { inlineIsLoadingCity = false }

        let cityName = result.title.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? result.title
        let country = result.subtitle.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? result.subtitle

        let targetListID = inlineAddTargetListID
        let targetData = targetListID.map { weatherService.weatherData(for: $0) } ?? weatherService.cityWeatherData

        // Check if city already exists
        if let existingCity = targetData.first(where: { $0.city.name == cityName && $0.city.country == country }) {
            if let targetListID {
                inlineAddTargetListID = nil
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showingInlineSearch = false
                    inlineSearchText = ""
                }
                revealCityOnMap(existingCity, in: targetListID)
                return
            }
            handleInlineSearchCitySelected(existingCity)
            return
        }

        // Resolve coordinates
        guard let coordinate = await inlineSearchManager.resolveCoordinate(for: result) else {
            return
        }

        // Create and fetch weather for new city
        let tempCity = City(name: cityName, country: country, latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let tempCityWeather = await weatherService.fetchWeatherForCity(tempCity) else {
            return
        }

        if let targetListID {
            await weatherService.addCityToList(tempCityWeather.city, listID: targetListID)
            inlineAddTargetListID = nil
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showingInlineSearch = false
                inlineSearchText = ""
            }
            revealCityOnMap(tempCityWeather, in: targetListID)
        } else {
            handleInlineSearchCitySelected(tempCityWeather)
        }
    }

    private func handleInlineSearchCitySelected(_ cityWeather: CityWeather) {
        if selectedTab == 1 {
            // On map: show as preview marker with expanded card
            previewCity = cityWeather
            previewSearchText = cityWeather.city.name
            tappedCity = cityWeather
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showingInlineSearch = false
                inlineSearchText = ""
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                centerOnCityTrigger = cityWeather
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showingMapExpandedCard = true
                }
            }
        } else {
            addCityDetailCity = cityWeather
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showingInlineSearch = false
                inlineSearchText = ""
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showingAddCityDetail = true
            }
        }
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
            WeatherDetailView(
                cityWeather: city,
                selectedDayOffset: $selectedDayOffset,
                namespace: popupNamespace,
                onDismiss: {
                    showingAddCityDetail = false
                },
                onAddCity: cityIsInSidebar(city) ? nil : {
                    Task {
                        await addCityToSidebar(city)
                        showingAddCityView = false
                        showingAddCityDetail = false
                        if selectedTab == 1 {
                            recenterOnAllCities = true
                        }
                    }
                },
                onAddCityToList: cityIsInSidebar(city) ? nil : { listID in
                    Task {
                        await weatherService.addCityToList(city.city, listID: listID)
                        PlatformFeedback.lightImpact()
                        showingAddCityView = false
                        showingAddCityDetail = false
                        if selectedTab == 1 {
                            recenterOnAllCities = true
                        }
                    }
                },
                availableLists: cityIsInSidebar(city) ? [] : CityListID.allLists,
                isInSidebar: cityIsInSidebar(city),
                showCloudCover: showCloudCover,
                usesNativeToolbar: true,
                initialChartMetric: overlayChartMetric
            )
            .background(theme.colors.background)
            .navigationTitle(city.city.localizedName(locale: locale))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    detailActionsMenu(for: city)
                }
                #else
                ToolbarItem {
                    detailActionsMenu(for: city)
                }
                #endif
            }
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

    private var usesMapLibreMap: Bool {
        mapMode == "maplibre"
    }

    private var mapView: some View {
        ZStack {
            if usesMapLibreMap {
                MapLibreWebMapView(
                    cities: mapCities,
                    selectedDayOffset: selectedDayOffset,
                    overlayMode: mapOverlayMode,
                    filterSunny: filterSunny,
                    tappedCity: $tappedCity,
                    recenterOnAllCities: $recenterOnAllCities,
                    centerOnCity: centerOnCityTrigger,
                    onMarkerTap: { city in
                        if showingMapExpandedCard && tappedCity?.id == city.id {
                            showingCityDetail = true
                            return
                        }
                        withAnimation(.smooth(duration: 0.3)) {
                            tappedCity = city
                        }
                        Task {
                            try? await Task.sleep(for: .milliseconds(150))
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                showingMapExpandedCard = true
                            }
                        }
                    }
                )
                .ignoresSafeArea()
            } else {
                MapKitMapView(
                countries: countries,
                cities: mapCities,
                selectedDayOffset: selectedDayOffset,
                showCloudCover: showCloudCover,
                overlayMode: mapOverlayMode,
                filterSunny: filterSunny,
                namespace: popupNamespace,
                showingCityDetail: Binding(
                    get: { showingMapExpandedCard },
                    set: { showingMapExpandedCard = $0 }
                ),
                tappedCity: $tappedCity,
                centerOnCity: centerOnCityTrigger,
                recenterOnAllCities: $recenterOnAllCities,
                focusOnSubsetCities: [],
                focusOnSubsetTrigger: .constant(false),
                mapMode: mapMode == "maplibre" ? "colorful" : mapMode,
                forceDotsOnly: true,
                onDoubleTapMarker: {
                    if previewCity != nil {
                        previewCity = nil
                    }
                    showingCityDetail = true
                },
                onTapCoordinate: { coord in
                    guard mapMode == "detailed", !isFetchingTappedLocation else { return }
                    isFetchingTappedLocation = true
                    withAnimation(.easeOut(duration: 0.2)) {
                        fetchingTappedCoordinate = coord
                    }
                    Task {
                        let request = MKReverseGeocodingRequest(location: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
                        let mapItem = try? await request?.mapItems.first
                        let addrRep = mapItem?.addressRepresentations
                        let name = addrRep?.cityName ?? mapItem?.name ?? "—"
                        let country = addrRep?.regionName ?? ""
                        let city = City(
                            name: name,
                            country: country,
                            latitude: coord.latitude,
                            longitude: coord.longitude
                        )
                        if let result = await weatherService.fetchWeatherForCity(city) {
                            await MainActor.run {
                                withAnimation(.smooth(duration: 0.3)) {
                                    tappedCity = result
                                }
                                Task {
                                    try? await Task.sleep(for: .milliseconds(150))
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                        showingMapExpandedCard = true
                                    }
                                }
                            }
                        } else {
                            await MainActor.run {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    fetchingTappedCoordinate = nil
                                }
                            }
                        }
                        await MainActor.run { isFetchingTappedLocation = false }
                    }
                },
                onClearFetchingDot: {
                    withAnimation(.easeOut(duration: 0.3)) {
                        fetchingTappedCoordinate = nil
                    }
                },
                fetchingCoordinate: fetchingTappedCoordinate
            )
            .ignoresSafeArea()
            }

            // Floating loading popup on map — positioned at 1/3 from top to match list view
            if weatherService.isLoading {
                GeometryReader { geo in
                    VStack(spacing: 20) {
                        Image(systemName: "cloud.sun.fill")
                            .font(.system(size: 56))
                            .weatherIconStyle(for: "cloud.sun.fill")
                        Text(localizedString("Loading Weather", locale: locale))
                            .font(.avenir(.title2, weight: .semibold))
                        Capsule()
                            .fill(theme.colors.primaryText.opacity(0.15))
                            .frame(width: 140, height: 4)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(theme.colors.primaryText)
                                    .frame(width: 140 * weatherService.loadingProgress, height: 4)
                            }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 28)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .allowsHitTesting(false)
            }

            // Tap-to-fetch loading indicator
            if isFetchingTappedLocation {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(theme.colors.primaryText)
                        Text("Fetching weather…")
                            .font(.avenir(.subheadline, weight: .medium))
                            .foregroundStyle(theme.colors.primaryText)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 100)
                }
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isFetchingTappedLocation)
            }


        }
        .background(Color(hex: 0xDDE9EF).ignoresSafeArea())
        .ignoresSafeArea()
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
    private func addCityButton(dismissExpanded: Bool) -> some View {
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
    private var showPrecipitation: Bool { overlayMode == "precipitation" }

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



#Preview {
    let _ = UserDefaults.standard.set(false, forKey: "isGridView")
    let _ = UserDefaults.standard.set(false, forKey: "hasLaunchedBefore")
    ContentView()
}

#Preview("Loading") {
    ContentView(previewLoading: true)
}
