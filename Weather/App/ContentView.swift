//
//  ContentView.swift
//  Weather
//
//  Created by Tom on 25/02/2026.
//
//  Purpose: Owns root app state and initialization. Presentation modifiers and
//  feature behavior live in focused extension files.
//

import SwiftUI
import MapKit

// MARK: - Root View State

struct ContentView: View {
    // MARK: Dependencies

    @State var weatherService: WeatherService
    @Environment(\.appTheme) var theme

    // MARK: Initialization

    @MainActor
    init(
        weatherService: WeatherService? = nil,
        initialRoute: AppNavigationRoute? = nil
    ) {
        _weatherService = State(initialValue: weatherService ?? WeatherService())

        // Prime onboarding before SwiftUI renders the empty home screen. Waiting
        // for `.task` allowed missing-data notices and the full-screen cover to
        // compete during the first frame, which could leave a new install stuck
        // on an unfetched default list with no tutorial.
        let isRunningInXcodePreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let shouldPrimeFirstLaunchTutorial = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
            && !AppDelegate.hasPendingHomeScreenShortcut()
            && !isRunningInXcodePreview
        _tutorialState = State(initialValue: TutorialPresentationState(
            showsFirstLaunch: shouldPrimeFirstLaunchTutorial
        ))

        if let initialRoute {
            _navigationPath = State(initialValue: [initialRoute])
        }
    }

    // MARK: Primary Selection and Navigation State

    /// The literal calendar day selected by the user in the device calendar.
    /// Cities whose local forecast range does not include it are omitted.
    @State var selectedForecastDate: Date = Calendar.current.startOfDay(for: Date())
    @Namespace var detailDaySelectionNamespace
    @State var selectedMapCityID: UUID?
    @AppStorage("weatherListSortMode") var listSortMode: String = WeatherListSortMode.sunny.rawValue
    @AppStorage("hasLaunchedBefore") var hasLaunchedBefore: Bool = false
    @State var citySearchState = CitySearchPresentationState()

    // MARK: Map Overlay State

    @State var filterSunny: Bool = false

    // MARK: Map, Settings, and Workflow State

    @State var mapCameraPosition: MapCameraPosition = .automatic
    @AppStorage("temperatureUnit") var temperatureUnitRaw: String = TemperatureUnit.defaultRawValue
    @State var showingSettings: Bool = false
    @State var tutorialState = TutorialPresentationState()
    @State var listManagementState = ListManagementState()
    @FocusState var inlineListNameFocused: Bool
    @State var listPreviewState = GeneratedListPreviewState()
    @State var daytimeScoreRefetchKeys: Set<String> = []
    @State var hasCompletedInitialWeatherLoad = false
    @AppStorage("showLegend") var showLegend: Bool = true
    @AppStorage("mapOverlayMode") var mapOverlayMode: String = "weather"

    // MARK: App Environment

    @Environment(\.locale) var locale
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    // Drives text layouts and additional non-color cues in feature views.
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.accessibilityDifferentiateWithoutColor) var differentiateWithoutColor
    // Drives high-contrast palette details that cannot be expressed
    // through the shared theme alone, such as chart labels and map-safe outlines.
    @Environment(\.colorSchemeContrast) var colorSchemeContrast
    @Environment(\.scenePhase) var scenePhase

    func localizedCityName(for city: City) -> String {
        localizedCityDisplayName(for: city, locale: locale)
    }

    var tempUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic
    }

    // MARK: App-Wide Presentation State

    @State var dateSwitcherForward: Bool = true
    @State var showingDatePopover: Bool = false

    @State var showingDeleteListConfirmation: Bool = false
    @State var listToDeleteID: CityListID?
    @State var showingCityRenameAlert: Bool = false
    @State var cityRenameText: String = ""
    @FocusState var searchFieldFocused: Bool
    @State var cityToRename: City?
    @State var listEditMode: Bool = false
    @State var newListName: String = ""
    @State var showingAddListAlert: Bool = false
    @State var navigationPath: [AppNavigationRoute] = []
    @State var developerWarning: DeveloperWarning?
    @State var pendingDeveloperWarnings: [DeveloperWarning] = []
    @State var isDismissingDeveloperWarning: Bool = false

    // Map controls are in MapView.swift.
    // Floating and expanded card content is in FloatingCard.swift.
}
