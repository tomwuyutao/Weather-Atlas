//
//  ContentView+iOSToolbar.swift
//  Weather
//
//  iOS toolbar builders: leading, principal, and trailing toolbar items,
//  date switcher content, map list switcher popover, and main menu popover.
//

import SwiftUI
import MapKit

extension ContentView {

    // MARK: - Map Special Mode

    /// Whether the map is in a special full-screen mode (country selection, loading overview, or showing overview results)
    var isMapSpecialMode: Bool {
        countrySelectionMode || isLoadingCountryOverview || countryOverviewActive
        || radialSearchMode || isLoadingRadialSearch || radialSearchActive
    }


    // MARK: - Leading Toolbar

    @ToolbarContentBuilder
    var iOSLeadingToolbarItems: some ToolbarContent {
        if isIPad {
            if sidebarVisibility == .detailOnly {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation {
                            sidebarVisibility = .all
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .frame(width: 44, height: 44)
                            .themedGlass(in: .circle)
                    }
                    .buttonStyle(.plain)
                }
                .sharedBackgroundVisibility(.hidden)

                ToolbarSpacer(.fixed, placement: .navigationBarLeading)
            }

            if !isMapSpecialMode, sidebarVisibility == .detailOnly {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingListSwitcher = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(toolbarTitle)
                                .font(.avenir(.subheadline, weight: .semibold))
                                .foregroundStyle(theme.colors.primaryText)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.colors.primaryText.opacity(0.6))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .themedGlass(in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
    }

    // MARK: - Principal Toolbar

    @ToolbarContentBuilder
    var iOSPrincipalToolbarItem: some ToolbarContent {
        if isIPad, !isMapSpecialMode {
            ToolbarItem(placement: .topBarLeading) {
                iPadDateSwitcherToolbarContent
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .themedGlass(in: .capsule)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        // iPhone list selector capsule is now in the bottom bar
    }

    // MARK: - Trailing Toolbar

    @ToolbarContentBuilder
    var iOSTrailingToolbarItems: some ToolbarContent {
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
            }
            .sharedBackgroundVisibility(.hidden)
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(filterSunny ? theme.colors.filterSunny : theme.colors.primaryText)
                    .frame(width: 44, height: 44)
                    .themedGlass(in: .circle)
            }
            .buttonStyle(.plain)
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                if isPlaying {
                    iOSStopPlayback()
                } else {
                    iOSStartPlayback()
                }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .frame(width: 44, height: 44)
                    .themedGlass(in: .circle)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
        }
        .sharedBackgroundVisibility(.hidden)
    }

