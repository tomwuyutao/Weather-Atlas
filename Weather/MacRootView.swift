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
        .task { await iOSOnAppear() }
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

    var macCommandReceivers: some View {
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
                    .gesture(WindowDragGesture())
                    .allowsWindowActivationEvents(true)
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
            if showingInlineSearch {
                nativeCitySearchScreen
            } else {
                AnyView(
                    iOSMapView
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 8) {
                                if weatherService.isLoading {
                                    LoadingWeatherOverlay(
                                        progress: weatherService.loadingProgress,
                                        locale: locale
                                    )
                                    .allowsHitTesting(false)
                                    .transition(.move(edge: .leading).combined(with: .opacity))
                                }

                                if showLegend {
                                    MapFloatingLegend(overlayMode: mapOverlayMode, compact: true) {
                                        withAnimation(.smooth(duration: 0.2)) {
                                            showLegend = false
                                        }
                                    }
                                    .transition(.move(edge: .leading).combined(with: .opacity))
                                }
                            }
                            .padding(.leading, 24)
                            .padding(.bottom, 24)
                        }
                        .animation(.smooth(duration: 0.22), value: showLegend)
                        .animation(.smooth(duration: 0.22), value: weatherService.isLoading)
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

    var macWindowDragTopArea: some View {
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
        createListAtBottom()
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
