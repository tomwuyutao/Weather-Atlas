//
//  IOSFloatingMapCard.swift
//  Weather
//
//  Floating city card shown above the iPhone map toolbar.
//

import SwiftUI

#if os(iOS)
extension ContentView {
    var iOSMainOverlays: some View {
        AnyView(iOSFloatingMapCardOverlay)
    }

    @ViewBuilder
    private var iOSFloatingMapCardOverlay: some View {
        if selectedTab == 1, !isMapSpecialMode, showingMapExpandedCard {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showingMapExpandedCard = false
                                tappedCity = nil
                                if previewCity != nil {
                                    previewCity = nil
                                    recenterOnAllCities = true
                                }
                            }
                        }
                        .frame(width: max(0, geometry.size.width - 92))

                    Color.clear
                        .frame(width: 92)
                        .allowsHitTesting(false)
                }
            }
            .zIndex(10)
        }

        if selectedTab == 1, !isMapSpecialMode, showingMapExpandedCard, let city = tappedCity {
            mapExpandedCard(for: city, hideCityName: shouldHideInlineMapCardCityName)
                .id(city.city.id)
                .padding(.horizontal, 26)
                .padding(.vertical, shouldAddInlineMapCardVerticalPadding ? 8 : 0)
                .padding(.bottom, previewCity != nil ? 42 : 14)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.4, anchor: .bottom).combined(with: .opacity).combined(with: .offset(y: 20)),
                        removal: .scale(scale: 0.4, anchor: .bottom).combined(with: .opacity).combined(with: .offset(y: 20))
                    )
                )
                .zIndex(12)
        }
    }
}

private struct IOSFloatingMapCardPreview: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.shared.colors.background.ignoresSafeArea()

            ContentView()
                .mapExpandedCard(for: previewCity, hideCityName: false)
                .padding(.horizontal, 26)
                .padding(.bottom, 14)
        }
    }

    private var previewCity: CityWeather {
        let hourly = [7, 9, 11, 13, 15, 17, 19].enumerated().map { index, hour in
            HourlyForecast(
                hour: hour,
                temperature: [17, 18, 20, 22, 23, 22, 20][index],
                apparentTemperature: [16, 18, 20, 22, 23, 21, 19][index],
                symbolName: "sun.max.fill",
                condition: .clear,
                precipitationChance: 0.02,
                cloudCover: 0.12,
                windSpeed: 12,
                uvIndex: 5,
                humidity: 0.46,
                visibility: 24
            )
        }

        let forecasts = (0..<10).map { offset in
            DailyForecast(
                dayOffset: offset,
                dailyLow: 16 + Double(offset % 3),
                dailyHigh: 22 + Double(offset % 5),
                symbolName: offset == 2 ? "cloud.sun.fill" : "sun.max.fill",
                condition: offset == 2 ? .partlySunny : .clear,
                hourlyForecasts: hourly,
                cloudCover: offset == 2 ? 0.4 : 0.14,
                precipitationChance: 0.04,
                visibility: 24,
                feelsLikeLow: 16 + Double(offset % 3),
                feelsLikeHigh: 22 + Double(offset % 5),
                humidity: 0.46,
                windSpeed: 12,
                uvIndex: 5,
                maxHumidity: 0.58,
                maxVisibility: 24,
                sunrise: nil,
                sunset: nil
            )
        }

        return CityWeather(
            city: City(name: "Athens", country: "Greece", latitude: 37.9838, longitude: 23.7275),
            condition: .clear,
            temperature: 22,
            symbolName: "sun.max.fill",
            dailyForecasts: forecasts,
            timeZone: TimeZone(identifier: "Europe/Athens") ?? .current,
            currentFeelsLike: 21,
            currentCloudCover: 0.14,
            currentWindSpeed: 12,
            currentUVIndex: 5,
            currentHumidity: 0.46,
            currentVisibility: 24
        )
    }
}

#Preview("iOS Floating Map Card") {
    IOSFloatingMapCardPreview()
}
#endif
