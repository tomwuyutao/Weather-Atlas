//
//  IPadRootView.swift
//  Weather
//
//  iPad split -view shell.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

#if os(iOS)
extension ContentView {
    var iOSNavigationSplitRoot: some View {
        NavigationSplitView(columnVisibility: $iPadSidebarVisibility, preferredCompactColumn: $iPadPreferredCompactColumn) {
            NavigationStack {
                iPadSidebarContent
            }
            .weatherTutorialTarget(.listManager)
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

    @ViewBuilder
    var iOSNativeDetailNavigationStack: some View {
        if shouldUseIPadLayout {
            iPadMapNavigationStack
        } else {
            nativeCitySearch(
                NavigationStack {
                    iPhoneMapTabContent
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
    }

    var iPadRootView: some View {
        NavigationSplitView(columnVisibility: $iPadSidebarVisibility, preferredCompactColumn: $iPadPreferredCompactColumn) {
            NavigationStack {
                iPadSidebarContent
            }
            .weatherTutorialTarget(.listManager)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            iPadMapNavigationStack
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            selectedTab = 1
            if sidebarExpandedListIDs.isEmpty {
                sidebarExpandedListIDs = Set(sidebarLists.map(\.rawValue))
            }
        }
    }

    var iPadMapNavigationStack: some View {
        NavigationStack {
            iPadMapContent
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: $showingAddCityDetail) {
                    AnyView(iOSAddCityDetailDestination)
                }
        }
        .onChange(of: inlineSearchText) { _, newValue in
            inlineSearchManager.search(query: newValue)
            inlineSearchSelectionIndex = 0
        }
        .onChange(of: inlineSearchFieldPresented) { _, isPresented in
            if !isPresented {
                showingInlineSearch = false
                resetNativeCitySearch()
            }
        }
        .onChange(of: showingCityDetail) { _, isShowing in
            guard isShowing else {
                iPadInspectorPresentedCityID = nil
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
        .onSubmit(of: .search) {
            confirmInlineSearchSelection()
        }
        .toolbar {
            iPadMapToolbarContent
        }
        .background {
            iPadCommandReceivers
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
        .fullScreenCover(isPresented: $showingCountryListBuilder) {
            CountryListBuilderView(initialCountry: countryListInitialCountry) { country, cityCount in
                commitCountryList(country, cityCount: cityCount)
            }
        }
    }

    var iPadCommandReceivers: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .weatherPreviousDayCommand)) { _ in
                guard shouldUseIPadLayout else { return }
                if showingInlineSearch, !inlineSearchText.isEmpty {
                    moveInlineSearchSelection(-1)
                    return
                }
                iPadStepSelectedDay(-1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .weatherNextDayCommand)) { _ in
                guard shouldUseIPadLayout else { return }
                if showingInlineSearch, !inlineSearchText.isEmpty {
                    moveInlineSearchSelection(1)
                    return
                }
                iPadStepSelectedDay(1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .weatherPreviousListCommand)) { _ in
                guard shouldUseIPadLayout else { return }
                iPadSwitchListByOffset(-1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .weatherNextListCommand)) { _ in
                guard shouldUseIPadLayout else { return }
                iPadSwitchListByOffset(1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .weatherCenterMapCommand)) { _ in
                guard shouldUseIPadLayout else { return }
                centerMapOnDots()
            }
            .onReceive(NotificationCenter.default.publisher(for: .weatherRefreshCommand)) { _ in
                guard shouldUseIPadLayout else { return }
                refreshActiveWeather()
            }
            .onReceive(NotificationCenter.default.publisher(for: .weatherSearchCommand)) { _ in
                guard shouldUseIPadLayout else { return }
                activateInlineSearch()
            }
            .onReceive(NotificationCenter.default.publisher(for: .weatherToggleSunnyFilterCommand)) { _ in
                guard shouldUseIPadLayout else { return }
                withAnimation {
                    filterSunny.toggle()
                    UserDefaults.standard.set(filterSunny, forKey: "menuFilterSunnyState")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .weatherToggleLegendCommand)) { _ in
                guard shouldUseIPadLayout else { return }
                withAnimation(.smooth(duration: 0.2)) {
                    showLegend.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .weatherOverlayCommand)) { notification in
                guard shouldUseIPadLayout, let mode = notification.object as? String else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    mapOverlayMode = mode
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .weatherSwitchListCommand)) { notification in
                guard shouldUseIPadLayout,
                      let rawValue = notification.object as? String,
                      let listID = sidebarLists.first(where: { $0.rawValue == rawValue }) else { return }
                Task { await switchToList(listID) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .weatherNewListCommand)) { _ in
                guard shouldUseIPadLayout else { return }
                beginCreatingListFromSwitcher()
            }
    }

    func iPadStepSelectedDay(_ delta: Int) {
        guard !showingInlineSearch else { return }
        selectedDayOffset = max(-1, min(9, selectedDayOffset + delta))
    }

    func iPadSwitchListByOffset(_ delta: Int) {
        let lists = sidebarLists
        guard let currentIndex = lists.firstIndex(of: weatherService.activeListID), !lists.isEmpty else { return }
        let nextIndex = (currentIndex + delta + lists.count) % lists.count
        Task { await switchToList(lists[nextIndex]) }
    }

    @ToolbarContentBuilder
    var iPadMapToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            mapTopListMenu
                .foregroundStyle(theme.colors.primaryText)
                .tint(theme.colors.primaryText)
                .weatherTutorialTarget(.listSwitcher)
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                centerMapOnDots()
            } label: {
                Image(systemName: "dot.squareshape.split.2x2")
                    .foregroundStyle(.primary)
                    .foregroundColor(.primary)
            }
            .tint(.primary)
            .help(localizedString("Center on Map", locale: locale))

            mapOverlayMenu

            sunnyFilterToolbarIndicator

            iPadToolbarMoreMenu
        }

        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            iPadToolbarSearchBar
        }
    }

    var iPadToolbarMoreMenu: some View {
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

            Divider()

            Button {
                showingSettings = true
            } label: {
                Label {
                    Text(localizedString("Settings", locale: locale))
                } icon: {
                    Image(systemName: "gearshape")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.primary)
                .foregroundColor(.primary)
        }
        .menuOrder(.fixed)
    }

    var iPadToolbarSearchBar: some View {
        IPadNativeSearchBar(
            text: $inlineSearchText,
            isPresented: $inlineSearchFieldPresented,
            placeholder: localizedString("Search for a city", locale: locale),
            onSubmit: confirmInlineSearchSelection
        )
        .frame(width: 230, height: 36)
        .weatherTutorialTarget(.search)
    }

    var iPadInspectorSearchPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            IPadNativeSearchBar(
                text: $inlineSearchText,
                isPresented: $inlineSearchFieldPresented,
                placeholder: localizedString("Search for a city", locale: locale),
                onSubmit: confirmInlineSearchSelection
            )
            .frame(width: 300, height: 36)

            if !inlineSearchText.isEmpty && !inlineSortedSearchResults.isEmpty {
                iPadSearchSuggestionsList
            }
        }
        .padding(12)
        .frame(width: 340)
        .presentationCompactAdaptation(.popover)
    }

    var iPadSearchSuggestionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            nativeCitySearchSuggestions
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .frame(width: 348)
        .presentationCompactAdaptation(.popover)
    }

    var iPadSidebarContent: some View {
        macListManagerSidebar
            .navigationTitle(localizedString("Lists", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        iOSAddListMenuItems
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.primary)
                            .foregroundColor(.primary)
                    }
                    .menuOrder(.fixed)
                    .tint(.primary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sidebarEditMode = sidebarEditMode.isEditing ? .inactive : .active
                        }
                    } label: {
                        Image(systemName: sidebarEditMode.isEditing ? "checkmark" : "pencil")
                            .foregroundStyle(.primary)
                            .foregroundColor(.primary)
                    }
                    .tint(.primary)
                }
            }
            .toolbarBackground(.automatic, for: .navigationBar)
            .tint(.primary)
    }

    var iPadMapContent: some View {
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
                iPadFloatingMapOverlays
            }

            if countryListSearchMode {
                GeometryReader { geometry in
                    countryListPreviewControls()
                        .frame(width: iPadFloatingCardSize.width)
                        .position(iPadFloatingCardCenter(in: geometry.size))
                        .transition(.opacity)
                        .zIndex(12)
                }
            }

            if !inlineSearchText.isEmpty && !inlineSortedSearchResults.isEmpty {
                iPadSearchSuggestionsList
                    .background(iPadInspectorBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.42), lineWidth: 0.8)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.26 : 0.14), radius: 20, y: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 92)
                    .padding(.trailing, 12)
                    .transition(.scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity))
                    .zIndex(30)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .tint(.primary)
        .if(showingInlineSearch) { view in
            view
        }
    }

    var iPadFloatingMapOverlays: some View {
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
                        .frame(width: iPadFloatingCardSize.width, height: iPadFloatingCardSize.height)
                        .matchedGeometryEffect(id: iPadMapDetailMorphID(for: city), in: iPadMapDetailNamespace, properties: .frame, anchor: .center)
                        .position(iPadFloatingCardCenter(in: geometry.size))
                        .transition(.opacity)
                        .zIndex(12)
                }

                if showingCityDetail, let city = tappedCity {
                    let panelWidth = iPadInspectorWidth
                    let panelHeight = min(max(500, geometry.size.height - 88), max(420, geometry.size.height - 56))

                    iPadFloatingDetailWindow(for: city)
                        .frame(width: panelWidth, height: panelHeight)
                        .matchedGeometryEffect(id: iPadMapDetailMorphID(for: city), in: iPadMapDetailNamespace, properties: .frame, anchor: .center)
                        .offset(x: geometry.size.width - panelWidth - iPadFloatingCardTrailingGap, y: geometry.size.height - panelHeight - iPadFloatingCardBottomGap)
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

    var iPadInspectorBackground: Color {
        colorScheme == .dark ? Color(hex: 0x262052) : theme.colors.background
    }

    func iPadDetailScrollView(for city: CityWeather) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            Color.clear
                .frame(height: 1)
                .id("iPadDetailTop")

            mapExpandedCard(
                for: city,
                forceMacStyle: true,
                forceIPhoneDetailSizing: true,
                plainBackground: true
            )
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .scrollContentBackground(.hidden)
    }

    func iPadFloatingDetailWindow(for city: CityWeather) -> some View {
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
                        .foregroundColor(iPadInspectorPinned ? theme.colors.accent : theme.colors.primaryText)
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
                        iPadInspectorPresentedCityID = nil
                        iPadInspectorPinned = false
                        macMapExpandedCardFocusesMarker = false
                        macExpandedCardShowsDetails = false
                        selectedDayOffset = -1
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .foregroundColor(.primary)
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

            Divider()
                .opacity(0.45)

            ScrollViewReader { proxy in
                if #available(iOS 18.0, *) {
                    iPadDetailScrollView(for: city)
                        .onScrollGeometryChange(for: Bool.self) { geometry in
                            geometry.contentOffset.y > 12
                        } action: { _, shouldShowTitle in
                            if iPadDetailHeaderShowsCityName != shouldShowTitle {
                                iPadDetailHeaderShowsCityName = shouldShowTitle
                            }
                        }
                        .onChange(of: city.id) { _, _ in
                            iPadDetailHeaderShowsCityName = false
                            proxy.scrollTo("iPadDetailTop", anchor: .top)
                        }
                } else {
                    iPadDetailScrollView(for: city)
                        .onChange(of: city.id) { _, _ in
                            iPadDetailHeaderShowsCityName = false
                            proxy.scrollTo("iPadDetailTop", anchor: .top)
                        }
                }
            }
        }
        .background(iPadInspectorBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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

    var iPadInspectorWidth: CGFloat { 380 }
    var iPadFloatingCardTrailingGap: CGFloat { 24 }
    var iPadFloatingCardBottomGap: CGFloat { -4 }

    var iPadFloatingCardSize: CGSize {
        CGSize(width: 312, height: 144)
    }

    var iPadInspectorMorphAnimation: Animation {
        .spring(response: 0.5, dampingFraction: 0.92, blendDuration: 0.08)
    }

    func iPadFloatingCardCenter(in mapSize: CGSize) -> CGPoint {
        CGPoint(
            x: mapSize.width / 2,
            y: mapSize.height - iPadFloatingCardBottomGap - iPadFloatingCardSize.height / 2
        )
    }

    func iPadMapDetailMorphID(for city: CityWeather) -> String {
        "ipad-map-detail-\(city.id.uuidString)"
    }
}
#endif

