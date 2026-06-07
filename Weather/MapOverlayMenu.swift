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
            ("weather",       "cloud.sun.fill",     localizedString("Weather", locale: locale)),
            ("temperature",   "thermometer.medium", localizedString("Temperature", locale: locale)),
            ("cloudCover",    "cloud.fill",         localizedString("Cloud Cover", locale: locale)),
            ("precipitation", "drop.fill",          localizedString("Precipitation", locale: locale)),
            ("windSpeed",     "wind",               localizedString("Wind Speed", locale: locale)),
            ("uvIndex",       "sun.max.fill",       localizedString("UV Index", locale: locale)),
            ("humidity",      "humidity.fill",      localizedString("Humidity", locale: locale)),
            ("visibility",    "eye.fill",           localizedString("Visibility", locale: locale))
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
                    Label {
                        Text(option.label)
                    } icon: {
                        Image(systemName: mapOverlayMode == option.mode ? "checkmark" : option.icon)
                            .foregroundStyle(.primary)
                    }
                }
            }
        } label: {
            Image(systemName: "square.3.layers.3d")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
                .foregroundColor(.primary)
        }
        .tint(.primary)
        #if os(macOS)
        .menuIndicator(.hidden)
        #endif
        .menuOrder(.fixed)
    }
}
