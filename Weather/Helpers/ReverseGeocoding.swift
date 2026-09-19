//
//  ReverseGeocoding.swift
//  Weather
//
//  Purpose: Resolves missing city names, countries, and time zones from
//  coordinates. This extension keeps reverse-geocoding policy out of the
//  WeatherKit request/conversion code in `WeatherService.swift`.
//

import CoreLocation
import Foundation
import MapKit
import SwiftTimeZoneLookup

// MARK: - Resolved Place Value

/// Canonical place metadata assembled from geocoding services.
/// It is intentionally a small value type: it is cached in memory but never
/// replaces a saved city's stable identifier or exact coordinate.
struct ResolvedPlace {
  /// Resolved locality or administrative name.
  let name: String?
  /// Resolved country name.
  let country: String?
  /// Optional timezone because some geocoders omit it.
  let timeZone: TimeZone?

}

// MARK: - Reverse Geocoding

extension WeatherService {
  /// Coordinate-to-IANA-zone lookup backed by bundled timezone boundaries.
  /// It is intentionally separate from reverse geocoding: catalog cities
  /// already supply their names and countries, so they need only this local
  /// lookup before WeatherKit can fetch a forecast.
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

  // MARK: - Cache Keys and Locale

  // MARK: - Provider Fallback Chain

  /// Resolves place metadata through caller data, cache, local time-zone
  /// boundaries, MapKit, then CLGeocoder.
  ///
  /// The order is cache → modern MapKit → established Core Location. Each
  /// later step is a graceful fallback, not a second source that overwrites a
  /// successful result from an earlier step.
  private func resolvedPlace(for city: City) async -> ResolvedPlace? {
    let placeKey =
      "\(city.latitude.bitPattern):\(city.longitude.bitPattern)|\(Locale(identifier: UserDefaults.standard.string(forKey: "appLanguage") ?? Locale.autoupdatingCurrent.identifier).identifier)"
    var place = ResolvedPlace(
      name: cleanGeocodedCityName(city.name),
      country: cleanGeocodedCityName(city.country),
      timeZone: cleanGeocodedCityName(city.timeZoneIdentifier)
        .flatMap(TimeZone.init(identifier:))
    )

    if let identifier = city.timeZoneIdentifier,
      place.timeZone == nil
    {
      reportDeveloperWarning(
        title: "Invalid City Time Zone",
        message:
          "The city \(city.displayName) has an invalid time zone identifier: \(identifier). Apple place resolution will be attempted."
      )
    }

    if let cachedPlace = resolvedPlaces[placeKey] {
      place = ResolvedPlace(
        name: place.name ?? cachedPlace.name,
        country: place.country ?? cachedPlace.country,
        timeZone: place.timeZone ?? cachedPlace.timeZone
      )
    }
    if place.timeZone == nil,
      let timeZone = coordinateTimeZone(for: city)
    {
      place = ResolvedPlace(
        name: place.name,
        country: place.country,
        timeZone: timeZone
      )
    }
    if place.name != nil && place.country != nil && place.timeZone != nil {
      resolvedPlaces[placeKey] = place
      return place
    }

    let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
    // Use the newer MapKit API where it exists; its result also carries an
    // optional timezone. `#available` preserves the same feature on older
    // deployment targets through the Core Location path below.
    if #available(iOS 26.0, *),
      let mapKitPlace = await resolvedPlaceWithMapKit(
        for: city,
        location: location
      )
    {
      place = ResolvedPlace(
        name: place.name ?? mapKitPlace.name,
        country: place.country ?? mapKitPlace.country,
        timeZone: place.timeZone ?? mapKitPlace.timeZone
      )
    }

    // A partial MapKit response is useful, but Core Location still gets one
    // chance to fill fields that MapKit omitted for the same coordinate.
    if place.name == nil || place.country == nil || place.timeZone == nil,
      let coreLocationPlace = await resolvedPlaceWithCoreLocation(
        for: city,
        location: location
      )
    {
      place = ResolvedPlace(
        name: place.name ?? coreLocationPlace.name,
        country: place.country ?? coreLocationPlace.country,
        timeZone: place.timeZone ?? coreLocationPlace.timeZone
      )
    }

    guard place.name != nil || place.country != nil || place.timeZone != nil else {
      return nil
    }
    resolvedPlaces[placeKey] = place
    return place
  }