#if os(iOS)
struct IPadNativeSearchBar: UIViewRepresentable {
    @Binding var text: String
    @Binding var isPresented: Bool
    let placeholder: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isPresented: $isPresented, onSubmit: onSubmit)
    }

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar(frame: .zero)
        searchBar.delegate = context.coordinator
        searchBar.placeholder = placeholder
        searchBar.searchBarStyle = .minimal
        searchBar.autocapitalizationType = .words
        searchBar.autocorrectionType = .no
        searchBar.returnKeyType = .search
        searchBar.backgroundImage = UIImage()
        searchBar.setBackgroundImage(UIImage(), for: .any, barMetrics: .default)
        searchBar.searchTextField.clearButtonMode = .never
        searchBar.searchTextField.borderStyle = .none
        searchBar.showsCancelButton = false
        return searchBar
    }

    func updateUIView(_ searchBar: UISearchBar, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isPresented = $isPresented
        context.coordinator.onSubmit = onSubmit

        if searchBar.text != text {
            searchBar.text = text
        }
        if searchBar.placeholder != placeholder {
            searchBar.placeholder = placeholder
        }
        searchBar.searchTextField.clearButtonMode = text.isEmpty ? .never : .whileEditing
        searchBar.setShowsCancelButton(false, animated: false)
        if isPresented && !searchBar.isFirstResponder {
            searchBar.becomeFirstResponder()
        } else if !isPresented && searchBar.isFirstResponder {
            searchBar.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        var text: Binding<String>
        var isPresented: Binding<Bool>
        var onSubmit: () -> Void

        init(text: Binding<String>, isPresented: Binding<Bool>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.isPresented = isPresented
            self.onSubmit = onSubmit
        }

        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            isPresented.wrappedValue = true
        }

        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            isPresented.wrappedValue = false
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            text.wrappedValue = searchText
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            onSubmit()
            searchBar.resignFirstResponder()
        }
    }
}
#endif
