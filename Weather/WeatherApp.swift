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
        .defaultSize(width: 1120, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            WeatherSidebarCommands()
            SettingsCommands()
            CommandGroup(after: .newItem) {
                Button("New List") {
                    NotificationCenter.default.post(name: .weatherNewListCommand, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            WeatherMapCommands()
            WeatherOverlayCommands()
            WeatherListCommands()
            WeatherNavigateCommands()
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
private struct WeatherSidebarCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .sidebar) {
            Button("Hide Sidebar") {
                NotificationCenter.default.post(name: .weatherToggleSidebarCommand, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
        }
    }
}

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

private struct WeatherMapCommands: Commands {
    var body: some Commands {
        CommandMenu("Map") {
            Button("Refresh Weather") {
                NotificationCenter.default.post(name: .weatherRefreshCommand, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)

            Toggle("Filter Sunny", isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: "menuFilterSunnyState") },
                set: { _ in NotificationCenter.default.post(name: .weatherToggleSunnyFilterCommand, object: nil) }
            ))

            Toggle("Show Legend", isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: "showLegend") },
                set: { _ in NotificationCenter.default.post(name: .weatherToggleLegendCommand, object: nil) }
            ))
        }
    }
}

private struct WeatherOverlayCommands: Commands {
    @AppStorage("mapOverlayMode") private var selectedOverlay: String = "weather"

    private let overlays: [(String, String)] = [
        ("weather", "Weather"),
        ("temperature", "Temperature"),
        ("cloudCover", "Cloud Cover"),
        ("precipitation", "Precipitation"),
        ("windSpeed", "Wind Speed"),
        ("uvIndex", "UV Index"),
        ("humidity", "Humidity"),
        ("visibility", "Visibility")
    ]

    var body: some Commands {
        CommandMenu("Overlay") {
            Picker(selection: Binding(
                get: { selectedOverlay },
                set: { mode in
                    selectedOverlay = mode
                    NotificationCenter.default.post(name: .weatherOverlayCommand, object: mode)
                }
            )) {
                ForEach(overlays, id: \.0) { mode, label in
                    Text(label).tag(mode)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        }
    }
}

private struct WeatherListCommands: Commands {
    @AppStorage("activeListID") private var activeListID: String = CityListID.europe.rawValue

    var body: some Commands {
        CommandMenu("List") {
            Picker(selection: Binding(
                get: { activeListID },
                set: { rawValue in
                    activeListID = rawValue
                    NotificationCenter.default.post(name: .weatherSwitchListCommand, object: rawValue)
                }
            )) {
                ForEach(CityListID.allLists) { listID in
                    Text(listID.localizedDisplayName()).tag(listID.rawValue)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        }
    }
}

private struct WeatherNavigateCommands: Commands {
    var body: some Commands {
        CommandMenu("Navigate") {
            Button("Center on Map") {
                NotificationCenter.default.post(name: .weatherCenterMapCommand, object: nil)
            }
            .keyboardShortcut("0", modifiers: .command)

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

            Button("Zoom In") {
                NotificationCenter.default.post(name: .weatherZoomInCommand, object: nil)
            }
            .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") {
                NotificationCenter.default.post(name: .weatherZoomOutCommand, object: nil)
            }
            .keyboardShortcut("-", modifiers: .command)

            Divider()

            Button("Pan Up") { NotificationCenter.default.post(name: .weatherPanCommand, object: "w") }
                .keyboardShortcut("w", modifiers: [])
            Button("Pan Left") { NotificationCenter.default.post(name: .weatherPanCommand, object: "a") }
                .keyboardShortcut("a", modifiers: [])
            Button("Pan Down") { NotificationCenter.default.post(name: .weatherPanCommand, object: "s") }
                .keyboardShortcut("s", modifiers: [])
            Button("Pan Right") { NotificationCenter.default.post(name: .weatherPanCommand, object: "d") }
                .keyboardShortcut("d", modifiers: [])
            Button("Zoom In Continuously") { NotificationCenter.default.post(name: .weatherKeyboardZoomCommand, object: "c") }
                .keyboardShortcut("c", modifiers: [])
            Button("Zoom Out Continuously") { NotificationCenter.default.post(name: .weatherKeyboardZoomCommand, object: "v") }
                .keyboardShortcut("v", modifiers: [])
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
    static let weatherRefreshCommand = Notification.Name("weatherRefreshCommand")
    static let weatherToggleSunnyFilterCommand = Notification.Name("weatherToggleSunnyFilterCommand")
    static let weatherToggleLegendCommand = Notification.Name("weatherToggleLegendCommand")
    static let weatherOverlayCommand = Notification.Name("weatherOverlayCommand")
    static let weatherSwitchListCommand = Notification.Name("weatherSwitchListCommand")
    static let weatherNewListCommand = Notification.Name("weatherNewListCommand")
    static let weatherToggleSidebarCommand = Notification.Name("weatherToggleSidebarCommand")
    static let weatherPanCommand = Notification.Name("weatherPanCommand")
    static let weatherKeyboardZoomCommand = Notification.Name("weatherKeyboardZoomCommand")
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
