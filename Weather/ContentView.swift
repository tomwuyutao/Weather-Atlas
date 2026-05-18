//
//  ContentView.swift
//  Weather
//
//  Created by Tom on 25/02/2026.
//

import SwiftUI
import CoreLocation
import MapKit
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

enum PlatformFeedback {
    static func lightImpact() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

struct ContentView: View {
    @State var weatherService = WeatherService()
    @Environment(\.appTheme) var theme
    var previewLoading: Bool = false

    @State var centerOnCityTrigger: CityWeather?

    @State var selectedDayOffset: Int = -1
    @State var showingCityDetail: Bool = false
    @State var tappedCity: CityWeather?
    @State var showingMapExpandedCard: Bool = false
    @AppStorage("hasLaunchedBefore") var hasLaunchedBefore: Bool = false
    @State var selectedTab: Int = 0
    @State var lastRefreshText: String = ""
    @State var showingAddCityView: Bool = false
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
    @State var inlineSearchText: String = ""
    @State var inlineSearchManager = CitySearchManager()
    @State var inlineIsLoadingCity = false
    @State var inlineSearchSelectionIndex: Int = 0
    
    @State var recenterOnAllCities: Bool = false
    @AppStorage("temperatureUnit") var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    @AppStorage("distanceUnit") var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue
    @State var showingSettings: Bool = false
    @AppStorage("showLegend") var showLegend: Bool = true
    @State var showingInfo: Bool = false
    @AppStorage("mapOverlayMode") var mapOverlayMode: String = "weather"
    @AppStorage("showDateSlider") var showDateSlider: Bool = true
    @State var visibleListIDs: Set<String> = []
    @Environment(\.locale) var locale
    @Environment(\.colorScheme) var colorScheme
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
            Button {
                showingSettings = true
            } label: {
                Label(localizedString("Settings", locale: locale), systemImage: "gearshape")
            }

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

                Button(role: .destructive) {
                    weatherService.removeCity(city)
                    showingCityDetail = false
                    showingMapExpandedCard = false
                    tappedCity = nil
                    selectedDayOffset = -1
                    if selectedTab == 1 {
                        recenterOnAllCities = true
                    }
                } label: {
                    Label {
                        Text(localizedString("Delete City", locale: locale))
                    } icon: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
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
                    Label(localizedString("Add City", locale: locale), systemImage: "plus")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.primary)
        }
        .tint(.primary)
        #if os(macOS)
        .menuIndicator(.hidden)
        #endif
        .menuOrder(.fixed)
    }


    @ViewBuilder
    func addCityButton(dismissExpanded: Bool) -> some View {
        let allLists = CityListID.allLists
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
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
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
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
        }
    }
}

private enum WeatherPreviewData {
    static var athens: CityWeather {
        let now = Date()
        let calendar = Calendar.current
        let hourly = [7, 9, 11, 13, 15, 17, 19].enumerated().map { index, hour in
            HourlyForecast(
                hour: hour,
                temperature: [16, 18, 21, 23, 24, 23, 21][index],
                apparentTemperature: [15, 18, 21, 23, 24, 23, 20][index],
                symbolName: index == 4 ? "cloud.sun.fill" : "sun.max.fill",
                condition: index == 4 ? .partlyCloudy : .clear,
                precipitationChance: 0.05,
                cloudCover: index == 4 ? 0.35 : 0.12,
                windSpeed: 12 + Double(index),
                uvIndex: max(1, 7 - abs(index - 3)),
                humidity: 0.45,
                visibility: 22
            )
        }

        let forecasts = (0..<10).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            let symbol = ["sun.max.fill", "sun.max.fill", "cloud.sun.fill", "sun.max.fill", "cloud.fill"][offset % 5]
            let condition: AppWeatherCondition = symbol == "cloud.fill" ? .cloudy : (symbol == "cloud.sun.fill" ? .partlyCloudy : .clear)
            return DailyForecast(
                dayOffset: offset,
                dailyLow: [16, 17, 18, 19, 18, 17, 18, 19, 18, 17][offset],
                dailyHigh: [21, 23, 24, 25, 23, 22, 23, 25, 25, 24][offset],
                symbolName: symbol,
                condition: condition,
                hourlyForecasts: hourly,
                cloudCover: condition == .cloudy ? 0.75 : 0.2,
                precipitationChance: 0.08,
                visibility: 22,
                feelsLikeLow: [15, 16, 17, 18, 18, 17, 18, 18, 17, 16][offset],
                feelsLikeHigh: [20, 22, 24, 25, 23, 22, 23, 24, 24, 23][offset],
                humidity: 0.48,
                windSpeed: 14,
                uvIndex: 5,
                maxHumidity: 0.58,
                maxVisibility: 24,
                sunrise: calendar.date(bySettingHour: 6, minute: 10, second: 0, of: date),
                sunset: calendar.date(bySettingHour: 20, minute: 20, second: 0, of: date)
            )
        }

        return CityWeather(
            city: City(name: "Athens", country: "Greece", latitude: 37.9838, longitude: 23.7275),
            condition: .clear,
            temperature: 21,
            symbolName: "sun.max.fill",
            dailyForecasts: forecasts,
            timeZone: TimeZone(identifier: "Europe/Athens") ?? .current,
            currentFeelsLike: 20,
            currentCloudCover: 0.15,
            currentWindSpeed: 13,
            currentUVIndex: 5,
            currentHumidity: 0.48,
            currentVisibility: 22
        )
    }
}

#if os(iOS)
private extension ContentView {
    static var iOSDetailPreview: some View {
        NavigationStack {
            ContentView().expandedCardDetailDestination(for: WeatherPreviewData.athens, dismissAction: {})
        }
    }
}
#endif

#Preview {
    let _ = UserDefaults.standard.set(false, forKey: "isGridView")
    let _ = UserDefaults.standard.set(false, forKey: "hasLaunchedBefore")
    ContentView()
}

#Preview("Loading") {
    ContentView(previewLoading: true)
}
#if os(iOS)
#Preview("iOS Detail") {
    ContentView.iOSDetailPreview
}
#endif

