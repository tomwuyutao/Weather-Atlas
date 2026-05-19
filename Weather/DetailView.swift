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
        ScrollView(.vertical, showsIndicators: false) {
            mapExpandedCard(for: city, forceMacStyle: true, plainBackground: true)
                .padding(.horizontal, detailViewHorizontalPadding)
                .padding(.top, detailViewTopPadding)
                .padding(.bottom, detailViewBottomPadding)
                .frame(maxWidth: detailViewMaxWidth)
                .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
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
