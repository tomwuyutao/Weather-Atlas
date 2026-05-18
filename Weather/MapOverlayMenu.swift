//
//  MapOverlayMenu.swift
//  Weather
//
//  Map overlay selector for the MapLibre map.
//

import SwiftUI

extension ContentView {

    var mapOverlayOptions: [(mode: String, icon: String, label: String)] {
        [
            ("weather",       "cloud.sun.fill",     "Weather"),
            ("temperature",   "thermometer.medium", "Temperature"),
            ("cloudCover",    "cloud.fill",         "Cloud Cover"),
            ("precipitation", "drop.fill",          "Precipitation"),
            ("windSpeed",     "wind",               "Wind Speed"),
            ("uvIndex",       "sun.max.fill",       "UV Index"),
            ("humidity",      "humidity.fill",      "Humidity"),
            ("visibility",    "eye.fill",           "Visibility")
        ]
    }

    var mapOverlayMenu: some View {
        Menu {
            ForEach(mapOverlayOptions, id: \.mode) { option in
                Button {
                    PlatformFeedback.lightImpact()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mapOverlayMode = option.mode
                    }
                } label: {
                    Label(option.label, systemImage: mapOverlayMode == option.mode ? "checkmark" : option.icon)
                }
            }
        } label: {
            Image(systemName: "square.3.layers.3d")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(theme.colors.primaryText)
        }
        .tint(theme.colors.primaryText)
        #if os(macOS)
        .menuIndicator(.hidden)
        #endif
        .menuOrder(.fixed)
    }
}
