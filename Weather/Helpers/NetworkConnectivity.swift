//
//  NetworkConnectivity.swift
//  Weather
//
//  Purpose: Publishes the device's usable internet-path state so weather
//  surfaces can preserve cached forecasts and explain when they are offline.
//

import Foundation
import Network
import Observation

/// App-wide network reachability state backed by Apple's `NWPathMonitor`.
///
/// This deliberately reports only a confirmed unsatisfied path as offline.
/// The brief initial monitor state is treated as unknown/usable so launch does
/// not flash an offline warning before iOS has evaluated the network path.
@MainActor
@Observable
final class NetworkConnectivity {
    /// Whether iOS has confirmed that no internet-capable path is available.
    private(set) var isOffline = false
    /// Lets the person hide the advisory banner for the current offline episode.
    private(set) var isOfflineBannerDismissed = false

    /// The monitor and dispatch queue are implementation details, not UI state.
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private let monitorQueue = DispatchQueue(
        label: "WeatherAtlas.NetworkConnectivity"
    )

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let status = path.status
            DispatchQueue.main.async { [weak self] in
                self?.apply(pathStatus: status)
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    deinit {
        pathMonitor.cancel()
    }

    /// Dismisses the banner without changing the offline data policy.
    func dismissOfflineBanner() {
        isOfflineBannerDismissed = true
    }

    /// Applies a new path result on the main actor. A recovered path re-arms
    /// the banner for a later, genuinely separate offline episode.
    private func apply(pathStatus: NWPath.Status) {
        let wasOffline = isOffline
        isOffline = pathStatus == .unsatisfied
        if wasOffline && !isOffline {
            isOfflineBannerDismissed = false
        }
    }
}
