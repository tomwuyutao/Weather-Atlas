//
//  WeatherApp.swift
//  Weather
//
//  Created by Tom on 25/02/2026.
//

import SwiftUI

@main
struct WeatherApp: App {
    init() {
        // Force MapKit and system frameworks to use English
        UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        
        // One-time migration: clear old city data so new defaults take effect
        let migrationKey = "defaultCitiesMigrationV2"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            UserDefaults.standard.removeObject(forKey: "savedCitiesList")
            UserDefaults.standard.removeObject(forKey: "cachedWeatherData")
            UserDefaults.standard.removeObject(forKey: "weatherCacheTimestamp")
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
        
        #if !os(macOS)
        // Set Avenir Next for navigation bar titles
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.titleTextAttributes = [.font: UIFont(name: "AvenirNext-DemiBold", size: 17)!]
        navBarAppearance.largeTitleTextAttributes = [.font: UIFont(name: "AvenirNext-Bold", size: 34)!]
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .defaultFont()
                .preferredColorScheme(.dark)
        }
    }
}
extension View {
    func defaultFont() -> some View {
        self.environment(\.font, .custom("AvenirNext-Regular", size: 17, relativeTo: .body))
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
        let name: String
        switch weight {
        case .ultraLight: name = "AvenirNext-UltraLight"
        case .thin: name = "AvenirNext-UltraLight"
        case .light: name = "AvenirNext-Regular"
        case .regular: name = "AvenirNext-Regular"
        case .medium: name = "AvenirNext-Medium"
        case .semibold: name = "AvenirNext-DemiBold"
        case .bold: name = "AvenirNext-Bold"
        case .heavy: name = "AvenirNext-Heavy"
        case .black: name = "AvenirNext-Heavy"
        default: name = "AvenirNext-Regular"
        }
        return .custom(name, size: size, relativeTo: style)
    }
}

