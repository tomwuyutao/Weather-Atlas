//
//  LocationProvider.swift
//  Weather
//
//  Purpose: Provides an explicitly requested current coordinate and display
//  metadata without prompting for permission during initialization.
//

@preconcurrency import CoreLocation
import Foundation
import MapKit
import Observation

// MARK: - Location State

/// User-visible phases of the current-location workflow.
nonisolated enum LocationProviderStatus: Equatable, Hashable, Sendable {
    /// No location request is active.
    case idle
    /// The device-wide Location Services switch is being checked off-main.
    case checkingAvailability
    /// The system authorization prompt has been requested.
    case requestingAuthorization
    /// Core Location is obtaining a one-shot coordinate.
    case locating
    /// A coordinate is available and its display metadata is being resolved.
    case resolvingPlace
    /// Coordinate and display metadata are both available.
    case ready
    /// The coordinate is usable, but display metadata resolution failed.
    case readyWithoutMetadata
    /// The user has denied this app's location access.
    case denied
    /// Device policy prevents this app from using location.
    case restricted
    /// Location Services are disabled for the device.
    case servicesDisabled
    /// The current one-shot request failed for a transient reason.
    case failed
}

/// Display metadata returned by Apple's reverse geocoder for the coordinate.
nonisolated struct CurrentLocationMetadata: Equatable, Hashable, Sendable {
    /// City, locality, or map-item name suitable for the Home card.
    let displayName: String?
    /// Geocoder-provided localized country name, when available.
    let countryName: String?
    /// Time zone identifier attached to the resolved place, when available.
    let timeZoneIdentifier: String?
}

/// Internal display-metadata resolution failures.
nonisolated private enum LocationMetadataResolutionError: Error {
    case requestUnavailable
    case noResult
}

// MARK: - Provider

