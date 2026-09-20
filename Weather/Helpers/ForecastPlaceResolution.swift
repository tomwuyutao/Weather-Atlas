//
//  ForecastPlaceResolution.swift
//  Weather
//
//  Purpose: Completes the timezone needed by WeatherKit without performing
//  network reverse geocoding. Place names belong to explicit search and Map
//  interactions, not forecast loading or app launch.
//

import Foundation
import SwiftTimeZoneLookup

// MARK: - Forecast Place Metadata

/// Caller-provided place labels plus the timezone required to interpret a
/// WeatherKit forecast. Names remain optional for coordinate-only locations.
struct ResolvedPlace {
  let name: String?
  let country: String?
  let timeZone: TimeZone
}

extension WeatherService {
  /// Bundled coordinate boundaries keep forecast loading independent from
  /// Apple's rate-limited reverse-geocoding services.
  private static let coordinateTimeZoneLookup: SwiftTimeZoneLookup? = {
    do {
      return try SwiftTimeZoneLookup()
    } catch {
      DeveloperDiagnostics.show(
        title: "Time Zone Lookup Unavailable",
        message:
          "The bundled coordinate time-zone database could not be opened: \(error.localizedDescription)"
      )
      return nil
    }
  }()

  /// Uses existing city metadata and fills only a missing timezone from the
  /// bundled database. This method deliberately never calls MapKit or
  /// `CLGeocoder`, so ordinary forecast loading cannot consume geocoding quota.
  func resolvedPlace(for city: City) -> ResolvedPlace? {
    let name = city.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let country = city.country.trimmingCharacters(in: .whitespacesAndNewlines)
    let suppliedTimeZone = city.timeZoneIdentifier.flatMap(
      TimeZone.init(identifier:)
    )
    let lookedUpTimeZone = Self.coordinateTimeZoneLookup?.simple(
      latitude: Float(city.latitude),
      longitude: Float(city.longitude)
    ).flatMap(TimeZone.init(identifier:))

    guard let timeZone = suppliedTimeZone ?? lookedUpTimeZone else {
      return nil
    }
    return ResolvedPlace(
      name: name.isEmpty ? nil : name,
      country: country.isEmpty ? nil : country,
      timeZone: timeZone
    )
  }
}
