//
//  WidgetLocation.swift
//  WeatherWidgets
//
//  Purpose: Resolves device coordinates and a validated local time zone for
//  current-location widget forecasts without reverse geocoding.
//

@preconcurrency import CoreLocation
import Foundation
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
      let timeZone = TimeZone(identifier: identifier)
    else {
      return nil
    }
    return timeZone
  }
}

// MARK: - Current-Location Acquisition

/// Device-location facts resolved entirely inside the widget extension.
struct WidgetCurrentLocationContext: Sendable {
  let latitude: Double
  let longitude: Double
  let timeZoneIdentifier: String
}

/// Shares one coordinate-and-timezone request across a WidgetKit family batch.
actor WidgetCurrentLocationRequestCoordinator {
  static let shared = WidgetCurrentLocationRequestCoordinator()

  private let requests = WidgetRequestCoordinator<
    String,
    WidgetCurrentLocationContext
  >(completedReuseInterval: .seconds(30))

  /// Actor-isolated coalescing boundary for concurrent WidgetKit requests.
  /// The retained coordinator state cannot be inlined into outside callers.
  func currentContext(
    locationTimeout: Duration
  ) async throws -> WidgetCurrentLocationContext {
    try await requests.value(for: "current-location") {
      try await WidgetCurrentLocationResolver.currentContext(
        locationTimeout: locationTimeout
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
  /// The bundled coordinate database could not identify the time zone.
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

  /// Resolves a fresh coordinate and its timezone from bundled boundaries.
  /// It never performs reverse geocoding or consumes the app's shared quota.
  static func currentContext(
    locationTimeout: Duration = .seconds(5)
  ) async throws -> WidgetCurrentLocationContext {
    let resolver = WidgetCurrentLocationResolver()
    let location = try await resolver.requestCurrentLocation(
      timeout: locationTimeout
    )
    try Task.checkCancellation()
    guard
      let timeZoneIdentifier = await WidgetTimeZoneResolver.shared.timeZone(
        latitude: location.coordinate.latitude,
        longitude: location.coordinate.longitude
      )?.identifier
    else {
      throw WidgetCurrentLocationError.timeZoneUnavailable
    }
    return WidgetCurrentLocationContext(
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude,
      timeZoneIdentifier: timeZoneIdentifier
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
    guard
      let location = locations.last(where: {
        let age = now.timeIntervalSince($0.timestamp)
        return $0.horizontalAccuracy >= 0
          && $0.horizontalAccuracy <= 5_000
          && CLLocationCoordinate2DIsValid($0.coordinate)
          && age >= -5
          && age <= 2 * 60
      })
    else {
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
      locationError.code == .denied
    {
      finish(with: .failure(WidgetCurrentLocationError.widgetUpdatesNotAuthorized))
    } else {
      finish(with: .failure(WidgetCurrentLocationError.locationUnavailable))
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard continuation != nil,
      !manager.isAuthorizedForWidgetUpdates
    else {
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

extension SunnyHoursLockScreenProvider {
  /// Updates the coordinate and timezone after travel. Nearby refreshes retain
  /// the published name; meaningful moves use neutral copy so a new coordinate
  /// is never labelled as the former city.
  func resolvedDeviceLocationCity(
    replacing publishedCity: WidgetDataCity
  ) async throws -> WidgetDataCity {
    let context = try await WidgetCurrentLocationRequestCoordinator.shared
      .currentContext(
        locationTimeout: .seconds(5)
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
    let movedMeaningfully =
      publishedLocation.map {
        $0.distance(from: newLocation) > 2_000
      } ?? true

    let cityName =
      movedMeaningfully
        ? widgetLocalizedString("Current Location")
        : publishedCity.cityName

    return WidgetDataCity(
      id: WidgetDataStore.currentLocationIdentifier,
      cityName: cityName,
      timeZoneIdentifier: context.timeZoneIdentifier,
      latitude: context.latitude,
      longitude: context.longitude
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
    guard
      selectionStillMatches(
        selectionIdentity,
        configuration: configuration,
        resolvesDeviceLocation: true
      )
    else {
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
    let remainsAuthorized = await MainActor.run {
      CLLocationManager().isAuthorizedForWidgetUpdates
    }
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
      let snapshot = WidgetForecastStore.firstMatchingSnapshot(
        forAny: [WidgetDataStore.currentLocationIdentifier],
        now: .now,
        maximumAge: nil,
        matching: {
          $0.locationSource == .deviceCurrentLocation
            && $0.currentLocationGeneration == generation
            && ({ (latitude: Double?, longitude: Double?) in
              guard let latitude,
                let longitude,
                latitude.isFinite,
                longitude.isFinite
              else {
                return false
              }
              return CLLocationCoordinate2DIsValid(
                CLLocationCoordinate2D(
                  latitude: latitude,
                  longitude: longitude
                )
              )
            })($0.latitude, $0.longitude)
        }
      ),
      let latitude = snapshot.latitude,
      let longitude = snapshot.longitude,
      let timeZoneIdentifier = snapshot.timeZoneIdentifier
    else {
      return nil
    }

    let localizedSnapshotName: String? = {
      guard
        snapshot.cityNameLocaleIdentifier
          == ({
            guard
              let identifier = WidgetDataStore.catalog()?
                .appLanguageIdentifier,
              !identifier.isEmpty
            else {
              return Locale.autoupdatingCurrent
            }
            return Locale(identifier: identifier)
          })().identifier,
        let name = snapshot.resolvedCityName?
          .trimmingCharacters(in: .whitespacesAndNewlines),
        !name.isEmpty
      else {
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
    guard
      let cachedCity = cachedIdentity.applying(
        snapshot,
        preservesResolvedCityName: true
      ), cachedCity.widgetCurrentIssue == nil
    else {
      return nil
    }
    return WidgetAppliedSnapshot(city: cachedCity, snapshot: snapshot)
  }

}
