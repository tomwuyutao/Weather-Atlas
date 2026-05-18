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

    var iOSNativeDetailNavigationStack: some View {
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
                    AnyView(self.selectedCityDetailDestination)
                }
                .navigationDestination(isPresented: $showingAddCityDetail) {
                    AnyView(iOSAddCityDetailDestination)
                }
            }
        )
    }

    var iPadRootView: some View {
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
                        AnyView(self.selectedCityDetailDestination)
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
                sidebarExpandedListIDs = Set(sidebarLists.map(\.rawValue))
            }
        }
    }

    var iPadSidebarContent: some View {
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

    var iPadMapContent: some View {
        ZStack {
            iOSMapView
                .overlay(alignment: .topLeading) {
                    if showLegend && !showingInlineSearch {
                        MapFloatingLegend(overlayMode: mapOverlayMode, compact: true) {
                            withAnimation(.smooth(duration: 0.2)) {
                                showLegend = false
                            }
                        }
                        .padding(.leading, 24)
                        .padding(.top, 68)
                        .transition(.scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .trailing) {
                    AnyView(iOSDateSliderOverlay)
                }
                .allowsHitTesting(!showingInlineSearch)

            if !showingInlineSearch {
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
                        .foregroundStyle(.primary)
                        .foregroundColor(.primary)
                }
                .tint(.primary)
                .help(localizedString("Center on Map", locale: locale))

                mapOverlayMenu

                Button {
                    withAnimation(.smooth(duration: 0.2)) {
                        showLegend.toggle()
                    }
                } label: {
                    Image(systemName: showLegend ? "eye.slash" : "eye")
                        .foregroundStyle(.primary)
                        .foregroundColor(.primary)
                }
                .tint(.primary)
                .help(localizedString("Legend", locale: locale))

                Button {
                    Task { await weatherService.refreshWeather() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.primary)
                        .foregroundColor(.primary)
                }
                .tint(.primary)
                .disabled(weatherService.isLoading)
                .help(localizedString("Refresh", locale: locale))

                Button {
                    withAnimation {
                        filterSunny.toggle()
                    }
                } label: {
                    Image(systemName: filterSunny ? "sun.max.fill" : "sun.max")
                        .foregroundStyle(.primary)
                        .foregroundColor(.primary)
                }
                .tint(.primary)
                .help(localizedString("Filter Sunny", locale: locale))

                iOSNativeMenu
            }
        }
        .tint(.primary)
        .if(showingInlineSearch) { view in
            view
        }
    }

    var iPadFloatingMapOverlays: some View {
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

            }
            .onAppear {
                macMapViewportSize = geometry.size
            }
            .onChange(of: geometry.size) { _, newSize in
                macMapViewportSize = newSize
            }
        }
    }

    func iPadExpandedCardTopLeft(in size: CGSize) -> CGSize {
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

    func iPadExpandedCardOffset(in size: CGSize) -> CGSize {
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

    func iPadExpandedCardRevealAnchor(in size: CGSize) -> UnitPoint {
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
}
#endif
