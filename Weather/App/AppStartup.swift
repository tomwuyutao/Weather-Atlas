//
//  AppStartup.swift
//  Weather
//
//  Purpose: Coordinates the app's first asynchronous load, including launch
//  shortcuts, onboarding, widget metadata, weather, and initial map fitting.
//

import Foundation

// MARK: - Initial Load

extension ContentView {
    func onAppearLoad() async {
        AppDelegate.updateHomeScreenShortcuts()

        // Publish list and city identities before WeatherKit finishes so the
        // widget gallery can immediately resolve the first city in the first list.
        publishWidgetCatalog()

        // A cold-launch quick action is supplied while the scene connects. Apply
        // it before tutorial checks or WeatherKit loading so its destination is
        // the first screen the user sees.
        let launchShortcut = AppDelegate.takePendingHomeScreenShortcut()
        if let launchShortcut {
            handleHomeScreenShortcut(launchShortcut)
        }

        // Previews should show the requested screen immediately. TutorialView's
        // dedicated previews instantiate it directly, so they remain unaffected.
        let isRunningInXcodePreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let shouldShowFirstLaunchTutorial = launchShortcut == nil
            && !isRunningInXcodePreview
            && !hasLaunchedBefore
        if shouldShowFirstLaunchTutorial {
            showLegend = true
            prepareTutorialListSelection()
            tutorialState.showsFirstLaunch = true
        }

        centerMapOnDots(useListCoordinates: true)
        if !shouldShowFirstLaunchTutorial {
            await weatherService.fetchWeatherForAllCities()
            await refreshCitiesMissingDaytimeSunninessData()
            hasCompletedInitialWeatherLoad = true
        }
        if !mapCities.isEmpty {
            centerMapOnDots(useListCoordinates: true)
        }
    }
}
