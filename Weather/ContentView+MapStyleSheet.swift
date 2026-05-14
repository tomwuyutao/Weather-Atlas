//
//  ContentView+MapStyleSheet.swift
//  Weather
//
//  Map overlay selector for the MapLibre map.
//

import SwiftUI

extension ContentView {

    // MARK: - Map Overlay Sheet

    var mapStyleSheet: some View {
        let overlays: [(String, String, String)] = [
            ("weather",       "cloud.sun.fill",    "Weather"),
            ("temperature",   "thermometer.medium", "Temperature"),
            ("cloudCover",    "cloud.fill",        "Cloud Cover"),
            ("precipitation", "drop.fill",         "Precipitation"),
            ("windSpeed",     "wind",              "Wind Speed"),
            ("uvIndex",       "sun.max.fill",      "UV Index"),
            ("humidity",      "humidity.fill",     "Humidity"),
            ("visibility",    "eye.fill",          "Visibility")
        ]

        return ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Capsule()
                    .fill(theme.colors.secondaryText.opacity(0.35))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 14)

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(overlays, id: \.0) { mode, icon, label in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    mapOverlayMode = mode
                                }
                                showingMapStyleSheet = false
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: icon)
                                        .font(.system(size: 16, weight: .medium))
                                        .frame(width: 24)
                                        .foregroundStyle(theme.colors.primaryText)

                                    Text(label)
                                        .font(.avenir(.body, weight: mapOverlayMode == mode ? .semibold : .medium))
                                        .foregroundStyle(theme.colors.primaryText)

                                    Spacer()

                                    if mapOverlayMode == mode {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(Color(hex: 0x1579C7))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(mapOverlayMode == mode ? Color(hex: 0x1579C7).opacity(0.08) : theme.colors.listCardFill)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(mapOverlayMode == mode ? Color(hex: 0x1579C7).opacity(0.4) : Color.clear, lineWidth: 1)
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
