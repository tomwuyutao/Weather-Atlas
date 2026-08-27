//
//  WidgetCurrentLocationResolver.swift
//  WeatherWidgets
//
//  Purpose: Resolves one current device location inside the widget extension.
//

@preconcurrency import CoreLocation
import Foundation
import MapKit

/// Device-location facts resolved entirely inside the widget extension.
struct WidgetCurrentLocationContext: Sendable {
    let latitude: Double
    let longitude: Double
    let locationTimestamp: Date
    let cityName: String?
    let timeZoneIdentifier: String?
}

/// Makes one caller's wait cancellation-responsive without cancelling the
/// shared Core Location operation other Home/Lock Screen timelines still use.
/// The observer may finish later, but completion is idempotent after the
/// caller's continuation has already been resumed by cancellation.
private actor WidgetCurrentLocationTaskWaiter {
    private var continuation: CheckedContinuation<
        WidgetCurrentLocationContext,
        Error
    >?
    private var observerTask: Task<Void, Never>?
    private var cancellationRequested = false

    func value(
        of task: Task<WidgetCurrentLocationContext, Error>
    ) async throws -> WidgetCurrentLocationContext {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                install(continuation, task: task)
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    private func install(
        _ continuation: CheckedContinuation<
            WidgetCurrentLocationContext,
            Error
        >,
        task: Task<WidgetCurrentLocationContext, Error>
    ) {
        guard !cancellationRequested else {
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        observerTask = Task.detached(priority: .utility) { [self] in
            do {
                await finish(.success(try await task.value))
            } catch {
                await finish(.failure(error))
            }
        }
    }

    private func finish(
        _ result: Result<WidgetCurrentLocationContext, Error>
    ) {
        guard let continuation else { return }
        self.continuation = nil
        observerTask?.cancel()
        observerTask = nil
        continuation.resume(with: result)
    }

    private func cancel() {
        cancellationRequested = true
        finish(.failure(CancellationError()))
    }
}

/// Shares one extension-owned Core Location + geocoding operation across
/// simultaneous Home and Lock Screen widget callbacks. The exact successful
/// context is returned to every waiter, so their WeatherKit request keys remain
/// identical instead of diverging through normal GPS jitter or timestamps.
actor WidgetCurrentLocationRequestCoordinator {
    static let shared = WidgetCurrentLocationRequestCoordinator()

    private struct InFlightRequest {
        let id: UUID
        let task: Task<WidgetCurrentLocationContext, Error>
        var waiterIDs: Set<UUID>
    }

    private struct CompletedRequest {
        let context: WidgetCurrentLocationContext
        let completedAt: ContinuousClock.Instant
    }

    private var inFlight: [String: InFlightRequest] = [:]
    private var recentlyCompleted: [String: CompletedRequest] = [:]
    /// WidgetKit commonly asks each installed family for its timeline in a
    /// sequential batch. Keep one exact coordinate through the provider's
    /// 24-second forecast budget, plus a small scheduling margin, so a later
    /// family cannot miss request coalescing solely because Core Location gave
    /// the same place a newer timestamp. Thirty seconds is still far shorter
    /// than WidgetKit's refresh cadence and does not meaningfully mask travel.
    private let completedReuseInterval: Duration = .seconds(30)

    func currentContext(
        locationTimeout: Duration,
        metadataTimeout: Duration,
        locale: Locale
    ) async throws -> WidgetCurrentLocationContext {
        try Task.checkCancellation()
        let key = locale.identifier
        let now = ContinuousClock.now
        recentlyCompleted = recentlyCompleted.filter {
            let age = $0.value.completedAt.duration(to: now)
            return age >= .zero && age < completedReuseInterval
        }
        if let completed = recentlyCompleted[key] {
            try Task.checkCancellation()
            return completed.context
        }

        let waiterID = UUID()
        let request: InFlightRequest
        if var existing = inFlight[key] {
            existing.waiterIDs.insert(waiterID)
            inFlight[key] = existing
            request = existing
        } else {
            let id = UUID()
            let task = Task<WidgetCurrentLocationContext, Error> {
                try await WidgetCurrentLocationResolver.currentContext(
                    locationTimeout: locationTimeout,
                    metadataTimeout: metadataTimeout,
                    locale: locale
                )
            }
            request = InFlightRequest(
                id: id,
                task: task,
                waiterIDs: [waiterID]
            )
            inFlight[key] = request
        }

        do {
            let context = try await WidgetCurrentLocationTaskWaiter().value(
                of: request.task
            )
            if inFlight[key]?.id == request.id {
                inFlight[key] = nil
            }
            recentlyCompleted[key] = CompletedRequest(
                context: context,
                completedAt: ContinuousClock.now
            )
            try Task.checkCancellation()
            return context
        } catch is CancellationError {
            removeWaiter(
                waiterID,
                key: key,
                requestID: request.id,
                cancelWhenEmpty: true
            )
            throw CancellationError()
        } catch {
            if inFlight[key]?.id == request.id {
                inFlight[key] = nil
            }
            throw error
        }
    }

    private func removeWaiter(
        _ waiterID: UUID,
        key: String,
        requestID: UUID,
        cancelWhenEmpty: Bool
    ) {
        guard var request = inFlight[key],
              request.id == requestID else {
            return
        }
        request.waiterIDs.remove(waiterID)
        if request.waiterIDs.isEmpty {
            if cancelWhenEmpty {
                request.task.cancel()
            }
            inFlight[key] = nil
        } else {
            inFlight[key] = request
        }
    }
}

/// Optional reverse-geocoded fields for a fresh widget-owned coordinate.
private struct WidgetCurrentLocationMetadata: Sendable {
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

/// Stable failures callers can translate into widget fallback behavior.
enum WidgetCurrentLocationError: Error, Equatable, Sendable {
    /// The containing app has not granted location access to widget updates.
    case widgetUpdatesNotAuthorized
    /// Location Services are disabled for the device.
    case locationServicesDisabled
    /// Core Location completed without a usable coordinate.
    case locationUnavailable
    /// Neither Apple metadata nor the bundled coordinate database could
    /// identify the coordinate's time zone.
    case timeZoneUnavailable
    /// Core Location did not complete within the widget's execution window.
    case timedOut
}

/// Bounds Apple's process-wide availability query independently. The system
/// documents that this synchronous call can block, so awaiting an ordinary
/// detached task would otherwise sit outside the advertised location timeout.
private actor WidgetLocationServicesAvailabilityRace {
    private var continuation: CheckedContinuation<Bool, Error>?
    private var queryTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var cancellationRequested = false

    func result(timeout: Duration) async throws -> Bool {
        try Task.checkCancellation()
        guard timeout > .zero else {
            throw WidgetCurrentLocationError.timedOut
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                install(continuation, timeout: timeout)
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    private func install(
        _ continuation: CheckedContinuation<Bool, Error>,
        timeout: Duration
    ) {
        guard !cancellationRequested else {
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        queryTask = Task.detached(priority: .utility) { [self] in
            let enabled = CLLocationManager.locationServicesEnabled()
            await finish(.success(enabled))
        }
        timeoutTask = Task.detached(priority: .utility) { [self] in
            do {
                try await Task.sleep(for: timeout)
                try Task.checkCancellation()
                await finish(.failure(WidgetCurrentLocationError.timedOut))
            } catch {
                // The availability result or caller cancellation won the race.
            }
        }
    }

    private func finish(_ result: Result<Bool, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        queryTask?.cancel()
        timeoutTask?.cancel()
        queryTask = nil
        timeoutTask = nil
        continuation.resume(with: result)
    }

    private func cancel() {
        cancellationRequested = true
        finish(.failure(CancellationError()))
    }
}

/// Performs a single, bounded Core Location request for WidgetKit timelines.
///
/// The containing app owns the system permission prompt. This resolver never
/// asks for authorization; it only proceeds when iOS says widget updates may
/// use location. A fresh resolver backs each request so delegate callbacks and
/// cancellation cannot leak between concurrent timeline generations.
@MainActor
final class WidgetCurrentLocationResolver: NSObject, CLLocationManagerDelegate {
    /// A short bound leaves the timeline provider time to fetch and render its
    /// forecast or fall back when the system cannot promptly provide location.
    nonisolated static let defaultTimeout: Duration = .seconds(8)

    private let manager: CLLocationManager
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var timeoutTask: Task<Void, Never>?

    private override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = kCLDistanceFilterNone
    }

    /// Returns one valid device location without ever presenting permission UI.
    ///
    /// - Parameter timeout: Maximum time to await Core Location. Passing zero
    ///   or a negative duration fails immediately with `.timedOut`.
    static func currentLocation(
        timeout: Duration = defaultTimeout
    ) async throws -> CLLocation {
        let resolver = WidgetCurrentLocationResolver()
        return try await resolver.requestCurrentLocation(timeout: timeout)
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
        let location = try await currentLocation(timeout: locationTimeout)
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
            locationTimestamp: location.timestamp,
            cityName: metadata?.cityName,
            timeZoneIdentifier: metadata?.timeZoneIdentifier
        )
    }

    private func requestCurrentLocation(timeout: Duration) async throws -> CLLocation {
        try Task.checkCancellation()
        guard timeout > .zero else {
            throw WidgetCurrentLocationError.timedOut
        }

        let clock = ContinuousClock()
        let startedAt = clock.now

        // Apple notes that this process-wide query can block, so keep it away
        // from the main actor and include it in the same absolute timeout.
        let servicesEnabled = try await WidgetLocationServicesAvailabilityRace()
            .result(timeout: timeout)
        try Task.checkCancellation()

        guard servicesEnabled else {
            throw WidgetCurrentLocationError.locationServicesDisabled
        }
        guard manager.isAuthorizedForWidgetUpdates else {
            throw WidgetCurrentLocationError.widgetUpdatesNotAuthorized
        }

        let remainingTimeout = timeout - startedAt.duration(to: clock.now)
        guard remainingTimeout > .zero else {
            throw WidgetCurrentLocationError.timedOut
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
                        try await Task.sleep(for: remainingTimeout)
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

/// Bounded Apple metadata chain owned by one provider callback. MapKit supplies
/// the same canonical city component preferred by the app; Core Location fills
/// any missing city or time-zone field. One timeout cancels the whole chain so a
/// metadata outage cannot consume the widget's WeatherKit execution window.
@MainActor
private final class WidgetCurrentLocationMetadataResolver {
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
