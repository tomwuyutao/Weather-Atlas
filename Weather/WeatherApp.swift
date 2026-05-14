//
//  WeatherApp.swift
//  Weather
//
//  Created by Tom on 25/02/2026.
//

import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }
}

@main
struct WeatherApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @State private var theme = AppTheme.shared

    private var appLocale: Locale {
        Locale(identifier: appLanguage)
    }
    
    init() {
        // Always reset overlay mode to weather on launch
        UserDefaults.standard.set("weather", forKey: "mapOverlayMode")

        // One-time migration: make the MapLibre-based map the default normal map.
        let mapLibreMigrationKey = "mapLibreDefaultMigrationV1"
        if !UserDefaults.standard.bool(forKey: mapLibreMigrationKey) {
            UserDefaults.standard.set("maplibre", forKey: "mapMode")
            UserDefaults.standard.set(true, forKey: mapLibreMigrationKey)
        }

        // One-time migration: clear old city data so new defaults take effect
        let migrationKey = "defaultCitiesMigrationV2"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            UserDefaults.standard.removeObject(forKey: "savedCitiesList")
            UserDefaults.standard.removeObject(forKey: "cachedWeatherData")
            UserDefaults.standard.removeObject(forKey: "weatherCacheTimestamp")
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
        
        // Keep native bars transparent so Liquid Glass floats over app content.
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithTransparentBackground()
        navBarAppearance.backgroundColor = .clear
        navBarAppearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = navBarAppearance

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithTransparentBackground()
        tabBarAppearance.backgroundColor = .clear
        tabBarAppearance.shadowColor = .clear
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }

    var body: some Scene {
        WindowGroup {
            ThemeRoot(theme: theme, appLocale: appLocale)
        }
    }
}
/// Outer layer: sets the preferred color scheme so the inner layer reads the correct one.
private struct ThemeRoot: View {
    let theme: AppTheme
    let appLocale: Locale
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ThemeContent(theme: theme, appLocale: appLocale)
            .preferredColorScheme(theme.preferredColorScheme(for: colorScheme))
    }
}

/// Inner layer: reads `colorScheme` *after* `preferredColorScheme` has been applied,
/// so automatic mode sees the correct system value and forced modes see their override.
/// Also keeps `AppTheme.shared.systemScheme` in sync so view modifiers update reactively.
private struct ThemeContent: View {
    let theme: AppTheme
    let appLocale: Locale
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let resolvedColors = theme.colors(for: colorScheme)
        ContentView()
            .environment(\.locale, appLocale)
            .defaultFont()
            .environment(\.appTheme, theme)
            .environment(\.themeColors, resolvedColors)
            .onChange(of: colorScheme, initial: true) { _, newScheme in
                theme.systemScheme = newScheme
            }
    }
}

extension View {
    func defaultFont() -> some View {
        self
    }
}

extension Font {
    static func avenir(_ style: TextStyle, weight: Font.Weight = .regular) -> Font {
        let size: CGFloat
        switch style {
        case .largeTitle: size = 34
        case .title: size = 28
        case .title2: size = 22
        case .title3: size = 20
        case .headline: size = 17
        case .subheadline: size = 15
        case .body: size = 17
        case .callout: size = 16
        case .footnote: size = 13
        case .caption: size = 12
        case .caption2: size = 11
        @unknown default: size = 17
        }
        return .system(size: size, weight: weight, design: .default)
    }
}

