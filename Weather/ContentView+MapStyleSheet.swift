//
//  ContentView+MapStyleSheet.swift
//  Weather
//
//  Extracted from ContentView.swift
//

import SwiftUI

extension ContentView {

    // MARK: - Map Style Sheet

    var mapStyleSheet: some View {
        ZStack(alignment: .top) {

            VStack(spacing: 0) {
                // Tab switcher row — fixed height so content below doesn't shift it
                HStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: 0) {
                        ForEach([("Map Style", 0), ("Overlays", 1)], id: \.1) { label, tag in
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    mapStyleTab = tag
                                }
                            } label: {
                                Text(label)
                                    .font(.avenir(.subheadline, weight: mapStyleTab == tag ? .semibold : .medium))
                                    .foregroundStyle(mapStyleTab == tag ? theme.colors.primaryText : theme.colors.secondaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background {
                                        if mapStyleTab == tag {
                                            Capsule().fill(theme.colors.listCardFill)
                                                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 240)
                    .padding(3)
                    .background(theme.colors.background.opacity(0.6), in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.colors.mapBorder.opacity(0.4), lineWidth: 1))
                    Spacer()
                }
                .frame(height: 72)
                .padding(.horizontal, 20)
                .padding(.top, 16)

                ZStack(alignment: .top) {
                    // Map Style tab — 2-column grid of thumbnail cards
                    let modes = ["minimal", "borders", "colorful", "detailed"]
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                        ForEach(modes, id: \.self) { mode in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation { mapMode = mode }
                                showingMapStyleSheet = false
                            } label: {
                                ZStack(alignment: .bottomLeading) {
                                    MapThumbnailView(mode: mode)
                                        .frame(maxWidth: .infinity)
                                        .aspectRatio(3/2, contentMode: .fit)
                                        .allowsHitTesting(false)

                                    Text(mode.capitalized)
                                        .font(.avenir(.footnote, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                                        .padding(8)

                                    if mapMode == mode {
                                        VStack {
                                            HStack {
                                                Spacer()
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 18, weight: .semibold))
                                                    .foregroundStyle(Color(hex: 0x1579C7))
                                                    .shadow(radius: 2)
                                                    .padding(8)
                                            }
                                            Spacer()
                                        }
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(
                                            mapMode == mode ? Color(hex: 0x1579C7) : theme.colors.mapBorder.opacity(0.4),
                                            lineWidth: mapMode == mode ? 2 : 1
                                        )
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .opacity(mapStyleTab == 0 ? 1 : 0)

                    // Overlays tab
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
                    .padding(.top, 8)
                    }
                    .opacity(mapStyleTab == 1 ? 1 : 0)
                }
            }
        }
    }
}
