//
//  WidgetLocation.swift
//  WeatherWidgets
//
//  Purpose: Resolves device coordinates, localized place metadata, and a
//  validated local time zone for current-location widget forecasts.
//

@preconcurrency import CoreLocation
import Foundation
import MapKit
import SwiftTimeZoneLookup

// MARK: - Coordinate Time-Zone Resolution

/// Serializes access to the package's bundled time-zone boundary databases.
///
/// WidgetKit can request multiple timelines concurrently. Keeping the lookup
/// object actor-isolated avoids concurrent access to its C database handles and
/// avoids reopening the bundled databases for every forecast request.
actor WidgetTimeZoneResolver {
    static let shared = WidgetTimeZoneResolver()

    private let lookup: SwiftTimeZoneLookup?

    private init() {
        lookup = try? SwiftTimeZoneLookup()
    }

    /// Returns a Foundation time zone only when the coordinate and the package's
    /// IANA identifier are both valid. No approximate longitude fallback is used.
    func timeZone(latitude: Double, longitude: Double) -> TimeZone? {
        guard latitude.isFinite,
              longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude),
              let identifier = lookup?.simple(
                  latitude: Float(latitude),
                  longitude: Float(longitude)
              ),
              let timeZone = TimeZone(identifier: identifier) else {
            return nil
        }
        return timeZone
    }
}

// MARK: - Current-Location Metadata

/// Optional reverse-geocoded fields for a fresh widget-owned coordinate.
struct WidgetCurrentLocationMetadata: Sendable {
    let cityName: String?
    let timeZoneIdentifier: String?

    init(cityName: String?, timeZoneIdentifier: String?) {
        self.cityName = Self.localityName(from: cityName)
        self.timeZoneIdentifier = Self.validTimeZoneIdentifier(
            timeZoneIdentifier
        )
    }

    var hasAnyValue: Bool {
        cityName != nil || timeZoneIdentifier != nil
    }

    var isComplete: Bool {
        cityName != nil && timeZoneIdentifier != nil
    }

    func fillingMissingFields(
        from other: WidgetCurrentLocationMetadata
    ) -> WidgetCurrentLocationMetadata {
        WidgetCurrentLocationMetadata(
            cityName: cityName ?? other.cityName,
            timeZoneIdentifier:
                timeZoneIdentifier ?? other.timeZoneIdentifier
        )
    }

    static let empty = WidgetCurrentLocationMetadata(
        cityName: nil,
        timeZoneIdentifier: nil
    )

    /// Matches `CurrentLocationMetadata` in the containing app: Apple's
    /// composite locality values are reduced to their leading locality.
    private static func localityName(from value: String?) -> String? {
        guard let trimmed = clean(value) else { return nil }
        let separators = CharacterSet(charactersIn: ",，、;；")
        guard let separator = trimmed.rangeOfCharacter(from: separators) else {
            return trimmed
        }

        return clean(String(trimmed[..<separator.lowerBound]))
    }

    private static func validTimeZoneIdentifier(_ identifier: String?) -> String? {
        guard let identifier = clean(identifier),
              TimeZone(identifier: identifier) != nil else {
            return nil
        }
        return identifier
    }

    private static func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !value.isEmpty else {
            return nil
        }
        return value
    }
}

// MARK: - Bounded Reverse Geocoding

/// Bounded Apple metadata chain owned by one provider callback. MapKit supplies
/// the same canonical city component preferred by the app; Core Location fills
/// any missing city or time-zone field. One timeout cancels the whole chain so a
/// metadata outage cannot consume the widget's WeatherKit execution window.
@MainActor
final class WidgetCurrentLocationMetadataResolver {
    private let geocoder = CLGeocoder()
    private var continuation: CheckedContinuation<WidgetCurrentLocationMetadata?, Never>?
    private var geocodeTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var cancelMapKitRequest: (() -> Void)?

    static func resolve(
        _ location: CLLocation,
        locale: Locale,
        timeout: Duration
    ) async -> WidgetCurrentLocationMetadata? {
        guard timeout > .zero else { return nil }
        let resolver = WidgetCurrentLocationMetadataResolver()
        return await resolver.resolve(
            location,
            locale: locale,
            timeout: timeout
        )
    }

