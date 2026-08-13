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
            refreshLocation: refreshLocation
        )
        .refreshable {
            await model.loadSavedWeather(
                forceRefresh: true,
                locale: locale
            )
            guard model.locationProvider.hasUsableCoordinate else {
                return
            }
            await model.refreshLocation(forceRefresh: true, locale: locale)
        }
        .task(id: weatherTaskID) {
            guard model.locationProvider.hasUsableCoordinate else {
                return
            }
            await model.refreshLocation(locale: locale)
        }
    }

    private func requestCurrentLocation() {
        model.locationProvider.requestCurrentLocation(preferredLocale: locale)
    }

    private func openLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        openURL(url)
    }

    private func refreshLocation() {
        guard model.locationProvider.hasUsableCoordinate else {
            requestCurrentLocation()
            return
        }
        Task {
            await model.refreshLocation(forceRefresh: true, locale: locale)
        }
    }
}

/// Coordinate identity makes the initial weather task restart only after Core
/// Location supplies a materially different physical position.
private struct LocalWeatherTaskID: Hashable {
    let latitude: Double?
    let longitude: Double?
}