    @ToolbarContentBuilder
    private var iOSNormalToolbarItems: some ToolbarContent {
        if isIPad {
            // Search (+ spinner)
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    if weatherService.isLoading || isLoadingMapList {
                        ProgressView()
                            .controlSize(.small)
                            .tint(theme.colors.primaryText)
                            .frame(width: 44, height: 44)
                    }

                    Button {
                        showingAddCityView = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
                .themedGlass(in: .capsule)
            }
            .sharedBackgroundVisibility(.hidden)

            // Discover
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showingMapExpandedCard = false
                            tappedCity = nil
                            previewCity = nil
                            countrySelectionMode = true
                        }
                    } label: {
                        Label(localizedString("Country Overview", locale: locale), systemImage: "globe.desk")
                    }

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showingMapExpandedCard = false
                            tappedCity = nil
                            previewCity = nil
                            radialSearchMode = true
                            radialSearchRadius = 250_000
                        }
                    } label: {
                        Label(localizedString("Radial Search", locale: locale), systemImage: "circle.dotted.circle")
                    }
                } label: {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .frame(width: 44, height: 44)
                        .themedGlass(in: .circle)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            // Center on map
            ToolbarItem(placement: .topBarTrailing) {
                if visibleListIDs.count > 1 {
                    Menu {
                        ForEach(CityListID.allLists.filter { visibleListIDs.contains($0.rawValue) }) { listID in
                            Button {
                                let cities: [CityWeather]
                                if listID == weatherService.activeListID {
                                    cities = weatherService.cityWeatherData
                                } else {
                                    cities = weatherService.otherListData[listID.rawValue] ?? []
                                }
                                focusSubsetCities = cities
                                focusSubsetTrigger = true
                            } label: {
                                Text(listID.localizedDisplayName(locale: locale))
                            }
                        }
                    } label: {
                        Image(systemName: "dot.squareshape.split.2x2")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .frame(width: 44, height: 44)
                            .themedGlass(in: .circle)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                } else {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        recenterOnAllCities = false
                        DispatchQueue.main.async {
                            recenterOnAllCities = true
                        }
                    } label: {
                        Image(systemName: "dot.squareshape.split.2x2")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .frame(width: 44, height: 44)
                            .themedGlass(in: .circle)
                    }
                    .buttonStyle(.plain)
                }
            }
            .sharedBackgroundVisibility(.hidden)

            // Map style
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingMapStyleSheet = true
                } label: {
                    Image(systemName: "map")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .frame(width: 44, height: 44)
                        .themedGlass(in: .circle)
                }
                .buttonStyle(.plain)
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            // Menu
            ToolbarItem(placement: .topBarTrailing) {
                iOSNativeMenu
            }
            .sharedBackgroundVisibility(.hidden)
        }

        if !isIPad {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    if filterSunny {
                        Button {
                            withAnimation { filterSunny = false }
                        } label: {
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(theme.colors.filterSunny)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                    }

                    if showPlaybackButton {
                        Button {
                            if isPlaying { iOSStopPlayback() } else { iOSStartPlayback() }
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(theme.colors.primaryText)
                                .frame(width: 44, height: 44)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)
                    }

                    if weatherService.isLoading || isLoadingMapList {
                        ProgressView()
                            .controlSize(.small)
                            .tint(theme.colors.primaryText)
                            .frame(width: 44, height: 44)
                    }

                    iOSNativeMenu
                }
                .themedGlass(in: .capsule)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    // MARK: - iPad Date Switcher

    var iPadDateSwitcherToolbarContent: some View {
        HStack(spacing: 6) {
            Button {
                if selectedDayOffset > -1 {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.smooth(duration: 0.2)) {
                        selectedDayOffset -= 1
                    }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selectedDayOffset > -1 ? .primary : .tertiary)
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
                .themedPopoverBackground()
            }

            Button {
                if selectedDayOffset < 9 {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

    // MARK: - iPhone Date Switcher Capsule

    var iOSDateSwitcherCapsule: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selectedDayOffset > -1 ? .primary : .tertiary)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .onTapGesture {
                    if selectedDayOffset > -1 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dateSwitcherForward = false
                        withAnimation(.smooth(duration: 0.2)) {
                            selectedDayOffset -= 1
                        }
                    }
                }

            Text(iOSDateText)
                .font(.avenir(.caption, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 80)
                .id("ios-date-\(selectedDayOffset)")
                .transition(.push(from: dateSwitcherForward ? .trailing : .leading))
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
                    .themedPopoverBackground()
                }

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selectedDayOffset < 9 ? .primary : .tertiary)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .onTapGesture {
                    if selectedDayOffset < 9 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dateSwitcherForward = true
                        withAnimation(.smooth(duration: 0.2)) {
                            selectedDayOffset += 1
                        }
                    }
                }
        }
        .padding(6)
        .themedGlass(in: .capsule)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Native Menu

    var iOSNativeMenu: some View {
        Menu {
            Button {
                showingSettings = true
            } label: {
                Label(localizedString("Settings", locale: locale), systemImage: "gearshape")
            }

            Divider()

            if selectedTab == 1 || isIPad {
                Toggle(isOn: Binding(
                    get: { showLegend },
                    set: { newValue in withAnimation(.smooth(duration: 0.3)) { showLegend = newValue } }
                )) {
                    Label(localizedString("Legend", locale: locale), systemImage: "eye")
                }
            }

            Button {
                Task { await weatherService.refreshWeather() }
            } label: {
                Label(localizedString("Refresh", locale: locale) + (timeSinceRefreshText().isEmpty ? "" : " (\(timeSinceRefreshText()))"), systemImage: "arrow.clockwise")
            }
            .disabled(weatherService.isLoading)

            if selectedTab == 1 || isIPad {
                Toggle(isOn: Binding(
                    get: { isPlaying },
                    set: { newValue in
                        if newValue { iOSStartPlayback() } else { iOSStopPlayback() }
                    }
                )) {
                    Label(localizedString("Playback", locale: locale), systemImage: "play.fill")
                }
            }

            Toggle(isOn: Binding(
                get: { filterSunny },
                set: { newValue in withAnimation { filterSunny = newValue } }
            )) {
                Label(localizedString("Filter Sunny", locale: locale), systemImage: "sun.max")
            }

            Divider()

            if isIPad {
                Toggle(isOn: Binding(
                    get: { showDateSlider },
                    set: { newValue in withAnimation { showDateSlider = newValue } }
                )) {
                    Label(localizedString("Date Slider", locale: locale), systemImage: "slider.horizontal.below.sun.max")
                }
            }

            if selectedTab == 0, !isIPad {
                Toggle(isOn: Binding(
                    get: { isGridView },
                    set: { newValue in
                        withAnimation(.easeOut(duration: 0.15)) {
                            listContentOpacity = 0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            isGridView = newValue
                            withAnimation(.easeIn(duration: 0.2)) {
                                listContentOpacity = 1
                            }
                        }
                    }
                )) {
                    Label(localizedString("Grid View", locale: locale), systemImage: "square.grid.2x2")
                }

                Toggle(isOn: Binding(
                    get: { isEditMode },
                    set: { newValue in withAnimation { isEditMode = newValue } }
                )) {
                    Label(localizedString("Edit Mode", locale: locale), systemImage: "pencil")
                }
            }

            if !isEditingListName {
                if let city = selectedTab == 1 ? (showingMapExpandedCard ? tappedCity : nil) : selectedCity,
                   cityIsInSidebar(city) {
                    Button(role: .destructive) {
                        weatherService.removeCity(city)
                        if selectedTab == 1 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showingMapExpandedCard = false
                                tappedCity = nil
                                recenterOnAllCities = true
                            }
                        } else {
                            if selectedCity?.id == city.id {
                                selectedCity = nil
                            }
                        }
                    } label: {
                        Label(localizedString("Delete", locale: locale) + " \"" + city.city.localizedName(locale: locale) + "\"", systemImage: "trash")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 36, height: 36)
                .padding(6)
                .themedGlass(in: .circle)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuOrder(.fixed)
    }
}
