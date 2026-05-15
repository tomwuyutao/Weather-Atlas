//
//  ContentView+MapStyleSheet.swift
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
                    Label(option.label, systemImage: option.icon)
                }
            }
        } label: {
            Image(systemName: "square.3.layers.3d")
        }
        .menuIndicator(.hidden)
        .menuOrder(.fixed)
    }

    // MARK: - Map Overlay Sheet

    var mapStyleSheet: some View {
        return ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Capsule()
                    .fill(theme.colors.secondaryText.opacity(0.35))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 14)

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(mapOverlayOptions, id: \.mode) { option in
                            Button {
                                PlatformFeedback.lightImpact()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    mapOverlayMode = option.mode
                                }
                                showingMapStyleSheet = false
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: option.icon)
                                        .font(.system(size: 16, weight: .medium))
                                        .frame(width: 24)
                                        .foregroundStyle(theme.colors.primaryText)

                                    Text(option.label)
                                        .font(.avenir(.body, weight: mapOverlayMode == option.mode ? .semibold : .medium))
                                        .foregroundStyle(theme.colors.primaryText)

                                    Spacer()

                                    if mapOverlayMode == option.mode {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(Color(hex: 0x1579C7))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .themedGlass(in: .rect(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(mapOverlayMode == option.mode ? Color(hex: 0x1579C7).opacity(0.08) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(mapOverlayMode == option.mode ? Color(hex: 0x1579C7).opacity(0.4) : theme.colors.primaryText.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
    }
}
