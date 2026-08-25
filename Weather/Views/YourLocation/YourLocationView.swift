//
//  YourLocationView.swift
//  Weather
//
//  Purpose: Owns the device-location lifecycle for the shared detail report.
//

import CoreLocation
import SwiftUI
import UIKit

// MARK: - Current Location Screen

/// A deliberately small current-location wrapper. Report presentation lives in
/// `CurrentLocationReportContent`; this view only starts and refreshes the
/// device-location workflow, including its permission recovery actions.
struct YourLocationView: View {
    // MARK: - Inputs and Environment

    let model: WeatherModel
    let router: AppNavigation
    @Binding var selectedDate: Date

    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    // MARK: - Task Identity

    private var weatherTaskID: LocalWeatherTaskID {
        LocalWeatherTaskID(
            latitude: model.locationProvider.coordinate?.latitude,
            longitude: model.locationProvider.coordinate?.longitude
        )
    }

    // MARK: - Presentation and Loading

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
            // Pull-to-refresh repeats a nearby search only after the initial
            // location task has established that feature's first result set.
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
            guard !Task.isCancelled else {
                return
            }

            guard model.locationProvider.hasUsableCoordinate else {
                await model.ensureCurrentLocationWeather(locale: locale)
                return
            }

            await model.ensureCurrentLocationWeather(locale: locale)

            // Establishing the first current-location forecast can advance the
            // model's location generation. Starting Nearby Sunnier Places only
            // after that work settles prevents the search from invalidating
            // itself and leaving the card in its loading state.
            guard !Task.isCancelled,
                  model.locationProvider.hasUsableCoordinate,
                  !model.didSearchNearby else {
                return
            }
            await model.searchNearbyPlaces(
                forceRefresh: false,
                locale: locale
            )
        }
    }

    // MARK: - Location Actions

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

// MARK: - Weather Task Identity

/// Coordinate identity makes the initial weather task restart only after Core
/// Location supplies a materially different physical position.
private struct LocalWeatherTaskID: Hashable {
    let latitude: Double?
    let longitude: Double?
}