  /// Uses Core Location as a second authoritative Apple source. It preserves a
  /// partial placemark and never broadens an absent locality into an
  /// administrative area, road, coordinate string, or country label.
  private func resolvedPlaceWithCoreLocation(
    for city: City,
    location: CLLocation
  ) async -> ResolvedPlace? {
    do {
      let placemarks = try await CLGeocoder().reverseGeocodeLocation(
        location,
        preferredLocale: Locale(
          identifier: UserDefaults.standard.string(forKey: "appLanguage")
            ?? Locale.autoupdatingCurrent.identifier)
      )
      guard let placemark = placemarks.first else {
        reportDeveloperWarning(
          title: "Geocoder Returned No Placemark",
          message:
            "Apple reverse geocoding returned no placemark for \(city.displayName) at \(city.latitude), \(city.longitude)."
        )
        return nil
      }

      let place = ResolvedPlace(
        name: cleanGeocodedCityName(placemark.locality),
        country: cleanGeocodedCityName(
          placemark.country ?? placemark.isoCountryCode
        ),
        timeZone: placemark.timeZone
      )
      if place.name == nil && place.country == nil && place.timeZone == nil {
        reportDeveloperWarning(
          title: "Geocoder Returned No Place Metadata",
          message:
            "Apple reverse geocoding returned no city, country, or time zone for \(city.latitude), \(city.longitude)."
        )
        return nil
      }
      return place
    } catch {
      reportDeveloperWarning(
        title: "Geocoder Failed",
        message:
          "Apple reverse geocoding failed for \(city.displayName) at \(city.latitude), \(city.longitude): \(error.localizedDescription)"
      )
      return nil
    }
  }

  @available(iOS 26.0, *)
  /// Queries MapKit for the nearest usable locality and timezone metadata.
  /// The API may return no nearby map item for valid coordinates, particularly
  /// in Simulator, so callers must treat `nil` as a normal fallback trigger.
  private func resolvedPlaceWithMapKit(for city: City, location: CLLocation) async -> ResolvedPlace?
  {
    let request = MKReverseGeocodingRequest(location: location)
    request?.preferredLocale = Locale(
      identifier: UserDefaults.standard.string(forKey: "appLanguage")
        ?? Locale.autoupdatingCurrent.identifier)

    do {
      guard let mapItems = try await request?.mapItems,
        let mapItem = mapItems.first
      else {
        reportDeveloperWarning(
          title: "MapKit Returned No Placemark",
          message:
            "Apple reverse geocoding returned no map item for \(city.displayName) at \(city.latitude), \(city.longitude)."
        )
        return nil
      }

      let placemark = mapItem.placemark
      let place = ResolvedPlace(
        name: cleanGeocodedCityName(placemark.locality),
        country: cleanGeocodedCityName(
          placemark.country ?? placemark.isoCountryCode
        ),
        timeZone: placemark.timeZone
      )
      if place.name == nil && place.country == nil && place.timeZone == nil {
        reportDeveloperWarning(
          title: "MapKit Returned No Place Metadata",
          message:
            "Apple reverse geocoding returned no city, country, or time zone for \(city.latitude), \(city.longitude)."
        )
        return nil
      }
      return place
    } catch {
      reportDeveloperWarning(
        title: "MapKit Geocoder Failed",
        message:
          "Apple reverse geocoding failed for \(city.displayName) at \(city.latitude), \(city.longitude): \(error.localizedDescription)"
      )
      return nil
    }
  }

  /// Trims a geocoder string and rejects empty results.
  private func cleanGeocodedCityName(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty
    else { return nil }
    return trimmed
  }

  /// Resolves only an IANA timezone from a coordinate. This stays local to
  /// the device and makes no MapKit or Core Location reverse-geocoding call.
  private func coordinateTimeZone(for city: City) -> TimeZone? {
    guard city.latitude.isFinite,
      city.longitude.isFinite,
      (-90...90).contains(city.latitude),
      (-180...180).contains(city.longitude),
      let identifier = Self.coordinateTimeZoneLookup?.simple(
        latitude: Float(city.latitude),
        longitude: Float(city.longitude)
      )
    else {
      return nil
    }
    return TimeZone(identifier: identifier)
  }

  // MARK: - City and Time Zone Resolution

  /// Resolves the user-visible city metadata and its timezone in one pass.
  ///
  /// A `City` can be created from a raw current-location coordinate before a
  /// name/country is known. This method fills that metadata only when needed;
  /// it never swaps the UUID or coordinate that other stores rely on.
  func resolvedCityAndTimeZone(
    for city: City
  ) async throws -> (city: City, timeZone: TimeZone) {
    let place = await resolvedPlace(for: city)
    guard let timeZone = place?.timeZone else {
      reportDeveloperWarning(
        title: "Time Zone Missing",
        message:
          "No valid time zone was available for \(city.displayName) at \(city.latitude), \(city.longitude)."
      )
      throw WeatherServiceError.undefinedTimeZone(city: city.displayName)
    }

    return (
      city: City(
        id: city.id,
        name: place?.name ?? "",
        titleName: city.titleName,
        country: place?.country ?? "",
        countryISO2Code: city.countryISO2Code,
        latitude: city.latitude,
        longitude: city.longitude,
        timeZoneIdentifier: timeZone.identifier,
        catalogIdentifier: city.catalogIdentifier
      ),
      timeZone: timeZone
    )
  }
}