    private func resolve(
        _ location: CLLocation,
        locale: Locale,
        timeout: Duration
    ) async -> WidgetCurrentLocationMetadata? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                guard !Task.isCancelled else {
                    finish(with: nil)
                    return
                }

                geocodeTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    var metadata = WidgetCurrentLocationMetadata.empty

                    if #available(iOS 26.0, *) {
                        do {
                            metadata = try await mapKitMetadata(
                                for: location,
                                locale: locale
                            )
                        } catch {
                            // Core Location below remains an independent Apple
                            // source for this exact coordinate.
                        }
                    }

                    guard !Task.isCancelled else {
                        finish(with: nil)
                        return
                    }

                    // A partial MapKit result must not suppress a valid locality
                    // or time zone available from Core Location.
                    if !metadata.isComplete {
                        do {
                            let coreMetadata = try await coreLocationMetadata(
                                for: location,
                                locale: locale
                            )
                            metadata = metadata.fillingMissingFields(
                                from: coreMetadata
                            )
                        } catch {
                            // Preserve any factual field MapKit already supplied.
                        }
                    }

                    guard !Task.isCancelled else {
                        finish(with: nil)
                        return
                    }
                    finish(with: metadata.hasAnyValue ? metadata : nil)
                }

                timeoutTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    self?.finish(with: nil)
                }
            }
        } onCancel: { [self] in
            Task { @MainActor in
                finish(with: nil)
            }
        }
    }

    private func finish(with metadata: WidgetCurrentLocationMetadata?) {
        guard let continuation else { return }
        self.continuation = nil
        cancelMapKitRequest?()
        cancelMapKitRequest = nil
        geocoder.cancelGeocode()
        geocodeTask?.cancel()
        timeoutTask?.cancel()
        geocodeTask = nil
        timeoutTask = nil
        continuation.resume(returning: metadata)
    }

    /// Uses only MapKit's city address component. A POI or street-level
    /// `mapItem.name` is not a city and must never become the widget title.
    @available(iOS 26.0, *)
    private func mapKitMetadata(
        for location: CLLocation,
        locale: Locale
    ) async throws -> WidgetCurrentLocationMetadata {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            throw WidgetCurrentLocationMetadataError.requestUnavailable
        }
        request.preferredLocale = locale
        cancelMapKitRequest = { request.cancel() }
        defer { cancelMapKitRequest = nil }

        guard let mapItem = try await request.mapItems.first else {
            throw WidgetCurrentLocationMetadataError.noResult
        }
        let metadata = WidgetCurrentLocationMetadata(
            cityName: mapItem.addressRepresentations?.cityName,
            timeZoneIdentifier: mapItem.timeZone?.identifier
        )
        guard metadata.hasAnyValue else {
            throw WidgetCurrentLocationMetadataError.noResult
        }
        return metadata
    }

    /// Uses Core Location only as a fallback/fill source, retaining the app's
    /// rule that administrative areas are not substitutes for a real locality.
    private func coreLocationMetadata(
        for location: CLLocation,
        locale: Locale
    ) async throws -> WidgetCurrentLocationMetadata {
        guard let placemark = try await geocoder.reverseGeocodeLocation(
            location,
            preferredLocale: locale
        ).first else {
            throw WidgetCurrentLocationMetadataError.noResult
        }
        let metadata = WidgetCurrentLocationMetadata(
            cityName: placemark.locality,
            timeZoneIdentifier: placemark.timeZone?.identifier
        )
        guard metadata.hasAnyValue else {
            throw WidgetCurrentLocationMetadataError.noResult
        }
        return metadata
    }
}

private enum WidgetCurrentLocationMetadataError: Error {
    case requestUnavailable
    case noResult
}

// MARK: - Current-Location Acquisition

/// Device-location facts resolved entirely inside the widget extension.
struct WidgetCurrentLocationContext: Sendable {
    let latitude: Double
    let longitude: Double
    let cityName: String?
    let timeZoneIdentifier: String?
}

