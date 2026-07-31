//
//  LocationProvider.swift
//  Weather
//
//  Purpose: Provides an explicitly requested current location and ISO country
//  without prompting for permission during app launch.
//

@preconcurrency import CoreLocation
import Foundation
import MapKit
import Observation

// MARK: - Location State

/// User-visible phases of the contextual nearby-location workflow.
nonisolated enum LocationProviderStatus: Equatable, Sendable {
    /// No location request is active.
    case idle
    /// The device-wide Location Services switch is being checked off-main.
    case checkingAvailability
    /// The system authorization prompt has been requested.
    case requestingAuthorization
    /// Core Location is obtaining a one-shot coordinate.
    case locating
    /// A coordinate is available and its ISO country is being resolved.
    case resolvingCountry
    /// Coordinate and ISO country are both available.
    case ready
    /// The coordinate is usable, but country resolution failed.
    case readyWithoutCountry
    /// The user has denied this app's location access.
    case denied
    /// Device policy prevents this app from using location.
    case restricted
    /// Location Services are disabled for the device.
    case servicesDisabled
    /// The current one-shot request failed for a transient reason.
    case failed
}

/// Current country metadata returned by Apple's reverse geocoder.
nonisolated struct CurrentCountry: Equatable, Hashable, Sendable {
    /// ISO 3166-1 alpha-2 country code.
    let isoCountryCode: String
    /// Geocoder-provided localized country name, when available.
    let localizedName: String?
}

/// Internal country-resolution failures.
nonisolated private enum CountryResolutionError: Error {
    case requestUnavailable
    case noResult
    case missingCountryCode
}

// MARK: - Provider

/// Owns Core Location's contextual authorization and one-shot location request.
///
/// Initializing this provider never requests permission or starts location
/// updates. Call `requestCurrentLocation(preferredLocale:)` from an explicit
/// nearby-discovery action.
@MainActor
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    /// Current workflow state consumed by the native settings UI.
    private(set) var status: LocationProviderStatus = .idle
    /// Most recent coordinate returned by Core Location.
    private(set) var coordinate: CLLocationCoordinate2D?
    /// ISO country metadata for the current coordinate.
    private(set) var country: CurrentCountry?

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
    /// Current country-resolution task.
    @ObservationIgnored private var countryResolutionTask: Task<Void, Never>?
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

    /// Preview-only initializer that performs no live location or geocoding.
    init(
        previewStatus: LocationProviderStatus,
        coordinate: CLLocationCoordinate2D? = nil,
        country: CurrentCountry? = nil
    ) {
        manager = CLLocationManager()
        self.status = previewStatus
        self.coordinate = coordinate
        self.country = country
        super.init()
        configureManager()
    }

    deinit {
        availabilityTask?.cancel()
        countryResolutionTask?.cancel()
        geocoder.cancelGeocode()
    }

    /// Starts the contextual authorization or one-shot location flow.
    func requestCurrentLocation(
        preferredLocale: Locale = .autoupdatingCurrent
    ) {
        self.preferredLocale = preferredLocale
        availabilityTask?.cancel()
        countryResolutionTask?.cancel()
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

    /// Refreshes a previously authorized nearby opt-in without ever triggering
    /// the first-use permission prompt.
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
        country = nil
        status = .resolvingCountry
        resolveCountry(for: location)
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

    /// Configures accuracy appropriate for city-radius discovery.
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

    /// Resolves ISO country metadata while retaining an unrestricted coordinate
    /// if reverse geocoding is temporarily unavailable.
    private func resolveCountry(for location: CLLocation) {
        countryResolutionTask?.cancel()
        countryResolutionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resolvedCountry: CurrentCountry
                if #available(iOS 26.0, *) {
                    resolvedCountry = try await mapKitCountry(for: location)
                } else {
                    resolvedCountry = try await coreLocationCountry(for: location)
                }
                guard !Task.isCancelled else { return }
                country = resolvedCountry
                status = .ready
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                country = nil
                status = .readyWithoutCountry
            }
        }
    }

    /// Uses MapKit's modern reverse-geocoding request on iOS 26 and later.
    @available(iOS 26.0, *)
    private func mapKitCountry(for location: CLLocation) async throws -> CurrentCountry {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            throw CountryResolutionError.requestUnavailable
        }
        request.preferredLocale = preferredLocale
        guard let mapItem = try await request.mapItems.first,
              let representations = mapItem.addressRepresentations else {
            throw CountryResolutionError.noResult
        }

        guard let rawCode = representations.region?.identifier else {
            throw CountryResolutionError.missingCountryCode
        }
        let code = rawCode
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .uppercased()
        guard code.count == 2 else {
            throw CountryResolutionError.missingCountryCode
        }
        return CurrentCountry(
            isoCountryCode: code,
            localizedName: representations.regionName
        )
    }

    /// Uses Core Location's reverse geocoder on the iOS 18 fallback path.
    private func coreLocationCountry(for location: CLLocation) async throws -> CurrentCountry {
        guard let placemark = try await geocoder.reverseGeocodeLocation(
            location,
            preferredLocale: preferredLocale
        ).first else {
            throw CountryResolutionError.noResult
        }
        let code = placemark.isoCountryCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard let code, code.count == 2 else {
            throw CountryResolutionError.missingCountryCode
        }
        return CurrentCountry(
            isoCountryCode: code,
            localizedName: placemark.country
        )
    }
}
