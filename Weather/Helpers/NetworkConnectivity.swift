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

// MARK: - Reachability State

/// The monitor has an explicit initial phase so callers never mistake an
/// unevaluated path for a confirmed internet connection.
nonisolated enum NetworkConnectivityStatus: Equatable, Sendable {
    case evaluating
    case available
    case offline
}

/// App-wide network reachability state backed by Apple's `NWPathMonitor`.
///
/// This deliberately reports only a confirmed unsatisfied path as offline.
/// The brief initial monitor state remains explicit, so launch neither flashes
/// an offline warning nor starts network work before iOS evaluates the path.
@MainActor
@Observable
final class NetworkConnectivity {
    /// Starts unevaluated and changes after the monitor's first path callback.
    private(set) var status: NetworkConnectivityStatus = .evaluating
    /// Whether iOS has confirmed that no internet-capable path is available.
    var isOffline: Bool { status == .offline }
    /// Whether the monitor has delivered at least one authoritative path result.
    var hasEvaluatedPath: Bool { status != .evaluating }
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
        let previousStatus = status
        status = pathStatus == .unsatisfied ? .offline : .available
        if previousStatus == .offline, status == .available {
            isOfflineBannerDismissed = false
        }
    }
}
