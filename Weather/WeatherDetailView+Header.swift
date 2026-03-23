//
//  WeatherDetailView+Header.swift
//  Weather
//
//  Extracted from WeatherDetailView.swift
//

import SwiftUI

extension WeatherDetailView {

    // MARK: - Inline Scrollable Header

    var inlineHeader: some View {
        GeometryReader { geo in
            let topInset = geo.safeAreaInsets.top
            ZStack(alignment: .topLeading) {
                // Large decorative icon — right side, semi-transparent
                Image(systemName: detailDisplayIcon)
                    .font(.system(size: 180))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .opacity(0.35)
                    .animation(.smooth(duration: 0.3), value: internalSelectedDay)
                    .background(alignment: .top) {
                        if !detailDisplayIcon.contains("moon") {
                            WeatherEffectOverlay(
                                condition: detailDisplayCondition,
                                isCompact: false,
                                iconHeight: 220,
                                iconName: detailDisplayIcon,
                                dropColor: detailDisplayCondition == .drizzle ? AppTheme.shared.colors.dotRain : nil
                            )
                            .id("detail-header-effect-\(internalSelectedDay)-\(detailDisplayCondition.displayName)")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, -40)
                    .offset(y: -10 + topInset)

                // Temperature + condition — bottom left
                VStack(alignment: .leading, spacing: 6) {
                    Spacer()

                    if isNow {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(tempUnit.display(cityWeather.temperature))
                                .font(.avenir(.largeTitle, weight: .bold))
                                .dynamicTypeSize(...DynamicTypeSize.large)
                                .contentTransition(.numericText())
                        }
                        .animation(.smooth(duration: 0.3), value: internalSelectedDay)

                        Text(detailDisplayCondition.localizedDisplayName(locale: locale))
                            .font(.avenir(.title3, weight: .medium))
                            .dynamicTypeSize(...DynamicTypeSize.large)
                            .contentTransition(.opacity)
                            .animation(.smooth(duration: 0.3), value: internalSelectedDay)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(tempUnit.display(forecast.dailyHigh))
                                .font(.avenir(.largeTitle, weight: .bold))
                                .dynamicTypeSize(...DynamicTypeSize.large)
                                .contentTransition(.numericText())
                            Text(" ")
                                .font(.avenir(.largeTitle, weight: .bold))
                            Text(tempUnit.display(forecast.dailyLow))
                                .font(.avenir(.largeTitle, weight: .bold))
                                .dynamicTypeSize(...DynamicTypeSize.large)
                                .contentTransition(.numericText())
                                .opacity(0.6)
                        }
                        .animation(.smooth(duration: 0.3), value: internalSelectedDay)

                        Text(forecast.condition.localizedDisplayName(locale: locale))
                            .font(.avenir(.title3, weight: .medium))
                            .dynamicTypeSize(...DynamicTypeSize.large)
                            .contentTransition(.opacity)
                            .animation(.smooth(duration: 0.3), value: internalSelectedDay)
                    }
                }
                .foregroundStyle(.white)
                .padding(.leading, 28)
                .padding(.bottom, 48)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(headerBackgroundColor)
        }
        .frame(height: expandedHeaderHeight)
        .clipped()
    }
}
