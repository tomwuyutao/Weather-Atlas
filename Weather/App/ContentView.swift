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

// MARK: - Shared Platform Helpers

enum PlatformFeedback {
    static func lightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Root Shared State

struct ContentView: View {
    @State var weatherService = WeatherService()
    @Environment(\.appTheme) var theme
    var previewLoading: Bool = false
    var previewSkipsInitialWeatherFetch: Bool = false

    // MARK: Preview Setup

    init(
        previewLoading: Bool = false,
        previewSearchResultCity: CityWeather? = nil,
        previewCountryListCountryName: String? = nil
    ) {
        self.previewLoading = previewLoading
        self.previewSkipsInitialWeatherFetch = previewSearchResultCity != nil || previewCountryListCountryName != nil

        if let previewSearchResultCity {
            _navigationPath = State(initialValue: [.map])
            _previewCity = State(initialValue: previewSearchResultCity)
            _tappedCity = State(initialValue: previewSearchResultCity)
            _showingMapExpandedCard = State(initialValue: true)
        }

        if let previewCountryListCountryName,
           let countryIndex = CountryCityCatalog.shared.country(matching: previewCountryListCountryName),
           let country = CountryCityCatalog.shared.countryWithCities(for: countryIndex) {
            _navigationPath = State(initialValue: [.map])
            _countryListSearchMode = State(initialValue: true)
            _countryListPreviewCountry = State(initialValue: country)
            _countryListInitialCountry = State(initialValue: country)
            _countryListPreviewCityCount = State(initialValue: 15)
            _showingInlineSearch = State(initialValue: false)
            _inlineSearchFieldPresented = State(initialValue: false)
            _showingMapExpandedCard = State(initialValue: false)
            _mapRecenterRequest = State(initialValue: .listCoordinates)
        }
    }

    @State var centerOnCityTrigger: CityWeather?

    // MARK: Selection and Navigation State

    @State var selectedDayOffset: Int = 0
    @Namespace var detailDaySelectionNamespace
    @State var tappedCity: CityWeather?
    @State var showingMapExpandedCard: Bool = false
    @AppStorage("weatherListSortMode") var weatherListSortModeRaw: String = WeatherListSortMode.sunny.rawValue
    @AppStorage("hasLaunchedBefore") var hasLaunchedBefore: Bool = false
    @State var addCityDetailCity: CityWeather?
    @State var previewCity: CityWeather?
    @State var presentedDetailCityID: UUID?

    // MARK: Map Overlay State

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
    @State var hourlyRefreshKeys: Set<String> = []
    @State var attemptedHourlyRefreshKeys: Set<String> = []

    // MARK: Map Camera and Settings State

    @State var mapRecenterRequest: MapRecenterRequest?
    @State var mapMarkerReloadID: Int = 0
    @State var settingsOpenedThemeStyle: AppThemeStyle?
    @AppStorage("temperatureUnit") var temperatureUnitRaw: String = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit") var distanceUnitRaw: String = DistanceUnit.defaultRawValue
    @State var showingSettings: Bool = false
    @State var showingFirstLaunchListPicker = false
    @State var firstLaunchSelectedListIDs: Set<String> = []
    @AppStorage("showLegend") var showLegend: Bool = true
    @AppStorage("mapOverlayMode") var mapOverlayMode: String = "weather"
    @AppStorage("mapProvider") var mapProviderRaw: String = WeatherMapProvider.openStreetMap.rawValue
    @AppStorage("showDateSlider") var showDateSlider: Bool = true
    @State var visibleListIDs: Set<String> = []

    // MARK: Environment

    @Environment(\.locale) var locale
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.scenePhase) var scenePhase

    // MARK: Active City Collections

    /// Cities to display on the map: the active list plus any temporary preview city.
    var mapCities: [CityWeather] {
        if countryListSearchMode {
            guard let countryListPreviewCountry else { return [] }
            return countryListPreviewWeatherCities(for: countryListPreviewCountry)
        }

        var result = weatherService.cityWeatherData
        // Include temporary preview city from search
        if let preview = previewCity, !result.contains(where: { $0.city.name == preview.city.name }) {
            result.append(preview)
        }
        return result
    }

