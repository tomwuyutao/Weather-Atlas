//
//  PlaceResolution.swift
//  Weather
//
//  Purpose: Resolves missing city names, countries, and time zones from coordinates.
//

import Foundation
import CoreLocation
import MapKit

struct ResolvedPlace {
    let name: String
    let country: String
    let timeZone: TimeZone?
}

// MARK: - Place Resolution

extension WeatherService {
    private func coordinateKey(for city: City) -> String {
        String(format: "%.3f,%.3f", city.latitude, city.longitude)
    }

    private func preferredGeocodingLocale() -> Locale {
        let identifier = UserDefaults.standard.string(forKey: "appLanguage") ?? Locale.autoupdatingCurrent.identifier
        return Locale(identifier: identifier)
    }

    private func resolvedPlace(for city: City) async -> ResolvedPlace? {
        let key = coordinateKey(for: city)
        if let cachedPlace = resolvedPlaces[key] {
            return cachedPlace
        }

        let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
        if #available(iOS 26.0, *) {
            if let place = await resolvedPlaceWithMapKit(for: city, location: location) {
                resolvedPlaces[key] = place
                if let timeZone = place.timeZone {
                    resolvedTimeZones[key] = timeZone
                }
                return place
            }
            return nil
        }

        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: preferredGeocodingLocale())
            guard let placemark = placemarks.first else {
                reportDeveloperWarning(
                    title: "Geocoder Returned No Placemark",
                    message: "Apple reverse geocoding returned no placemark for \(city.localizedName()) at \(city.latitude), \(city.longitude)."
                )
                return nil
            }
            let resolvedName = resolvedCityName(from: placemark, originalCity: city)
            guard let resolvedName else {
                reportDeveloperWarning(
                    title: "Geocoder Returned No City Name",
                    message: "Apple reverse geocoding returned only district/road-level names for \(city.latitude), \(city.longitude). Contact developer to correct this coordinate."
                )
                return nil
            }
            let resolvedCountry = placemark.country
                ?? placemark.isoCountryCode
            guard let resolvedCountry else {
                reportDeveloperWarning(
                    title: "Geocoder Returned No Country",
                    message: "Apple reverse geocoding returned a placemark without a country for \(resolvedName) at \(city.latitude), \(city.longitude)."
                )
                return nil
            }
            let place = ResolvedPlace(name: resolvedName, country: resolvedCountry, timeZone: placemark.timeZone)
            resolvedPlaces[key] = place
            if let timeZone = placemark.timeZone {
                resolvedTimeZones[key] = timeZone
            }
            return place
        } catch {
            reportDeveloperWarning(
                title: "Geocoder Failed",
                message: "Apple reverse geocoding failed for \(city.localizedName()) at \(city.latitude), \(city.longitude): \(error.localizedDescription)"
            )
            return nil
        }
    }

    @available(iOS 26.0, *)
    private func resolvedPlaceWithMapKit(for city: City, location: CLLocation) async -> ResolvedPlace? {
        let request = MKReverseGeocodingRequest(location: location)
        request?.preferredLocale = preferredGeocodingLocale()

        do {
            guard let mapItems = try await request?.mapItems,
                  let mapItem = mapItems.first else {
                reportDeveloperWarning(
                    title: "MapKit Returned No Placemark",
                    message: "Apple reverse geocoding returned no map item for \(city.localizedName()) at \(city.latitude), \(city.longitude)."
                )
                return nil
            }

            let placemark = mapItem.placemark
            guard let resolvedName = resolvedCityName(from: placemark, originalCity: city) else {
                reportDeveloperWarning(
                    title: "MapKit Returned No City Name",
                    message: "Apple reverse geocoding returned only district/road-level names for \(city.latitude), \(city.longitude). Contact developer to correct this coordinate."
                )
                return nil
            }

            guard let resolvedCountry = placemark.country ?? placemark.isoCountryCode else {
                reportDeveloperWarning(
                    title: "MapKit Returned No Country",
                    message: "Apple reverse geocoding returned a placemark without a country for \(resolvedName) at \(city.latitude), \(city.longitude)."
                )
                return nil
            }

            return ResolvedPlace(name: resolvedName, country: resolvedCountry, timeZone: placemark.timeZone)
        } catch {
            reportDeveloperWarning(
                title: "MapKit Geocoder Failed",
                message: "Apple reverse geocoding failed for \(city.localizedName()) at \(city.latitude), \(city.longitude): \(error.localizedDescription)"
            )
            return nil
        }
    }

    private func resolvedCityName(from placemark: CLPlacemark, originalCity city: City) -> String? {
        if let locality = cleanGeocodedCityName(placemark.locality) {
            return locality
        }

        if let explicitName = cleanGeocodedCityName(city.name) {
            return explicitName
        }

        return nil
    }

    private func cleanGeocodedCityName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    func resolvedCity(for city: City) async throws -> City {
        if !city.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !city.country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return city
        }

        guard let place = await resolvedPlace(for: city) else {
            throw WeatherServiceError.unresolvedPlace(city: city.localizedName())
        }
        return City(
            id: city.id,
            name: place.name,
            country: place.country,
            latitude: city.latitude,
            longitude: city.longitude,
            timeZoneIdentifier: city.timeZoneIdentifier
        )
    }

    private func resolvedTimeZone(for city: City) async -> TimeZone? {
        let key = coordinateKey(for: city)
        if let identifier = city.timeZoneIdentifier {
            guard let timeZone = TimeZone(identifier: identifier) else {
                reportDeveloperWarning(
                    title: "Invalid City Time Zone",
                    message: "The city \(city.localizedName()) has an invalid time zone identifier: \(identifier)."
                )
                return nil
            }
            resolvedTimeZones[key] = timeZone
            return timeZone
        }
        if let cachedTimeZone = resolvedTimeZones[key] {
            return cachedTimeZone
        }
        if let timeZone = await resolvedPlace(for: city)?.timeZone {
            return timeZone
        }
        return nil
    }

    func resolvedTimeZoneOrThrow(for city: City) async throws -> TimeZone {
        if let timeZone = await resolvedTimeZone(for: city) {
            return timeZone
        }

        reportDeveloperWarning(
            title: "Time Zone Missing",
            message: "No Apple-provided time zone was available for \(city.localizedName()) at \(city.latitude), \(city.longitude)."
        )
        throw WeatherServiceError.undefinedTimeZone(city: city.localizedName())
    }
}
