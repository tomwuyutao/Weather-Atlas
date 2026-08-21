//
//  ReverseGeocoding.swift
//  Weather
//
//  Purpose: Resolves missing city names, countries, and time zones from
//  coordinates. This extension keeps reverse-geocoding policy out of the
//  WeatherKit request/conversion code in `WeatherService.swift`.
//

import Foundation
import CoreLocation
import MapKit
import SwiftTimeZoneLookup

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

    /// A geocoder can legitimately return only part of a placemark. Keeping each
    /// field independent prevents a valid timezone from being discarded merely
    /// because the same response omitted a presentation-only name or country.
    var hasAnyMetadata: Bool {
        name != nil || country != nil || timeZone != nil
    }

    var isComplete: Bool {
        name != nil && country != nil && timeZone != nil
    }

    /// Fills only absent fields. Earlier values are either caller-provided source
    /// metadata or results from the preferred Apple API and must not be replaced
    /// by a later provider response.
    func fillingMissingFields(from other: ResolvedPlace) -> ResolvedPlace {
        ResolvedPlace(
            name: name ?? other.name,
            country: country ?? other.country,
            timeZone: timeZone ?? other.timeZone
        )
    }
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
                message: "The bundled coordinate time-zone database could not be opened: \(error.localizedDescription)"
            )
            return nil
        }
    }()

    // MARK: - Cache Keys and Locale

    /// Builds an exact coordinate key for in-process place and timezone caches.
    /// A rounded cell can straddle a locality, country, or timezone boundary;
    /// using the source bit patterns prevents one nearby point's metadata from
    /// being substituted for another point merely because they are close.
    private func coordinateKey(for city: City) -> String {
        "\(city.latitude.bitPattern):\(city.longitude.bitPattern)"
    }

    /// Place names and country strings are localized geocoder output, so their
    /// cache identity includes the requested app language. Timezones remain in
    /// the separate exact-coordinate cache because they are locale-independent.
    private func localizedPlaceKey(for city: City) -> String {
        "\(coordinateKey(for: city))|\(preferredGeocodingLocale().identifier)"
    }

    /// Uses the in-app language when requesting localized geocoder results.
    /// This intentionally reads the app preference rather than the device-only
    /// locale, so a person who changes Weather Atlas's language sees matching
    /// place names in the response.
    private func preferredGeocodingLocale() -> Locale {
        let identifier = UserDefaults.standard.string(forKey: "appLanguage") ?? Locale.autoupdatingCurrent.identifier
        return Locale(identifier: identifier)
    }

    // MARK: - Reverse Geocoding

    /// Resolves place metadata through caller data, cache, local time-zone
    /// boundaries, MapKit, then CLGeocoder.
    ///
    /// The order is cache → modern MapKit → established Core Location. Each
    /// later step is a graceful fallback, not a second source that overwrites a
    /// successful result from an earlier step.
    private func resolvedPlace(for city: City) async -> ResolvedPlace? {
        let coordinateKey = coordinateKey(for: city)
        let placeKey = localizedPlaceKey(for: city)
        var place = ResolvedPlace(
            name: cleanGeocodedCityName(city.name),
            country: cleanGeocodedCityName(city.country),
            timeZone: validTimeZone(from: city.timeZoneIdentifier)
        )

        if let identifier = city.timeZoneIdentifier,
           place.timeZone == nil {
            reportDeveloperWarning(
                title: "Invalid City Time Zone",
                message: "The city \(city.displayName) has an invalid time zone identifier: \(identifier). Apple place resolution will be attempted."
            )
        }

        if let cachedPlace = resolvedPlaces[placeKey] {
            place = place.fillingMissingFields(from: cachedPlace)
        }
        if place.timeZone == nil,
           let timeZone = coordinateTimeZone(for: city) {
            place = ResolvedPlace(
                name: place.name,
                country: place.country,
                timeZone: timeZone
            )
            resolvedTimeZones[coordinateKey] = timeZone
        }
        if place.isComplete {
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
           ) {
            place = place.fillingMissingFields(from: mapKitPlace)
            if let timeZone = place.timeZone {
                resolvedTimeZones[coordinateKey] = timeZone
            }
        }

        // A partial MapKit response is useful, but Core Location still gets one
        // chance to fill fields that MapKit omitted for the same coordinate.
        if !place.isComplete,
           let coreLocationPlace = await resolvedPlaceWithCoreLocation(
               for: city,
               location: location
           ) {
            place = place.fillingMissingFields(from: coreLocationPlace)
        }

        guard place.hasAnyMetadata else { return nil }
        resolvedPlaces[placeKey] = place
        if let timeZone = place.timeZone {
            resolvedTimeZones[coordinateKey] = timeZone
        }
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
                preferredLocale: preferredGeocodingLocale()
            )
            guard let placemark = placemarks.first else {
                reportDeveloperWarning(
                    title: "Geocoder Returned No Placemark",
                    message: "Apple reverse geocoding returned no placemark for \(city.displayName) at \(city.latitude), \(city.longitude)."
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
            if !place.hasAnyMetadata {
                reportDeveloperWarning(
                    title: "Geocoder Returned No Place Metadata",
                    message: "Apple reverse geocoding returned no city, country, or time zone for \(city.latitude), \(city.longitude)."
                )
                return nil
            }
            return place
        } catch {
            reportDeveloperWarning(
                title: "Geocoder Failed",
                message: "Apple reverse geocoding failed for \(city.displayName) at \(city.latitude), \(city.longitude): \(error.localizedDescription)"
            )
            return nil
        }
    }

    @available(iOS 26.0, *)
    /// Queries MapKit for the nearest usable locality and timezone metadata.
    /// The API may return no nearby map item for valid coordinates, particularly
    /// in Simulator, so callers must treat `nil` as a normal fallback trigger.
    private func resolvedPlaceWithMapKit(for city: City, location: CLLocation) async -> ResolvedPlace? {
        let request = MKReverseGeocodingRequest(location: location)
        request?.preferredLocale = preferredGeocodingLocale()

        do {
            guard let mapItems = try await request?.mapItems,
                  let mapItem = mapItems.first else {
                reportDeveloperWarning(
                    title: "MapKit Returned No Placemark",
                    message: "Apple reverse geocoding returned no map item for \(city.displayName) at \(city.latitude), \(city.longitude)."
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
            if !place.hasAnyMetadata {
                reportDeveloperWarning(
                    title: "MapKit Returned No Place Metadata",
                    message: "Apple reverse geocoding returned no city, country, or time zone for \(city.latitude), \(city.longitude)."
                )
                return nil
            }
            return place
        } catch {
            reportDeveloperWarning(
                title: "MapKit Geocoder Failed",
                message: "Apple reverse geocoding failed for \(city.displayName) at \(city.latitude), \(city.longitude): \(error.localizedDescription)"
            )
            return nil
        }
    }

    /// Trims a geocoder string and rejects empty results.
    private func cleanGeocodedCityName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Accepts only a real Foundation timezone. An invalid persisted identifier
    /// is treated as missing so Apple resolution can repair it.
    private func validTimeZone(from identifier: String?) -> TimeZone? {
        guard let identifier = cleanGeocodedCityName(identifier) else {
            return nil
        }
        return TimeZone(identifier: identifier)
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
              ) else {
            return nil
        }
        return TimeZone(identifier: identifier)
    }

    // MARK: - City and Time Zone Resolution

    /// Returns a canonically named city while preserving stable identity and coordinates.
    ///
    /// A `City` can be created from a raw current-location coordinate before a
    /// name/country is known. This method fills that metadata only when needed;
    /// it never swaps the UUID or coordinate that other stores rely on.
    func resolvedCity(for city: City) async throws -> City {
        let place = await resolvedPlace(for: city)
        return City(
            id: city.id,
            name: place?.name ?? "",
            titleName: city.titleName,
            country: place?.country ?? "",
            latitude: city.latitude,
            longitude: city.longitude,
            timeZoneIdentifier: place?.timeZone?.identifier,
            catalogIdentifier: city.catalogIdentifier
        )
    }

    /// Resolves a timezone from saved metadata, cache, local coordinate
    /// boundaries, or finally reverse geocoding.
    ///
    /// The ordered sources reflect confidence and cost: an IANA identifier saved
    /// with the city is authoritative, an in-memory result is free, and reverse
    /// geocoding is slower/network-dependent. No geographic approximation or
    /// guessed GMT value is used when those factual sources are unavailable.
    private func resolvedTimeZone(for city: City) async -> TimeZone? {
        let key = coordinateKey(for: city)
        if let identifier = city.timeZoneIdentifier {
            if let timeZone = TimeZone(identifier: identifier) {
                resolvedTimeZones[key] = timeZone
                return timeZone
            } else {
                reportDeveloperWarning(
                    title: "Invalid City Time Zone",
                    message: "The city \(city.displayName) has an invalid time zone identifier: \(identifier). Apple place resolution will be attempted."
                )
            }
        }
        if let cachedTimeZone = resolvedTimeZones[key] {
            return cachedTimeZone
        }
        if let timeZone = await resolvedPlace(for: city)?.timeZone {
            return timeZone
        }

        return nil
    }

    /// Returns a real resolved timezone or throws instead of substituting GMT.
    func resolvedTimeZoneOrThrow(for city: City) async throws -> TimeZone {
        if let timeZone = await resolvedTimeZone(for: city) {
            return timeZone
        }

        reportDeveloperWarning(
            title: "Time Zone Missing",
            message: "No valid time zone was available for \(city.displayName) at \(city.latitude), \(city.longitude)."
        )
        throw WeatherServiceError.undefinedTimeZone(city: city.displayName)
    }
}
