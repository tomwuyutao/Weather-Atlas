//
//  ContentView.swift
//  Weather
//
//  Created by Tom on 25/02/2026.
//
//  Purpose: Owns the app state and routes it into the single iOS shell.
//  Feature-specific UI is split into extension files.
//

import SwiftUI
import UIKit

// MARK: - Haptics

enum Haptics {
    static func lightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Root Shared State

struct ContentView: View {
    @State var weatherService = WeatherService()
    @Environment(\.appTheme) var theme

    // MARK: Startup Setup

    init(
        initialRoute: AppNavigationRoute? = nil,
        previewCityWeather: CityWeather? = nil,
        showsMapDateSliderTutorialPreview: Bool = false
    ) {
        if let initialRoute {
            _navigationPath = State(initialValue: [initialRoute])
        }
        if let previewCityWeather {
            _tappedCity = State(initialValue: previewCityWeather)
            _hasLaunchedBefore = AppStorage(wrappedValue: true, "hasLaunchedBefore")
        }
        if showsMapDateSliderTutorialPreview {
            _selectedDayOffset = State(initialValue: 4)
            _hasLaunchedBefore = AppStorage(wrappedValue: true, "hasLaunchedBefore")
            _hasSeenMapDateSliderTutorial = AppStorage(wrappedValue: false, "hasSeenMapDateSliderTutorial")
            _showingMapDateSliderTutorial = State(initialValue: true)
        }
    }

    @State var centerOnCityTrigger: CityWeather?

    // MARK: Selection and Navigation State

    @State var selectedDayOffset: Int = 0
    @Namespace var detailDaySelectionNamespace
    @State var tappedCity: CityWeather?
    @State var showingMapExpandedCard: Bool = false
    @AppStorage("weatherListSortMode") var listSortMode: String = WeatherListSortMode.sunny.rawValue
    @AppStorage("hasLaunchedBefore") var hasLaunchedBefore: Bool = false
    @State var addCityDetailCity: CityWeather?
    @State var showingAddSearchedCityListDialog: Bool = false
    @State var temporaryMapSearchCity: CityWeather?
    @State var routeShowsBackButton: Bool = false

    // MARK: Map Overlay State

    @State var filterSunny: Bool = false
    @State var showingSearchSheet: Bool = false
    @State var searchFieldPresented: Bool = false
    @State var searchText: String = ""
    @State var citySearchManager = CitySearchManager()
    @State var isLoadingSearchCity = false
    @State var loadingSearchResultID: String?
    @State var searchSelectionIndex: Int = 0
    @State var searchDebounceTask: Task<Void, Never>?
    @State var searchIsSettled: Bool = true

    // MARK: Map Camera and Settings State

    @State var mapRecenterRequest: MapRecenterRequest?
    @State var mapMarkerReloadID: Int = 0
    @State var themeStyleBeforeSettings: AppThemeStyle?
    @AppStorage("temperatureUnit") var temperatureUnitRaw: String = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit") var distanceUnitRaw: String = DistanceUnit.defaultRawValue
    @State var showingSettings: Bool = false
    @State var isResettingListsToDefaults = false
    @State var showingFirstLaunchTutorial = false
    @State var showingReplayTutorial = false
    @State var continentListTutorialSelectedIDs: Set<String> = []
    @AppStorage("hasSeenMapDateSliderTutorial") var hasSeenMapDateSliderTutorial = false
    @State var showingMapDateSliderTutorial = false
    @State var isFadingMapDateSliderTutorial = false
    @State var showingAddListOptionsSheet = false
    @State var showingContinentListSearchSheet = false
    @State var showingCountryListSearchSheet = false
    @State var countryListSearchText: String = ""
    @State var listPreviewName: String?
    @State var listPreviewAllCities: [City] = []
    @State var listPreviewCityCount = CountryCityCatalog.defaultCountryCityCount
    @State var daytimeScoreRefetchKeys: Set<String> = []
    @AppStorage("showLegend") var showLegend: Bool = true
    @AppStorage("mapOverlayMode") var mapOverlayMode: String = "weather"
    @State var visibleListIDs: Set<String> = []

    // MARK: Environment

    @Environment(\.locale) var locale
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.scenePhase) var scenePhase

    // MARK: Active City Collections

    /// Cities to display on the map: the active list plus any temporary searched city from Map search.
    var mapCities: [CityWeather] {
        if isListPreviewActive {
            return []
        }
        var result = weatherService.cityWeatherData
        if let preview = temporaryMapSearchCity, !result.contains(where: { $0.city.name == preview.city.name }) {
            result.append(preview)
        }
        return result
    }

    var mapFitCities: [City] {
        if isListPreviewActive {
            return listPreviewCities
        }
        return weatherService.cityListCoordinates()
    }

    var listPreviewCities: [City] {
        Array(listPreviewAllCities.prefix(listPreviewCityCount))
    }

    var listPreviewMaximumCount: Int {
        min(CountryCityCatalog.maxCountryCityCount, listPreviewAllCities.count)
    }

    var isListPreviewActive: Bool {
        currentRoute == .listPreview && listPreviewName != nil
    }

    func cityCountText(_ count: Int) -> String {
        if count == 1 {
            return "\(count) \(localizedString("City", locale: locale))"
        }
        return "\(count) \(localizedString("Cities", locale: locale))"
    }

    /// Cities to display in the list view: the saved active list only.
    var listViewCities: [CityWeather] {
        weatherService.cityWeatherData
    }

    var tempUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic
    }

    // MARK: Refresh Timing

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
        rootView
    }

    // MARK: - Root View State
    @State var dateSwitcherForward: Bool = true
    @State var showingDatePopover: Bool = false
    @State var isDraggingDateSlider: Bool = false
    @State var sliderDragStartDay: Int = 0
    @State var sliderDragFraction: CGFloat = 0

    @State var showingDeleteListConfirmation: Bool = false
    @State var showingRenameAlert: Bool = false
    @State var renameAlertText: String = ""
    @FocusState var renameAlertFocused: Bool
    @FocusState var searchFieldFocused: Bool
    @State var listToRenameID: CityListID?
    @State var listEditMode: Bool = false
    @State var listOrderRevision: Int = 0
    @State var newListName: String = ""
    @State var showingAddListAlert: Bool = false
    @State var searchAddTargetListID: CityListID?
    @State var navigationPath: [AppNavigationRoute] = []
    @State var developerWarning: DeveloperWarning?

    var toolbarTitle: String {
        weatherService.activeListID.localizedDisplayName(locale: locale)
    }

    // Map controls are in MapView.swift.
    // Floating and expanded card content is in FloatingCard.swift.
    // Map date slider is in MapDateSlider.swift

    var dateSwitcherText: String {
        if selectedDayOffset == -1 { return localizedString("Now", locale: locale) }
        if selectedDayOffset == 0 { return localizedString("Today", locale: locale) }
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMMdEEE", options: 0, locale: locale)
        formatter.locale = locale
        return formatter.string(from: Calendar.current.date(byAdding: .day, value: selectedDayOffset, to: Date()) ?? Date())
    }


}
