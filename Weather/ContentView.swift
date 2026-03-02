//
//  ContentView.swift
//  Weather
//
//  Created by Tom on 25/02/2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var weatherService = WeatherService()

    @State private var countries: [CountryPath] = []
    @State private var centerOnCityTrigger: CityWeather?

    @State private var selectedCity: CityWeather?
    @State private var selectedDayOffset: Int = 0
    @State private var isEditMode: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isZoomedOut: Bool = true
    @State private var showingCityDetail: Bool = false
    @State private var tappedCity: CityWeather?
    @Namespace private var popupNamespace
    @State private var searchText: String = ""
    @State private var citySearchManager = CitySearchManager()
    @State private var selectedTab: Int = 0
    @State private var showingSearchSheet: Bool = true
    @State private var selectedDetent: PresentationDetent = .height(80)
    @State private var lastRefreshText: String = ""
    @State private var showingAddCityView: Bool = false
    @State private var showingAddCityDetail: Bool = false
    @State private var addCityDetailCity: CityWeather?
    @State private var showCloudCover: Bool = false
    @State private var filterSunny: Bool = false
    @State private var isPlaying: Bool = false
    
    @State private var mapScale: CGFloat = 10.0
    @State private var mapOffset: CGSize = .zero
    @State private var mapLastScale: CGFloat = 10.0
    @State private var mapLastOffset: CGSize = .zero
    @State private var mapHasInitialized: Bool = false
    @State private var recenterOnAllCities: Bool = false
    @State private var detailOpenedFromList: Bool = false

    private func timeSinceRefreshText() -> String {
        guard let lastFetch = weatherService.lastFetchDate else {
            return ""
        }
        let elapsed = Date().timeIntervalSince(lastFetch)
        let minutes = Int(elapsed / 60)
        if minutes < 1 {
            return "Now"
        } else if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            return "\(hours)h"
        }
    }

    var body: some View {
        #if os(macOS)
        desktopView
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            desktopView
        } else {
            iOSView
        }
        #endif
    }

    // MARK: - Desktop View (macOS & iPadOS)

    private var desktopView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar - uses the same content as the iOS large sheet
            DesktopSidebar(
                cities: weatherService.cityWeatherData,
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
    @State private var iOSPreviousDayOffset: Int = 0
    @State private var showingDatePopover: Bool = false
    @State private var playbackTask: Task<Void, Never>?
    @State private var showPlaybackButton: Bool = false
    @State private var playbackButtonHideTask: Task<Void, Never>?
    @State private var showingMenuPopover: Bool = false
    @AppStorage("isGridView") private var isGridView: Bool = false
    @State private var gridDragItem: CityWeather?
    @State private var showingListSwitcher: Bool = false
    @State private var listContentOpacity: Double = 1.0
    @State private var longPressedCity: CityWeather?

    private var iOSDateText: String {
        if selectedDayOffset == 0 { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, EEE"
        return formatter.string(from: Calendar.current.date(byAdding: .day, value: selectedDayOffset, to: Date()) ?? Date())
    }

    private var iOSView: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    if selectedTab == 0 {
                        iOSListView
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    } else {
                        iOSMapView
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedTab)

                // Floating bottom toolbar
                HStack(alignment: .bottom, spacing: 12) {
                    // Date switcher capsule
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
                                .presentationBackground(.thickMaterial)
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
                    .glassEffect(.regular.interactive(), in: .capsule)

                    Spacer()

                    // View switcher capsule with optional re-center button above map icon
                    VStack(alignment: .trailing, spacing: 10) {
                        if selectedTab == 1 {
                            Image(systemName: "location.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 42, height: 36)
                                .glassEffect(.regular.interactive(), in: .capsule)
                                .offset(x: -6)
                                .onTapGesture {
                                    recenterOnAllCities = true
                                }
                                .transition(.scale.combined(with: .opacity))
                        }

                        HStack(spacing: 8) {
                            Image(systemName: isGridView ? "square.grid.2x2" : "list.bullet")
                                .contentTransition(.symbolEffect(.replace))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(selectedTab == 0 ? .primary : .secondary)
                                .frame(width: 42, height: 36)
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
                                .foregroundStyle(selectedTab == 1 ? .primary : .secondary)
                                .frame(width: 42, height: 36)
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
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .padding(.top, 20)
                .contentShape(Rectangle())
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { }
            .toolbar {
                if isEditMode {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation { isEditMode = false }
                        } label: {
                            Image(systemName: "checkmark")
                        }
                    }
                } else {
                    if weatherService.isLoading {
                        ToolbarItem(placement: .topBarTrailing) {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if filterSunny {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                withAnimation {
                                    filterSunny = false
                                }
                            } label: {
                                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                    .foregroundStyle(.blue)
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

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingMenuPopover = true
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .popover(isPresented: $showingMenuPopover) {
                            iOSCustomMenu
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $showingCityDetail) {
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
                            if selectedTab == 1 {
                                recenterOnAllCities = true
                            }
                        } : nil,
                        isInSidebar: cityIsInSidebar(city),
                        showCloudCover: showCloudCover
                    )
                    .navigationBarBackButtonHidden(true)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showingCityDetail = false
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                        }
                        ToolbarItem(placement: .principal) {
                            Text(city.city.name)
                                .font(.avenir(.title3, weight: .semibold))
                        }
                        if !cityIsInSidebar(city) {
                            ToolbarItem(placement: .topBarTrailing) {
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
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        if cityIsInSidebar(city) {
                            ToolbarItem(placement: .topBarTrailing) {
                                Menu {
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
                                        Label("Reveal on Map", systemImage: "map")
                                    }
                                    
                                    Button(role: .destructive) {
                                        weatherService.removeCity(city)
                                        showingCityDetail = false
                                        if selectedTab == 1 {
                                            recenterOnAllCities = true
                                        }
                                    } label: {
                                        Label("Delete City", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                            }
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $showingAddCityView) {
                AddCitySearchView(
                    cities: weatherService.cityWeatherData,
                    citySearchManager: CitySearchManager(),
                    weatherService: weatherService,
                    onCitySelected: { cityWeather in
                        addCityDetailCity = cityWeather
                        showingAddCityDetail = true
                    }
                )
                .navigationDestination(isPresented: $showingAddCityDetail) {
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
                                Text(city.city.name)
                                    .font(.avenir(.title3, weight: .semibold))
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
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
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
        .onChange(of: selectedDayOffset) { oldValue, _ in
            iOSPreviousDayOffset = oldValue
        }
    }

    private var iOSListSwitcher: some View {
        Button {
            showingListSwitcher = true
        } label: {
            Text(weatherService.activeListID.displayName)
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
    
    private var iOSListSwitcherMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(CityListID.allCases) { listID in
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
                        Text(listID.displayName)
                            .font(.avenir(.body, weight: listID == weatherService.activeListID ? .bold : .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        if listID == weatherService.activeListID {
                            Circle()
                                .fill(.white)
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
        .frame(width: 170)
        .presentationBackground(.ultraThinMaterial)
    }
    
    private var iOSCustomMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow(icon: "plus", title: "Add City") {
                showingMenuPopover = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation {
                        showingAddCityView = true
                    }
                }
            }

            if selectedTab == 0 {
                menuRow(icon: isEditMode ? "checkmark" : "pencil", title: isEditMode ? "Done Editing" : (isGridView ? "Edit Grid" : "Edit List")) {
                    showingMenuPopover = false
                    withAnimation { isEditMode.toggle() }
                }

                menuRow(icon: isGridView ? "list.bullet" : "square.grid.2x2", title: isGridView ? "List View" : "Grid View") {
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

            Divider().padding(.horizontal, 12).padding(.vertical, 4)

            menuRow(icon: filterSunny ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle", title: filterSunny ? "Clear Filter" : "Filter") {
                showingMenuPopover = false
                withAnimation { filterSunny.toggle() }
            }

            if selectedTab == 1 {
                menuRow(icon: isPlaying ? "stop.fill" : "play.fill", title: isPlaying ? "Stop Playback" : "Play Forecast") {
                    showingMenuPopover = false
                    if isPlaying { iOSStopPlayback() } else { iOSStartPlayback() }
                }
            }

            menuRow(icon: "arrow.clockwise", title: "Refresh\(timeSinceRefreshText().isEmpty ? "" : " (\(timeSinceRefreshText()))")") {
                showingMenuPopover = false
                Task { await weatherService.refreshWeather() }
            }
            .opacity(weatherService.isLoading ? 0.4 : 1.0)
            .disabled(weatherService.isLoading)

            Divider().padding(.horizontal, 12).padding(.vertical, 4)

            menuRow(icon: "gearshape", title: "Settings") {
                showingMenuPopover = false
            }
        }
        .padding(.vertical, 8)
        .frame(width: 220)
        .presentationBackground(.ultraThinMaterial)
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
                .symbolRenderingMode(.multicolor)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                .frame(height: 30)

            Text("\(Int(forecast.daytimeHigh))°")
                .font(.avenir(.title2, weight: .medium))
                .contentTransition(.numericText())

            Text(cityWeather.city.name)
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
                        .foregroundStyle(.white, .red)
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
                    Label("Delete", systemImage: "trash")
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
                VStack(spacing: 20) {
                    Spacer().frame(maxHeight: .infinity)
                    Image(systemName: "cloud.sun.fill")
                        .font(.system(size: 56))
                        .symbolRenderingMode(.multicolor)
                    Text("Loading Weather")
                        .font(.avenir(.title2, weight: .semibold))
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 140, height: 4)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(.white)
                                .frame(width: 140 * weatherService.loadingProgress, height: 4)
                        }
                    Spacer().frame(maxHeight: .infinity)
                    Spacer().frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
            } else if weatherService.cityWeatherData.isEmpty && weatherService.hasSavedCities {
                ContentUnavailableView("Loading Weather", systemImage: "cloud.sun", description: Text("Fetching forecasts for your cities…"))
            } else if weatherService.cityWeatherData.isEmpty {
                ContentUnavailableView("No Cities", systemImage: "cloud.sun", description: Text("Tap + to add a city"))
            } else if isGridView {
                ScrollView {
                    iOSListSwitcher
                        .padding(.top, 16)
                        .padding(.bottom, 20)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(iOSFilteredCities) { cityWeather in
                            gridCell(for: cityWeather)
                        }
                    }
                    .padding(.horizontal, 16)
                    .opacity(listContentOpacity)
                }
                .gesture(swipeDayGesture())
                .transition(.opacity)
            } else {
                List {
                    iOSListSwitcher
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 20, trailing: 16))
                        .padding(.top, 8)

                    ForEach(iOSFilteredCities) { cityWeather in
                        HStack {
                            Text(cityWeather.city.name)
                                .font(.avenir(.body, weight: .medium))
                            Spacer()
                            Text("\(Int(cityWeather.forecast(for: selectedDayOffset).daytimeHigh))°")
                                .font(.avenir(.title2, weight: .medium))
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                            Image(systemName: cityWeather.forecast(for: selectedDayOffset).weatherIcon)
                                .font(.title3)
                                .symbolRenderingMode(.multicolor)
                                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                                .frame(width: 32)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(longPressedCity?.id == cityWeather.id ? Color.white.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
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
                                menuRow(icon: "map", title: "Reveal on Map") {
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
                                
                                menuRow(icon: "trash", title: "Delete City") {
                                    longPressedCity = nil
                                    weatherService.removeCity(cityWeather)
                                    if selectedCity?.id == cityWeather.id {
                                        selectedCity = nil
                                    }
                                }
                                .foregroundStyle(.red)
                            }
                            .padding(.vertical, 8)
                            .frame(width: 220)
                            .presentationCompactAdaptation(.popover)
                            .presentationBackground(.ultraThinMaterial)
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
                    .opacity(listContentOpacity)
                }
                .listStyle(.plain)
                .environment(\.editMode, Binding(
                    get: { isEditMode ? .active : .inactive },
                    set: { newValue in isEditMode = (newValue == .active) }
                ))
                .gesture(swipeDayGesture())
                .transition(.opacity)
            }
        }
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
                return forecast.condition == .clear && forecast.cloudCover < 0.30
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
            if weatherService.cityWeatherData.isEmpty && weatherService.isLoading {
                // First launch: show loading overlay on map
                Color.black
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 16) {
                            Image(systemName: "globe.europe.africa.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("Loading Map Data…")
                                .font(.avenir(.headline, weight: .medium))
                                .foregroundStyle(.secondary)
                            ProgressView()
                                .controlSize(.regular)
                        }
                    }
            }

            SVGMapView(
                countries: countries,
                cities: weatherService.cityWeatherData,
                selectedDayOffset: selectedDayOffset,
                showCloudCover: showCloudCover,
                filterSunny: filterSunny,
                isPlaying: isPlaying,
                namespace: popupNamespace,
                isZoomedOut: $isZoomedOut,
                showingCityDetail: $showingCityDetail,
                tappedCity: $tappedCity,
                mapScale: $mapScale,
                mapOffset: $mapOffset,
                mapLastScale: $mapLastScale,
                mapLastOffset: $mapLastOffset,
                mapHasInitialized: $mapHasInitialized,
                centerOnCity: centerOnCityTrigger,
                recenterOnAllCities: $recenterOnAllCities
            )
            .ignoresSafeArea()

            // City detail popup (desktop/iPad only — iPhone uses navigation)
            #if os(macOS)
            if showingCityDetail, let city = tappedCity {
                Color.black.opacity(0.3)
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
            #else
            if UIDevice.current.userInterfaceIdiom == .pad {
                if showingCityDetail, let city = tappedCity {
                    Color.black.opacity(0.3)
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
            }
            #endif
        }
    }

    private func cityIsInSidebar(_ cityWeather: CityWeather) -> Bool {
        weatherService.cityWeatherData.contains(where: { $0.city.name == cityWeather.city.name })
    }

    private func addCityToSidebar(_ cityWeather: CityWeather) async {
        await weatherService.addCity(cityWeather.city)
        // Update the tapped city to the newly added one from the sidebar
        if let newCity = weatherService.cityWeatherData.first(where: { $0.city.name == cityWeather.city.name }) {
            tappedCity = newCity
        }
    }
}

#Preview {
    ContentView()
}

#Preview("Loading") {
    VStack(spacing: 20) {
        Spacer()
        Image(systemName: "cloud.sun.fill")
            .font(.system(size: 56))
            .symbolRenderingMode(.multicolor)
        Text("Loading Weather")
            .font(.avenir(.title2, weight: .semibold))
        Capsule()
            .fill(Color.white.opacity(0.15))
            .frame(width: 140, height: 4)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.white)
                    .frame(width: 140 * 0.4, height: 4)
            }
        Spacer()
    }
    .frame(maxWidth: .infinity)
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
    var showAsDot: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var forecast: DailyForecast {
        cityWeather.forecast(for: dayOffset)
    }

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
        ZStack(alignment: .center) {
            // Dot layer
            Circle()
                .fill(displayCondition.dotColor)
                .frame(width: 10, height: 10)
                .shadow(color: displayCondition.dotColor.opacity(0.5), radius: 4)
                .scaleEffect(showAsDot ? 1 : 0.01)
                .opacity(showAsDot ? 1 : 0)

            // Icon layer
            Group {
                if isCompact {
                    Image(systemName: displayIcon)
                        .id(isPlaying ? "playing" : "filter-\(filterSunny)")
                        .font(.title)
                        .symbolRenderingMode(.multicolor)
                        .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                        .frame(width: 40, height: 40)
                        .background(alignment: .top) {
                            WeatherEffectOverlay(condition: displayCondition, isCompact: true, iconHeight: 40)
                        }
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: displayIcon)
                            .id(isPlaying ? "playing" : "filter-\(filterSunny)")
                            .font(.title)
                            .symbolRenderingMode(.multicolor)
                            .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                            .background(alignment: .top) {
                                WeatherEffectOverlay(condition: displayCondition, isCompact: false, iconHeight: 36)
                            }

                        Text(showCloudCover ? "\(forecast.cloudCoverPercent)%" : "\(Int(forecast.daytimeHigh))°")
                            .font(.avenir(.caption, weight: .medium))
                            .foregroundStyle(.primary)
                            .offset(x: 2)
                            .contentTransition(.numericText())
                            .animation(.smooth(duration: 0.4), value: dayOffset)
                            .animation(.smooth(duration: 0.4), value: showCloudCover)
                    }
                    .frame(width: 40, height: 56)
                }
            }
            .scaleEffect(showAsDot ? 0.01 : 1, anchor: .center)
            .opacity(showAsDot ? 0 : 1)
        }
        .frame(width: 40, height: 56)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.3), value: showAsDot)
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