    var mapFitCities: [City] {
        if countryListSearchMode, let countryListPreviewCountry {
            return countryListPreviewCities(for: countryListPreviewCountry)
        }
        return weatherService.cityListCoordinates()
    }

    func countryListPreviewCities(for country: CountryCityGroup) -> [City] {
        Array(country.cities.prefix(countryListPreviewCityCount))
    }

    func countryListPreviewWeatherCities(for country: CountryCityGroup) -> [CityWeather] {
        countryListPreviewCities(for: country).map { city in
            CityWeather(
                id: city.id,
                city: city,
                condition: .cloudy,
                temperature: 24,
                symbolName: "cloud.fill",
                dailyForecasts: [.previewCloudy(dayOffset: 0)],
                timeZone: .current
            )
        }
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
    @FocusState var inlineSearchFocused: Bool
    @State var showingCityRenameAlert: Bool = false
    @State var cityRenameText: String = ""
    @FocusState var cityRenameFocused: Bool
    @State var cityToRename: CityWeather?
    @State var cityToRenameListID: CityListID?
    @State var listToRenameID: CityListID?
    @State var listEditMode: Bool = false
    @State var showingListManager: Bool = false
    @State var expandedListIDs: Set<String> = []
    @State var listOrderRevision: Int = 0
    @State var cityOrderRevision: Int = 0
    @State var newListName: String = ""
    @State var showingAddListAlert: Bool = false
    @State var showingCountryListBuilder: Bool = false
    @State var countryListInitialCountry: CountryCityGroup?
    @State var countryListSearchMode: Bool = false
    @State var countryListPreviewCountry: CountryCityGroup?
    @State var countryListPreviewCityCount: Int = 15
    @State var inlineAddTargetListID: CityListID?
    @State var listManagerEditMode: EditMode = .inactive
    @State var expandedWeatherCardShowsDetails: Bool = false
    @State var expandedWeatherCardChartMetric: WeatherChartMetric = .temperature
    @State var expandedWeatherCardChartRange: WeatherChartTimeRange = .daytime
    @State var detailChartSwipeDirection: Int = 1
    @State var navigationPath: [AppNavigationRoute] = []

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

    func hourlyRefreshKey(for cityWeather: CityWeather, dayOffset: Int? = nil) -> String {
        "\(cityWeather.id.uuidString)-\(dayOffset ?? max(0, selectedDayOffset))"
    }

    func shouldRefreshHourlyData(for cityWeather: CityWeather, forecast: DailyForecast) -> Bool {
        guard weatherService.hasResolvedTimeZone(cityWeather) else { return true }
        guard expandedWeatherCardChartRange != .tenDay else { return false }
        if expandedWeatherCardChartRange == .entireDay {
            return forecast.hourlyForecasts.isEmpty
        }
        return forecast.hourlyForecasts.filter { [7, 9, 11, 13, 15, 17, 19].contains($0.hour) }.isEmpty
    }

    func refreshHourlyDataIfNeeded(for cityWeather: CityWeather, forecast: DailyForecast) async {
        guard shouldRefreshHourlyData(for: cityWeather, forecast: forecast) else { return }
        let refreshKey = hourlyRefreshKey(for: cityWeather, dayOffset: forecast.dayOffset)
        guard !attemptedHourlyRefreshKeys.contains(refreshKey),
              !hourlyRefreshKeys.contains(refreshKey) else {
            return
        }

        hourlyRefreshKeys.insert(refreshKey)
        attemptedHourlyRefreshKeys.insert(refreshKey)
        defer { hourlyRefreshKeys.remove(refreshKey) }

        guard let refreshedWeather = await weatherService.refreshWeatherForCity(cityWeather) else {
            return
        }

        if tappedCity?.id == cityWeather.id {
            tappedCity = refreshedWeather
        }
    }

}

#Preview("ContentView") {
    let _ = UserDefaults.standard.set(false, forKey: "isGridView")
    let _ = UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
    ContentView(previewLoading: true)
}

#Preview("Country List Map") {
    let _ = UserDefaults.standard.set(false, forKey: "isGridView")
    let _ = UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
    let _ = UserDefaults.standard.set(WeatherMapProvider.openStreetMap.rawValue, forKey: "mapProvider")
    ContentView(previewCountryListCountryName: "Switzerland")
}