/// Owns Core Location's contextual authorization and one-shot location request.
///
/// Initializing this provider never requests permission or starts location
/// updates. Call `requestCurrentLocation(preferredLocale:)` from an explicit
/// current-location action.
@MainActor
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    /// Current workflow state consumed by the native settings UI.
    private(set) var status: LocationProviderStatus = .idle
    /// Most recent coordinate returned by Core Location.
    private(set) var coordinate: CLLocationCoordinate2D?
    /// Localized display metadata for the current coordinate.
    private(set) var metadata: CurrentLocationMetadata?

    /// Whether the current coordinate can already power an unrestricted query.
    var hasUsableCoordinate: Bool {
        coordinate.map(CLLocationCoordinate2DIsValid) == true
    }

    /// Whether a one-shot refresh can run without presenting authorization UI.
    var hasLocationAuthorization: Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .notDetermined, .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// System manager retained for delegate callbacks.
    @ObservationIgnored private let manager: CLLocationManager
    /// Pre-iOS 26 reverse geocoder retained so prior work can be cancelled.
    @ObservationIgnored private let geocoder = CLGeocoder()
    /// Current display-metadata resolution task.
    @ObservationIgnored private var metadataResolutionTask: Task<Void, Never>?
    /// Off-main device-wide Location Services check.
    @ObservationIgnored private var availabilityTask: Task<Void, Never>?
    /// Whether authorization was requested as part of a location action.
    @ObservationIgnored private var shouldLocateAfterAuthorization = false
    /// Locale requested by the app's currently selected language.
    @ObservationIgnored private var preferredLocale = Locale.autoupdatingCurrent

    /// Installs the delegate and mirrors existing authorization without
    /// initiating a permission request.
    override init() {
        manager = CLLocationManager()
        super.init()
        configureManager()
        synchronizeAuthorizationStatus()
    }

    deinit {
        availabilityTask?.cancel()
        metadataResolutionTask?.cancel()
        geocoder.cancelGeocode()
    }

    /// Starts the contextual authorization or one-shot location flow.
    func requestCurrentLocation(
        preferredLocale: Locale = .autoupdatingCurrent
    ) {
        self.preferredLocale = preferredLocale
        availabilityTask?.cancel()
        metadataResolutionTask?.cancel()
        geocoder.cancelGeocode()
        status = .checkingAvailability

        // Apple documents that this process-wide check can block briefly.
        // Keep that work away from the main actor before invoking any manager
        // APIs that may display authorization UI.
        availabilityTask = Task { [weak self] in
            let servicesEnabled = await Task.detached(priority: .userInitiated) {
                CLLocationManager.locationServicesEnabled()
            }.value
            guard let self, !Task.isCancelled else { return }
            guard servicesEnabled else {
                status = .servicesDisabled
                return
            }
            continueLocationRequest()
        }
    }

    /// Refreshes a previously authorized location without ever triggering the
    /// first-use permission prompt.
    func requestCurrentLocationIfAuthorized(
        preferredLocale: Locale = .autoupdatingCurrent
    ) {
        guard hasLocationAuthorization else { return }
        requestCurrentLocation(preferredLocale: preferredLocale)
    }

    /// Mirrors changes made in the system authorization prompt or Settings.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if shouldLocateAfterAuthorization {
                shouldLocateAfterAuthorization = false
                beginOneShotLocationRequest()
            } else if coordinate == nil {
                status = .idle
            }
        case .notDetermined:
            status = shouldLocateAfterAuthorization ? .requestingAuthorization : .idle
        case .denied:
            shouldLocateAfterAuthorization = false
            status = .denied
        case .restricted:
            shouldLocateAfterAuthorization = false
            status = .restricted
        @unknown default:
            shouldLocateAfterAuthorization = false
            status = .failed
        }
    }

    /// Accepts the newest valid location from the one-shot callback.
    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last(where: {
            $0.horizontalAccuracy >= 0
                && CLLocationCoordinate2DIsValid($0.coordinate)
        }) else {
            status = .failed
            return
        }

        coordinate = location.coordinate
        metadata = nil
        status = .resolvingPlace
        resolveMetadata(for: location)
    }

    /// Converts Core Location failures into stable states rather than exposing
    /// provider-localized error text directly in the UI.
    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        if let locationError = error as? CLError,
           locationError.code == .denied {
            synchronizeAuthorizationStatus()
            return
        }
        status = .failed
    }

    /// Configures accuracy appropriate for city-level weather lookup.
    private func configureManager() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = kCLDistanceFilterNone
    }

    /// Reads current authorization without prompting or starting updates.
    private func synchronizeAuthorizationStatus() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse, .notDetermined:
            status = coordinate == nil ? .idle : status
        case .denied:
            status = .denied
        case .restricted:
            status = .restricted
        @unknown default:
            status = .failed
        }
    }

    /// Starts one request after authorization has already been granted.
    private func beginOneShotLocationRequest() {
        status = .locating
        manager.requestLocation()
    }

    /// Continues on the main actor after device-wide availability is known.
    private func continueLocationRequest() {
        switch manager.authorizationStatus {
        case .notDetermined:
            shouldLocateAfterAuthorization = true
            status = .requestingAuthorization
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            beginOneShotLocationRequest()
        case .denied:
            status = .denied
        case .restricted:
            status = .restricted
        @unknown default:
            status = .failed
        }
    }

    /// Resolves display metadata while retaining the coordinate if reverse
    /// geocoding is temporarily unavailable.
    private func resolveMetadata(for location: CLLocation) {
        metadataResolutionTask?.cancel()
        metadataResolutionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resolvedMetadata: CurrentLocationMetadata
                if #available(iOS 26.0, *) {
                    // Fix for Home's place label: MapKit may return no item in
                    // Simulator or at a coordinate it cannot name. Fall back
                    // to Core Location so the card still receives the normal
                    // reverse-geocoded locality (for example, "London").
                    do {
                        resolvedMetadata = try await mapKitMetadata(
                            for: location
                        )
                    } catch {
                        resolvedMetadata = try await coreLocationMetadata(
                            for: location
                        )
                    }
                } else {
                    resolvedMetadata = try await coreLocationMetadata(for: location)
                }
                guard !Task.isCancelled else { return }
                metadata = resolvedMetadata
                status = .ready
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                metadata = nil
                status = .readyWithoutMetadata
            }
        }
    }

    /// Uses MapKit's modern reverse-geocoding request on iOS 26 and later.
    @available(iOS 26.0, *)
    private func mapKitMetadata(
        for location: CLLocation
    ) async throws -> CurrentLocationMetadata {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            throw LocationMetadataResolutionError.requestUnavailable
        }
        request.preferredLocale = preferredLocale
        guard let mapItem = try await request.mapItems.first else {
            throw LocationMetadataResolutionError.noResult
        }

        let representations = mapItem.addressRepresentations
        guard let displayName = representations?.cityName ?? mapItem.name,
              !displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty else {
            throw LocationMetadataResolutionError.noResult
        }
        return CurrentLocationMetadata(
            displayName: displayName,
            countryName: representations?.regionName,
            timeZoneIdentifier: mapItem.timeZone?.identifier
        )
    }

    /// Uses Core Location's reverse geocoder on the iOS 18 fallback path.
    private func coreLocationMetadata(
        for location: CLLocation
    ) async throws -> CurrentLocationMetadata {
        guard let placemark = try await geocoder.reverseGeocodeLocation(
            location,
            preferredLocale: preferredLocale
        ).first else {
            throw LocationMetadataResolutionError.noResult
        }
        return CurrentLocationMetadata(
            displayName: placemark.locality
                ?? placemark.subAdministrativeArea
                ?? placemark.administrativeArea,
            countryName: placemark.country,
            timeZoneIdentifier: placemark.timeZone?.identifier
        )
    }
}
