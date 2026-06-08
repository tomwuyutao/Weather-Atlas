//
//  ContentView.swift
//  Weather
//
//  Created by Tom on 25/02/2026.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

enum PlatformFeedback {
    static func lightImpact() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

#if os(iOS)
enum IPhoneNavigationRoute: Hashable {
    case map
    case cityDetail
    case addCityDetail
    case listManager
}
#endif

struct ContentView: View {
    @State var weatherService = WeatherService()
    @Environment(\.appTheme) var theme
    var previewLoading: Bool = false
    var previewSkipsInitialWeatherFetch: Bool = false

    init(previewLoading: Bool = false, previewSearchResultCity: CityWeather? = nil) {
        self.previewLoading = previewLoading
        self.previewSkipsInitialWeatherFetch = previewSearchResultCity != nil

        if let previewSearchResultCity {
            _selectedTab = State(initialValue: 1)
            _previewCity = State(initialValue: previewSearchResultCity)
            _previewSearchText = State(initialValue: previewSearchResultCity.city.name)
            _tappedCity = State(initialValue: previewSearchResultCity)
            _showingMapExpandedCard = State(initialValue: true)
        }
    }

    @State var centerOnCityTrigger: CityWeather?

    @State var selectedDayOffset: Int = -1
    @Namespace var detailDaySelectionNamespace
    @Namespace var iPadMapDetailNamespace
    @State var showingCityDetail: Bool = false
    @State var tappedCity: CityWeather?
    @State var showingMapExpandedCard: Bool = false
    @AppStorage("hasLaunchedBefore") var hasLaunchedBefore: Bool = false
    @State var selectedTab: Int = 0
    @State var lastRefreshText: String = ""
    @State var showingAddCityDetail: Bool = false
    @State var addCityDetailCity: CityWeather?
    @State var previewCity: CityWeather?
    @State var previewSearchText: String = ""
    var showCloudCover: Bool { mapOverlayMode == "cloudCover" }
    var overlayChartMetric: WeatherChartMetric? {
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
    @State var inlineSearchFieldPresented: Bool = false
    @State var inlineSearchText: String = ""
    @State var inlineSearchManager = CitySearchManager()
    @State var inlineIsLoadingCity = false
    @State var inlineSearchSelectionIndex: Int = 0
    
    @State var recenterOnAllCities: Bool = false
    @State var recenterUsesListCoordinates: Bool = false
    @State var mapMarkerReloadID: Int = 0
    @State var settingsOpenedThemeStyle: AppThemeStyle?
    @State var iPadInspectorPresentedCityID: UUID?
    @AppStorage("temperatureUnit") var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    @AppStorage("distanceUnit") var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue
    @State var showingSettings: Bool = false
    #if os(iOS)
    @State var tutorialStep: WeatherTutorialStep?
    @State var tutorialTargetFrames: [WeatherTutorialTarget: CGRect] = [:]
    @State var shouldShowFirstLaunchListPickerAfterTutorial = false
    @State var showingFirstLaunchListPicker = false
    @State var firstLaunchSelectedListIDs: Set<String> = []
    #endif
    @AppStorage("showLegend") var showLegend: Bool = true
    @AppStorage("mapOverlayMode") var mapOverlayMode: String = "weather"
    @AppStorage("showDateSlider") var showDateSlider: Bool = true
    @State var visibleListIDs: Set<String> = []
    @Environment(\.locale) var locale
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    #if os(macOS)
    @Environment(\.openSettings) var openSettings
    #endif
    
    /// Cities to display on the map — from the active list + preview city
    var mapCities: [CityWeather] {
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
            return "\(minutes) m"
        } else {
            let hours = minutes / 60
            return "\(hours) h"
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
    @State var listOrderRevision: Int = 0
    @State var cityOrderRevision: Int = 0
    @State var sidebarNewListName: String = ""
    @State var sidebarShowingAddListAlert: Bool = false
    @State var inlineAddTargetListID: CityListID?
    #if os(iOS)
    @State var sidebarEditMode: EditMode = .inactive
    #endif
    #if os(macOS) || os(iOS)
    @State var macSidebarVisibility: NavigationSplitViewVisibility = .all
    @State var macMapExpandedCardAnchor: CGPoint?
    @State var macMapExpandedCardBaseOffset: CGSize = .zero
    @GestureState var macMapExpandedCardGestureOffset: CGSize = .zero
    @State var macHoverPresentedCardCityID: UUID?
    @State var macMapExpandedCardFocusesMarker: Bool = false
    @State var macExpandedCardShowsDetails: Bool = false
    @State var macExpandedCardChartMetric: WeatherChartMetric = .temperature
    @State var macExpandedCardChartRange: WeatherChartTimeRange = .daytime
    @State var detailChartSwipeDirection: Int = 1
    @State var macSidebarSelection: String?
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
    @State var iPhoneNavigationPath: [IPhoneNavigationRoute] = []
    #endif

    var toolbarTitle: String {
        weatherService.activeListID.localizedDisplayName(locale: locale)
    }

    @State var isLoadingMapList: Bool = false
    @State var capsuleSwipeFromTrailing: Bool = true

    // Map overlay menu is in MapOverlayMenu.swift

    // Map expanded card is in MapExpandedCard.swift
    // Map date slider is in MapDateSlider.swift

    var iOSDateText: String {
        if selectedDayOffset == -1 { return localizedString("Now", locale: locale) }
        if selectedDayOffset == 0 { return localizedString("Today", locale: locale) }
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMMdEEE", options: 0, locale: locale)
        formatter.locale = locale
        return formatter.string(from: Calendar.current.date(byAdding: .day, value: selectedDayOffset, to: Date()) ?? Date())
    }






    private func renamedCityMatching(_ city: CityWeather) -> CityWeather? {
        weatherService.cityWeatherData.first { candidate in
            candidate.city.latitude == city.city.latitude && candidate.city.longitude == city.city.longitude
        }
    }

    func detailActionsMenu(for city: CityWeather) -> some View {
        Menu {
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
                .tint(.primary)

                Button(localizedString("Delete City", locale: locale), systemImage: "trash", role: .destructive) {
                    weatherService.removeCity(city)
                    #if os(iOS)
                    if !shouldUseIPadLayout {
                        dismissIPhoneRoute(.cityDetail)
                    } else {
                        showingCityDetail = false
                    }
                    #else
                    showingCityDetail = false
                    #endif
                    showingMapExpandedCard = false
                    tappedCity = nil
                    selectedDayOffset = -1
                    if selectedTab == 1 {
                        recenterOnAllCities = true
                    }
                }
                .tint(theme.colors.destructive)
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
                    Label {
                        Text(localizedString("Add City", locale: locale))
                    } icon: {
                        Image(systemName: "plus")
                            .foregroundStyle(.primary)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.primary)
                .foregroundColor(.primary)
        }
        #if os(macOS)
        .menuIndicator(.hidden)
        #endif
        .menuOrder(.fixed)
    }

    @ViewBuilder
    func detailToolbarTrailingAction(for city: CityWeather) -> some View {
        if shouldShowPreviewCityAddButton(for: city) {
            Button {
                Task {
                    await addCityToSidebar(city)
                    showingCityDetail = false
                    if selectedTab == 1 {
                        recenterOnAllCities = true
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        previewCity = nil
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(.primary)
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .tint(.primary)
        } else {
            detailActionsMenu(for: city)
        }
    }

    func shouldShowPreviewCityAddButton(for city: CityWeather) -> Bool {
        guard let previewCity else { return false }
        return !cityIsInSidebar(city) && citiesMatch(previewCity, city)
    }

    func citiesMatch(_ lhs: CityWeather, _ rhs: CityWeather) -> Bool {
        lhs.id == rhs.id ||
        (
            lhs.city.name == rhs.city.name &&
            lhs.city.country == rhs.city.country &&
            lhs.city.latitude == rhs.city.latitude &&
            lhs.city.longitude == rhs.city.longitude
        )
    }

    @ViewBuilder
    func addCityButton(dismissExpanded: Bool) -> some View {
        let allLists = sidebarLists
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
                    .background(AppTheme.shared.colors.accent.opacity(0.85), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
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
                    .background(AppTheme.shared.colors.accent.opacity(0.85), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview("ContentView") {
    let _ = UserDefaults.standard.set(false, forKey: "isGridView")
    let _ = UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
    ContentView()
}

#Preview("Tutorial") {
    let _ = UserDefaults.standard.set(false, forKey: "isGridView")
    let _ = UserDefaults.standard.set(false, forKey: "hasLaunchedBefore")
    ContentView()
}

