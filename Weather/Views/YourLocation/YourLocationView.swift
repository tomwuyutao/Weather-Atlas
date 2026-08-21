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

    @State private var isNearbySearchQueued = false

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
            refreshCurrentLocation: refreshCurrentLocation
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
            guard !Task.isCancelled,
                  model.locationProvider.hasUsableCoordinate else {
                await model.ensureCurrentLocationWeather(locale: locale)
                return
            }

            if !model.didSearchNearby, !isNearbySearchQueued {
                isNearbySearchQueued = true
            }
            await model.ensureCurrentLocationWeather(locale: locale)
        }
        .task(id: nearbySearchTaskID) {
            let taskID = nearbySearchTaskID
            guard taskID.isQueued else { return }

            guard !Task.isCancelled else { return }
            await model.searchNearbyPlaces(
                forceRefresh: false,
                locale: locale
            )
            if nearbySearchTaskID == taskID {
                isNearbySearchQueued = false
            }
        }
    }

    private var nearbySearchTaskID: NearbySearchTaskID {
        NearbySearchTaskID(
            location: weatherTaskID,
            isQueued: isNearbySearchQueued
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

}

/// Coordinate identity makes the initial weather task restart only after Core
/// Location supplies a materially different physical position.
private struct LocalWeatherTaskID: Hashable {
    let latitude: Double?
    let longitude: Double?
}

private struct NearbySearchTaskID: Hashable {
    let location: LocalWeatherTaskID
    let isQueued: Bool
}
