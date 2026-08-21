//
//  YourLocationView.swift
//  Weather
//
//  Purpose: Owns the device-location lifecycle for the shared detail report.
//

import CoreLocation
import SwiftUI
import UIKit

/// A deliberately small current-location wrapper. Report presentation lives in
/// `CurrentLocationReportContent`; this view only starts and refreshes the
/// device-location workflow, including its permission recovery actions.
struct YourLocationView: View {
    let model: WeatherModel
    let router: AppNavigation
    @Binding var selectedDate: Date

    @State private var nearbySearchRequest: NearbySearchRequest?
    @State private var activeNearbySearchTaskID: NearbySearchTaskID?
    @State private var isNearbyCardVisible = false

    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    private var weatherTaskID: LocalWeatherTaskID {
        LocalWeatherTaskID(
            latitude: model.locationProvider.coordinate?.latitude,
            longitude: model.locationProvider.coordinate?.longitude
        )
    }

    var body: some View {
        CurrentLocationReportContent(
            model: model,
            router: router,
            selectedDate: $selectedDate,
            requestCurrentLocation: requestCurrentLocation,
            openLocationSettings: openLocationSettings,
            refreshCurrentLocation: refreshCurrentLocation,
            searchNearby: requestNearbySearch,
            onNearbyVisibilityChange: handleNearbyVisibilityChange
        )
        .refreshable {
            let refreshesNearby = model.didSearchNearby
            await model.loadSavedWeather(
                forceRefresh: true
            )
            await model.ensureCurrentLocationWeather(
                forceRefresh: true,
                locale: locale
            )
            guard model.locationProvider.hasUsableCoordinate else {
                return
            }
            if refreshesNearby {
                await model.searchNearbyPlaces(
                    forceRefresh: true,
                    locale: locale
                )
            }
        }
        .task(id: weatherTaskID) {
            await model.ensureCurrentLocationWeather(locale: locale)
            guard !Task.isCancelled,
                  model.locationProvider.hasUsableCoordinate,
                  isNearbyCardVisible,
                  nearbySearchRequest == nil else {
                return
            }
            nearbySearchRequest = .automatic
        }
        .task(id: nearbySearchTaskID) {
            let taskID = nearbySearchTaskID
            guard let request = taskID.request else { return }

            if request == .automatic {
                do {
                    // A short cancellable delay prevents a fast flick past the
                    // lower card from spending the 25-city request budget.
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }

            activeNearbySearchTaskID = taskID
            // Coordinate tasks and card-visibility tasks can restart together.
            // Await the current-only path first so its coordinate invalidation
            // cannot supersede the nearby generation we are about to create.
            await model.ensureCurrentLocationWeather(locale: locale)
            guard !Task.isCancelled else { return }
            await model.searchNearbyPlaces(
                forceRefresh: request.isExplicit,
                locale: locale
            )
            if activeNearbySearchTaskID == taskID {
                activeNearbySearchTaskID = nil
            }
            if nearbySearchTaskID == taskID {
                nearbySearchRequest = nil
            }
        }
    }

    private var nearbySearchTaskID: NearbySearchTaskID {
        NearbySearchTaskID(
            location: weatherTaskID,
            request: nearbySearchRequest
        )
    }

    private func requestCurrentLocation() {
        model.useCurrentLocation(preferredLocale: locale)
    }

    private func openLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        openURL(url)
    }

    private func refreshCurrentLocation() {
        guard model.locationProvider.hasUsableCoordinate else {
            requestCurrentLocation()
            return
        }
        Task {
            await model.ensureCurrentLocationWeather(
                forceRefresh: true,
                locale: locale
            )
        }
    }

    private func requestNearbySearch() {
        guard model.locationProvider.hasUsableCoordinate else {
            requestCurrentLocation()
            return
        }
        nearbySearchRequest = .explicit(UUID())
    }

    private func handleNearbyVisibilityChange(_ isVisible: Bool) {
        isNearbyCardVisible = isVisible
        if isVisible {
            if nearbySearchRequest == nil,
               !model.didSearchNearby,
               !model.isSearchingNearby {
                nearbySearchRequest = .automatic
            }
        } else if activeNearbySearchTaskID == nil,
                  nearbySearchRequest == .automatic {
            // This only cancels the debounce. Once the bounded batch has begun,
            // allow it to finish and populate the card for the next scroll.
            nearbySearchRequest = nil
        }
    }
}

/// Coordinate identity makes the initial weather task restart only after Core
/// Location supplies a materially different physical position.
private struct LocalWeatherTaskID: Hashable {
    let latitude: Double?
    let longitude: Double?
}

private enum NearbySearchRequest: Hashable {
    case automatic
    case explicit(UUID)

    var isExplicit: Bool {
        if case .explicit = self { return true }
        return false
    }
}

private struct NearbySearchTaskID: Hashable {
    let location: LocalWeatherTaskID
    let request: NearbySearchRequest?
}