/// Shares one location and metadata request across a WidgetKit family batch.
actor WidgetCurrentLocationRequestCoordinator {
    static let shared = WidgetCurrentLocationRequestCoordinator()

    private let requests = WidgetRequestCoordinator<
        String,
        WidgetCurrentLocationContext
    >(completedReuseInterval: .seconds(30))

    func currentContext(
        locationTimeout: Duration,
        metadataTimeout: Duration,
        locale: Locale
    ) async throws -> WidgetCurrentLocationContext {
        try await requests.value(for: locale.identifier) {
            try await WidgetCurrentLocationResolver.currentContext(
                locationTimeout: locationTimeout,
                metadataTimeout: metadataTimeout,
                locale: locale
            )
        }
    }
}

/// Stable failures callers can translate into widget fallback behavior.
enum WidgetCurrentLocationError: Error, Equatable, Sendable {
    /// The containing app has not granted location access to widget updates.
    case widgetUpdatesNotAuthorized
    /// Core Location completed without a usable coordinate.
    case locationUnavailable
    /// Neither Apple metadata nor the bundled coordinate database could
    /// identify the coordinate's time zone.
    case timeZoneUnavailable
    /// Core Location did not complete within the widget's execution window.
    case timedOut
}

/// Performs a single, bounded Core Location request for WidgetKit timelines.
///
/// The containing app owns the system permission prompt. This resolver never
/// asks for authorization; it only proceeds when iOS says widget updates may
/// use location. A fresh resolver backs each request so delegate callbacks and
/// cancellation cannot leak between concurrent timeline generations.
@MainActor
final class WidgetCurrentLocationResolver: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var timeoutTask: Task<Void, Never>?

    private override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Rechecks authorization immediately before a freshly fetched forecast is
    /// persisted. Permission can change while WeatherKit is suspended.
    static func widgetUpdatesAuthorized() -> Bool {
        CLLocationManager().isAuthorizedForWidgetUpdates
    }

    /// Resolves a fresh coordinate and, within a separate short deadline, the
    /// city/time-zone facts needed to keep a travelling Current Location widget
    /// truthful without reopening the containing app. Metadata failure is
    /// nonfatal; callers can use a generic label and device timezone fallback.
    static func currentContext(
        locationTimeout: Duration = .seconds(5),
        metadataTimeout: Duration = .seconds(3),
        locale: Locale = .autoupdatingCurrent
    ) async throws -> WidgetCurrentLocationContext {
        let resolver = WidgetCurrentLocationResolver()
        let location = try await resolver.requestCurrentLocation(
            timeout: locationTimeout
        )
        try Task.checkCancellation()
        let metadata = await WidgetCurrentLocationMetadataResolver.resolve(
            location,
            locale: locale,
            timeout: metadataTimeout
        )
        try Task.checkCancellation()
        return WidgetCurrentLocationContext(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            cityName: metadata?.cityName,
            timeZoneIdentifier: metadata?.timeZoneIdentifier
        )
    }

    private func requestCurrentLocation(timeout: Duration) async throws -> CLLocation {
        try Task.checkCancellation()
        guard timeout > .zero else {
            throw WidgetCurrentLocationError.timedOut
        }

        guard manager.isAuthorizedForWidgetUpdates else {
            throw WidgetCurrentLocationError.widgetUpdatesNotAuthorized
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation

                guard !Task.isCancelled else {
                    finish(with: .failure(CancellationError()))
                    return
                }

                timeoutTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    self?.finish(with: .failure(WidgetCurrentLocationError.timedOut))
                }

                manager.requestLocation()
            }
        } onCancel: { [self] in
            Task { @MainActor in
                finish(with: .failure(CancellationError()))
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let now = Date()
        guard let location = locations.last(where: {
            let age = now.timeIntervalSince($0.timestamp)
            return $0.horizontalAccuracy >= 0
                && $0.horizontalAccuracy <= 5_000
                && CLLocationCoordinate2DIsValid($0.coordinate)
                && age >= -5
                && age <= 2 * 60
        }) else {
            finish(with: .failure(WidgetCurrentLocationError.locationUnavailable))
            return
        }

        finish(with: .success(location))
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        if let locationError = error as? CLError,
           locationError.code == .denied {
            finish(with: .failure(WidgetCurrentLocationError.widgetUpdatesNotAuthorized))
        } else {
            finish(with: .failure(WidgetCurrentLocationError.locationUnavailable))
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil,
              !manager.isAuthorizedForWidgetUpdates else {
            return
        }
        finish(with: .failure(WidgetCurrentLocationError.widgetUpdatesNotAuthorized))
    }

    // MARK: - Completion

    /// Completes at most once across success, failure, timeout, and cancellation.
    private func finish(with result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        manager.stopUpdatingLocation()
        manager.delegate = nil
        continuation.resume(with: result)
    }
}

// MARK: - Provider Device-Location Adaptation

/// Device-location identity resolved for the exact current coordinate.
struct WidgetResolvedDeviceLocationCity {
    let city: WidgetDataCity
    /// True only when this request produced a nonempty locality in the app's
    /// selected language.
    let hasFreshResolvedCityName: Bool
}

extension SunnyHoursLockScreenProvider {
    /// Updates the label and timezone after travel. If metadata briefly fails
    /// without meaningful movement, the last published identity remains safe;
    /// after a move, neutral copy and the local timezone database prevent the
    /// new coordinate from being labelled as the former city.
    func resolvedDeviceLocationCity(
        replacing publishedCity: WidgetDataCity,
        languageIdentifier: String
    ) async throws -> WidgetResolvedDeviceLocationCity {
        let context = try await WidgetCurrentLocationRequestCoordinator.shared
            .currentContext(
                locationTimeout: .seconds(5),
                metadataTimeout: .seconds(3),
                locale: Locale(identifier: languageIdentifier)
            )
        let newLocation = CLLocation(
            latitude: context.latitude,
            longitude: context.longitude
        )
        let publishedLocation = publishedCity.latitude.flatMap { latitude in
            publishedCity.longitude.map { longitude in
                CLLocation(latitude: latitude, longitude: longitude)
            }
        }
        let movedMeaningfully = publishedLocation.map {
            $0.distance(from: newLocation) > 2_000
        } ?? true

        let resolvedName = context.cityName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let freshResolvedName = resolvedName.flatMap { $0.isEmpty ? nil : $0 }
        let cityName = freshResolvedName
            ?? (movedMeaningfully
                ? widgetLocalizedString("Current Location")
                : publishedCity.cityName)

        let geocodedTimeZone = context.timeZoneIdentifier.flatMap {
            TimeZone(identifier: $0)?.identifier
        }
        let coordinateTimeZone: String?
        if geocodedTimeZone == nil {
            coordinateTimeZone = await WidgetTimeZoneResolver.shared.timeZone(
                latitude: context.latitude,
                longitude: context.longitude
            )?.identifier
        } else {
            coordinateTimeZone = nil
        }
        let retainedTimeZone = movedMeaningfully
            ? nil
            : publishedCity.timeZoneIdentifier.flatMap {
                TimeZone(identifier: $0)?.identifier
            }
        guard let timeZoneIdentifier = geocodedTimeZone
            ?? coordinateTimeZone
            ?? retainedTimeZone else {
            throw WidgetCurrentLocationError.timeZoneUnavailable
        }

        return WidgetResolvedDeviceLocationCity(
            city: WidgetDataCity(
                id: WidgetDataStore.currentLocationIdentifier,
                cityName: cityName,
                timeZoneIdentifier: timeZoneIdentifier,
                latitude: context.latitude,
                longitude: context.longitude
            ),
            hasFreshResolvedCityName: freshResolvedName != nil
        )
    }

    /// Uses the extension's last verified Current Location response when a new
    /// Core Location fix fails. Older snapshots must remain within the app's
    /// two-kilometre jitter bound; generation-tagged snapshots may follow travel
    /// farther away while the app's published Current Location identity remains
    /// unchanged. Both paths verify the source, timezone, reset epoch, and cache
    /// age, so neither can borrow Home or Saved Place weather. A short retry
    /// remains in force so live position is preferred as soon as it is available.
    func transientCurrentLocationFallback(
        for publishedCity: WidgetDataCity,
        defaultLocationKind: WidgetDefaultLocationKind?,
        selectionIdentity: WidgetSelectionIdentity,
        configuration: SunnyHoursLockScreenConfigurationIntent
    ) async -> WidgetRefreshResult {
        let authorizationFailure = await currentLocationAuthorizationFailure(
            for: publishedCity,
            whenRequired: true
        )
        guard selectionStillMatches(
            selectionIdentity,
            configuration: configuration,
            resolvesDeviceLocation: true
        ) else {
            return resultForCurrentSelection(configuration)
        }
        if let authorizationFailure {
            WidgetForecastStore.removeSnapshot(
                for: WidgetDataStore.currentLocationIdentifier
            )
            return authorizationFailure
        }
        if let cached = cityUsingFallbackWidgetSnapshot(
            for: publishedCity,
            defaultLocationKind: defaultLocationKind
        ) {
            return WidgetRefreshResult(
                city: cached.city,
                snapshot: cached.snapshot,
                reloadPolicy: .transientFailure
            )
        }
        if let cached = latestVerifiedDeviceLocationFallback(
            defaultLocationKind: defaultLocationKind
        ) {
            return WidgetRefreshResult(
                city: cached.city,
                snapshot: cached.snapshot,
                reloadPolicy: .transientFailure
            )
        }

        // Without a source- and identity-verified snapshot, retain no weather
        // rather than displaying a potentially different city.
        return WidgetRefreshResult(
            city: publishedCity.markingUnavailable(
                .unresolvedPlace("widget current location")
            ),
            snapshot: nil,
            reloadPolicy: .transientFailure
        )
    }

    /// Checks permission immediately before any cached device-coordinate value
    /// can be displayed. A timeout and a revocation callback can race, so the
    /// earlier Core Location error alone is not a sufficient authorization fact.
    func currentLocationAuthorizationFailure(
        for city: WidgetDataCity,
        whenRequired: Bool
    ) async -> WidgetRefreshResult? {
        guard whenRequired else { return nil }
        let remainsAuthorized = await WidgetCurrentLocationResolver
            .widgetUpdatesAuthorized()
        guard !remainsAuthorized else { return nil }

        return WidgetRefreshResult(
            city: city.markingUnavailable(
                .unresolvedPlace("widget current location permission")
            ),
            snapshot: nil,
            reloadPolicy: .persistentFailure
        )
    }

    /// Accepts an extension-owned coordinate beyond the app catalog's ordinary
    /// two-kilometre jitter bound only when both sides still share the exact
    /// Current Location generation. This covers travel while the app stays
    /// closed; a later app-published location changes the generation and makes
    /// the older extension snapshot ineligible immediately.
    private func latestVerifiedDeviceLocationFallback(
        defaultLocationKind: WidgetDefaultLocationKind?
    ) -> WidgetAppliedSnapshot? {
        guard defaultLocationKind == .currentLocation,
              let catalog = WidgetDataStore.catalog(),
              catalog.resolvedDefaultLocationKind == .currentLocation,
              let generation = catalog.currentLocationGeneration,
              let snapshot = WidgetForecastStore.fallbackSnapshot(
                  forAny: [WidgetDataStore.currentLocationIdentifier],
                  matching: {
                      $0.locationSource == .deviceCurrentLocation
                          && $0.currentLocationGeneration == generation
                          && validCoordinate(
                              latitude: $0.latitude,
                              longitude: $0.longitude
                          )
                  }
              ),
              let latitude = snapshot.latitude,
              let longitude = snapshot.longitude,
              let timeZoneIdentifier = snapshot.timeZoneIdentifier else {
            return nil
        }

        let localizedSnapshotName: String? = {
            guard snapshot.cityNameLocaleIdentifier
                    == WidgetDataStore.appLocale.identifier,
                  let name = snapshot.resolvedCityName?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else {
                return nil
            }
            return name
        }()
        let cachedIdentity = WidgetDataCity(
            id: WidgetDataStore.currentLocationIdentifier,
            cityName: localizedSnapshotName
                ?? widgetLocalizedString("Current Location"),
            timeZoneIdentifier: timeZoneIdentifier,
            latitude: latitude,
            longitude: longitude
        )
        guard let cachedCity = cachedIdentity.applying(
            snapshot,
            preservesResolvedCityName: true
        ), cachedCity.widgetCurrentIssue == nil else {
            return nil
        }
        return WidgetAppliedSnapshot(city: cachedCity, snapshot: snapshot)
    }

    private func validCoordinate(
        latitude: Double?,
        longitude: Double?
    ) -> Bool {
        guard let latitude,
              let longitude,
              latitude.isFinite,
              longitude.isFinite else {
            return false
        }
        return CLLocationCoordinate2DIsValid(
            CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            )
        )
    }
}
