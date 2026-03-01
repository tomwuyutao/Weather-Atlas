//
//  ContentView.swift
//  Weather
//
//  Created by Tom on 25/02/2026.
//

import SwiftUI
import MapKit

struct ContentView: View {
    @State private var weatherService = WeatherService()

    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.0, longitude: 10.0),
            span: MKCoordinateSpan(latitudeDelta: 30.0, longitudeDelta: 40.0)
        )
    )

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
    @State private var showCloudCover: Bool = false
    @State private var filterSunny: Bool = false
    @State private var isPlaying: Bool = false

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
                    withAnimation {
                        position = .region(
                            MKCoordinateRegion(
                                center: CLLocationCoordinate2D(
                                    latitude: cityWeather.city.latitude,
                                    longitude: cityWeather.city.longitude
                                ),
                                span: MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 5.0)
                            )
                        )
                    }
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
                lastFetchDate: weatherService.lastFetchDate,
                isRefreshing: weatherService.isLoading
            )
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
                HStack(spacing: 12) {
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
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(width: 80)
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

                    // View switcher capsule
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet")
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
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedTab == 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Text("My Cities")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .fixedSize()
                            .allowsHitTesting(false)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
            .toolbar {
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

                if isPlaying {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            iOSStopPlayback()
                        } label: {
                            Image(systemName: "stop.fill")
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingAddCityView = true
                        } label: {
                            Label("Add City", systemImage: "plus")
                        }

                        if selectedTab == 0 {
                            Button {
                                withAnimation {
                                    isEditMode.toggle()
                                }
                            } label: {
                                Label(isEditMode ? "Done Editing" : "Edit List", systemImage: isEditMode ? "checkmark" : "pencil")
                            }
                        }

                        Divider()

                        Button {
                            withAnimation {
                                filterSunny.toggle()
                            }
                        } label: {
                            Label(filterSunny ? "Clear Filter" : "Filter", systemImage: filterSunny ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        }

                        if selectedTab == 1 {
                            Button {
                                if isPlaying {
                                    iOSStopPlayback()
                                } else {
                                    iOSStartPlayback()
                                }
                            } label: {
                                Label(isPlaying ? "Stop Playback" : "Play Forecast", systemImage: isPlaying ? "stop.fill" : "play.fill")
                            }
                        }

                        Button {
                            Task {
                                await weatherService.refreshWeather()
                            }
                        } label: {
                            let refreshText = timeSinceRefreshText()
                            Label("Refresh\(refreshText.isEmpty ? "" : " (\(refreshText))")", systemImage: "arrow.clockwise")
                        }
                        .disabled(weatherService.isLoading)

                        Divider()

                        Button {
                            // Settings action placeholder
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
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
                            }
                        },
                        isInSidebar: cityIsInSidebar(city),
                        showCloudCover: showCloudCover
                    )
                    .navigationBarBackButtonHidden(true)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showingCityDetail = false
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("Back")
                                }
                            }
                        }
                        if !cityIsInSidebar(city) {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    Task {
                                        await addCityToSidebar(city)
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
            .navigationDestination(isPresented: $showingAddCityView) {
                AddCitySearchView(
                    cities: weatherService.cityWeatherData,
                    citySearchManager: CitySearchManager(),
                    weatherService: weatherService,
                    onCitySelected: { cityWeather in
                        selectedCity = cityWeather
                        tappedCity = cityWeather
                        // Update map position without animation
                        position = .region(
                            MKCoordinateRegion(
                                center: CLLocationCoordinate2D(
                                    latitude: cityWeather.city.latitude,
                                    longitude: cityWeather.city.longitude
                                ),
                                span: MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 5.0)
                            )
                        )
                        // Replace the add city view with the detail view directly
                        showingAddCityView = false
                        showingCityDetail = true
                    }
                )
            }
        }
        .task {
            await weatherService.fetchWeatherForAllCities()
        }
        .onChange(of: selectedDayOffset) { oldValue, _ in
            iOSPreviousDayOffset = oldValue
        }
    }

    private func iOSStartPlayback() {
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
                isPlaying = false
            }
        }
    }

    private func iOSStopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }

    private var iOSListView: some View {
        Group {
            if weatherService.cityWeatherData.isEmpty {
                ContentUnavailableView("No Cities", systemImage: "cloud.sun", description: Text("Tap + to add a city"))
            } else {
                List {
                    ForEach(iOSFilteredCities) { cityWeather in
                        Button {
                            if !isEditMode {
                                tappedCity = cityWeather
                                showingCityDetail = true
                            }
                        } label: {
                            CityRow(
                                cityWeather: cityWeather,
                                dayOffset: selectedDayOffset,
                                showCloudCover: false
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
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
                    .onDelete { indexSet in
                        for index in indexSet {
                            let cityToDelete = iOSFilteredCities[index]
                            weatherService.removeCity(cityToDelete)
                            if selectedCity?.id == cityToDelete.id {
                                selectedCity = nil
                            }
                        }
                    }
                    .onMove { source, destination in
                        weatherService.moveCity(from: source, to: destination)
                    }
                }
                .listStyle(.plain)
                .environment(\.editMode, .constant(isEditMode ? .active : .inactive))
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
            Map(position: $position, selection: $selectedCity) {
                ForEach(weatherService.cityWeatherData) { cityWeather in
                    let forecast = cityWeather.forecast(for: selectedDayOffset)
                    let passesFilter = !filterSunny || (forecast.condition == .clear && forecast.cloudCover < 0.30)

                    Annotation(cityWeather.city.name,
                             coordinate: CLLocationCoordinate2D(
                                latitude: cityWeather.city.latitude,
                                longitude: cityWeather.city.longitude
                             )) {
                        WeatherMarker(
                            cityWeather: cityWeather,
                            dayOffset: selectedDayOffset,
                            isCompact: isZoomedOut,
                            namespace: popupNamespace,
                            showCloudCover: showCloudCover,
                            filterSunny: filterSunny,
                            passesFilter: passesFilter,
                            isPlaying: isPlaying
                        )
                        .opacity(passesFilter ? 1 : 0)
                        .animation(.easeInOut(duration: 0.3), value: passesFilter)
                        .allowsHitTesting(passesFilter)
                        .onTapGesture {
                            tappedCity = cityWeather
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                showingCityDetail = true
                            }
                        }
                    }
                    .tag(cityWeather)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .mapControls {
                MapPitchToggle()
                // MapUserLocationButton removed
                // Scale and Compass are intentionally omitted to hide them
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                // Determine if zoomed out based on the span
                // If span is larger than ~8 degrees, consider it "zoomed out"
                let span = context.region.span
                isZoomedOut = span.latitudeDelta > 50.0 || span.longitudeDelta > 50.0
            }
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
                        }
                    },
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
                            }
                        },
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

struct WeatherMarker: View {
    let cityWeather: CityWeather
    let dayOffset: Int
    let isCompact: Bool
    let namespace: Namespace.ID
    let showCloudCover: Bool
    var filterSunny: Bool = false
    var passesFilter: Bool = true
    var isPlaying: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var forecast: DailyForecast {
        cityWeather.forecast(for: dayOffset)
    }

    private var displayIcon: String {
        if filterSunny {
            if isPlaying {
                // During playback: always sun so no icon transitions
                return "sun.max.fill"
            } else {
                // Not playing: only sun for passing cities, others keep real icon for clean fade out
                return passesFilter ? "sun.max.fill" : forecast.weatherIcon
            }
        }
        return forecast.weatherIcon
    }

    var body: some View {
        if isCompact {
            // Compact mode: just the weather icon, no text
            Image(systemName: displayIcon)
                .id(isPlaying ? "playing" : "filter-\(filterSunny)")
                .font(.title2)
                .symbolRenderingMode(.multicolor)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.2), radius: 2)
                .matchedGeometryEffect(id: "marker-\(cityWeather.id)", in: namespace)
        } else {
            // Full mode: weather icon + temperature or cloud cover
            VStack(spacing: 2) {
                Image(systemName: displayIcon)
                    .id(isPlaying ? "playing" : "filter-\(filterSunny)")
                    .font(.title2)
                    .symbolRenderingMode(.multicolor)
                    .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))

                Text(showCloudCover ? "\(forecast.cloudCoverPercent)%" : "\(Int(forecast.daytimeHigh))°")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .offset(x: 2)
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.4), value: dayOffset)
                    .animation(.smooth(duration: 0.4), value: showCloudCover)
            }
            .frame(width: 32, height: 46)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.2), radius: 3)
            .matchedGeometryEffect(id: "marker-\(cityWeather.id)", in: namespace)
        }
    }
}
