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
    @State private var weatherService = WeatherService()
    @Environment(\.appTheme) private var theme

    @State private var countries: [CountryPath] = []
    @State private var centerOnCityTrigger: CityWeather?

    @State private var selectedCity: CityWeather?
    @State private var selectedDayOffset: Int = 0
    @State private var isEditMode: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isZoomedOut: Bool = true
    @State private var showingCityDetail: Bool = false
    @State private var tappedCity: CityWeather?
    @State private var showingMapExpandedCard: Bool = false
    @Namespace private var popupNamespace
    @State private var searchText: String = ""
    @State private var citySearchManager = CitySearchManager()
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore: Bool = false
    @State private var selectedTab: Int = 0
    @State private var showingSearchSheet: Bool = true
    @State private var selectedDetent: PresentationDetent = .height(80)
    @State private var lastRefreshText: String = ""
    @State private var showingAddCityView: Bool = false
    @State private var showingAddCityDetail: Bool = false
    @State private var addCityDetailCity: CityWeather?
    @State private var previewCity: CityWeather?
    @State private var previewSearchText: String = ""
    @State private var showCloudCover: Bool = false
    @State private var filterSunny: Bool = false
    @State private var isPlaying: Bool = false
    @State private var showingInlineSearch: Bool = false
    @State private var inlineSearchText: String = ""
    @FocusState private var inlineSearchFocused: Bool
    @State private var inlineSearchManager = CitySearchManager()
    
    @State private var mapScale: CGFloat = 10.0
    @State private var mapOffset: CGSize = .zero
    @State private var mapLastScale: CGFloat = 10.0
    @State private var mapLastOffset: CGSize = .zero
    @State private var mapHasInitialized: Bool = false
    @State private var recenterOnAllCities: Bool = false
    @State private var detailOpenedFromList: Bool = false
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    @State private var showingSettings: Bool = false
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("mapMode") private var mapMode: String = "minimal"
    @AppStorage("showDateSlider") private var showDateSlider: Bool = true
    @State private var mapVisibleListIDs: Set<String> = []
    @Environment(\.locale) private var locale
    
    /// Cities to display on the map — combined from all selected lists + preview city
    private var mapCities: [CityWeather] {
        if countryOverviewActive {
            return countryOverviewData
        }
        if radialSearchActive {
            return radialSearchData
        }
        var result: [CityWeather]
        if mapVisibleListIDs.isEmpty || mapVisibleListIDs == Set([weatherService.activeListID.rawValue]) {
            result = weatherService.cityWeatherData
        } else {
            var combined: [CityWeather] = []
            var seenNames = Set<String>()
            for listID in CityListID.allLists where mapVisibleListIDs.contains(listID.rawValue) {
                let cities: [CityWeather]
                if listID == weatherService.activeListID {
                    cities = weatherService.cityWeatherData
                } else {
                    cities = weatherService.otherListData[listID.rawValue] ?? []
                }
                for city in cities {
                    if !seenNames.contains(city.city.name) {
                        combined.append(city)
                        seenNames.insert(city.city.name)
                    }
                }
            }
            result = combined
        }
        // Include temporary preview city from search
        if let preview = previewCity, !result.contains(where: { $0.city.name == preview.city.name }) {
            result.append(preview)
        }
        return result
    }
    
    private var mapToolbarTitle: String {
        let selectedLists = CityListID.allLists.filter { mapVisibleListIDs.contains($0.rawValue) }
        let firstName = selectedLists.first?.localizedDisplayName(locale: locale) ?? weatherService.activeListID.localizedDisplayName(locale: locale)
        let extra = selectedLists.count - 1
        if extra > 0 {
            return "\(firstName), +\(extra)"
        }
        return firstName
    }
    
    private var tempUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
    }

    private var isIPad: Bool {
        #if os(macOS)
        return false
        #else
        return UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    private func timeSinceRefreshText() -> String {
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
        desktopView
        #else
        iOSView
        #endif
    }

    // MARK: - Desktop View (macOS & iPadOS)

    private var desktopView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar - uses the same content as the iOS large sheet
            DesktopSidebar(
                cities: mapCities,
                selectedCity: $selectedCity,
                selectedDayOffset: $selectedDayOffset,
                isEditMode: $isEditMode,
                searchText: $searchText,
                showingCityDetail: $showingCityDetail,
                tappedCity: $tappedCity,
                citySearchManager: citySearchManager,
                weatherService: weatherService,
                showCloudCover: showCloudCover,
                onCitySelected: { cityWeather in
                    selectedCity = cityWeather
                    centerOnCityTrigger = cityWeather
                },
                onDeleteCity: { cityWeather in
                    weatherService.removeCity(cityWeather)
                    if selectedCity?.id == cityWeather.id {
                        selectedCity = nil
                    }
                },
                onMoveCity: { source, destination in
                    weatherService.moveCity(from: source, to: destination)
                },
                onRefresh: {
                    await weatherService.refreshWeather()
                },
                onSwitchList: { listID in
                    mapHasInitialized = false
                    recenterOnAllCities = false
                    withAnimation(.easeOut(duration: 0.15)) {
                        listContentOpacity = 0
                    }
                    Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        await weatherService.switchList(to: listID)
                        withAnimation(.easeIn(duration: 0.2)) {
                            listContentOpacity = 1
                        }
                        recenterOnAllCities = true
                    }
                },
                lastFetchDate: weatherService.lastFetchDate,
                isRefreshing: weatherService.isLoading,
                detailOpenedFromList: $detailOpenedFromList
            )
            .opacity(listContentOpacity)
        } detail: {
            // Map view with bottom date bar
            mapView
                .overlay(alignment: .bottom) {
                    DesktopDateBar(selectedDayOffset: $selectedDayOffset, showCloudCover: $showCloudCover, filterSunny: $filterSunny, isPlaying: $isPlaying)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
        }
        .task {
            countries = SVGMapParser.parse()
            print("Starting weather fetch...")
            await weatherService.fetchWeatherForAllCities()
            print("Weather data count: \(weatherService.cityWeatherData.count)")
        }
    }

    // MARK: - iOS View

    #if !os(macOS)
    @Namespace private var tabBarNamespace
    @Namespace private var countryBarNS
    @Namespace private var radialBarNS
    @Namespace private var bottomBarNS
    @State private var iOSPreviousDayOffset: Int = 0
    @State private var showingDatePopover: Bool = false
    @State private var isDraggingDateSlider: Bool = false
    @State private var sliderDragStartDay: Int = 0
    @State private var sliderDragFraction: CGFloat = 0
    @State private var playbackTask: Task<Void, Never>?
    @State private var showPlaybackButton: Bool = false
    @State private var playbackButtonHideTask: Task<Void, Never>?
    @State private var showingMenuPopover: Bool = false
    @State private var showingDetailMenuPopover: Bool = false
    @AppStorage("isGridView") private var isGridView: Bool = false
    @State private var gridDragItem: CityWeather?
    @State private var showingListSwitcher: Bool = false
    @State private var listContentOpacity: Double = 1.0
    @State private var longPressedCity: CityWeather?
    @State private var isEditingListName: Bool = false
    @State private var editingListName: String = ""
    @FocusState private var listNameFieldFocused: Bool
    @State private var showingDeleteListConfirmation: Bool = false
    @State private var isReorderingLists: Bool = false
    @State private var reorderableLists: [CityListID] = []
    @State private var draggingListID: CityListID? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var showingMapStylePopover: Bool = false
    @State private var showingDiscoverPopover: Bool = false
    @State private var countrySelectionMode: Bool = false
    @State private var mapCenterCoordinate: CLLocationCoordinate2D?
    @State private var countryUnderPin: String = ""
    @State private var showCountrySelectedAlert: Bool = false
    @State private var selectedCountryName: String = ""
    @State private var countryOverviewData: [CityWeather] = []
    @State private var countryOverviewActive: Bool = false
    @State private var countryOverviewCountryName: String = ""
    @State private var isLoadingCountryOverview: Bool = false
    @State private var countryOverviewProgress: Double = 0
    @State private var countryOverviewLoadingTask: Task<Void, Never>?
    @State private var countryOverviewCache: [String: (data: [CityWeather], date: Date)] = [:]
    @State private var resolvedGridCityName: String?
    @State private var resolvedGridCityNames: [UUID: String] = [:]
    @State private var showingAddToListPopover: Bool = false

    @State private var showingMapListSwitcher: Bool = false
    @State private var showingRecenterPopover: Bool = false
    @State private var focusSubsetCities: [CityWeather] = []
    @State private var focusSubsetTrigger: Bool = false
    @State private var isLoadingMapList: Bool = false
    @State private var gridPreviewPoints: [CLLocationCoordinate2D] = []

    // MARK: - Radial Search State
    @State private var radialSearchMode: Bool = false
    @State private var radialSearchActive: Bool = false
    @State private var isLoadingRadialSearch: Bool = false
    @State private var radialSearchProgress: Double = 0
    @State private var radialSearchLoadingTask: Task<Void, Never>?
    @State private var radialSearchData: [CityWeather] = []
    @State private var radialSearchRadius: Double = 250_000

    // MARK: - Vertical Date Slider (Map Mode)

    private func mapExpandedCard(for cityWeather: CityWeather) -> some View {
        let forecast = cityWeather.forecast(for: selectedDayOffset)
        let tempUnit = TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
        let icon: String = {
            switch forecast.condition {
            case .rain, .drizzle, .snow: return "cloud.fill"
            default: return forecast.weatherIcon
            }
        }()
        // Match effect condition to the displayed icon
        let effectCondition: AppWeatherCondition = {
            if icon == "cloud.fill" {
                switch forecast.condition {
                case .rain: return .rain
                case .drizzle: return .drizzle
                case .snow: return .snow
                default: return .cloudy
                }
            }
            return forecast.condition
        }()
        return HStack(alignment: .center, spacing: 0) {
            // Left: temperature, city, details
            VStack(alignment: .leading, spacing: 6) {
                // Large temperature
                Text(tempUnit.display(forecast.daytimeHigh))
                    .font(.custom("AvenirNext-Medium", size: 38, relativeTo: .largeTitle))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())

                // City name
                Text((countryOverviewActive || radialSearchActive) ? (resolvedGridCityName ?? "…") : cityWeather.city.localizedName(locale: locale))
                    .font(.avenir(.body, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // Cloud cover, precipitation & 7-day forecast dots
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 11))
                        Text("\(forecast.cloudCoverPercent)%")
                            .font(.avenir(.caption, weight: .medium))
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 11))
                        Text("\(Int(forecast.precipitationChance * 100))%")
                            .font(.avenir(.caption, weight: .medium))
                    }

                    HStack(spacing: 5) {
                        ForEach(0..<min(7, cityWeather.dailyForecasts.count), id: \.self) { i in
                            let dayForecast = cityWeather.dailyForecasts[i]
                            Circle()
                                .fill(dayForecast.condition.dotColor)
                                .frame(width: i == selectedDayOffset ? 8 : 6, height: i == selectedDayOffset ? 8 : 6)
                                .shadow(color: dayForecast.condition.dotColor.opacity(0.6), radius: 3)
                                .opacity(i == selectedDayOffset ? 1 : 0.6)
                        }
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Right: weather icon, centered vertically
            Image(systemName: icon)
                .font(.system(size: 40))
                .weatherIconStyle(for: icon)
                .frame(width: 56, height: 48)
                .background(alignment: .top) {
                    WeatherEffectOverlay(condition: effectCondition, isCompact: false, iconHeight: 48, iconName: icon)
                }
                .padding(.trailing, 10)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: isIPad ? 420 : .infinity)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .onTapGesture {
            if isIPad {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showingMapExpandedCard = false
                }
                if sidebarVisibility != .all {
                    withAnimation {
                        sidebarVisibility = .all
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    showingCityDetail = true
                }
            } else {
                showingCityDetail = true
            }
        }
    }

    private func mapDateSlider(height: CGFloat) -> some View {
        let totalDays = 10
        let stepHeight = height / CGFloat(totalDays - 1)

        return ZStack(alignment: .topTrailing) {
            // Today endpoint (top)
            if isDraggingDateSlider && sliderDragFraction > 0.05 {
                sliderEndpointLabel(text: localizedString("Today", locale: locale), isWhite: false)
                    .offset(y: -4)
                    .transition(.opacity)
            }

            // Final day endpoint (bottom)
            if isDraggingDateSlider && sliderDragFraction < 0.95 {
                sliderEndpointLabel(text: sliderDateText(for: totalDays - 1), isWhite: false)
                    .offset(y: height - 4)
                    .transition(.opacity)
            }

            // Selected day indicator
            HStack(spacing: isDraggingDateSlider ? 6 : 3) {
                let displayDay = isDraggingDateSlider
                    ? Int(round(sliderDragFraction * CGFloat(totalDays - 1)))
                    : selectedDayOffset

                Text(sliderDateText(for: max(0, min(totalDays - 1, displayDay))))
                    .font(.avenir(isDraggingDateSlider ? .body : .subheadline, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .frame(minWidth: isDraggingDateSlider ? 64 : 52)
                    .fixedSize()
                    .padding(.horizontal, isDraggingDateSlider ? 14 : 12)
                    .padding(.vertical, isDraggingDateSlider ? 9 : 7)
                    .themedGlass(in: .capsule)

                Capsule()
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: isDraggingDateSlider ? 30 : 24, height: isDraggingDateSlider ? 20 : 16)
                    .offset(x: isDraggingDateSlider ? 12 : 9)
                    .shadow(color: .black.opacity(0.25), radius: 4, x: -2)
            }
            .animation(.smooth(duration: 0.2), value: isDraggingDateSlider)
            .offset(y: (isDraggingDateSlider ? sliderDragFraction * CGFloat(totalDays - 1) : CGFloat(selectedDayOffset)) * stepHeight - (isDraggingDateSlider ? 10 : 8))
        }
        .animation(.smooth(duration: 0.15), value: selectedDayOffset)
        .frame(height: height)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDraggingDateSlider {
                        sliderDragStartDay = selectedDayOffset
                        sliderDragFraction = CGFloat(selectedDayOffset) / CGFloat(totalDays - 1)
                        withAnimation(.easeOut(duration: 0.2)) {
                            isDraggingDateSlider = true
                        }
                    }
                    let fractionalDelta = value.translation.height / height
                    let startFraction = CGFloat(sliderDragStartDay) / CGFloat(totalDays - 1)
                    sliderDragFraction = max(0, min(1, startFraction + fractionalDelta))
                    let nearestDay = max(0, min(totalDays - 1, Int(round(sliderDragFraction * CGFloat(totalDays - 1)))))
                    if nearestDay != selectedDayOffset {
                        selectedDayOffset = nearestDay
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                .onEnded { _ in
                    let snappedDay = Int(round(sliderDragFraction * CGFloat(totalDays - 1)))
                    let clamped = max(0, min(totalDays - 1, snappedDay))
                    withAnimation(.smooth(duration: 0.15)) {
                        selectedDayOffset = clamped
                        isDraggingDateSlider = false
                    }
                }
        )
    }

    private func sliderEndpointLabel(text: String, isWhite: Bool) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.avenir(.subheadline, weight: .medium))
                .foregroundStyle(AppTheme.shared.colors.primaryText.opacity(0.7))
                .shadow(color: .black.opacity(0.5), radius: 2)
                .fixedSize()

            Capsule()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 24, height: 16)
                .offset(x: 9)
        }
    }

    private func sliderDateText(for day: Int) -> String {
        if day == 0 { return localizedString("Today", locale: locale) }
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "dMMM", options: 0, locale: locale)
        formatter.locale = locale
        return formatter.string(from: Calendar.current.date(byAdding: .day, value: day, to: Date()) ?? Date())
    }

    private var iOSDateText: String {
        if selectedDayOffset == 0 { return localizedString("Today", locale: locale) }
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMMdEEE", options: 0, locale: locale)
        formatter.locale = locale
        return formatter.string(from: Calendar.current.date(byAdding: .day, value: selectedDayOffset, to: Date()) ?? Date())
    }

    private var iOSView: some View {
        iOSNavigationContent
            .overlay {
                iOSDeleteListConfirmationOverlay
            }
            .animation(.easeOut(duration: 0.2), value: showingDeleteListConfirmation)

    }

    @ViewBuilder
    private var iOSNavigationContainer: some View {
        if isIPad {
            iPadNavigationSplitView
        } else {
            iPhoneNavigationStack
        }
    }

    private var iPadNavigationSplitView: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            NavigationStack {
                iOSListView
                    .background(.thinMaterial)
                    .overlay {
                        if weatherService.isLoading, !weatherService.cityWeatherData.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "cloud.sun.fill")
                                    .font(.system(size: 40))
                                    .weatherIconStyle(for: "cloud.sun.fill")
                                Text(localizedString("Loading Weather", locale: locale))
                                    .font(.avenir(.headline, weight: .semibold))
                                Capsule()
                                    .fill(theme.colors.primaryText.opacity(0.15))
                                    .frame(width: 120, height: 4)
                                    .overlay(alignment: .leading) {
                                        Capsule()
                                            .fill(theme.colors.primaryText)
                                            .frame(width: 120 * weatherService.loadingProgress, height: 4)
                                    }
                            }
                            .padding(24)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .allowsHitTesting(false)
                            .transition(.opacity)
                        }
                    }
                    .toolbar(removing: .sidebarToggle)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                withAnimation {
                                    sidebarVisibility = .detailOnly
                                }
                            } label: {
                                Image(systemName: "sidebar.left")
                            }
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    listContentOpacity = 0
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    isGridView.toggle()
                                    withAnimation(.easeIn(duration: 0.2)) {
                                        listContentOpacity = 1
                                    }
                                }
                            } label: {
                                Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                withAnimation { isEditMode.toggle() }
                            } label: {
                                Image(systemName: isEditMode ? "checkmark" : "pencil")
                            }
                        }
                    }
                    .navigationDestination(isPresented: $showingCityDetail) {
                        iOSCityDetailDestination
                    }
            }
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 400)
        } detail: {
            iPadDetailContent
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(showingInlineSearch && !inlineSearchText.isEmpty ? .hidden : .visible, for: .navigationBar)
                .toolbar { iOSLeadingToolbarItems }
                .toolbar { iOSPrincipalToolbarItem }
                .toolbar { iOSTrailingToolbarItems }
                .toolbar(removing: .sidebarToggle)
                .fullScreenCover(isPresented: $showingAddCityView) {
                    iOSAddCitySheet
                }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var iPhoneNavigationStack: some View {
        NavigationStack {
            iOSMainZStack
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { iOSLeadingToolbarItems }
                .toolbar { iOSPrincipalToolbarItem }
                .toolbar { iOSTrailingToolbarItems }
                .navigationDestination(isPresented: $showingCityDetail) {
                    iOSCityDetailDestination
                }
                .navigationDestination(isPresented: $showingAddCityDetail) {
                    iOSAddCityDetailDestination
                }
        }
    }

    private var iOSNavigationContent: some View {
        iOSNavigationContainer
        .task { await iOSOnAppear() }
        .onChange(of: weatherService.activeListID) { _, newListID in
            mapVisibleListIDs.insert(newListID.rawValue)
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
                resolvedGridCityName = nil
            }
        }
        .onChange(of: tappedCity) { _, newCity in
            if (countryOverviewActive || radialSearchActive), let city = newCity {
                // Check cache first
                if let cached = resolvedGridCityNames[city.id] {
                    resolvedGridCityName = cached
                    return
                }
                resolvedGridCityName = nil
                Task {
                    let location = CLLocation(latitude: city.city.latitude, longitude: city.city.longitude)
                    if let request = MKReverseGeocodingRequest(location: location) {
                        if let items = try? await request.mapItems, let item = items.first {
                            let name = item.addressRepresentations?.cityName
                                ?? item.addressRepresentations?.cityWithContext(.short)
                                ?? item.name
                            let resolved = name ?? city.city.country
                            resolvedGridCityNames[city.id] = resolved
                            // Only update if this is still the tapped city
                            if tappedCity?.id == city.id {
                                resolvedGridCityName = resolved
                            }
                        } else {
                            // Rate limited or error — fall back to country name
                            if tappedCity?.id == city.id {
                                let fallback = city.city.country
                                resolvedGridCityNames[city.id] = fallback
                                resolvedGridCityName = fallback
                            }
                        }
                    } else {
                        if tappedCity?.id == city.id {
                            let fallback = city.city.country
                            resolvedGridCityNames[city.id] = fallback
                            resolvedGridCityName = fallback
                        }
                    }
                }
            }
        }
        .onChange(of: showingCityDetail) { _, showing in
            iOSHandleCityDetailDismiss(showing: showing)
        }
        .onChange(of: mapCenterCoordinate?.latitude) { _, _ in
            updateCountryUnderPin()
            updateRadialGridPreview()
        }
        .onChange(of: mapCenterCoordinate?.longitude) { _, _ in
            updateCountryUnderPin()
            updateRadialGridPreview()
        }
        .onChange(of: radialSearchRadius) { _, _ in
            updateRadialGridPreview()
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
    }

    private func iOSOnAppear() async {
        if isIPad || hasLaunchedBefore {
            selectedTab = 1
        }
        if !hasLaunchedBefore {
            hasLaunchedBefore = true
        }
        if mapVisibleListIDs.isEmpty {
            mapVisibleListIDs = [weatherService.activeListID.rawValue]
        }
        if countryOverviewCache.isEmpty {
            countryOverviewCache = CountryOverviewCacheManager.load()
        }
        print("📱 [DEBUG] iOS .task started")
        if countries.isEmpty {
            print("📱 [DEBUG] Parsing SVG map...")
            countries = SVGMapParser.parse()
            print("📱 [DEBUG] SVG map parsed, \(countries.count) countries")
        }
        print("📱 [DEBUG] About to call fetchWeatherForAllCities()...")
        await weatherService.fetchWeatherForAllCities()
        print("📱 [DEBUG] fetchWeatherForAllCities() returned, cityWeatherData.count = \(weatherService.cityWeatherData.count)")
    }

    private func iOSHandleCityDetailDismiss(showing: Bool) {
        if showing, isIPad, let city = tappedCity {
            centerOnCityTrigger = city
        }
        if !showing, showingMapExpandedCard, let city = tappedCity {
            if !weatherService.cityWeatherData.contains(where: { $0.city.name == city.city.name }) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showingMapExpandedCard = false
                    tappedCity = nil
                    recenterOnAllCities = true
                }
            }
        }
    }

    @State private var gridPreviewTask: Task<Void, Never>?

    private func updateCountryUnderPin() {
        guard countrySelectionMode, let coord = mapCenterCoordinate else { return }
        updateCountryUnderPinDirect(coord)
    }

    private func updateCountryUnderPinDirect(_ coord: CLLocationCoordinate2D) {
        let svgPoint = GeoProjection.geoToSVG(latitude: coord.latitude, longitude: coord.longitude)
        let found = countries.first(where: { $0.path.boundingBox.contains(svgPoint) && $0.path.contains(svgPoint) })
        let name = found?.title ?? ""
        if name != countryUnderPin {
            withAnimation(.easeOut(duration: 0.15)) {
                countryUnderPin = name
            }
            gridPreviewTask?.cancel()
            gridPreviewPoints = []
            if let country = found {
                let title = country.title
                gridPreviewTask = Task {
                    // Small delay so rapid panning doesn't trigger expensive computation
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    // Recheck that the country is still the same
                    guard countryUnderPin == title else { return }
                    let grid = generateCountryGrid(for: country)
                    guard !Task.isCancelled, countryUnderPin == title else { return }
                    gridPreviewPoints = grid.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    }
                }
            }
        }
    }

    private func generateCountryGrid(for country: CountryPath, maxPoints: Int = 150) -> [City] {
        let bbox = country.path.boundingBox
        let topLeft = GeoProjection.svgToGeo(svgPoint: CGPoint(x: bbox.minX, y: bbox.minY))
        let bottomRight = GeoProjection.svgToGeo(svgPoint: CGPoint(x: bbox.maxX, y: bbox.maxY))
        
        let minLat = min(topLeft.latitude, bottomRight.latitude)
        let maxLat = max(topLeft.latitude, bottomRight.latitude)
        let minLon = min(topLeft.longitude, bottomRight.longitude)
        let maxLon = max(topLeft.longitude, bottomRight.longitude)
        
        let midLat = (minLat + maxLat) / 2
        
        // Try increasing spacing until we're under maxPoints
        for spacing in [0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0, 7.0] {
            // Adjust longitude spacing so the grid appears square on Mercator projection
            let lonSpacing = spacing / max(cos(midLat * .pi / 180), 0.3)
            var gridCities: [City] = []
            var lat = minLat + spacing / 2
            while lat <= maxLat {
                var lon = minLon + lonSpacing / 2
                while lon <= maxLon {
                    let svgPoint = GeoProjection.geoToSVG(latitude: lat, longitude: lon)
                    if country.path.contains(svgPoint) {
                        // Normalize longitude to -180...180 for WeatherKit
                        var normalizedLon = lon
                        if normalizedLon > 180 { normalizedLon -= 360 }
                        if normalizedLon < -180 { normalizedLon += 360 }
                        let city = City(
                            name: "\(country.title) \(gridCities.count + 1)",
                            country: country.title,
                            latitude: lat,
                            longitude: normalizedLon
                        )
                        gridCities.append(city)
                    }
                    lon += lonSpacing
                }
                lat += spacing
            }
            if gridCities.count <= maxPoints {
                return gridCities
            }
        }
        return []
    }

    // MARK: - Radial Grid Generation

    private func generateRadialGrid(center: CLLocationCoordinate2D, radiusMeters: Double, maxPoints: Int = 100) -> [City] {
        let latDegreesPerMeter = 1.0 / 111_320.0
        let radiusDegLat = radiusMeters * latDegreesPerMeter
        let radiusDegLon = radiusDegLat / max(cos(center.latitude * .pi / 180), 0.1)

        let minLat = center.latitude - radiusDegLat
        let maxLat = center.latitude + radiusDegLat
        let minLon = center.longitude - radiusDegLon
        let maxLon = center.longitude + radiusDegLon

        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)

        // Finer spacing tiers for smaller circles
        let spacings: [Double] = radiusMeters < 100_000 ? [0.25, 0.4, 0.5, 0.75, 1.0, 1.5, 2.0] :
                                  radiusMeters < 200_000 ? [0.5, 0.75, 1.0, 1.5, 2.0, 3.0] :
                                  [0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0]
        for spacing in spacings {
            let lonSpacing = spacing / max(cos(center.latitude * .pi / 180), 0.3)
            var gridCities: [City] = []
            var lat = minLat + spacing / 2
            while lat <= maxLat {
                var lon = minLon + lonSpacing / 2
                while lon <= maxLon {
                    let pointLocation = CLLocation(latitude: lat, longitude: lon)
                    if centerLocation.distance(from: pointLocation) <= radiusMeters {
                        var normalizedLon = lon
                        if normalizedLon > 180 { normalizedLon -= 360 }
                        if normalizedLon < -180 { normalizedLon += 360 }

                        // Clip to land: check if point falls on any country SVG path
                        let svgPoint = GeoProjection.geoToSVG(latitude: lat, longitude: normalizedLon)
                        let isOnLand = countries.contains { country in
                            country.path.boundingBox.contains(svgPoint) && country.path.contains(svgPoint)
                        }
                        if isOnLand {
                            let city = City(
                                name: "Radial \(gridCities.count + 1)",
                                country: "Radial Search",
                                latitude: lat,
                                longitude: normalizedLon
                            )
                            gridCities.append(city)
                        }
                    }
                    lon += lonSpacing
                }
                lat += spacing
            }
            if gridCities.count <= maxPoints {
                return gridCities
            }
        }
        return []
    }

    @State private var radialGridPreviewTask: Task<Void, Never>?

    private func updateRadialGridPreview() {
        guard radialSearchMode, let coord = mapCenterCoordinate else { return }
        radialGridPreviewTask?.cancel()
        gridPreviewPoints = []
        radialGridPreviewTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, radialSearchMode else { return }
            let grid = generateRadialGrid(center: coord, radiusMeters: radialSearchRadius)
            guard !Task.isCancelled, radialSearchMode else { return }
            gridPreviewPoints = grid.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
        }
    }

    @ToolbarContentBuilder
    private var iOSLeadingToolbarItems: some ToolbarContent {
        if isIPad {
            if sidebarVisibility == .detailOnly {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation {
                            sidebarVisibility = .all
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                }

                ToolbarSpacer(.fixed, placement: .navigationBarLeading)
            }

            if !isMapSpecialMode, sidebarVisibility == .detailOnly {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingMapListSwitcher = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(mapToolbarTitle)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .popover(isPresented: $showingMapListSwitcher) {
                        iOSMapListSwitcherMenu
                            .presentationCompactAdaptation(.popover)
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var iOSPrincipalToolbarItem: some ToolbarContent {
        if isIPad, !isMapSpecialMode {
            ToolbarItem(placement: .topBarLeading) {
                iPadDateSwitcherToolbarContent
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .themedGlass(in: .capsule)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        if !isIPad, selectedTab == 1, !isMapSpecialMode {
            ToolbarItem(placement: .principal) {
                Button {
                    showingMapListSwitcher = true
                } label: {
                    HStack(spacing: 4) {
                        Text(mapToolbarTitle)
                            .font(.avenir(.headline, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .themedGlass(in: .capsule)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingMapListSwitcher) {
                    iOSMapListSwitcherMenu
                        .presentationCompactAdaptation(.popover)
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    /// Whether the map is in a special full-screen mode (country selection, loading overview, or showing overview results)
    private var isMapSpecialMode: Bool {
        countrySelectionMode || isLoadingCountryOverview || countryOverviewActive
        || radialSearchMode || isLoadingRadialSearch || radialSearchActive
    }

    // iPhone-only main content (iPad uses NavigationSplitView with iPadDetailContent)
    private var iOSMainZStack: some View {
        ZStack(alignment: .bottom) {
            iPhoneTabContent

            // Expanded city card on map
            if selectedTab == 1, (!isMapSpecialMode || countryOverviewActive || radialSearchActive), showingMapExpandedCard, let city = tappedCity {
                mapExpandedCard(for: city)
                    .id(city.city.id)
                    .transition(.blurReplace)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 72)
                    .zIndex(1)
            }

            // Country selection overlay (top part: pin + country name)
            if countrySelectionMode {
                countrySelectionTopOverlay
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(3)
            }

            // Country selection + loading bottom bar (unified with morphing animation)
            if countrySelectionMode || isLoadingCountryOverview {
                countrySearchBottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(3)
            }

            // Country overview exit button (only after loading completes)
            if countryOverviewActive, !isLoadingCountryOverview {
                countryOverviewExitOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(3)
            }

            // Radial search selection overlay (top part: radius label)
            if radialSearchMode {
                radialSelectionTopOverlay
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(3)
            }

            // Radial selection + loading bottom bar (unified with morphing animation)
            if radialSearchMode || isLoadingRadialSearch {
                radialSearchBottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(3)
            }

            // Radial search exit button (only after loading completes)
            if radialSearchActive, !isLoadingRadialSearch {
                radialSearchExitOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(3)
            }

            // Search results overlay (only when typing)
            if showingInlineSearch, !inlineSearchText.isEmpty {
                iOSInlineSearchResults
                    .transition(.opacity)
                    .zIndex(10)
            }

            // Floating bottom toolbar / inline search bar / preview toolbar
            if !isMapSpecialMode {
                iOSUnifiedBottomBar
                    .zIndex(11)
            }

        }
    }

    // MARK: - iPhone Tab Content

    private var iPhoneTabContent: some View {
        ZStack {
            iOSMapView
                .overlay(alignment: .trailing) {
                    if selectedTab == 1, (!isMapSpecialMode || (countryOverviewActive && !isLoadingCountryOverview) || (radialSearchActive && !isLoadingRadialSearch)) {
                        Color.clear
                            .frame(width: 60, height: 420)
                            .contentShape(Rectangle())
                            .overlay(alignment: .trailing) {
                                mapDateSlider(height: 340)
                            }
                            .padding(.bottom, 350)
                            .transition(.opacity)
                    }
                }
                .opacity(selectedTab == 1 ? 1 : 0)

            if !isMapSpecialMode {
                iOSListView
                    .background(theme.colors.background)
                    .offset(x: selectedTab == 0 ? 0 : -10000)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedTab)
    }

    // MARK: - iPad Detail Content

    private var iPadDetailContent: some View {
        ZStack(alignment: .bottom) {
            iOSMapView
                
                .overlay(alignment: .trailing) {
                    if showDateSlider, !isMapSpecialMode || (countryOverviewActive && !isLoadingCountryOverview) || (radialSearchActive && !isLoadingRadialSearch) {
                        Color.clear
                            .frame(width: 60, height: 420)
                            .contentShape(Rectangle())
                            .overlay(alignment: .trailing) {
                                mapDateSlider(height: 340)
                            }
                            .padding(.bottom, 350)
                            .transition(.opacity)
                    }
                }

            // Expanded city card on map
            if !isMapSpecialMode || countryOverviewActive || radialSearchActive, showingMapExpandedCard, let city = tappedCity {
                mapExpandedCard(for: city)
                    .id(city.city.id)
                    .transition(.blurReplace)
                    .padding(.horizontal, 16)
                    .zIndex(1)
            }

            // Country selection overlay (top part: pin + country name)
            if countrySelectionMode {
                countrySelectionTopOverlay
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(3)
            }

            // Country selection + loading bottom bar
            if countrySelectionMode || isLoadingCountryOverview {
                countrySearchBottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(3)
            }

            // Country overview exit button
            if countryOverviewActive, !isLoadingCountryOverview {
                countryOverviewExitOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(3)
            }

            // Radial search selection overlay
            if radialSearchMode {
                radialSelectionTopOverlay
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(3)
            }

            // Radial selection + loading bottom bar
            if radialSearchMode || isLoadingRadialSearch {
                radialSearchBottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(3)
            }

            // Radial search exit button
            if radialSearchActive, !isLoadingRadialSearch {
                radialSearchExitOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(3)
            }
        }
    }


    @ToolbarContentBuilder
    private var iOSTrailingToolbarItems: some ToolbarContent {
        if (countryOverviewActive && !isLoadingCountryOverview) || (radialSearchActive && !isLoadingRadialSearch) {
            iOSCountryOverviewToolbarItems
        } else if !isMapSpecialMode {
            iOSDefaultTrailingToolbarItems
        }
    }

    @ToolbarContentBuilder
    private var iOSDefaultTrailingToolbarItems: some ToolbarContent {
        if isEditMode {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation { isEditMode = false }
                } label: {
                    Image(systemName: "checkmark")
                }
            }
        } else {
            iOSNormalToolbarItems
        }
    }

    @ToolbarContentBuilder
    private var iOSCountryOverviewToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation { filterSunny.toggle() }
            } label: {
                Image(systemName: filterSunny ? "sun.max.fill" : "sun.max")
                    .foregroundStyle(filterSunny ? theme.colors.filterSunny : .primary)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                if isPlaying {
                    iOSStopPlayback()
                } else {
                    iOSStartPlayback()
                }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
        }
    }

    @ToolbarContentBuilder
    private var iOSNormalToolbarItems: some ToolbarContent {
        if !isIPad, weatherService.isLoading || isLoadingMapList {
            ToolbarItem(placement: .topBarTrailing) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 36, height: 36)
                    .themedGlass(in: .circle)
            }
            .sharedBackgroundVisibility(.hidden)
        }

        if filterSunny {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation {
                        filterSunny = false
                    }
                } label: {
                    Image(systemName: "sun.max.fill")
                        .foregroundStyle(theme.colors.filterSunny)
                }
            }
        }

        if showPlaybackButton {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if isPlaying {
                        iOSStopPlayback()
                    } else {
                        iOSStartPlayback()
                    }
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
            }
        }

        if isIPad {
            // Loading spinner
            if weatherService.isLoading || isLoadingMapList {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            // Search
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddCityView = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
            }

            // Discover
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingDiscoverPopover = true
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .popover(isPresented: $showingDiscoverPopover) {
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            showingDiscoverPopover = false
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showingMapExpandedCard = false
                                tappedCity = nil
                                previewCity = nil
                                countrySelectionMode = true
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "globe.desk")
                                    .font(.system(size: 14))
                                    .frame(width: 20)
                                Text(localizedString("Country Overview", locale: locale))
                                    .font(.avenir(.body, weight: .medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.leading, 16)
                            .padding(.trailing, 16)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            showingDiscoverPopover = false
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showingMapExpandedCard = false
                                tappedCity = nil
                                previewCity = nil
                                radialSearchMode = true
                                radialSearchRadius = 250_000
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "circle.dotted.circle")
                                    .font(.system(size: 14))
                                    .frame(width: 20)
                                Text(localizedString("Radial Search", locale: locale))
                                    .font(.avenir(.body, weight: .medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.leading, 16)
                            .padding(.trailing, 16)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 8)
                    .frame(width: 240)
                    .presentationCompactAdaptation(.popover)
                    .themedPopoverBackground()
                }
            }

            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            // Center on map
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if mapVisibleListIDs.count > 1 {
                        showingRecenterPopover = true
                    } else {
                        recenterOnAllCities = false
                        DispatchQueue.main.async {
                            recenterOnAllCities = true
                        }
                    }
                } label: {
                    Image(systemName: "dot.squareshape.split.2x2")
                }
                .popover(isPresented: $showingRecenterPopover) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(CityListID.allLists.filter { mapVisibleListIDs.contains($0.rawValue) }) { listID in
                            Button {
                                showingRecenterPopover = false
                                let cities: [CityWeather]
                                if listID == weatherService.activeListID {
                                    cities = weatherService.cityWeatherData
                                } else {
                                    cities = weatherService.otherListData[listID.rawValue] ?? []
                                }
                                focusSubsetCities = cities
                                focusSubsetTrigger = true
                            } label: {
                                HStack(spacing: 12) {
                                    Text(listID.localizedDisplayName(locale: locale))
                                        .font(.avenir(.body, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding(.leading, 24)
                                .padding(.trailing, 16)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(width: 160)
                    .presentationCompactAdaptation(.popover)
                    .themedPopoverBackground()
                }
            }

            // Map style
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingMapStylePopover = true
                } label: {
                    Image(systemName: "map")
                }
                .popover(isPresented: $showingMapStylePopover) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(["minimal", "borders", "detailed"], id: \.self) { mode in
                            Button {
                                showingMapStylePopover = false
                                withAnimation { mapMode = mode }
                            } label: {
                                HStack(spacing: 12) {
                                    Text(mode.capitalized)
                                        .font(.avenir(.body, weight: mapMode == mode ? .bold : .medium))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if mapMode == mode {
                                        Circle()
                                            .fill(Color.primary)
                                            .frame(width: 6, height: 6)
                                    }
                                }
                                .padding(.leading, 24)
                                .padding(.trailing, 16)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(width: 160)
                    .presentationCompactAdaptation(.popover)
                    .themedPopoverBackground()
                }
            }

            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            // Menu
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingMenuPopover = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .frame(width: 36, height: 36)
                        .themedGlass(in: .circle)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingMenuPopover) {
                    iOSCustomMenu
                        .presentationCompactAdaptation(.popover)
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }

        if !isIPad {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingMenuPopover = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .frame(width: 36, height: 36)
                        .themedGlass(in: .circle)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingMenuPopover) {
                    iOSCustomMenu
                        .presentationCompactAdaptation(.popover)
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }





    private var iPadDateSwitcherToolbarContent: some View {
        HStack(spacing: 6) {
            Button {
                if selectedDayOffset > 0 {
                    withAnimation(.smooth(duration: 0.2)) {
                        selectedDayOffset -= 1
                    }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selectedDayOffset > 0 ? .primary : .tertiary)
            }
            .buttonStyle(.plain)

            Button {
                showingDatePopover = true
            } label: {
                Text(iOSDateText)
                    .font(.avenir(.body, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 90)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingDatePopover) {
                DatePicker(
                    "",
                    selection: Binding(
                        get: {
                            Calendar.current.date(byAdding: .day, value: selectedDayOffset, to: Date()) ?? Date()
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
                .themedPopoverBackground()
            }

            Button {
                if selectedDayOffset < 9 {
                    withAnimation(.smooth(duration: 0.2)) {
                        selectedDayOffset += 1
                    }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selectedDayOffset < 9 ? .primary : .tertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private var iOSDateSwitcherCapsule: some View {
        HStack(spacing: 0) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selectedDayOffset > 0 ? .primary : .tertiary)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .onTapGesture {
                    if selectedDayOffset > 0 {
                        withAnimation(.smooth(duration: 0.2)) {
                            selectedDayOffset -= 1
                        }
                    }
                }

            Text(iOSDateText)
                .font(.avenir(.subheadline, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 80)
                .id("ios-date-\(selectedDayOffset)")
                .transition(.asymmetric(
                    insertion: .move(edge: selectedDayOffset >= iOSPreviousDayOffset ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: selectedDayOffset >= iOSPreviousDayOffset ? .leading : .trailing).combined(with: .opacity)
                ))
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture {
                    showingDatePopover = true
                }
                .popover(isPresented: $showingDatePopover) {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: {
                                Calendar.current.date(byAdding: .day, value: selectedDayOffset, to: Date()) ?? Date()
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
                    .themedPopoverBackground()
                }

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selectedDayOffset < 9 ? .primary : .tertiary)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .onTapGesture {
                    if selectedDayOffset < 9 {
                        withAnimation(.smooth(duration: 0.2)) {
                            selectedDayOffset += 1
                        }
                    }
                }
        }
        .padding(6)
        .themedGlass(in: .capsule)
    }

    private var iOSMapControlsCapsule: some View {
        HStack(spacing: 8) {
            Button {
                showingDiscoverPopover = true
            } label: {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingDiscoverPopover) {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        showingDiscoverPopover = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedTab = 1
                            showingMapExpandedCard = false
                            tappedCity = nil
                            previewCity = nil
                            countrySelectionMode = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "globe.desk")
                                .font(.system(size: 14))
                                .frame(width: 20)
                            Text(localizedString("Country Overview", locale: locale))
                                .font(.avenir(.body, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.leading, 16)
                        .padding(.trailing, 16)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingDiscoverPopover = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedTab = 1
                            showingMapExpandedCard = false
                            tappedCity = nil
                            previewCity = nil
                            radialSearchMode = true
                            radialSearchRadius = 250_000
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "circle.dotted.circle")
                                .font(.system(size: 14))
                                .frame(width: 20)
                            Text(localizedString("Radial Search", locale: locale))
                                .font(.avenir(.body, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.leading, 16)
                        .padding(.trailing, 16)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
                .frame(width: 240)
                .presentationCompactAdaptation(.popover)
                .themedPopoverBackground()
            }

            Button {
                if mapVisibleListIDs.count > 1 {
                    showingRecenterPopover = true
                } else {
                    recenterOnAllCities = false
                    DispatchQueue.main.async {
                        recenterOnAllCities = true
                    }
                }
            } label: {
                Image(systemName: "dot.squareshape.split.2x2")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingRecenterPopover) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(CityListID.allLists.filter { mapVisibleListIDs.contains($0.rawValue) }) { listID in
                        Button {
                            showingRecenterPopover = false
                            let cities: [CityWeather]
                            if listID == weatherService.activeListID {
                                cities = weatherService.cityWeatherData
                            } else {
                                cities = weatherService.otherListData[listID.rawValue] ?? []
                            }
                            focusSubsetCities = cities
                            focusSubsetTrigger = true
                        } label: {
                            HStack(spacing: 12) {
                                Text(listID.localizedDisplayName(locale: locale))
                                    .font(.avenir(.body, weight: .medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.leading, 24)
                            .padding(.trailing, 16)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
                .frame(width: 160)
                .presentationCompactAdaptation(.popover)
                .themedPopoverBackground()
            }

            Button {
                showingMapStylePopover = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingMapStylePopover) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(["minimal", "borders", "detailed"], id: \.self) { mode in
                        Button {
                            showingMapStylePopover = false
                            withAnimation { mapMode = mode }
                        } label: {
                            HStack(spacing: 12) {
                                Text(mode.capitalized)
                                    .font(.avenir(.body, weight: mapMode == mode ? .bold : .medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if mapMode == mode {
                                    Circle()
                                        .fill(Color.primary)
                                        .frame(width: 6, height: 6)
                                }
                            }
                            .padding(.leading, 24)
                            .padding(.trailing, 16)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
                .frame(width: 160)
                .presentationCompactAdaptation(.popover)
                .themedPopoverBackground()
            }
        }
        .padding(6)
        .themedGlass(in: .capsule)
        .transition(.scale.combined(with: .opacity))
    }

    private var countrySelectionTopOverlay: some View {
        ZStack {
            // Center pin — offset upward so the tip points at the map center
            Image(systemName: "mappin")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(theme.colors.destructive)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                .offset(y: -18)

            // Top capsule with country name
            VStack {
                if !countryUnderPin.isEmpty {
                    Text(countryUnderPin)
                        .font(.avenir(.headline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .themedGlass(in: .capsule)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text(localizedString("Move map to select a country", locale: locale))
                        .font(.avenir(.subheadline, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .themedGlass(in: .capsule)
                }

                Spacer()
            }
            .padding(.top, 60)
        }
    }

    private func confirmCountryOverview() {
        let name = countryUnderPin
        guard let country = countries.first(where: { $0.title == name }) else { return }
        
        countryOverviewCountryName = name
        gridPreviewPoints = []
        
        // Check cache (2 hour validity)
        if let cached = countryOverviewCache[name],
           Date().timeIntervalSince(cached.date) < 7200 {
            countryOverviewData = cached.data
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                countrySelectionMode = false
                countryUnderPin = ""
                countryOverviewActive = true
            }
            return
        }
        
        let gridCities = generateCountryGrid(for: country)
        guard !gridCities.isEmpty else { return }
        
        countryOverviewData = []
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            countrySelectionMode = false
            countryUnderPin = ""
            isLoadingCountryOverview = true
            countryOverviewActive = true
        }
        
        countryOverviewLoadingTask = Task {
            let results = await weatherService.fetchWeatherForGrid(gridCities, onProgress: { progress in
                Task { @MainActor in
                    countryOverviewProgress = progress
                }
            }, onResult: { cityWeather in
                Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.2)) {
                        countryOverviewData.append(cityWeather)
                    }
                }
            })
            guard !Task.isCancelled else { return }
            await MainActor.run {
                countryOverviewCache[name] = (data: results, date: Date())
                CountryOverviewCacheManager.save(countryOverviewCache)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isLoadingCountryOverview = false
                    countryOverviewProgress = 0
                }
            }
        }
    }

    @ViewBuilder
    private var countrySearchBottomBar: some View {
        VStack {
            Spacer()

            GlassEffectContainer(spacing: 20) {
                HStack(spacing: countrySelectionMode ? 20 : 12) {
                    if countrySelectionMode {
                        // Confirm button
                        Button {
                            confirmCountryOverview()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                        }
                        .themedAccentGlass(tint: countryUnderPin.isEmpty ? .gray : theme.colors.accent, in: .circle)
                        .glassEffectID("cConfirm", in: countryBarNS)
                        .disabled(countryUnderPin.isEmpty)
                    } else {
                        // Loading capsule
                        HStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.small)

                            Text(String(format: localizedString("Loading %@…", locale: locale), countryOverviewCountryName))
                                .font(.avenir(.subheadline, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text("\(Int(countryOverviewProgress * 100))%")
                                .font(.avenir(.subheadline, weight: .medium))
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .themedGlass(in: .capsule)
                        .glassEffectID("cConfirm", in: countryBarNS)
                    }

                    if !countrySelectionMode {
                        Spacer()
                    }

                    // Cancel button
                    Button {
                        if isLoadingCountryOverview {
                            countryOverviewLoadingTask?.cancel()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isLoadingCountryOverview = false
                                countryOverviewActive = false
                                countryOverviewData = []
                                countryOverviewCountryName = ""
                                countryOverviewProgress = 0
                                recenterOnAllCities = true
                            }
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                countrySelectionMode = false
                                countryUnderPin = ""
                                gridPreviewPoints = []
                                recenterOnAllCities = true
                            }
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                    }
                    .themedGlass(in: .circle)
                    .glassEffectID("cCancel", in: countryBarNS)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: countrySelectionMode)
            }
        }
    }

    private var countryOverviewExitOverlay: some View {
        VStack {
            Spacer()

            HStack(alignment: .bottom, spacing: 12) {
                // Exit capsule — left aligned
                HStack(spacing: 12) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(countryOverviewCountryName)
                        .font(.avenir(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .themedGlass(in: .capsule)
                .contentShape(Capsule())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showingMapExpandedCard = false
                        tappedCity = nil
                        countryOverviewActive = false
                        countryOverviewData = []
                        countryOverviewCountryName = ""
                        resolvedGridCityNames = [:]
                        resolvedGridCityName = nil
                        recenterOnAllCities = true
                    }
                }

                Spacer()

                // Recenter + map settings — right aligned
                HStack(spacing: 8) {
                    Button {
                        focusSubsetCities = countryOverviewData
                        focusSubsetTrigger = true
                    } label: {
                        Image(systemName: "dot.squareshape.split.2x2")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingMapStylePopover = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingMapStylePopover) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(["minimal", "borders", "detailed"], id: \.self) { mode in
                                Button {
                                    showingMapStylePopover = false
                                    withAnimation { mapMode = mode }
                                } label: {
                                    HStack(spacing: 12) {
                                        Text(mode.capitalized)
                                            .font(.avenir(.body, weight: mapMode == mode ? .bold : .medium))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if mapMode == mode {
                                            Circle()
                                                .fill(Color.primary)
                                                .frame(width: 6, height: 6)
                                        }
                                    }
                                    .padding(.leading, 24)
                                    .padding(.trailing, 16)
                                    .padding(.vertical, 11)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                        .frame(width: 160)
                        .presentationCompactAdaptation(.popover)
                        .themedPopoverBackground()
                    }
                }
                .padding(6)
                .themedGlass(in: .capsule)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Radial Search Overlays

    private var radialSelectionTopOverlay: some View {
        VStack {
            Text(formatRadius(radialSearchRadius))
                .font(.avenir(.headline, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .themedGlass(in: .capsule)
                .contentTransition(.numericText())

            Spacer()
        }
        .padding(.top, 60)
    }

    private func formatRadius(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.0f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }

    private func confirmRadialSearch() {
        guard let center = mapCenterCoordinate else { return }
        gridPreviewPoints = []

        let gridCities = generateRadialGrid(center: center, radiusMeters: radialSearchRadius)
        guard !gridCities.isEmpty else { return }

        radialSearchData = []
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            radialSearchActive = true
            isLoadingRadialSearch = true
            radialSearchMode = false
        }

        radialSearchLoadingTask = Task {
            let results = await weatherService.fetchWeatherForGrid(gridCities, onProgress: { progress in
                Task { @MainActor in
                    radialSearchProgress = progress
                }
            }, onResult: { cityWeather in
                Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.2)) {
                        radialSearchData.append(cityWeather)
                    }
                }
            })
            guard !Task.isCancelled else { return }
            await MainActor.run {
                _ = results
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isLoadingRadialSearch = false
                    radialSearchProgress = 0
                }
            }
        }
    }

    @ViewBuilder
    private var radialSearchBottomBar: some View {
        VStack {
            Spacer()

            GlassEffectContainer(spacing: 20) {
                HStack(spacing: radialSearchMode ? 20 : 12) {
                    if radialSearchMode {
                        // Confirm button
                        Button {
                            confirmRadialSearch()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                        }
                        .themedAccentGlass(tint: theme.colors.accent, in: .circle)
                        .glassEffectID("rConfirm", in: radialBarNS)
                    } else {
                        // Loading capsule
                        HStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.small)

                            Text(localizedString("Radial Search…", locale: locale))
                                .font(.avenir(.subheadline, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text("\(Int(radialSearchProgress * 100))%")
                                .font(.avenir(.subheadline, weight: .medium))
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .themedGlass(in: .capsule)
                        .glassEffectID("rConfirm", in: radialBarNS)
                    }

                    if !radialSearchMode {
                        Spacer()
                    }

                    // Cancel button
                    Button {
                        if isLoadingRadialSearch {
                            radialSearchLoadingTask?.cancel()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isLoadingRadialSearch = false
                                radialSearchActive = false
                                radialSearchData = []
                                radialSearchProgress = 0
                                recenterOnAllCities = true
                            }
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                radialSearchMode = false
                                gridPreviewPoints = []
                                radialSearchRadius = 160_000
                                recenterOnAllCities = true
                            }
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                    }
                    .themedGlass(in: .circle)
                    .glassEffectID("rCancel", in: radialBarNS)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: radialSearchMode)
            }
        }
    }

    private var radialSearchExitOverlay: some View {
        VStack {
            Spacer()

            HStack(alignment: .bottom, spacing: 12) {
                // Exit capsule — left aligned
                HStack(spacing: 12) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(localizedString("Radial Search", locale: locale))
                        .font(.avenir(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .themedGlass(in: .capsule)
                .contentShape(Capsule())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showingMapExpandedCard = false
                        tappedCity = nil
                        radialSearchActive = false
                        radialSearchData = []
                        resolvedGridCityNames = [:]
                        resolvedGridCityName = nil
                        recenterOnAllCities = true
                    }
                }

                Spacer()

                // Recenter + map settings — right aligned
                HStack(spacing: 8) {
                    Button {
                        focusSubsetCities = radialSearchData
                        focusSubsetTrigger = true
                    } label: {
                        Image(systemName: "dot.squareshape.split.2x2")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingMapStylePopover = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingMapStylePopover) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(["minimal", "borders", "detailed"], id: \.self) { mode in
                                Button {
                                    showingMapStylePopover = false
                                    withAnimation { mapMode = mode }
                                } label: {
                                    HStack(spacing: 12) {
                                        Text(mode.capitalized)
                                            .font(.avenir(.body, weight: mapMode == mode ? .bold : .medium))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if mapMode == mode {
                                            Circle()
                                                .fill(Color.primary)
                                                .frame(width: 6, height: 6)
                                        }
                                    }
                                    .padding(.leading, 24)
                                    .padding(.trailing, 16)
                                    .padding(.vertical, 11)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                        .frame(width: 160)
                        .presentationCompactAdaptation(.popover)
                        .themedPopoverBackground()
                    }
                }
                .padding(6)
                .themedGlass(in: .capsule)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private var iOSCityDetailDestination: some View {
        if let city = tappedCity {
            WeatherDetailView(
                cityWeather: city,
                selectedDayOffset: selectedDayOffset,
                namespace: popupNamespace,
                onDismiss: {
                    showingCityDetail = false
                },
                onAddCity: cityIsInSidebar(city) ? nil : {
                    Task {
                        await addCityToSidebar(city)
                        showingCityDetail = false
                        if selectedTab == 1 {
                            recenterOnAllCities = true
                        }
                    }
                },
                onDeleteCity: cityIsInSidebar(city) ? {
                    weatherService.removeCity(city)
                    showingCityDetail = false
                    showingMapExpandedCard = false
                    tappedCity = nil
                    if selectedTab == 1 {
                        recenterOnAllCities = true
                    }
                } : nil,
                isInSidebar: cityIsInSidebar(city),
                showCloudCover: showCloudCover
            )
            .background(theme.colors.background)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(theme.colors.background, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                if isIPad {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation {
                                sidebarVisibility = sidebarVisibility == .all ? .detailOnly : .all
                            }
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingCityDetail = false
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text((countryOverviewActive || radialSearchActive) ? (resolvedGridCityName ?? "…") : city.city.localizedName(locale: locale))
                        .font(.avenir(.title3, weight: .semibold))
                        .dynamicTypeSize(...DynamicTypeSize.large)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if isIPad, cityIsInSidebar(city) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Color.clear
                            .frame(width: 60, height: 1)
                    }
                }
                if !cityIsInSidebar(city) {
                    ToolbarItem(placement: .topBarTrailing) {
                        if countryOverviewActive || radialSearchActive {
                            Button {
                                showingAddToListPopover = true
                            } label: {
                                Image(systemName: "plus")
                                    .foregroundStyle(theme.colors.accent)
                            }
                            .popover(isPresented: $showingAddToListPopover) {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(CityListID.allLists) { list in
                                        Button {
                                            showingAddToListPopover = false
                                            let cityName = resolvedGridCityName ?? city.city.country
                                            let namedCity = City(name: cityName, country: city.city.country, latitude: city.city.latitude, longitude: city.city.longitude)
                                            Task {
                                                await weatherService.addCityToList(namedCity, listID: list)
                                                showingCityDetail = false
                                            }
                                        } label: {
                                            HStack(spacing: 12) {
                                                Text(list.localizedDisplayName(locale: locale))
                                                    .font(.avenir(.body, weight: .medium))
                                                    .foregroundStyle(.primary)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 11)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .frame(minWidth: 180)
                                .presentationCompactAdaptation(.popover)
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
                                Image(systemName: "plus")
                                    .foregroundStyle(theme.colors.accent)
                            }
                        }
                    }
                }
                if cityIsInSidebar(city), !isIPad {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingDetailMenuPopover = true
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(theme.colors.primaryText)
                                .frame(width: 36, height: 36)
                                .themedGlass(in: .circle)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingDetailMenuPopover) {
                            VStack(alignment: .leading, spacing: 0) {
                                menuRow(icon: "map", title: localizedString("Reveal on Map", locale: locale)) {
                                    showingDetailMenuPopover = false
                                    let revealCity = city
                                    showingCityDetail = false
                                    centerOnCityTrigger = nil
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        selectedTab = 1
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        centerOnCityTrigger = revealCity
                                    }
                                }
                                
                                menuRow(icon: "trash", title: localizedString("Delete City", locale: locale)) {
                                    showingDetailMenuPopover = false
                                    weatherService.removeCity(city)
                                    showingCityDetail = false
                                    if selectedTab == 1 {
                                        recenterOnAllCities = true
                                    }
                                }
                                .foregroundStyle(theme.colors.destructive)
                            }
                            .padding(.vertical, 8)
                            .frame(width: 220)
                            .themedPopoverBackground()
                            .presentationCompactAdaptation(.popover)
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
        }
    }

    // MARK: - Inline Search Overlay (iPhone)

    // MARK: - Unified Bottom Bar (morphs between toolbar and search)

    private var iOSUnifiedBottomBar: some View {
        HStack(spacing: 12) {
            if showingInlineSearch {
                // SEARCH STATE: search bar (full width) + x button
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
                .padding(.horizontal, 14)
                .frame(height: 36)
                .padding(6)
                .matchedGeometryEffect(id: "bottomBarCenter", in: bottomBarNS)
                .themedGlass(in: .capsule)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: inlineSearchText.isEmpty)

                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .padding(6)
                    .matchedGeometryEffect(id: "bottomBarRight", in: bottomBarNS)
                    .themedGlass(in: .circle)
                    .contentShape(Circle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            showingInlineSearch = false
                            inlineSearchText = ""
                            inlineSearchFocused = false
                        }
                    }

            } else if previewCity != nil {
                // PREVIEW STATE: + button + search bar (city name) + x button
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
                    .frame(width: 36, height: 36)
                    .padding(6)
                    .matchedGeometryEffect(id: "bottomBarLeft", in: bottomBarNS)
                    .themedGlass(in: .circle)
                    .contentShape(Circle())
                    .onTapGesture {
                        if let city = previewCity {
                            Task {
                                await addCityToSidebar(city)
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    previewCity = nil
                                }
                            }
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
                .contentShape(Capsule())
                .onTapGesture {
                    if isIPad {
                        showingAddCityView = true
                    } else {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            showingInlineSearch = true
                            inlineSearchText = previewSearchText
                        }
                    }
                }

                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .padding(6)
                    .matchedGeometryEffect(id: "bottomBarRight", in: bottomBarNS)
                    .themedGlass(in: .circle)
                    .contentShape(Circle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showingMapExpandedCard = false
                            previewCity = nil
                            recenterOnAllCities = true
                        }
                    }

            } else {
                // NORMAL STATE: tab switcher + spacer + date/map controls
                HStack(spacing: 8) {
                    Image(systemName: isGridView ? "square.grid.2x2" : "list.bullet")
                        .contentTransition(.symbolEffect(.replace))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(selectedTab == 0 ? theme.colors.dotRain : .secondary)
                        .frame(width: 42, height: 44)
                        .background {
                            if selectedTab == 0 {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .contentShape(Capsule())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selectedTab = 0
                            }
                        }

                    Image(systemName: selectedTab == 1 ? "map.fill" : "map")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(selectedTab == 1 ? theme.colors.dotRain : .secondary)
                        .frame(width: 42, height: 44)
                        .background {
                            if selectedTab == 1 {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .contentShape(Capsule())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selectedTab = 1
                            }
                        }
                }
                .padding(6)
                .matchedGeometryEffect(id: "bottomBarLeft", in: bottomBarNS)
                .themedGlass(in: .capsule)
                .fixedSize()

                Spacer()

                Group {
                    if selectedTab == 0 {
                        iOSDateSwitcherCapsule
                    } else {
                        iOSMapControlsCapsule
                    }
                }
                .matchedGeometryEffect(id: "bottomBarRight", in: bottomBarNS)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    inlineSearchFocused = true
                }
            } else {
                inlineSearchManager.search(query: "")
                inlineSearchFocused = false
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
        .background(theme.colors.searchOverlayBackground)
        .ignoresSafeArea(edges: .bottom)
    }

    @State private var inlineIsLoadingCity = false

    private func inlineIsExistingCity(_ result: CitySearchResult) -> Bool {
        let name = result.title.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? result.title
        let country = result.subtitle.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? result.subtitle
        return weatherService.cityWeatherData.contains(where: { $0.city.name == name && $0.city.country == country })
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

        // Check if city already exists
        if let existingCity = weatherService.cityWeatherData.first(where: { $0.city.name == cityName && $0.city.country == country }) {
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

        handleInlineSearchCitySelected(tempCityWeather)
    }

    private func handleInlineSearchCitySelected(_ cityWeather: CityWeather) {
        if selectedTab == 1 || isIPad {
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
                selectedDayOffset: selectedDayOffset,
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
                isInSidebar: cityIsInSidebar(city),
                showCloudCover: showCloudCover
            )
            .background(theme.colors.background)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(theme.colors.background, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingAddCityDetail = false
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(city.city.localizedName(locale: locale))
                        .font(.avenir(.title3, weight: .semibold))
                        .dynamicTypeSize(...DynamicTypeSize.large)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if !cityIsInSidebar(city) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task {
                                await addCityToSidebar(city)
                                showingAddCityView = false
                                showingAddCityDetail = false
                                if selectedTab == 1 {
                                    recenterOnAllCities = true
                                }
                            }
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(theme.colors.accent)
                        }
                    }
                }
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
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                
                Text(String(format: localizedString("Are you sure you want to delete \"%@\"? This cannot be undone.", locale: locale), weatherService.activeListID.localizedDisplayName(locale: locale)))
                    .font(.avenir(.subheadline, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
                
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
                        deleteCurrentList()
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
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }



    private var iOSListSwitcher: some View {
        Group {
            if isEditingListName {
                TextField("List name", text: $editingListName)
                    .font(.avenir(.title, weight: .bold))
                    .multilineTextAlignment(.center)
                    .submitLabel(.done)
                    .focused($listNameFieldFocused)
                    .onSubmit { commitListNameEdit() }
                    .onChange(of: listNameFieldFocused) { _, focused in
                        if !focused { commitListNameEdit() }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .onAppear { listNameFieldFocused = true }
            } else {
                Button {
                    showingListSwitcher = true
                } label: {
                    Text(weatherService.activeListID.localizedDisplayName(locale: locale))
                        .font(.avenir(.title, weight: .bold))
                        .overlay(alignment: .trailing) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .offset(x: 20)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingListSwitcher) {
                    iOSListSwitcherMenu
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
    }
    
    private var iOSListSwitcherMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isReorderingLists {
                // Reorder mode: drag handle items
                let rowHeight: CGFloat = 44
                ForEach(Array(reorderableLists.enumerated()), id: \.element.id) { index, listID in
                    HStack(spacing: 12) {
                        Text(listID.localizedDisplayName(locale: locale))
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                    .opacity(draggingListID == listID ? 0.5 : 1.0)
                    .offset(y: draggingListID == listID ? dragOffset : 0)
                    .zIndex(draggingListID == listID ? 1 : 0)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if draggingListID == nil {
                                    draggingListID = listID
                                }
                                guard draggingListID == listID else { return }
                                dragOffset = value.translation.height
                                
                                guard let fromIndex = reorderableLists.firstIndex(of: listID) else { return }
                                let proposedOffset = Int(round(value.translation.height / rowHeight))
                                let toIndex = min(max(fromIndex + proposedOffset, 0), reorderableLists.count - 1)
                                if toIndex != fromIndex {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        reorderableLists.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                                    }
                                    // Reset offset after move so it stays near the finger
                                    let moved = toIndex - fromIndex
                                    dragOffset -= CGFloat(moved) * rowHeight
                                }
                            }
                            .onEnded { _ in
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    dragOffset = 0
                                    draggingListID = nil
                                }
                            }
                    )
                }
                
                Divider()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                
                // Done button
                Button {
                    CityListID.saveListOrder(reorderableLists)
                    isReorderingLists = false
                } label: {
                    HStack(spacing: 12) {
                        Text("Done")
                            .font(.avenir(.body, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "checkmark")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                // Normal mode: tappable list items
                ForEach(CityListID.allLists) { listID in
                    Button {
                        showingListSwitcher = false
                        guard listID != weatherService.activeListID else { return }
                        mapHasInitialized = false
                        recenterOnAllCities = false
                        withAnimation(.easeOut(duration: 0.15)) {
                            listContentOpacity = 0
                        }
                        Task {
                            try? await Task.sleep(for: .milliseconds(150))
                            await weatherService.switchList(to: listID)
                            withAnimation(.easeIn(duration: 0.2)) {
                                listContentOpacity = 1
                            }
                            recenterOnAllCities = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text(listID.localizedDisplayName(locale: locale))
                                .font(.avenir(.body, weight: listID == weatherService.activeListID ? .bold : .medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            if listID == weatherService.activeListID {
                                Circle()
                                    .fill(Color.primary)
                                    .frame(width: 6, height: 6)
                                    .frame(width: 13)
                            }
                        }
                        .padding(.leading, 24)
                        .padding(.trailing, 16)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                
                Divider()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                
                Button {
                    showingListSwitcher = false
                    startAddingNewList()
                } label: {
                    HStack(spacing: 12) {
                        Text("Add List")
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "plus")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Button {
                    showingListSwitcher = false
                    startEditingListName()
                } label: {
                    HStack(spacing: 12) {
                        Text("Rename List")
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "pencil")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Button {
                    reorderableLists = CityListID.allLists
                    isReorderingLists = true
                } label: {
                    HStack(spacing: 12) {
                        Text("Reorder Lists")
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Button {
                    showingListSwitcher = false
                    showingDeleteListConfirmation = true
                } label: {
                    HStack(spacing: 12) {
                        Text(localizedString("Delete List", locale: locale))
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(theme.colors.destructive)
                        Spacer()
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.colors.destructive)
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 210)
        .themedPopoverBackground()
        .onChange(of: showingListSwitcher) { _, showing in
            if !showing {
                isReorderingLists = false
                draggingListID = nil
                dragOffset = 0
            }
        }
    }
    
    private var iOSListSwitcherMenuListsOnly: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(CityListID.allLists) { listID in
                Button {
                    showingListSwitcher = false
                    guard listID != weatherService.activeListID else { return }
                    mapHasInitialized = false
                    recenterOnAllCities = false
                    withAnimation(.easeOut(duration: 0.15)) {
                        listContentOpacity = 0
                    }
                    Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        await weatherService.switchList(to: listID)
                        withAnimation(.easeIn(duration: 0.2)) {
                            listContentOpacity = 1
                        }
                        recenterOnAllCities = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(listID.localizedDisplayName(locale: locale))
                            .font(.avenir(.body, weight: listID == weatherService.activeListID ? .bold : .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        if listID == weatherService.activeListID {
                            Circle()
                                .fill(Color.primary)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 210)
        .themedPopoverBackground()
    }

    private var iOSMapListSwitcherMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(CityListID.allLists) { listID in
                Button {
                    let id = listID.rawValue
                    if mapVisibleListIDs.contains(id) {
                        // Don't allow deselecting the last list
                        if mapVisibleListIDs.count > 1 {
                            mapVisibleListIDs.remove(id)
                            // If we deselected the active list, switch to one that's still visible
                            if listID == weatherService.activeListID,
                               let remainingID = mapVisibleListIDs.first,
                               let newActiveList = CityListID.allLists.first(where: { $0.rawValue == remainingID }) {
                                Task {
                                    await weatherService.switchList(to: newActiveList)
                                    recenterOnAllCities = true
                                }
                            } else {
                                recenterOnAllCities = true
                            }
                        }
                    } else {
                        mapVisibleListIDs.insert(id)
                        // Fetch data for this list if not already loaded
                        if listID != weatherService.activeListID {
                            Task {
                                isLoadingMapList = true
                                await weatherService.fetchWeatherForList(listID)
                                isLoadingMapList = false
                                recenterOnAllCities = true
                            }
                        } else {
                            recenterOnAllCities = true
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(listID.localizedDisplayName(locale: locale))
                            .font(.avenir(.body, weight: mapVisibleListIDs.contains(listID.rawValue) ? .bold : .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: mapVisibleListIDs.contains(listID.rawValue) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(mapVisibleListIDs.contains(listID.rawValue) ? .white : .secondary)
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 210)
        .themedPopoverBackground()
    }
    private var iOSCustomMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isIPad {
                menuRow(icon: "magnifyingglass", title: localizedString("Search", locale: locale)) {
                    showingMenuPopover = false
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showingInlineSearch = true
                    }
                }
            }

            if !isEditingListName {
                if let city = selectedTab == 1 ? (showingMapExpandedCard ? tappedCity : nil) : selectedCity,
                   cityIsInSidebar(city) {
                    menuRow(icon: "trash", title: localizedString("Delete", locale: locale) + " \"" + city.city.localizedName(locale: locale) + "\"") {
                        showingMenuPopover = false
                        weatherService.removeCity(city)
                        if selectedTab == 1 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingMapExpandedCard = false
                                tappedCity = nil
                                recenterOnAllCities = true
                            }
                        } else {
                            if selectedCity?.id == city.id {
                                selectedCity = nil
                            }
                        }
                    }
                    .foregroundStyle(theme.colors.destructive)
                }
            }

            if selectedTab == 0, !isIPad {
                menuRow(icon: isEditMode ? "checkmark" : "pencil", title: isEditMode ? localizedString("Done Editing", locale: locale) : (isGridView ? localizedString("Edit Grid", locale: locale) : localizedString("Edit List", locale: locale))) {
                    showingMenuPopover = false
                    withAnimation { isEditMode.toggle() }
                }

                menuRow(icon: isGridView ? "list.bullet" : "square.grid.2x2", title: isGridView ? localizedString("List View", locale: locale) : localizedString("Grid View", locale: locale)) {
                    showingMenuPopover = false
                    withAnimation(.easeOut(duration: 0.15)) {
                        listContentOpacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        isGridView.toggle()
                        withAnimation(.easeIn(duration: 0.2)) {
                            listContentOpacity = 1
                        }
                    }
                }
            }

            if isIPad {
                menuRow(icon: "slider.horizontal.below.sun.max", title: showDateSlider ? localizedString("Hide Date Slider", locale: locale) : localizedString("Show Date Slider", locale: locale)) {
                    showingMenuPopover = false
                    withAnimation { showDateSlider.toggle() }
                }
            }

            Divider().padding(.horizontal, 12).padding(.vertical, 4)

            menuRow(icon: filterSunny ? "sun.max.fill" : "sun.max", title: filterSunny ? localizedString("Clear Filter", locale: locale) : localizedString("Filter Sunny", locale: locale)) {
                showingMenuPopover = false
                withAnimation { filterSunny.toggle() }
            }

            if selectedTab == 1 || isIPad {
                menuRow(icon: isPlaying ? "stop.fill" : "play.fill", title: isPlaying ? localizedString("Stop Playback", locale: locale) : localizedString("Play Forecast", locale: locale)) {
                    showingMenuPopover = false
                    if isPlaying { iOSStopPlayback() } else { iOSStartPlayback() }
                }
            }

            menuRow(icon: "arrow.clockwise", title: localizedString("Refresh", locale: locale) + (timeSinceRefreshText().isEmpty ? "" : " (\(timeSinceRefreshText()))")) {
                showingMenuPopover = false
                Task { await weatherService.refreshWeather() }
            }
            .opacity(weatherService.isLoading ? 0.4 : 1.0)
            .disabled(weatherService.isLoading)

            Divider().padding(.horizontal, 12).padding(.vertical, 4)

            menuRow(icon: "gearshape", title: localizedString("Settings", locale: locale)) {
                showingMenuPopover = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showingSettings = true
                }
            }
        }
        .padding(.vertical, 8)
        .frame(width: 220)
        .themedPopoverBackground()
    }

    private func menuRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .frame(width: 24)
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.avenir(.body, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func gridCell(for cityWeather: CityWeather) -> some View {
        let forecast = cityWeather.forecast(for: selectedDayOffset)
        VStack(spacing: 8) {
            Image(systemName: forecast.weatherIcon)
                .font(.title2)
                .weatherIconStyle(for: forecast.weatherIcon)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                .frame(height: 30)

            Text(tempUnit.display(forecast.daytimeHigh))
                .font(.avenir(.title2, weight: .medium))
                .contentTransition(.numericText())

            Text(cityWeather.city.localizedName(locale: locale))
                .font(.avenir(.footnote, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            if isEditMode {
                Button {
                    withAnimation {
                        weatherService.removeCity(cityWeather)
                        if selectedCity?.id == cityWeather.id {
                            selectedCity = nil
                        }
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, theme.colors.destructive)
                }
                .offset(x: -6, y: -6)
                .transition(.scale.combined(with: .opacity))
            }
        }
        
        .onTapGesture {
            if !isEditMode {
                detailOpenedFromList = true
                tappedCity = cityWeather
                showingCityDetail = true
            }
        }
        .onDrag {
            if isEditMode {
                gridDragItem = cityWeather
                return NSItemProvider(object: cityWeather.id.uuidString as NSString)
            }
            return NSItemProvider()
        }
        .onDrop(of: [.text], delegate: GridDropDelegate(
            item: cityWeather,
            dragItem: $gridDragItem,
            cities: weatherService.cityWeatherData,
            moveCity: { from, to in
                weatherService.moveCity(from: from, to: to)
            }
        ))
        .contextMenu {
            if !isEditMode {
                Button(role: .destructive) {
                    weatherService.removeCity(cityWeather)
                    if selectedCity?.id == cityWeather.id {
                        selectedCity = nil
                    }
                } label: {
                    Label(localizedString("Delete", locale: locale), systemImage: "trash")
                }
            }
        }
    }

    private func iOSStartPlayback() {
        playbackButtonHideTask?.cancel()
        withAnimation { showPlaybackButton = true }
        isPlaying = true
        if selectedDayOffset >= 9 {
            selectedDayOffset = 0
        }
        playbackTask = Task {
            while !Task.isCancelled && selectedDayOffset < 9 {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { break }
                withAnimation(.smooth(duration: 0.4)) {
                    selectedDayOffset += 1
                }
            }
            if !Task.isCancelled {
                iOSStopPlayback()
            }
        }
    }

    private func iOSStopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
        // Auto-hide button after 10 seconds
        playbackButtonHideTask?.cancel()
        playbackButtonHideTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            withAnimation { showPlaybackButton = false }
        }
    }

    @State private var isAddingNewList: Bool = false
    
    private func startEditingListName() {
        editingListName = weatherService.activeListID.localizedDisplayName(locale: locale)
        isEditingListName = true
    }
    
    private func startAddingNewList() {
        isAddingNewList = true
        withAnimation(.easeOut(duration: 0.15)) {
            listContentOpacity = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await weatherService.addNewList(name: "")
            withAnimation(.easeIn(duration: 0.2)) {
                listContentOpacity = 1
            }
            editingListName = ""
            isEditingListName = true
        }
    }
    
    private func deleteCurrentList() {
        withAnimation(.easeOut(duration: 0.15)) {
            listContentOpacity = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await weatherService.deleteCurrentList()
            withAnimation(.easeIn(duration: 0.2)) {
                listContentOpacity = 1
            }
            recenterOnAllCities = true
        }
    }
    
    private func commitListNameEdit() {
        let name = editingListName.trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            isEditingListName = false
        }
        if name.isEmpty {
            // Empty name: use "New List" for new lists, keep existing name for renames
            if isAddingNewList {
                weatherService.renameCurrentList(to: localizedString("New List", locale: locale))
            }
        } else {
            weatherService.renameCurrentList(to: name)
        }
        isAddingNewList = false
    }
    
    private func swipeDayGesture() -> some Gesture {
        DragGesture(minimumDistance: 30, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }
                let maxDay = max(weatherService.forecastDays.count - 1, 0)
                if horizontal < 0 && selectedDayOffset < maxDay {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        iOSPreviousDayOffset = selectedDayOffset
                        selectedDayOffset += 1
                    }
                } else if horizontal > 0 && selectedDayOffset > 0 {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        iOSPreviousDayOffset = selectedDayOffset
                        selectedDayOffset -= 1
                    }
                }
            }
    }
    
    private var iOSListView: some View {
        Group {
            if weatherService.cityWeatherData.isEmpty && weatherService.isLoading {
                // First launch loading state
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
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            } else if weatherService.cityWeatherData.isEmpty && weatherService.hasSavedCities {
                VStack(spacing: 0) {
                    iOSListSwitcher
                        .padding(.top, 24)
                        .padding(.bottom, 20)
                    Spacer()
                    ContentUnavailableView(localizedString("Loading Weather", locale: locale), systemImage: "cloud.sun", description: Text(localizedString("Fetching forecasts for your cities…", locale: locale)))
                    Spacer()
                }
            } else if weatherService.cityWeatherData.isEmpty {
                VStack(spacing: 0) {
                    iOSListSwitcher
                        .padding(.top, 24)
                        .padding(.bottom, 20)
                    Spacer()
                    if !isEditingListName {
                        Button {
                            if isIPad {
                                showingAddCityView = true
                            } else {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                    showingInlineSearch = true
                                }
                            }
                        } label: {
                            Label(localizedString("Search", locale: locale), systemImage: "magnifyingglass")
                                .font(.avenir(.body, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(theme.colors.accent, in: Capsule())
                                .themedGlass(in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 40)
                        .transition(.scale.combined(with: .opacity))
                    }
                    Spacer()
                    Spacer()
                }
            } else if isGridView {
                ScrollView {
                    iOSListSwitcher
                        .padding(.top, 24)
                        .padding(.bottom, 20)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(iOSFilteredCities) { cityWeather in
                            gridCell(for: cityWeather)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, isIPad ? 20 : 100)
                }
                .gesture(swipeDayGesture())
                .transition(.opacity)
            } else {
                List {
                    iOSListSwitcher
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 20, trailing: 16))
                        .padding(.top, 8)

                    ForEach(iOSFilteredCities) { cityWeather in
                        HStack {
                            Text(cityWeather.city.localizedName(locale: locale))
                                .font(.avenir(.body, weight: .medium))
                            Spacer()
                            Text(tempUnit.display(cityWeather.forecast(for: selectedDayOffset).daytimeHigh))
                                .font(.avenir(.title2, weight: .medium))
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                                .padding(.trailing, 4)
                            Image(systemName: cityWeather.forecast(for: selectedDayOffset).weatherIcon)
                                .font(.title3)
                                .weatherIconStyle(for: cityWeather.forecast(for: selectedDayOffset).weatherIcon)
                                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                                .frame(width: 32)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(longPressedCity?.id == cityWeather.id ? Color.primary.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .scaleEffect(longPressedCity?.id == cityWeather.id ? 0.97 : 1.0)
                        .animation(.easeOut(duration: 0.2), value: longPressedCity?.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !isEditMode {
                                detailOpenedFromList = true
                                tappedCity = cityWeather
                                showingCityDetail = true
                            }
                        }
                        .onLongPressGesture {
                            longPressedCity = cityWeather
                        }
                        .popover(isPresented: Binding(
                            get: { longPressedCity?.id == cityWeather.id },
                            set: { if !$0 { longPressedCity = nil } }
                        )) {
                            VStack(alignment: .leading, spacing: 0) {
                                menuRow(icon: "map", title: localizedString("Reveal on Map", locale: locale)) {
                                    let revealCity = cityWeather
                                    longPressedCity = nil
                                    showingCityDetail = false
                                    centerOnCityTrigger = nil
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        selectedTab = 1
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        centerOnCityTrigger = revealCity
                                    }
                                }
                                
                                Divider().padding(.horizontal, 12).padding(.vertical, 4)
                                
                                menuRow(icon: "trash", title: localizedString("Delete City", locale: locale)) {
                                    longPressedCity = nil
                                    weatherService.removeCity(cityWeather)
                                    if selectedCity?.id == cityWeather.id {
                                        selectedCity = nil
                                    }
                                }
                                .foregroundStyle(theme.colors.destructive)
                            }
                            .padding(.vertical, 8)
                            .frame(width: 220)
                            .presentationCompactAdaptation(.popover)
                            .themedPopoverBackground()
                        }
                    }
                    .onDelete(perform: isEditMode ? { indexSet in
                        for index in indexSet {
                            let cityToDelete = iOSFilteredCities[index]
                            weatherService.removeCity(cityToDelete)
                            if selectedCity?.id == cityToDelete.id {
                                selectedCity = nil
                            }
                        }
                    } : nil)
                    .onMove(perform: isEditMode ? { source, destination in
                        weatherService.moveCity(from: source, to: destination)
                    } : nil)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                .listStyle(.plain)
                .contentMargins(.bottom, isIPad ? 20 : 100)
                .environment(\.editMode, Binding(
                    get: { isEditMode ? .active : .inactive },
                    set: { newValue in isEditMode = (newValue == .active) }
                ))
                .gesture(swipeDayGesture())
                .transition(.opacity)
            }
        }
        .opacity(listContentOpacity)
    }

    private var iOSFilteredCities: [CityWeather] {
        var cities = weatherService.cityWeatherData
        if !searchText.isEmpty {
            cities = cities.filter {
                $0.city.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        if filterSunny {
            cities = cities.filter {
                let forecast = $0.forecast(for: selectedDayOffset)
                return forecast.condition == .clear
            }
        }
        return cities
    }

    private var iOSMapView: some View {
        mapView
    }
    #endif

    private var mapView: some View {
        ZStack {
            MapKitMapView(
                countries: countries,
                cities: mapCities,
                selectedDayOffset: selectedDayOffset,
                showCloudCover: showCloudCover,
                filterSunny: filterSunny,
                isPlaying: isPlaying,
                namespace: popupNamespace,
                showingCityDetail: Binding(
                    get: { showingMapExpandedCard || (isIPad && showingCityDetail) },
                    set: { showingMapExpandedCard = $0 }
                ),
                tappedCity: $tappedCity,
                centerOnCity: centerOnCityTrigger,
                recenterOnAllCities: $recenterOnAllCities,
                focusOnSubsetCities: focusSubsetCities,
                focusOnSubsetTrigger: $focusSubsetTrigger,
                mapMode: mapMode,
                countrySelectionMode: countrySelectionMode,
                forceDotsOnly: countryOverviewActive || radialSearchActive,
                gridPreviewPoints: gridPreviewPoints,
                mapCenterCoordinate: $mapCenterCoordinate,
                radialSearchMode: radialSearchMode,
                radialSearchRadius: radialSearchRadius,
                onRadiusChange: { newRadius in
                    radialSearchRadius = newRadius
                },
                onDoubleTapMarker: {
                    if previewCity != nil {
                        previewCity = nil
                    }
                    showingCityDetail = true
                },
                onCameraMove: { coord in
                    if countrySelectionMode {
                        updateCountryUnderPinDirect(coord)
                    }
                }
            )
            .ignoresSafeArea()

            // Floating loading popup on map — positioned at 1/3 from top to match list view
            if weatherService.isLoading, !(isIPad && sidebarVisibility != .detailOnly) {
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

            // City detail popup (desktop/iPad only — iPhone uses navigation)
            #if os(macOS)
            if showingCityDetail, let city = tappedCity {
                theme.colors.modalOverlay
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showingCityDetail = false
                        }
                    }
                    .transition(.opacity)

                WeatherDetailView(
                    cityWeather: city,
                    selectedDayOffset: selectedDayOffset,
                    namespace: popupNamespace,
                    onDismiss: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showingCityDetail = false
                        }
                    },
                    onAddCity: cityIsInSidebar(city) ? nil : {
                        Task {
                            await addCityToSidebar(city)
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                showingCityDetail = false
                            }
                            recenterOnAllCities = true
                        }
                    },
                    onDeleteCity: cityIsInSidebar(city) ? {
                        weatherService.removeCity(city)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showingCityDetail = false
                            showingMapExpandedCard = false
                            tappedCity = nil
                        }
                        recenterOnAllCities = true
                    } : nil,
                    onRevealOnMap: detailOpenedFromList ? {
                        let revealCity = city
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showingCityDetail = false
                        }
                        centerOnCityTrigger = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            centerOnCityTrigger = revealCity
                        }
                    } : nil,
                    isInSidebar: cityIsInSidebar(city),
                    showCloudCover: showCloudCover
                )
            }
            #endif
        }
    }

    private func cityIsInSidebar(_ cityWeather: CityWeather) -> Bool {
        weatherService.cityWeatherData.contains(where: { $0.city.name == cityWeather.city.name && $0.city.country == cityWeather.city.country })
    }

    private func addCityToSidebar(_ cityWeather: CityWeather) async {
        await weatherService.addCity(cityWeather.city)
        // Update the tapped city to the newly added one from the sidebar
        if let newCity = weatherService.cityWeatherData.first(where: { $0.city.name == cityWeather.city.name && $0.city.country == cityWeather.city.country }) {
            tappedCity = newCity
        }
    }
}

#Preview {
    ContentView()
}

#Preview("中文") {
    ContentView()
        .environment(\.locale, Locale(identifier: "zh-Hans"))
}

#Preview("Cards") {
    let sampleCities: [(String, AppWeatherCondition, Double, String)] = [
        ("Beijing", .clear, 28, "sun.max.fill"),
        ("London", .rain, 14, "cloud.rain.fill"),
        ("Paris", .partlyCloudy, 22, "cloud.sun.fill"),
        ("Shanghai", .cloudy, 19, "cloud.fill"),
        ("Berlin", .snow, -2, "cloud.snow.fill"),
        ("Rome", .clear, 30, "sun.max.fill"),
    ]

    let cityWeathers: [CityWeather] = sampleCities.map { name, condition, temp, symbol in
        let forecast = DailyForecast(
            dayOffset: 0,
            daytimeLow: temp - 5,
            daytimeHigh: temp,
            symbolName: symbol,
            condition: condition,
            hourlyForecasts: [],
            cloudCover: condition == .cloudy ? 0.8 : 0.2,
            precipitationChance: condition == .rain ? 0.7 : 0.1
        )
        return CityWeather(
            city: City(name: name, country: "", latitude: 0, longitude: 0),
            condition: condition,
            temperature: temp,
            symbolName: symbol,
            dailyForecasts: [forecast],
            timeZone: .current
        )
    }

    ScrollView {
        VStack(spacing: 24) {
            Text("Pin Mode")
                .font(.headline)
            HStack(spacing: 40) {
                ForEach(cityWeathers.prefix(3)) { cw in
                    WeatherMarker(
                        cityWeather: cw,
                        dayOffset: 0,
                        isCompact: true,
                        namespace: Namespace().wrappedValue,
                        showCloudCover: false,
                        displayMode: .card
                    )
                }
            }

            Divider()

            Text("Dot Mode")
                .font(.headline)
            HStack(spacing: 40) {
                ForEach(cityWeathers.prefix(3)) { cw in
                    WeatherMarker(
                        cityWeather: cw,
                        dayOffset: 0,
                        isCompact: true,
                        namespace: Namespace().wrappedValue,
                        showCloudCover: false,
                        displayMode: .dot
                    )
                }
            }
        }
        .padding(32)
    }
    .preferredColorScheme(.dark)
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
    var filterSunny: Bool = false
    var passesFilter: Bool = true
    var isPlaying: Bool = false
    var displayMode: MarkerDisplayMode = .card
    var isSelected: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    
    private var tempUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
    }

    private var forecast: DailyForecast {
        cityWeather.forecast(for: dayOffset)
    }

    private var showAsDot: Bool { displayMode == .dot }
    private var showAsCard: Bool { displayMode == .card }

    private var displayIcon: String {
        if filterSunny {
            if isPlaying {
                return "sun.max.fill"
            } else {
                return passesFilter ? "sun.max.fill" : forecast.weatherIcon
            }
        }
        // Use plain cloud for rain/drizzle/snow — the animation shows the precipitation
        if forecast.condition == .rain || forecast.condition == .drizzle || forecast.condition == .snow {
            return "cloud.fill"
        }
        return forecast.weatherIcon
    }

    private var displayCondition: AppWeatherCondition {
        if filterSunny && passesFilter {
            return .clear
        }
        // Match animation to the displayed icon, not raw condition
        // e.g. mostlyCloudy maps to .partlyCloudy but shows cloud.fill (no sun)
        let icon = displayIcon
        if icon == "cloud.fill" {
            switch forecast.condition {
            case .rain: return .rain
            case .drizzle: return .drizzle
            case .snow: return .snow
            default: return .cloudy
            }
        }
        return forecast.condition
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Pulse ring behind everything
            if isSelected {
                SelectedPulseRing(shape: .circle, color: displayCondition.dotColor)
                    .frame(width: 10, height: 10)
            }

            // Dot layer — always present as anchor
            Circle()
                .fill(displayCondition.dotColor)
                .frame(width: 10, height: 10)
                .shadow(color: displayCondition.dotColor.opacity(isSelected ? 0.8 : 0.5), radius: isSelected ? 12 : 4)
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
        .animation(.easeInOut(duration: 0.3), value: displayMode)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .animation(.smooth(duration: 0.4), value: dayOffset)
    }

    private var pinView: some View {
        VStack(spacing: 1) {
            // Temperature — primary, largest
            Text(showCloudCover ? "\(forecast.cloudCoverPercent)%" : tempUnit.display(forecast.daytimeHigh))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppTheme.shared.colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.4), value: dayOffset)
                .offset(x: 2)
                .animation(.smooth(duration: 0.4), value: showCloudCover)

            // City name — secondary, smaller
            Text(cityWeather.city.localizedName(locale: locale))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.shared.colors.primaryText.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .offset(y: -16)
    }
}
#if !os(macOS)
struct GridDropDelegate: DropDelegate {
    let item: CityWeather
    @Binding var dragItem: CityWeather?
    let cities: [CityWeather]
    let moveCity: (IndexSet, Int) -> Void

    func performDrop(info: DropInfo) -> Bool {
        dragItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragItem,
              dragItem.id != item.id,
              let fromIndex = cities.firstIndex(where: { $0.id == dragItem.id }),
              let toIndex = cities.firstIndex(where: { $0.id == item.id }) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
            moveCity(IndexSet(integer: fromIndex), destination)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
#endif

private struct CachedCountryOverviewEntry: Codable {
    let countryName: String
    let data: [CachedCityWeather]
    let date: Date
}
private enum CountryOverviewCacheManager {
    private static let cacheKey = "countryOverviewCache"
    
    static func load() -> [String: (data: [CityWeather], date: Date)] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let entries = try? JSONDecoder().decode([CachedCountryOverviewEntry].self, from: data) else {
            return [:]
        }
        var result: [String: (data: [CityWeather], date: Date)] = [:]
        for entry in entries {
            // Skip entries older than 2 hours
            if Date().timeIntervalSince(entry.date) < 7200 {
                result[entry.countryName] = (data: entry.data.map { $0.toCityWeather() }, date: entry.date)
            }
        }
        return result
    }
    
    static func save(_ cache: [String: (data: [CityWeather], date: Date)]) {
        let entries = cache.compactMap { name, value -> CachedCountryOverviewEntry? in
            // Only persist entries less than 2 hours old
            guard Date().timeIntervalSince(value.date) < 7200 else { return nil }
            return CachedCountryOverviewEntry(
                countryName: name,
                data: value.data.map { CachedCityWeather(from: $0) },
                date: value.date
            )
        }
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
        }
    }
}


