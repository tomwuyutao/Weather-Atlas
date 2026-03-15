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
        // Loading spinner — always upper-left, styled like the "…" button
        if weatherService.isLoading || isLoadingMapList {
            ToolbarItem(placement: .navigationBarLeading) {
                ProgressView()
                    .controlSize(.small)
                    .tint(theme.colors.primaryText)
                    .frame(width: 44, height: 44)
                    .themedGlass(in: .circle)
            }
            .sharedBackgroundVisibility(.hidden)
        }

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
                        showingMapListSwitcher = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(mapToolbarTitle)
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
                    .popover(isPresented: $showingMapListSwitcher) {
                        iOSMapListSwitcherMenu
                            .presentationCompactAdaptation(.popover)
                    }
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
        if !isIPad, selectedTab == 1, !isMapSpecialMode {
            ToolbarItem(placement: .principal) {
                Button {
                    showingMapListSwitcher = true
                } label: {
                    HStack(spacing: 6) {
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
                .fixedSize()
                .popover(isPresented: $showingMapListSwitcher) {
                    iOSMapListSwitcherMenu
                        .presentationCompactAdaptation(.popover)
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
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
                        .frame(width: 44, height: 44)
                        .background(theme.colors.accent, in: .circle)
                }
                .buttonStyle(.plain)
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
            // Search
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddCityView = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .frame(width: 44, height: 44)
                        .themedGlass(in: .circle)
                }
                .buttonStyle(.plain)
            }
            .sharedBackgroundVisibility(.hidden)

            // Discover
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingDiscoverPopover = true
                } label: {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .frame(width: 44, height: 44)
                        .themedGlass(in: .circle)
                }
                .buttonStyle(.plain)
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
            .sharedBackgroundVisibility(.hidden)

            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            // Center on map
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .frame(width: 44, height: 44)
                        .themedGlass(in: .circle)
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
                                .padding(.leading, 16)
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
                Button {
                    showingMenuPopover = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .frame(width: 44, height: 44)
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

                        Rectangle()
                            .fill(theme.colors.primaryText.opacity(0.15))
                            .frame(width: 1, height: 20)
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

                        Rectangle()
                            .fill(theme.colors.primaryText.opacity(0.15))
                            .frame(width: 1, height: 20)
                    }

                    Button {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            showingInlineSearch = true
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)

                    Rectangle()
                        .fill(theme.colors.primaryText.opacity(0.15))
                        .frame(width: 1, height: 20)

                    Button {
                        showingMenuPopover = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingMenuPopover) {
                        iOSCustomMenu
                            .presentationCompactAdaptation(.popover)
                    }
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
        HStack(spacing: 0) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selectedDayOffset > -1 ? .primary : .tertiary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .onTapGesture {
                    if selectedDayOffset > -1 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .onTapGesture {
                    if selectedDayOffset < 9 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.smooth(duration: 0.2)) {
                            selectedDayOffset += 1
                        }
                    }
                }
        }
        .padding(6)
        .themedGlass(in: .capsule)
    }

    // MARK: - Map List Switcher Popover

    var iOSMapListSwitcherMenu: some View {
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
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: mapVisibleListIDs.contains(listID.rawValue) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(mapVisibleListIDs.contains(listID.rawValue) ? theme.colors.dotRain : .secondary)
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

    // MARK: - Main Menu Popover

    var iOSCustomMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isEditingListName {
                if let city = selectedTab == 1 ? (showingMapExpandedCard ? tappedCity : nil) : selectedCity,
                   cityIsInSidebar(city) {
                    menuRow(icon: "trash", title: localizedString("Delete", locale: locale) + " \"" + city.city.localizedName(locale: locale) + "\"") {
                        showingMenuPopover = false
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

//            menuRow(icon: "info.circle", title: localizedString("Info", locale: locale)) {
//                showingMenuPopover = false
//                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
//                    showingInfo = true
//                }
//            }

            if selectedTab == 1 || isIPad {
                menuRow(icon: showLegend ? "eye.fill" : "eye.slash", title: showLegend ? localizedString("Hide Legend", locale: locale) : localizedString("Show Legend", locale: locale)) {
                    showingMenuPopover = false
                    withAnimation(.smooth(duration: 0.3)) {
                        showLegend.toggle()
                    }
                }
            }

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

    // MARK: - Menu Row Helper

    func menuRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .frame(width: 24)
                Text(title)
                    .font(.avenir(.body, weight: .medium))
                Spacer()
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
