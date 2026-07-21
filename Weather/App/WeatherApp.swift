//
//  WeatherApp.swift
//  Weather
//
//  Purpose: Defines the SwiftUI app entry point and launch-time data migrations.
//

import SwiftUI
import UIKit

// MARK: - App Entry Point

@main
struct WeatherApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @State private var theme = AppTheme.shared
    // iPad: Share the observable model across WindowGroup scenes so list and
    // weather mutations remain consistent when multiple app windows are open.
    @State private var weatherService: WeatherService

    private var appLocale: Locale {
        Locale(identifier: appLanguage)
    }
    
    init() {
        AppLanguageDefaults.configureInitialLanguage()

        // Always reset overlay mode to weather on launch
        UserDefaults.standard.set("weather", forKey: "mapOverlayMode")

        // One-time migration: clear old default-list data so new region defaults take effect.
        let migrationKey = "defaultCitiesMigrationV3"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            UserDefaults.standard.removeObject(forKey: "savedCitiesList")
            UserDefaults.standard.removeObject(forKey: "cachedWeatherData")
            UserDefaults.standard.removeObject(forKey: "weatherCacheTimestamp")
            UserDefaults.standard.removeObject(forKey: "deletedBuiltInLists")
            UserDefaults.standard.removeObject(forKey: "listOrder")
            UserDefaults.standard.removeObject(forKey: "customListNames")

            for rawValue in ["china", "europe", "asia", "northAmerica", "southAmerica", "africa", "australia"] {
                UserDefaults.standard.removeObject(forKey: "savedCitiesList_\(rawValue)")
                UserDefaults.standard.removeObject(forKey: "cachedWeatherData_\(rawValue)")
                UserDefaults.standard.removeObject(forKey: "weatherCacheTimestamp_\(rawValue)")
            }

            if UserDefaults.standard.string(forKey: "activeListID") == "china" {
                UserDefaults.standard.set(CityListID.europe.rawValue, forKey: "activeListID")
            }
            UserDefaults.standard.set(true, forKey: migrationKey)
        }

        // Daily weather metrics now come from WeatherKit's native daytime forecast.
        // Refresh weather snapshots once without affecting saved city lists or preferences.
        let weatherCacheMigrationKey = "weatherCacheDaytimeForecastMigrationV1"
        if !UserDefaults.standard.bool(forKey: weatherCacheMigrationKey) {
            let cacheKeyPrefixes = ["cachedWeatherData", "weatherCacheTimestamp"]
            for key in UserDefaults.standard.dictionaryRepresentation().keys where cacheKeyPrefixes.contains(where: { key.hasPrefix($0) }) {
                UserDefaults.standard.removeObject(forKey: key)
            }
            UserDefaults.standard.set(true, forKey: weatherCacheMigrationKey)
        }

        // Construct the shared model only after persistence migrations finish,
        // so every iPad scene starts from the migrated source of truth.
        _weatherService = State(initialValue: WeatherService())
    }

    var body: some Scene {
        WindowGroup {
            ThemeRoot(
                theme: theme,
                appLocale: appLocale,
                weatherService: weatherService
            )
        }
    }
}
