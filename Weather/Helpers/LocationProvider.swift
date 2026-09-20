//
//  LocationProvider.swift
//  Weather
//
//  Purpose: Provides an explicitly requested current coordinate and display
//  metadata without prompting for permission during initialization.
//
//  Reading guide: this is a small state machine around `CLLocationManager`.
//  It separates permission, one-shot coordinate acquisition, and reverse-
//  geocoded display metadata so the app can still use a valid coordinate when
//  Apple cannot name it.
//

// Core Location's delegate APIs predate Swift concurrency annotations.
// `@preconcurrency` imports its declarations compatibly while this main-actor
// class keeps all delegate-driven mutable state on one predictable executor.
@preconcurrency import CoreLocation
import Foundation
import MapKit
import Observation

// MARK: - Location State

/// User-visible phases of the current-location workflow.
/// These states intentionally distinguish permission failures from temporary
/// lookup failures, allowing Settings/Home to suggest the right recovery action.
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

// MARK: - Shared Location Presentation State

/// Display metadata returned by Apple's reverse geocoder for the coordinate.
/// All fields are optional because a coordinate can be precise and usable even
/// when a provider cannot supply one of these presentation-only details.
nonisolated struct CurrentLocationMetadata: Equatable, Hashable, Sendable {
  /// Concise city/locality used by ordinary place labels.
  let displayName: String?
  /// Full locality-and-area value retained for a forecast-report heading.
  let titleName: String?
  /// Geocoder-provided localized country name, when available.
  let countryName: String?
  /// Stable ISO 3166-1 alpha-2 country identity, when available.
  let isoCountryCode: String?
  /// Time zone identifier attached to the resolved place, when available.
  let timeZoneIdentifier: String?

  /// Preserve the same two-name contract used by a directly tapped Map
  /// location: ordinary labels receive the leading locality, while report
  /// headings retain Apple's complete locality-and-area value.
  init(
    displayName: String?,
    titleName: String? = nil,
    countryName: String?,
    isoCountryCode: String?,
    timeZoneIdentifier: String?
  ) {
    let normalizedDisplayName = displayName.flatMap {
      let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
      return value.isEmpty ? nil : value
    }
    let normalizedTitleName =
      titleName.flatMap {
        let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
      } ?? normalizedDisplayName
    self.displayName = Self.localityName(
      from: normalizedDisplayName ?? normalizedTitleName
    )
    self.titleName = normalizedTitleName
    self.countryName = countryName
    let normalizedISO2Code = isoCountryCode?.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).uppercased()
    self.isoCountryCode =
      normalizedISO2Code?.count == 2
      ? normalizedISO2Code
      : nil
    self.timeZoneIdentifier = timeZoneIdentifier
  }

  /// Apple can return values such as "Southwark, London" for a precise
  /// location. Keep the locality before a geographic separator for ordinary
  /// place labels; callers that need a report title retain the original.
  static func localityName(from value: String?) -> String? {
    guard
      let trimmed = value?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ), !trimmed.isEmpty
    else {
      return nil
    }

    let separators = CharacterSet(charactersIn: ",，、;；")
    guard let separator = trimmed.rangeOfCharacter(from: separators) else {
      return trimmed
    }

    let locality = trimmed[..<separator.lowerBound].trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    return locality.isEmpty ? nil : locality
  }

  static let empty = CurrentLocationMetadata(
    displayName: nil,
    countryName: nil,
    isoCountryCode: nil,
    timeZoneIdentifier: nil
  )
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
/// `NSObject` is required because Core Location talks back through an Objective-
/// C delegate. `@Observable` exposes only the state that SwiftUI reads; private
/// manager/task references are explicitly ignored by the observation system.
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
  /// Metadata is not required: weather and nearby-place queries use latitude /
  /// longitude, so a reverse-geocoding outage should not disable them.
  var hasUsableCoordinate: Bool {
    coordinate.map(CLLocationCoordinate2DIsValid) == true
  }

  /// True while a manually chosen home location is supplying the app's
  /// location. Core Location callbacks must not replace that choice later.
  private(set) var isUsingHomeLocation = false

  // MARK: - Core Location Dependencies and Task State

  /// System manager retained for delegate callbacks.
  @ObservationIgnored let manager: CLLocationManager
  /// Pre-iOS 26 reverse geocoder retained so prior work can be cancelled.
  @ObservationIgnored private let geocoder = CLGeocoder()
  /// Current display-metadata resolution task.
  @ObservationIgnored private var metadataTask: Task<Void, Never>?
  /// Off-main device-wide Location Services check.
  @ObservationIgnored private var availabilityTask: Task<Void, Never>?
  /// Whether authorization was requested as part of a location action.
  @ObservationIgnored private var locateAfterAuthorization = false
  /// Whether the active one-shot request should also resolve display metadata.
  /// Launch and foreground refreshes need only coordinates; keeping those
  /// requests coordinate-only preserves the geocoding budget for user actions.
  @ObservationIgnored private var resolvesMetadataAfterLocation = true
  /// Locale requested by the app's currently selected language.
  @ObservationIgnored private var preferredLocale = Locale.autoupdatingCurrent

  /// Installs the delegate and mirrors existing authorization without
  /// initiating a permission request.
  override init() {
    manager = CLLocationManager()
    super.init()
    // Merely configuring/querying authorization never shows the permission
    // prompt. The prompt is deferred to an explicit user-driven request.
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    manager.distanceFilter = kCLDistanceFilterNone
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse, .notDetermined:
      status = coordinate == nil ? .idle : status
    case .denied:
      clearPublishedLocation(status: .denied)
    case .restricted:
      clearPublishedLocation(status: .restricted)
    @unknown default:
      clearPublishedLocation(status: .failed)
    }
  }

  deinit {
    // The provider can disappear while either async helper is suspended.
    // Cancel work and a legacy geocode so it cannot update stale state.
    availabilityTask?.cancel()
    metadataTask?.cancel()
    geocoder.cancelGeocode()
  }

  // MARK: - Public Location Requests

  /// Starts the contextual authorization or one-shot location flow.
  func requestCurrentLocation(
    preferredLocale: Locale = .autoupdatingCurrent,
    resolvePlaceMetadata: Bool = true
  ) {
    isUsingHomeLocation = false
    self.preferredLocale = preferredLocale
    resolvesMetadataAfterLocation = resolvePlaceMetadata
    // A newer request supersedes pending availability/metadata work. This
    // prevents an old location from replacing a more recent user action.
    availabilityTask?.cancel()
    metadataTask?.cancel()
    geocoder.cancelGeocode()
    status = .checkingAvailability

    // Apple documents that this process-wide check can block briefly.
    // Keep that work away from the main actor before invoking any manager
    // APIs that may display authorization UI.
    availabilityTask = Task { [weak self] in
      // `Task` returns to the main actor after awaiting the detached check,
      // so assignments to observable state below remain actor-safe.
      let servicesEnabled = await Task.detached(priority: .userInitiated) {
        CLLocationManager.locationServicesEnabled()
      }.value
      guard let self, !Task.isCancelled else { return }
      guard servicesEnabled else {
        clearPublishedLocation(status: .servicesDisabled)
        return
      }
      continueRequest()
    }
  }

  /// Publishes a resolved city as the app's stable home location without
  /// requesting system permission. This lets every current-location surface
  /// share its existing weather and map workflow with a manual home choice.
  func useHomeLocation(_ city: City) {
    availabilityTask?.cancel()
    metadataTask?.cancel()
    geocoder.cancelGeocode()
    locateAfterAuthorization = false
    isUsingHomeLocation = true
    coordinate = CLLocationCoordinate2D(
      latitude: city.latitude,
      longitude: city.longitude
    )
    metadata = CurrentLocationMetadata(
      displayName: city.name,
      titleName: city.titleName,
      countryName: city.country,
      isoCountryCode: countryISO2Code(representedBy: city),
      timeZoneIdentifier: city.timeZoneIdentifier
    )
    status = .ready
  }

  /// Clears a previously published device or home coordinate. System
  /// authorization itself remains untouched, which is the only state iOS
  /// permits an app to retain during a reset.
  func clearLocation() {
    availabilityTask?.cancel()
    metadataTask?.cancel()
    geocoder.cancelGeocode()
    locateAfterAuthorization = false
    isUsingHomeLocation = false
    coordinate = nil
    metadata = nil
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse, .notDetermined:
      status = coordinate == nil ? .idle : status
    case .denied:
      clearPublishedLocation(status: .denied)
    case .restricted:
      clearPublishedLocation(status: .restricted)
    @unknown default:
      clearPublishedLocation(status: .failed)
    }
  }

  // MARK: - CLLocationManager Delegate Callbacks

  /// Mirrors changes made in the system authorization prompt or Settings.
  /// Core Location may call this both after the initial system prompt and when
  /// the person later changes permission in Settings.
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard !isUsingHomeLocation else { return }
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      if locateAfterAuthorization {
        locateAfterAuthorization = false
        status = .locating
        manager.requestLocation()
      } else if coordinate == nil {
        status = .idle
      }
    case .notDetermined:
      status = locateAfterAuthorization ? .requestingAuthorization : .idle
    case .denied:
      locateAfterAuthorization = false
      clearPublishedLocation(status: .denied)
    case .restricted:
      locateAfterAuthorization = false
      clearPublishedLocation(status: .restricted)
    @unknown default:
      locateAfterAuthorization = false
      clearPublishedLocation(status: .failed)
    }
  }

  /// Accepts the newest valid location from the one-shot callback.
  /// A one-shot request can still deliver multiple candidates; the last valid
  /// value is normally Core Location's most recent/best refinement.
  func locationManager(
    _ manager: CLLocationManager,
    didUpdateLocations locations: [CLLocation]
  ) {
    guard !isUsingHomeLocation else { return }
    guard
      let location = locations.last(where: {
        $0.horizontalAccuracy >= 0
          && CLLocationCoordinate2DIsValid($0.coordinate)
      })
    else {
      clearPublishedLocation(status: .failed)
      return
    }

    // Publish the coordinate first so WeatherKit can start immediately.
    coordinate = location.coordinate
    metadata = nil

    // Automatic launch and foreground refreshes deliberately stop here.
    // A coordinate is sufficient for forecasts, and avoiding place-name work
    // keeps Apple's reverse-geocoding quota available for direct user queries.
    guard resolvesMetadataAfterLocation else {
      status = .readyWithoutMetadata
      return
    }

    status = .resolvingPlace
    metadataTask?.cancel()
    metadataTask = Task { [weak self] in
      guard let self else { return }
      await self.resolveMetadataOnce(for: location)
    }
  }

  /// Converts Core Location failures into stable states rather than exposing
  /// provider-localized error text directly in the UI.
  func locationManager(
    _ manager: CLLocationManager,
    didFailWithError error: Error
  ) {
    guard !isUsingHomeLocation else { return }
    if let locationError = error as? CLError {
      // iOS 18 can finish a one-shot request by reporting `.locationUnknown`
      // immediately after delivering a valid coordinate. That transient
      // callback must not erase the successful result already on screen.
      if locationError.code == .locationUnknown, hasUsableCoordinate {
        return
      }
      guard locationError.code == .denied else {
        clearPublishedLocation(status: .failed)
        return
      }
      switch manager.authorizationStatus {
      case .authorizedAlways, .authorizedWhenInUse, .notDetermined:
        status = coordinate == nil ? .idle : status
      case .denied:
        clearPublishedLocation(status: .denied)
      case .restricted:
        clearPublishedLocation(status: .restricted)
      @unknown default:
        clearPublishedLocation(status: .failed)
      }
      return
    }
    clearPublishedLocation(status: .failed)
  }

  // MARK: - Authorization and One-Shot Flow

  /// Reads current authorization without prompting or starting updates.

  /// Continues on the main actor after device-wide availability is known.
  /// Only the `.notDetermined` branch asks iOS to show the permission prompt.
  private func continueRequest() {
    switch manager.authorizationStatus {
    case .notDetermined:
      locateAfterAuthorization = true
      status = .requestingAuthorization
      manager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      status = .locating
      manager.requestLocation()
    case .denied:
      clearPublishedLocation(status: .denied)
    case .restricted:
      clearPublishedLocation(status: .restricted)
    @unknown default:
      clearPublishedLocation(status: .failed)
    }
  }

  /// Permission and request failures invalidate the meaning of a previously
  /// published coordinate as "current." Clearing both values prevents stale
  /// location data from continuing to drive weather or nearby searches.
  private func clearPublishedLocation(status: LocationProviderStatus) {
    metadataTask?.cancel()
    geocoder.cancelGeocode()
    coordinate = nil
    metadata = nil
    self.status = status
  }

  // MARK: - Reverse-Geocoded Display Metadata

  /// Performs one full factual metadata pass. Keeping publication in this
  /// awaited helper keeps the delegate callback small and cancellation-safe.
  private func resolveMetadataOnce(for location: CLLocation) async {
    var resolvedMetadata = CurrentLocationMetadata.empty
    do {
      if #available(iOS 26.0, *) {
        do {
          resolvedMetadata = try await mapKitMetadata(for: location)
        } catch {
          // Core Location below remains a second authoritative source
          // for this exact coordinate.
        }
      }

      // A partial MapKit result must not suppress a valid locality,
      // country, or timezone available from Core Location.
      if resolvedMetadata.displayName == nil
        || resolvedMetadata.countryName == nil
        || resolvedMetadata.timeZoneIdentifier == nil
        || resolvedMetadata.isoCountryCode == nil
      {
        let coreMetadata = try await coreLocationMetadata(for: location)
        resolvedMetadata = CurrentLocationMetadata(
          displayName: resolvedMetadata.displayName
            ?? coreMetadata.displayName,
          titleName: resolvedMetadata.titleName
            ?? coreMetadata.titleName,
          countryName: resolvedMetadata.countryName
            ?? coreMetadata.countryName,
          isoCountryCode: resolvedMetadata.isoCountryCode
            ?? coreMetadata.isoCountryCode,
          timeZoneIdentifier: resolvedMetadata.timeZoneIdentifier
            ?? coreMetadata.timeZoneIdentifier
        )
      }
      // Awaited APIs may finish after cancellation, so check again
      // immediately before publishing their result into SwiftUI state.
      guard !Task.isCancelled else { return }
      metadata =
        resolvedMetadata.displayName != nil
          || resolvedMetadata.countryName != nil
          || resolvedMetadata.isoCountryCode != nil
          || resolvedMetadata.timeZoneIdentifier != nil
        ? resolvedMetadata
        : nil
      status =
        resolvedMetadata.displayName != nil
          && resolvedMetadata.countryName != nil
          && resolvedMetadata.timeZoneIdentifier != nil
        ? .ready
        : .readyWithoutMetadata
    } catch is CancellationError {
      return
    } catch {
      guard !Task.isCancelled else { return }
      // Retain factual MapKit fields if Core Location failed after a
      // partial response; only the absent fields remain blank.
      metadata =
        resolvedMetadata.displayName != nil
          || resolvedMetadata.countryName != nil
          || resolvedMetadata.isoCountryCode != nil
          || resolvedMetadata.timeZoneIdentifier != nil
        ? resolvedMetadata
        : nil
      status = .readyWithoutMetadata
    }
  }

  /// Uses MapKit's modern reverse-geocoding request on iOS 26 and later.
  /// This stays in a separately availability-gated method so older iOS builds
  /// never need to link or execute the newer API.
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

    // A POI or street-level `mapItem.name` is not a city. Only a real city
    // address component is eligible for the current-location place label.
    let representations = mapItem.addressRepresentations
    let metadata = CurrentLocationMetadata(
      displayName: cleanMetadataValue(representations?.cityName),
      countryName: cleanMetadataValue(
        mapItem.placemark.country
          ?? mapItem.placemark.isoCountryCode
      ),
      isoCountryCode: cleanMetadataValue(
        mapItem.placemark.isoCountryCode
      ),
      timeZoneIdentifier: ({ (identifier: String?) -> String? in

        guard let identifier = cleanMetadataValue(identifier),
          TimeZone(identifier: identifier) != nil
        else {
          return nil
        }
        return identifier
      })(
        mapItem.timeZone?.identifier)
    )
    guard
      metadata.displayName != nil
        || metadata.countryName != nil
        || metadata.isoCountryCode != nil
        || metadata.timeZoneIdentifier != nil
    else {
      throw LocationMetadataResolutionError.noResult
    }
    return metadata
  }

  /// Uses Core Location's reverse geocoder as an independent Apple source.
  /// Wider administrative areas are deliberately not substituted for a city.
  private func coreLocationMetadata(
    for location: CLLocation
  ) async throws -> CurrentLocationMetadata {
    guard
      let placemark = try await geocoder.reverseGeocodeLocation(
        location,
        preferredLocale: preferredLocale
      ).first
    else {
      throw LocationMetadataResolutionError.noResult
    }
    let metadata = CurrentLocationMetadata(
      displayName: cleanMetadataValue(placemark.locality),
      countryName: cleanMetadataValue(
        placemark.country ?? placemark.isoCountryCode
      ),
      isoCountryCode: cleanMetadataValue(placemark.isoCountryCode),
      timeZoneIdentifier: ({ (identifier: String?) -> String? in

        guard let identifier = cleanMetadataValue(identifier),
          TimeZone(identifier: identifier) != nil
        else {
          return nil
        }
        return identifier
      })(
        placemark.timeZone?.identifier)
    )
    guard
      metadata.displayName != nil
        || metadata.countryName != nil
        || metadata.isoCountryCode != nil
        || metadata.timeZoneIdentifier != nil
    else {
      throw LocationMetadataResolutionError.noResult
    }
    return metadata
  }

  private func cleanMetadataValue(_ value: String?) -> String? {
    guard
      let value = value?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ), !value.isEmpty
    else {
      return nil
    }
    return value
  }

  /// Provider-resolved homes normally carry their ISO code directly. This
  /// deterministic catalog fallback upgrades homes saved by an older schema
  /// using exact source identity first, then an unambiguous country label in
  /// any language Weather Atlas supports. It never guesses from proximity.
  private func countryISO2Code(representedBy city: City) -> String? {
    if let code = city.countryISO2Code {
      return code
    }

    let englishLocale = Locale(identifier: "en")
    let countries = CountryCityCatalog.catalog.countriesByCode.values.sorted {
      $0.localizedName(locale: englishLocale).localizedStandardCompare(
        $1.localizedName(locale: englishLocale)
      ) == .orderedAscending
    }
    if let catalogIdentifier = city.catalogIdentifier,
      let country = countries.first(where: { country in
        country.cities.contains {
          $0.catalogIdentifier == catalogIdentifier
        }
      })
    {
      return country.iso2
    }

    return CountryCityCatalog.countryISO2Code(
      matchingCountryName: city.country
    )
  }
}
