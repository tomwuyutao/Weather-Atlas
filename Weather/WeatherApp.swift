//
//  WeatherApp.swift
//  Weather
//
//  Created by Tom on 25/02/2026.
//

import SwiftUI

#if os(iOS)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }
}
#endif

@main
struct WeatherApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @State private var theme = AppTheme.shared

    private var appLocale: Locale {
        Locale(identifier: appLanguage)
    }
    
    init() {
        // Always reset overlay mode to weather on launch
        UserDefaults.standard.set("weather", forKey: "mapOverlayMode")

        // One-time migration: clear old city data so new defaults take effect
        let migrationKey = "defaultCitiesMigrationV2"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            UserDefaults.standard.removeObject(forKey: "savedCitiesList")
            UserDefaults.standard.removeObject(forKey: "cachedWeatherData")
            UserDefaults.standard.removeObject(forKey: "weatherCacheTimestamp")
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
        
        #if os(iOS)
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
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ThemeRoot(theme: theme, appLocale: appLocale)
        }
        .defaultSize(width: 1280, height: 870)
        .windowStyle(.hiddenTitleBar)
        .commands {
            SidebarCommands()
            SettingsCommands()
            CommandGroup(after: .sidebar) {
                Divider()
                Button("Center on Map") {
                    NotificationCenter.default.post(name: .weatherCenterMapCommand, object: nil)
                }
                Button("Zoom In") {
                    NotificationCenter.default.post(name: .weatherZoomInCommand, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") {
                    NotificationCenter.default.post(name: .weatherZoomOutCommand, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)
                Divider()
                Button("Previous Date") {
                    NotificationCenter.default.post(name: .weatherPreviousDayCommand, object: nil)
                }
                .keyboardShortcut(.upArrow, modifiers: [])
                Button("Next Date") {
                    NotificationCenter.default.post(name: .weatherNextDayCommand, object: nil)
                }
                .keyboardShortcut(.downArrow, modifiers: [])
                Divider()
                Button("Previous List") {
                    NotificationCenter.default.post(name: .weatherPreviousListCommand, object: nil)
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                Button("Next List") {
                    NotificationCenter.default.post(name: .weatherNextListCommand, object: nil)
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .shift])
            }
        }

        Window("Settings", id: "settings") {
            SettingsRoot(theme: theme, appLocale: appLocale)
        }
        .defaultSize(width: 390, height: 773)
        .windowResizability(.contentMinSize)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.expanded)
        .keyboardShortcut(",", modifiers: .command)
        #else
        WindowGroup {
            ThemeRoot(theme: theme, appLocale: appLocale)
        }
        #endif
    }
}

#if os(macOS)
private struct SettingsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings") {
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
#endif

extension Notification.Name {
    static let weatherCenterMapCommand = Notification.Name("weatherCenterMapCommand")
    static let weatherZoomInCommand = Notification.Name("weatherZoomInCommand")
    static let weatherZoomOutCommand = Notification.Name("weatherZoomOutCommand")
    static let weatherPreviousDayCommand = Notification.Name("weatherPreviousDayCommand")
    static let weatherNextDayCommand = Notification.Name("weatherNextDayCommand")
    static let weatherPreviousListCommand = Notification.Name("weatherPreviousListCommand")
    static let weatherNextListCommand = Notification.Name("weatherNextListCommand")
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
            .tint(resolvedColors.accent)
            .onChange(of: colorScheme, initial: true) { _, newScheme in
                theme.systemScheme = newScheme
            }
    }
}

#if os(macOS)
private struct SettingsRoot: View {
    let theme: AppTheme
    let appLocale: Locale
    @State private var weatherService = WeatherService()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let resolvedColors = theme.colors(for: colorScheme)
        NavigationStack {
            SettingsView(
                weatherService: weatherService,
                onResetLists: {
                    Task {
                        await weatherService.resetAllLists()
                    }
                }
            )
            .navigationTitle("Settings")
        }
        .environment(\.locale, appLocale)
        .defaultFont()
        .environment(\.appTheme, theme)
        .environment(\.themeColors, resolvedColors)
        .tint(resolvedColors.accent)
        .preferredColorScheme(theme.preferredColorScheme(for: colorScheme))
        .onChange(of: colorScheme, initial: true) { _, newScheme in
            theme.systemScheme = newScheme
        }
    }
}
#endif

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
