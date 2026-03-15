//
//  WeatherDetailView+Header.swift
//  Weather
//
//  Extracted from WeatherDetailView.swift
//

import SwiftUI

extension WeatherDetailView {

    // MARK: - Header Background Color Block

    @ViewBuilder
    var headerBackgroundBlock: some View {
        if !isPopup {
            GeometryReader { geo in
                headerBackgroundColor
                    .frame(height: currentHeaderHeight + geo.safeAreaInsets.top)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isHeaderCollapsed)
            }
            .frame(height: currentHeaderHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isHeaderCollapsed)
            .zIndex(2)
        }
    }

    // MARK: - Floating Header (iOS only)

    @ViewBuilder
    var floatingHeader: some View {
        if !isPopup {
            ZStack(alignment: .bottom) {
                // ── EXPANDED content ────────────────────────────────────
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        // Large decorative icon — right, slightly cropped
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
                            .offset(y: -36)

                        // Temperature + condition — top left, below back button
                        VStack(alignment: .leading, spacing: 6) {
                            if isNow {
                                // Today: show current temperature
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
                                // Future days: show daily high with low at 60% opacity
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
                        .padding(.top, geo.safeAreaInsets.top)
                    }
                    .opacity(isHeaderCollapsed ? 0 : 1)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isHeaderCollapsed)
                }

                // ── COLLAPSED content ────────────────────────────────────
                if isHeaderCollapsed {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 0) {
                                Text(tempUnit.display(isNow ? cityWeather.temperature : forecast.dailyHigh))
                                    .font(.avenir(.title, weight: .bold))
                                    .foregroundStyle(.white)
                                    .contentTransition(.numericText())
                                if !isNow {
                                    Text(" ")
                                        .font(.avenir(.title, weight: .bold))
                                    Text(tempUnit.display(forecast.dailyLow))
                                        .font(.avenir(.title, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .contentTransition(.numericText())
                                }
                            }
                            Text(detailDisplayCondition.localizedDisplayName(locale: locale))
                                .font(.avenir(.subheadline, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                                .contentTransition(.opacity)
                        }
                        .animation(.smooth(duration: 0.3), value: internalSelectedDay)
                        Spacer()
                        Image(systemName: detailDisplayIcon)
                            .font(.system(size: 36))
                            .foregroundStyle(detailDisplayIcon.contains("moon") ? AppTheme.shared.colors.moonIconColor : .white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 50)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity.combined(with: .move(edge: .bottom))
                        )
                    )
                }

                // ── DRAG HANDLE ─────────────────────────────
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(.white.opacity(0.4))
                    .frame(width: 36, height: 5)

                    .frame(width: 80, height: 44)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 10, coordinateSpace: .global)
                            .onChanged { value in
                                let h = abs(value.translation.width)
                                let v = abs(value.translation.height)
                                guard v > h else { return }
                                headerDragOffset = value.translation.height
                            }
                            .onEnded { value in
                                let translation = value.translation.height
                                let velocity = value.velocity.height
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    if !isHeaderCollapsed && (translation < -40 || velocity < -200) {
                                        isHeaderCollapsed = true
                                    } else if isHeaderCollapsed && (translation > 40 || velocity > 200) {
                                        isHeaderCollapsed = false
                                    }
                                    headerDragOffset = 0
                                }
                            }
                    )
            }
            .frame(height: currentHeaderHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isHeaderCollapsed)
            .zIndex(3)
        }
    }
}
