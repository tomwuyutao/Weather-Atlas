//
//  DetailView.swift
//  Weather
//
//  Shared city detail destination for iOS and macOS.
//

import SwiftUI

extension ContentView {
    @ViewBuilder
    var selectedCityDetailDestination: some View {
        if let city = tappedCity {
            #if os(iOS)
            if !shouldUseIPadLayout {
                iPhoneMapExpandedCardDetailDestination(for: city)
            } else {
                fullWeatherDetailDestination(for: city)
            }
            #else
            fullWeatherDetailDestination(for: city)
            #endif
        }
    }

    #if os(iOS)
    @ToolbarContentBuilder
    private func iPhoneDetailBottomToolbar(for city: CityWeather, dismissAction: @escaping () -> Void) -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    dismissAction()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(.primary)
                        .foregroundColor(.primary)
                }
                .tint(.primary)

                Spacer()

                detailToolbarTrailingAction(for: city)
            }
        }
    }

    @ViewBuilder
    private func iPhoneDetailBottomToolbarFallback(for city: CityWeather, dismissAction: @escaping () -> Void) -> some View {
        if #available(iOS 26.0, *) {
            EmptyView()
        } else {
            HStack(spacing: 0) {
                Button {
                    dismissAction()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.plain)
                .tint(.primary)
                .iPhoneFloatingToolbarCapsule()

                Spacer(minLength: 12)

                detailToolbarTrailingAction(for: city)
                    .font(.system(size: 21, weight: .regular))
                    .frame(width: 46, height: 46)
                    .iPhoneFloatingToolbarCapsule()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, -2)
        }
    }
    #endif

    private func iPhoneMapExpandedCardDetailDestination(for city: CityWeather) -> some View {
        expandedCardDetailDestination(for: city, dismissAction: {
            dismissIPhoneRoute(.cityDetail)
            selectedDayOffset = -1
        })
    }

    private func fullWeatherDetailDestination(for city: CityWeather) -> some View {
        expandedCardDetailDestination(for: city, dismissAction: {
            #if os(iOS)
            if !shouldUseIPadLayout {
                dismissIPhoneRoute(.cityDetail)
            } else {
                showingCityDetail = false
            }
            #else
            showingCityDetail = false
            #endif
            selectedDayOffset = -1
        })
    }

    func expandedCardDetailDestination(for city: CityWeather, dismissAction: @escaping () -> Void) -> some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                mapExpandedCard(
                    for: city,
                    forceMacStyle: true,
                    forceIPhoneDetailSizing: detailViewUsesIPhoneSizing,
                    plainBackground: true
                )
                    .padding(.horizontal, detailViewHorizontalPadding)
                    .padding(.top, detailViewTopPadding)
                    .padding(.bottom, detailViewBottomPadding)
                    .frame(maxWidth: detailViewMaxWidth)
                    .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)

            #if os(iOS)
            iPhoneDetailBottomToolbarFallback(for: city, dismissAction: dismissAction)
            #endif
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("")
        #if os(iOS)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            iPhoneDetailBottomToolbar(for: city, dismissAction: dismissAction)
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(.primary)
        #endif
        .onAppear {
            if let overlayChartMetric {
                macExpandedCardChartMetric = overlayChartMetric
            }
            macExpandedCardShowsDetails = true
        }
        .onDisappear {
            macExpandedCardShowsDetails = false
        }
    }

    private var detailViewUsesIPhoneSizing: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    private var detailViewHorizontalPadding: CGFloat {
        #if os(iOS)
        shouldUseIPadLayout ? 20 : 6
        #else
        16
        #endif
    }

    private var detailViewTopPadding: CGFloat {
        #if os(iOS)
        12
        #else
        16
        #endif
    }

    private var detailViewBottomPadding: CGFloat {
        #if os(iOS)
        24
        #else
        16
        #endif
    }

    private var detailViewMaxWidth: CGFloat? {
        #if os(iOS)
        shouldUseIPadLayout ? 560 : nil
        #else
        460
        #endif
    }
}
